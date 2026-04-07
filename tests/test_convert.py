import struct
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from convert import (
    build_ffmpeg_video_filter,
    build_interleaved_frame_name,
    build_matcher_subcommand,
    build_video_extraction_plans,
    discover_video_files,
    prepare_input_directory,
    read_text_image_count,
    select_best_sparse_model,
)


class ConvertSparseModelSelectionTest(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name)
        self.sparse_root = self.root / "distorted" / "sparse"
        self.sparse_root.mkdir(parents=True, exist_ok=True)

    def tearDown(self):
        self.tempdir.cleanup()

    def write_binary_count(self, path: Path, count: int) -> None:
        path.write_bytes(struct.pack("<Q", count))

    def create_binary_model(
        self,
        name: str,
        *,
        camera_count: int = 1,
        registered_image_count: int = 0,
        point_count: int = 0,
    ) -> Path:
        model_path = self.sparse_root / name
        model_path.mkdir(parents=True, exist_ok=True)

        # 这里不需要写完整 COLMAP 模型.
        # 选择逻辑只读取二进制头里的记录数.
        self.write_binary_count(model_path / "cameras.bin", camera_count)
        self.write_binary_count(model_path / "images.bin", registered_image_count)
        self.write_binary_count(model_path / "points3D.bin", point_count)
        return model_path

    def test_select_best_sparse_model_prefers_registered_images(self):
        self.create_binary_model("0", registered_image_count=4, point_count=2)
        self.create_binary_model("1", registered_image_count=15, point_count=2581)
        self.create_binary_model("2", registered_image_count=360, point_count=92946)

        best_model = select_best_sparse_model(self.sparse_root)

        self.assertEqual(best_model.path.name, "2")
        self.assertEqual(best_model.registered_image_count, 360)
        self.assertEqual(best_model.point_count, 92946)

    def test_select_best_sparse_model_uses_points_as_tiebreaker(self):
        self.create_binary_model("0", registered_image_count=30, point_count=100)
        self.create_binary_model("1", registered_image_count=30, point_count=500)

        best_model = select_best_sparse_model(self.sparse_root)

        self.assertEqual(best_model.path.name, "1")
        self.assertEqual(best_model.point_count, 500)

    def test_read_text_image_count_uses_two_lines_per_image(self):
        image_text = "\n".join(
            [
                "# comment",
                "1 1 0 0 0 0 0 0 1 image_0001.jpg",
                "0 0 -1 1 1 -1",
                "2 1 0 0 0 0 0 0 1 image_0002.jpg",
                "2 2 -1 3 3 -1",
            ]
        )
        image_path = self.root / "images.txt"
        image_path.write_text(image_text + "\n", encoding="utf-8")

        self.assertEqual(read_text_image_count(image_path), 2)

    def test_discover_video_files_prefers_generated_videos_over_recursive_auxiliary_videos(self):
        """`generated_videos` 应先于全局递归兜底, 避免把辅助视频扫进来."""

        generated_dir = self.root / "0" / "generated_videos"
        rendering_dir = self.root / "0" / "rendering_4D_maps"
        generated_dir.mkdir(parents=True, exist_ok=True)
        rendering_dir.mkdir(parents=True, exist_ok=True)

        (generated_dir / "generated_video_0.mp4").write_bytes(b"rgb")
        (rendering_dir / "background_depth.mp4").write_bytes(b"depth")
        (rendering_dir / "merged_mask.mp4").write_bytes(b"mask")

        videos, discovery_mode = discover_video_files(self.root)

        self.assertEqual(discovery_mode, "generated_videos_recursive")
        self.assertEqual(
            [path.relative_to(self.root).as_posix() for path in videos],
            ["0/generated_videos/generated_video_0.mp4"],
        )

    def test_build_video_extraction_plans_ignore_generated_mask_video(self):
        """`merged_mask.mp4` 当前不应再被当成训练 mask 入口."""

        generated_dir = self.root / "0" / "generated_videos"
        rendering_dir = self.root / "0" / "rendering_4D_maps"
        generated_dir.mkdir(parents=True, exist_ok=True)
        rendering_dir.mkdir(parents=True, exist_ok=True)

        rgb_video = generated_dir / "generated_video_0.mp4"
        rgb_video.write_bytes(b"rgb")
        (rendering_dir / "merged_mask.mp4").write_bytes(b"mask")

        plans = build_video_extraction_plans(self.root, [rgb_video])

        self.assertEqual(len(plans), 1)
        self.assertEqual(plans[0].video_path, rgb_video)
        self.assertEqual(plans[0].frame_prefix, "001_0_generated_videos_generated_video_0")

    def test_build_video_extraction_plans_do_not_require_generated_mask_coverage(self):
        """部分视角存在 `merged_mask.mp4` 时, 也不应影响 RGB 抽帧计划."""

        rgb_video_paths = []
        for view_id in ("0", "1"):
            generated_dir = self.root / view_id / "generated_videos"
            generated_dir.mkdir(parents=True, exist_ok=True)
            rgb_video = generated_dir / "generated_video_0.mp4"
            rgb_video.write_bytes(b"rgb")
            rgb_video_paths.append(rgb_video)

        rendering_dir = self.root / "0" / "rendering_4D_maps"
        rendering_dir.mkdir(parents=True, exist_ok=True)
        (rendering_dir / "merged_mask.mp4").write_bytes(b"mask")

        plans = build_video_extraction_plans(self.root, rgb_video_paths)

        self.assertEqual(len(plans), 2)
        self.assertEqual(
            [plan.frame_prefix for plan in plans],
            [
                "001_0_generated_videos_generated_video_0",
                "002_1_generated_videos_generated_video_0",
            ],
        )


class ConvertVideoExtractionOptionsTest(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name)
        self.video_source = self.root / "videos"
        self.source_path = self.root / "scene"
        self.video_source.mkdir(parents=True, exist_ok=True)
        self.source_path.mkdir(parents=True, exist_ok=True)

        self.video_path = self.video_source / "view0.mp4"
        self.video_path.write_bytes(b"video")

    def tearDown(self):
        self.tempdir.cleanup()

    def test_build_ffmpeg_video_filter_defaults_to_fps(self):
        self.assertEqual(build_ffmpeg_video_filter(5.333333333333, 0), "fps=5.333333333333")

    def test_build_ffmpeg_video_filter_prefers_frame_step(self):
        self.assertEqual(
            build_ffmpeg_video_filter(5.333333333333, 3),
            "select=not(mod(n\\,3)),setpts=N/FRAME_RATE/TB",
        )

    def test_build_matcher_subcommand_supports_sequential(self):
        self.assertEqual(build_matcher_subcommand("exhaustive"), "exhaustive_matcher")
        self.assertEqual(build_matcher_subcommand("sequential"), "sequential_matcher")

    def test_build_interleaved_frame_name_is_time_major(self):
        self.assertEqual(
            build_interleaved_frame_name(2, 11, "011_view"),
            "frame_000002_view_011_011_view.jpg",
        )

    @mock.patch("convert.run_command")
    @mock.patch("convert.discover_video_files")
    def test_prepare_input_directory_uses_fps_filter_when_no_frame_step(
        self,
        mock_discover_video_files,
        mock_run_command,
    ):
        mock_discover_video_files.return_value = ([self.video_path], "direct")

        def fake_run_command(command, _step_name):
            output_path = Path(command[-1].replace("%06d", "000001"))
            output_path.write_bytes(b"frame")

        mock_run_command.side_effect = fake_run_command

        prepare_input_directory(
            source_path=self.source_path,
            video_source=self.video_source,
            ffmpeg_command="ffmpeg",
            video_fps=5.333333333333,
            video_frame_step=0,
            video_naming="grouped",
            overwrite=False,
        )

        command = mock_run_command.call_args[0][0]
        self.assertIn("fps=5.333333333333", command)

    @mock.patch("convert.run_command")
    @mock.patch("convert.discover_video_files")
    def test_prepare_input_directory_uses_frame_step_filter_when_requested(
        self,
        mock_discover_video_files,
        mock_run_command,
    ):
        mock_discover_video_files.return_value = ([self.video_path], "direct")

        def fake_run_command(command, _step_name):
            output_path = Path(command[-1].replace("%06d", "000001"))
            output_path.write_bytes(b"frame")

        mock_run_command.side_effect = fake_run_command

        prepare_input_directory(
            source_path=self.source_path,
            video_source=self.video_source,
            ffmpeg_command="ffmpeg",
            video_fps=5.333333333333,
            video_frame_step=3,
            video_naming="grouped",
            overwrite=False,
        )

        command = mock_run_command.call_args[0][0]
        self.assertIn("select=not(mod(n\\,3)),setpts=N/FRAME_RATE/TB", command)
        self.assertNotIn("fps=5.333333333333", command)

    @mock.patch("convert.run_command")
    @mock.patch("convert.discover_video_files")
    def test_prepare_input_directory_interleaves_views_by_frame_index(
        self,
        mock_discover_video_files,
        mock_run_command,
    ):
        second_video_path = self.video_source / "view1.mp4"
        second_video_path.write_bytes(b"video")
        mock_discover_video_files.return_value = ([self.video_path, second_video_path], "direct")

        def fake_run_command(command, _step_name):
            output_pattern = Path(command[-1])
            output_pattern.parent.mkdir(parents=True, exist_ok=True)
            for frame_number in (1, 2):
                output_path = output_pattern.with_name(f"{frame_number:06d}.jpg")
                output_path.write_bytes(f"frame-{output_pattern.parent.name}-{frame_number}".encode("utf-8"))

        mock_run_command.side_effect = fake_run_command

        prepare_input_directory(
            source_path=self.source_path,
            video_source=self.video_source,
            ffmpeg_command="ffmpeg",
            video_fps=5.333333333333,
            video_frame_step=3,
            video_naming="interleaved",
            overwrite=False,
        )

        extracted_names = sorted(path.name for path in self.source_path.joinpath("input").iterdir())
        self.assertEqual(
            extracted_names,
            [
                "frame_000001_view_001_001_view0.jpg",
                "frame_000001_view_002_002_view1.jpg",
                "frame_000002_view_001_001_view0.jpg",
                "frame_000002_view_002_002_view1.jpg",
            ],
        )


if __name__ == "__main__":
    unittest.main()

import struct
import tempfile
import unittest
from pathlib import Path

from convert import (
    build_video_extraction_plans,
    discover_video_files,
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

    def test_build_video_extraction_plans_attaches_generated_mask_video(self):
        """VerseCrafter 风格目录应自动把 `merged_mask.mp4` 绑定到同视角 RGB 视频."""

        generated_dir = self.root / "0" / "generated_videos"
        rendering_dir = self.root / "0" / "rendering_4D_maps"
        generated_dir.mkdir(parents=True, exist_ok=True)
        rendering_dir.mkdir(parents=True, exist_ok=True)

        rgb_video = generated_dir / "generated_video_0.mp4"
        mask_video = rendering_dir / "merged_mask.mp4"
        rgb_video.write_bytes(b"rgb")
        mask_video.write_bytes(b"mask")

        plans = build_video_extraction_plans(self.root, [rgb_video])

        self.assertEqual(len(plans), 1)
        self.assertEqual(plans[0].mask_video_path, mask_video)
        self.assertEqual(plans[0].frame_prefix, "001_0_generated_videos_generated_video_0")

    def test_build_video_extraction_plans_requires_full_mask_coverage(self):
        """只给部分视角提供 `merged_mask.mp4` 时, 应立即失败."""

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

        with self.assertRaises(SystemExit):
            build_video_extraction_plans(self.root, rgb_video_paths)


if __name__ == "__main__":
    unittest.main()

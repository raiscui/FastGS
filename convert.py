#
# Copyright (C) 2023, Inria
# GRAPHDECO research group, https://team.inria.fr/graphdeco
# All rights reserved.
#
# This software is free for non-commercial, research and evaluation use
# under the terms of the LICENSE.md file.
#
# For inquiries contact  george.drettakis@inria.fr
#

import logging
import shutil
import struct
import subprocess
import tempfile
from argparse import ArgumentParser
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Sequence, Set, Tuple


VIDEO_EXTENSIONS: Set[str] = {
    ".mp4",
    ".mov",
    ".m4v",
    ".avi",
    ".mkv",
    ".webm",
    ".mpg",
    ".mpeg",
}


@dataclass(frozen=True)
class SparseModelStats:
    path: Path
    camera_count: int
    registered_image_count: int
    point_count: int


@dataclass(frozen=True)
class VideoExtractionPlan:
    video_path: Path
    frame_prefix: str


def parse_args():
    parser = ArgumentParser("Colmap converter")
    parser.add_argument("--no_gpu", action="store_true")
    parser.add_argument("--skip_matching", action="store_true")
    parser.add_argument("--source_path", "-s", required=True, type=str)
    parser.add_argument("--camera", default="OPENCV", type=str)
    parser.add_argument("--colmap_executable", default="", type=str)
    parser.add_argument(
        "--colmap_gpu_index",
        default="",
        type=str,
        help="Explicit GPU index list forwarded to COLMAP, e.g. `0` or `0,1`.",
    )
    parser.add_argument("--resize", action="store_true")
    parser.add_argument("--magick_executable", default="", type=str)

    # 兼容旧流程的同时,允许用户显式指定“视频目录 -> 自动抽帧 -> 再做 COLMAP”.
    parser.add_argument(
        "--video_path",
        default="",
        type=str,
        help="Directory containing videos that should be treated as one capture set.",
    )
    parser.add_argument(
        "--video_fps",
        default=2.0,
        type=float,
        help="Frame sampling rate used when extracting images from videos.",
    )
    parser.add_argument(
        "--video_frame_step",
        default=0,
        type=int,
        help="Extract every Nth decoded frame from videos. When > 0, takes precedence over --video_fps.",
    )
    parser.add_argument(
        "--ffmpeg_executable",
        default="",
        type=str,
        help="Path to ffmpeg. Defaults to `ffmpeg` in PATH.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Delete generated outputs before re-running conversion. In video mode this also recreates source_path/input.",
    )
    parser.add_argument(
        "--matcher",
        default="exhaustive",
        choices=("exhaustive", "sequential"),
        help="COLMAP matching strategy. Use `sequential` for ordered image sequences such as videos.",
    )
    parser.add_argument(
        "--video_naming",
        default="grouped",
        choices=("grouped", "interleaved"),
        help="How extracted video frames are named. `interleaved` is useful for fair sequential matcher tests on synchronized multi-view videos.",
    )
    parser.add_argument(
        "--final_image_naming",
        default="preserve",
        choices=("preserve", "numeric"),
        help="How extracted frames are finally named inside source_path/input before COLMAP. `numeric` rewrites them to contiguous 6-digit names such as `000001.jpg`.",
    )
    return parser.parse_args()


def run_command(command: Sequence[str], step_name: str) -> None:
    command_list = [str(part) for part in command]
    logging.info("Running %s: %s", step_name, " ".join(command_list))

    try:
        subprocess.run(command_list, check=True)
    except FileNotFoundError as exc:
        logging.error("%s failed because executable `%s` was not found.", step_name, exc.filename)
        raise SystemExit(1) from exc
    except subprocess.CalledProcessError as exc:
        logging.error("%s failed with code %s. Exiting.", step_name, exc.returncode)
        raise SystemExit(exc.returncode) from exc


def command_supports_option(command: str, subcommand: str, option_name: str) -> bool:
    """探测本机 COLMAP 子命令是否支持某个选项.

    COLMAP 4.x 把部分 GPU 相关参数从 `Sift*` 挪到了 `Feature*`.
    这里在运行真实命令前先读一遍帮助输出, 避免把某个版本绑死.
    """
    try:
        result = subprocess.run(
            [command, subcommand, "-h"],
            check=True,
            capture_output=True,
            text=True,
        )
    except (FileNotFoundError, subprocess.CalledProcessError):
        return False

    help_text = f"{result.stdout}\n{result.stderr}"
    return option_name in help_text


def read_binary_count(path: Path) -> int:
    """读取 COLMAP 二进制模型文件头里的记录数."""
    with path.open("rb") as handle:
        raw_count = handle.read(8)

    if len(raw_count) != 8:
        raise ValueError(f"`{path}` is too small to contain a COLMAP record count.")

    return struct.unpack("<Q", raw_count)[0]


def count_non_comment_lines(path: Path) -> int:
    count = 0
    with path.open("r", encoding="utf-8") as handle:
        for raw_line in handle:
            stripped = raw_line.strip()
            if stripped and not stripped.startswith("#"):
                count += 1
    return count


def read_text_image_count(path: Path) -> int:
    # `images.txt` 中每张图占两行:
    # 第一行是位姿和文件名, 第二行是 2D 点列表.
    return count_non_comment_lines(path) // 2


def read_optional_model_count(model_path: Path, binary_name: str, text_name: str) -> int:
    binary_path = model_path / binary_name
    if binary_path.exists():
        return read_binary_count(binary_path)

    text_path = model_path / text_name
    if not text_path.exists():
        return 0

    if text_name == "images.txt":
        return read_text_image_count(text_path)

    return count_non_comment_lines(text_path)


def list_sparse_model_stats(sparse_root: Path) -> List[SparseModelStats]:
    model_directories = sorted(path for path in sparse_root.iterdir() if path.is_dir())
    if not model_directories:
        logging.error("No COLMAP sparse models were found in `%s`.", sparse_root)
        raise SystemExit(1)

    stats: List[SparseModelStats] = []
    for model_path in model_directories:
        model_stats = SparseModelStats(
            path=model_path,
            camera_count=read_optional_model_count(model_path, "cameras.bin", "cameras.txt"),
            registered_image_count=read_optional_model_count(model_path, "images.bin", "images.txt"),
            point_count=read_optional_model_count(model_path, "points3D.bin", "points3D.txt"),
        )
        stats.append(model_stats)
        logging.info(
            "COLMAP sparse model `%s`: cameras=%s, registered_images=%s, points=%s",
            model_path.name,
            model_stats.camera_count,
            model_stats.registered_image_count,
            model_stats.point_count,
        )

    return stats


def select_best_sparse_model(sparse_root: Path) -> SparseModelStats:
    """为 undistort 选择最稳的 COLMAP sparse 子模型.

    真实数据里 `mapper` 可能会产出多个子模型.
    固定写死 `sparse/0` 会把“最先生成的模型”误当成“最好的模型”.
    """
    if not sparse_root.is_dir():
        logging.error("Expected COLMAP sparse root at `%s`, but it does not exist.", sparse_root)
        raise SystemExit(1)

    sparse_models = list_sparse_model_stats(sparse_root)
    best_model = max(
        sparse_models,
        key=lambda model: (
            model.registered_image_count,
            model.point_count,
            model.camera_count,
        ),
    )

    if best_model.registered_image_count <= 0:
        logging.error(
            "COLMAP mapper did not produce a usable sparse model in `%s`.",
            sparse_root,
        )
        raise SystemExit(1)

    logging.info(
        "Selected COLMAP sparse model `%s` for undistortion (registered_images=%s, points=%s).",
        best_model.path.name,
        best_model.registered_image_count,
        best_model.point_count,
    )
    return best_model


def list_media_files(directory: Path, extensions: Set[str]) -> List[Path]:
    return sorted(
        path for path in directory.iterdir() if path.is_file() and path.suffix.lower() in extensions
    )


def find_named_directories(root: Path, directory_name: str) -> List[Path]:
    return sorted(
        path for path in root.rglob("*") if path.is_dir() and path.name.lower() == directory_name.lower()
    )


def discover_video_files(video_source: Path) -> Tuple[List[Path], str]:
    # 先保留旧行为: 如果目录根下就有视频,直接使用.
    direct_videos = list_media_files(video_source, VIDEO_EXTENSIONS)
    if direct_videos:
        return direct_videos, "direct"

    # 你的真实数据是 `<root>/<index>/rgb/*.mp4`.
    # 因此优先递归收集名为 `rgb` 的目录,避免把 `debug` 等目录也扫进来.
    rgb_videos: List[Path] = []
    for rgb_directory in find_named_directories(video_source, "rgb"):
        rgb_videos.extend(list_media_files(rgb_directory, VIDEO_EXTENSIONS))

    if rgb_videos:
        return sorted(rgb_videos), "rgb_recursive"

    # VerseCrafter / 多视角生成视频常见布局:
    # `<root>/<view_id>/generated_videos/*.mp4`
    # 这里必须先于全局递归, 否则会把 rendering_4D_maps 里的辅助视频一起扫进去.
    generated_videos: List[Path] = []
    for generated_directory in find_named_directories(video_source, "generated_videos"):
        generated_videos.extend(list_media_files(generated_directory, VIDEO_EXTENSIONS))

    if generated_videos:
        return sorted(generated_videos), "generated_videos_recursive"

    # 最后再做全局递归兜底,兼容其他未来目录布局.
    recursive_videos = sorted(
        path for path in video_source.rglob("*") if path.is_file() and path.suffix.lower() in VIDEO_EXTENSIONS
    )
    if recursive_videos:
        return recursive_videos, "recursive"

    return [], "missing"


def build_frame_prefix(video_source: Path, video_path: Path, index: int) -> str:
    try:
        relative_video = video_path.relative_to(video_source).with_suffix("")
        prefix_parts = [sanitize_stem(part) for part in relative_video.parts]
    except ValueError:
        prefix_parts = [sanitize_stem(video_path.stem)]

    compact_parts = [part for part in prefix_parts if part]
    compact_prefix = "_".join(compact_parts[-4:])
    return f"{index:03d}_{compact_prefix or 'video'}"


def sanitize_stem(file_stem: str) -> str:
    safe_chars = []
    for char in file_stem:
        if char.isalnum() or char in {"-", "_"}:
            safe_chars.append(char)
        else:
            safe_chars.append("_")

    safe_stem = "".join(safe_chars).strip("_")
    return safe_stem or "video"


def build_video_extraction_plans(
    video_source: Path,
    videos: Sequence[Path],
) -> List[VideoExtractionPlan]:
    plans: List[VideoExtractionPlan] = []

    for index, video_path in enumerate(videos, start=1):
        # 这里只为 RGB 视频生成稳定帧名前缀.
        # `merged_mask.mp4` 当前已确认是深度链路辅助数据, 不能在这里转成训练 mask.
        plans.append(
            VideoExtractionPlan(
                video_path=video_path,
                frame_prefix=build_frame_prefix(video_source, video_path, index),
            )
        )

    return plans


def build_ffmpeg_video_filter(video_fps: float, video_frame_step: int) -> str:
    if video_frame_step > 0:
        return f"select=not(mod(n\\,{video_frame_step})),setpts=N/FRAME_RATE/TB"

    return f"fps={video_fps}"


def build_matcher_subcommand(matcher: str) -> str:
    return f"{matcher}_matcher"


def build_interleaved_frame_name(frame_index: int, view_index: int, frame_prefix: str) -> str:
    return f"frame_{frame_index:06d}_view_{view_index:03d}_{frame_prefix}.jpg"


def reorder_extracted_frames_interleaved(
    temporary_root: Path,
    input_path: Path,
    extraction_plans: Sequence[VideoExtractionPlan],
) -> int:
    extracted_frame_sets: List[List[Path]] = []
    for plan in extraction_plans:
        view_dir = temporary_root / plan.frame_prefix
        frame_paths = sorted(path for path in view_dir.iterdir() if path.is_file())
        if not frame_paths:
            continue
        extracted_frame_sets.append(frame_paths)

    if not extracted_frame_sets:
        return 0

    max_frame_count = max(len(frame_paths) for frame_paths in extracted_frame_sets)
    written_count = 0
    for frame_index in range(max_frame_count):
        for view_index, frame_paths in enumerate(extracted_frame_sets, start=1):
            if frame_index >= len(frame_paths):
                continue

            source_path = frame_paths[frame_index]
            destination_name = build_interleaved_frame_name(
                frame_index=frame_index + 1,
                view_index=view_index,
                frame_prefix=source_path.parent.name,
            )
            shutil.move(str(source_path), str(input_path / destination_name))
            written_count += 1

    return written_count


def remove_path(path: Path) -> None:
    if not path.exists():
        return

    if path.is_dir():
        shutil.rmtree(path)
    else:
        path.unlink()


def rename_files_to_contiguous_numeric_sequence(directory: Path) -> int:
    file_paths = sorted(path for path in directory.iterdir() if path.is_file())
    if not file_paths:
        return 0

    staged_paths = []
    for index, source_path in enumerate(file_paths, start=1):
        staged_path = directory / f".tmp_numeric_rename_{index:06d}{source_path.suffix.lower()}"
        source_path.rename(staged_path)
        staged_paths.append(staged_path)

    for index, staged_path in enumerate(staged_paths, start=1):
        destination_path = directory / f"{index:06d}{staged_path.suffix.lower()}"
        staged_path.rename(destination_path)

    return len(staged_paths)


def cleanup_generated_outputs(source_path: Path, include_input: bool) -> None:
    generated_paths = [
        source_path / "distorted",
        source_path / "images",
        source_path / "masks",
        source_path / "sparse",
        source_path / "images_2",
        source_path / "images_4",
        source_path / "images_8",
    ]

    if include_input:
        generated_paths.append(source_path / "input")

    for path in generated_paths:
        remove_path(path)


def detect_video_source(source_path: Path, explicit_video_path: str) -> Optional[Path]:
    if explicit_video_path:
        video_path = Path(explicit_video_path).expanduser()
        if not video_path.is_dir():
            logging.error("`--video_path` does not exist or is not a directory: %s", video_path)
            raise SystemExit(1)
        return video_path

    input_path = source_path / "input"
    if input_path.is_dir() and any(input_path.iterdir()):
        return None

    videos, _ = discover_video_files(source_path)
    if videos:
        return source_path

    return None


def prepare_input_directory(
    source_path: Path,
    video_source: Optional[Path],
    ffmpeg_command: str,
    video_fps: float,
    video_frame_step: int,
    video_naming: str,
    overwrite: bool,
    final_image_naming: str = "preserve",
) -> Path:
    input_path = source_path / "input"

    # 图片模式沿用旧结构: `<source_path>/input`.
    if video_source is None:
        if not input_path.is_dir():
            logging.error(
                "Could not find `%s`. Provide a scene root with an `input` directory, or use `--video_path`.",
                input_path,
            )
            raise SystemExit(1)
        if not any(input_path.iterdir()):
            logging.error(
                "`%s` is empty. Put source images there, or use `--video_path` to extract frames from videos.",
                input_path,
            )
            raise SystemExit(1)
        return input_path

    videos, discovery_mode = discover_video_files(video_source)
    if not videos:
        logging.error("No supported video files were found in: %s", video_source)
        raise SystemExit(1)

    extraction_plans = build_video_extraction_plans(video_source, videos)

    logging.info(
        "Discovered %s video(s) in `%s` using `%s` mode.",
        len(videos),
        video_source,
        discovery_mode,
    )

    # 视频模式默认抽帧到 `<source_path>/input`.
    # 如果该目录已经有内容,默认报错而不是静默混用旧帧,避免把两批素材搅在一起.
    if input_path.exists():
        has_existing_files = any(input_path.iterdir())
        if has_existing_files and not overwrite:
            logging.error(
                "`%s` already contains files. Use `--overwrite` to regenerate frames from videos.",
                input_path,
            )
            raise SystemExit(1)

        if overwrite:
            remove_path(input_path)

    input_path.mkdir(parents=True, exist_ok=True)

    temporary_root_context = tempfile.TemporaryDirectory(dir=input_path) if video_naming == "interleaved" else None
    temporary_root = Path(temporary_root_context.name) if temporary_root_context else None
    try:
        for plan in extraction_plans:
            frame_prefix = plan.frame_prefix
            if temporary_root is None:
                frame_pattern = input_path / f"{frame_prefix}_%06d.jpg"
            else:
                per_view_dir = temporary_root / frame_prefix
                per_view_dir.mkdir(parents=True, exist_ok=True)
                frame_pattern = per_view_dir / "%06d.jpg"

            video_filter = build_ffmpeg_video_filter(video_fps, video_frame_step)
            run_command(
                [
                    ffmpeg_command,
                    "-y",
                    "-i",
                    str(plan.video_path),
                    "-vf",
                    video_filter,
                    "-q:v",
                    "2",
                    str(frame_pattern),
                ],
                f"frame extraction for {plan.video_path.name}",
            )

        if temporary_root is not None:
            written_count = reorder_extracted_frames_interleaved(
                temporary_root=temporary_root,
                input_path=input_path,
                extraction_plans=extraction_plans,
            )
            logging.info("Reordered %s extracted frame(s) into interleaved naming.", written_count)

        if final_image_naming == "numeric":
            renamed_count = rename_files_to_contiguous_numeric_sequence(input_path)
            logging.info(
                "Renamed %s extracted frame(s) to contiguous numeric filenames.",
                renamed_count,
            )
    finally:
        if temporary_root_context is not None:
            temporary_root_context.cleanup()

    extracted_frames = [path for path in input_path.iterdir() if path.is_file()]
    if not extracted_frames:
        logging.error("No frames were extracted into `%s`.", input_path)
        raise SystemExit(1)

    logging.info("Extracted %s frames into %s", len(extracted_frames), input_path)
    return input_path


def move_sparse_outputs(source_path: Path) -> None:
    sparse_path = source_path / "sparse"
    sparse_zero_path = sparse_path / "0"
    sparse_zero_path.mkdir(parents=True, exist_ok=True)

    for source_file in sparse_path.iterdir():
        if source_file.name == "0":
            continue

        destination_file = sparse_zero_path / source_file.name
        if destination_file.exists():
            remove_path(destination_file)
        shutil.move(str(source_file), str(destination_file))


def resize_images(source_path: Path, magick_command: str) -> None:
    print("Copying and resizing...")

    resize_jobs = [
        ("images_2", "50%"),
        ("images_4", "25%"),
        ("images_8", "12.5%"),
    ]
    images_path = source_path / "images"
    image_files = [path for path in images_path.iterdir() if path.is_file()]

    for folder_name, scale in resize_jobs:
        destination_dir = source_path / folder_name
        destination_dir.mkdir(parents=True, exist_ok=True)

        for image_path in image_files:
            destination_file = destination_dir / image_path.name
            shutil.copy2(image_path, destination_file)
            run_command(
                [magick_command, "mogrify", "-resize", scale, str(destination_file)],
                f"resize {image_path.name} -> {folder_name}",
            )


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
    args = parse_args()

    if args.video_fps <= 0 and args.video_frame_step <= 0:
        logging.error("`--video_fps` must be greater than 0, got %s", args.video_fps)
        raise SystemExit(1)
    if args.video_frame_step < 0:
        logging.error("`--video_frame_step` must be >= 0, got %s", args.video_frame_step)
        raise SystemExit(1)

    source_path = Path(args.source_path).expanduser()
    source_path.mkdir(parents=True, exist_ok=True)

    colmap_command = args.colmap_executable or "colmap"
    ffmpeg_command = args.ffmpeg_executable or "ffmpeg"
    magick_command = args.magick_executable or "magick"
    use_gpu = 0 if args.no_gpu else 1
    colmap_gpu_index = args.colmap_gpu_index.strip()

    feature_use_gpu_option = "--SiftExtraction.use_gpu"
    feature_gpu_index_option = "--SiftExtraction.gpu_index"
    if command_supports_option(colmap_command, "feature_extractor", "--FeatureExtraction.use_gpu"):
        feature_use_gpu_option = "--FeatureExtraction.use_gpu"
        feature_gpu_index_option = "--FeatureExtraction.gpu_index"

    matching_use_gpu_option = "--SiftMatching.use_gpu"
    matching_gpu_index_option = "--SiftMatching.gpu_index"
    matcher_command = build_matcher_subcommand(args.matcher)
    if command_supports_option(colmap_command, matcher_command, "--FeatureMatching.use_gpu"):
        matching_use_gpu_option = "--FeatureMatching.use_gpu"
        matching_gpu_index_option = "--FeatureMatching.gpu_index"

    video_source = detect_video_source(source_path, args.video_path)
    if args.overwrite:
        cleanup_generated_outputs(source_path, include_input=video_source is not None)

    input_path = prepare_input_directory(
        source_path=source_path,
        video_source=video_source,
        ffmpeg_command=ffmpeg_command,
        video_fps=args.video_fps,
        video_frame_step=args.video_frame_step,
        video_naming=args.video_naming,
        overwrite=args.overwrite,
        final_image_naming=args.final_image_naming,
    )

    if not args.skip_matching:
        distorted_sparse_path = source_path / "distorted" / "sparse"
        distorted_sparse_path.mkdir(parents=True, exist_ok=True)

        # 这里保留原先 single_camera 的默认假设.
        # 对“同一镜头拍的一整套视频/图片”最稳,也和用户当前场景相符.
        run_command(
            [
                colmap_command,
                "feature_extractor",
                "--database_path",
                str(source_path / "distorted" / "database.db"),
                "--image_path",
                str(input_path),
                "--ImageReader.single_camera",
                "1",
                "--ImageReader.camera_model",
                args.camera,
                feature_use_gpu_option,
                str(use_gpu),
                *(
                    [
                        feature_gpu_index_option,
                        colmap_gpu_index,
                    ]
                    if use_gpu and colmap_gpu_index
                    else []
                ),
            ],
            "feature extraction",
        )

        run_command(
            [
                colmap_command,
                matcher_command,
                "--database_path",
                str(source_path / "distorted" / "database.db"),
                matching_use_gpu_option,
                str(use_gpu),
                *(
                    [
                        matching_gpu_index_option,
                        colmap_gpu_index,
                    ]
                    if use_gpu and colmap_gpu_index
                    else []
                ),
            ],
            "feature matching",
        )

        # 继续复用原脚本的 mapper 参数.
        # 这里只把命令调用改成更稳的 subprocess 列表形式.
        run_command(
            [
                colmap_command,
                "mapper",
                "--database_path",
                str(source_path / "distorted" / "database.db"),
                "--image_path",
                str(input_path),
                "--output_path",
                str(distorted_sparse_path),
                "--Mapper.ba_global_function_tolerance=0.000001",
            ],
            "mapper",
        )

    selected_sparse_model = select_best_sparse_model(source_path / "distorted" / "sparse")

    run_command(
        [
            colmap_command,
            "image_undistorter",
            "--image_path",
            str(input_path),
            "--input_path",
            str(selected_sparse_model.path),
            "--output_path",
            str(source_path),
            "--output_type",
            "COLMAP",
        ],
        "image undistortion",
    )

    move_sparse_outputs(source_path)

    if args.resize:
        resize_images(source_path, magick_command)

    print("Done.")


if __name__ == "__main__":
    main()

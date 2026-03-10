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
import subprocess
from argparse import ArgumentParser
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


def parse_args():
    parser = ArgumentParser("Colmap converter")
    parser.add_argument("--no_gpu", action="store_true")
    parser.add_argument("--skip_matching", action="store_true")
    parser.add_argument("--source_path", "-s", required=True, type=str)
    parser.add_argument("--camera", default="OPENCV", type=str)
    parser.add_argument("--colmap_executable", default="", type=str)
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


def remove_path(path: Path) -> None:
    if not path.exists():
        return

    if path.is_dir():
        shutil.rmtree(path)
    else:
        path.unlink()


def cleanup_generated_outputs(source_path: Path, include_input: bool) -> None:
    generated_paths = [
        source_path / "distorted",
        source_path / "images",
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
    overwrite: bool,
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

    for index, video_path in enumerate(videos, start=1):
        frame_prefix = build_frame_prefix(video_source, video_path, index)
        frame_pattern = input_path / f"{frame_prefix}_%06d.jpg"
        run_command(
            [
                ffmpeg_command,
                "-y",
                "-i",
                str(video_path),
                "-vf",
                f"fps={video_fps}",
                "-q:v",
                "2",
                str(frame_pattern),
            ],
            f"frame extraction for {video_path.name}",
        )

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

    if args.video_fps <= 0:
        logging.error("`--video_fps` must be greater than 0, got %s", args.video_fps)
        raise SystemExit(1)

    source_path = Path(args.source_path).expanduser()
    source_path.mkdir(parents=True, exist_ok=True)

    colmap_command = args.colmap_executable or "colmap"
    ffmpeg_command = args.ffmpeg_executable or "ffmpeg"
    magick_command = args.magick_executable or "magick"
    use_gpu = 0 if args.no_gpu else 1

    video_source = detect_video_source(source_path, args.video_path)
    if args.overwrite:
        cleanup_generated_outputs(source_path, include_input=video_source is not None)

    input_path = prepare_input_directory(
        source_path=source_path,
        video_source=video_source,
        ffmpeg_command=ffmpeg_command,
        video_fps=args.video_fps,
        overwrite=args.overwrite,
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
                "--SiftExtraction.use_gpu",
                str(use_gpu),
            ],
            "feature extraction",
        )

        run_command(
            [
                colmap_command,
                "exhaustive_matcher",
                "--database_path",
                str(source_path / "distorted" / "database.db"),
                "--SiftMatching.use_gpu",
                str(use_gpu),
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

    run_command(
        [
            colmap_command,
            "image_undistorter",
            "--image_path",
            str(input_path),
            "--input_path",
            str(source_path / "distorted" / "sparse" / "0"),
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

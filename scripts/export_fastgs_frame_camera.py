#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.util
import json
import math
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image


REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))


def load_colmap_loader_module():
    # Avoid importing `scene.__init__`, which pulls in training-only deps.
    module_path = REPO_ROOT / "scene" / "colmap_loader.py"
    spec = importlib.util.spec_from_file_location("colmap_loader_standalone", module_path)
    if spec is None or spec.loader is None:
        raise ImportError(f"Unable to load COLMAP loader module: {module_path}")

    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


COLMAP_LOADER = load_colmap_loader_module()
read_extrinsics_binary = COLMAP_LOADER.read_extrinsics_binary
read_intrinsics_binary = COLMAP_LOADER.read_intrinsics_binary


@dataclass(frozen=True)
class FrameSelection:
    parser_index: int
    image_id: int
    image_name: str
    image_path: Path
    width: int
    height: int
    camera_to_world: np.ndarray
    intrinsics: np.ndarray


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "从 FastGS/COLMAP 数据集导出单帧相机 JSON，"
            "字段对齐 FreeFix 的 *_camera_trajectory_unity.json。"
        )
    )
    parser.add_argument(
        "--data-dir",
        type=Path,
        required=True,
        help="FastGS 数据集根目录，例如 /autodl-fs/data/fastgs/nt1_sr",
    )
    parser.add_argument(
        "--image-name",
        type=str,
        default=None,
        help="要导出的图像名，例如 000001.jpg。默认导出排序后的第一张。",
    )
    parser.add_argument(
        "--image-index",
        type=int,
        default=0,
        help="按图像名排序后的 0-based 索引。默认 0，即第一张。",
    )
    parser.add_argument(
        "--images-dir",
        type=Path,
        default=None,
        help="显式指定图像目录。默认优先 data-dir/images，其次 data-dir/input。",
    )
    parser.add_argument(
        "--fps",
        type=float,
        default=1.0,
        help="写入 JSON 的 fps 元数据，默认 1.0。",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=None,
        help="基础 JSON 输出路径。默认写到 data-dir/<image>_camera_trajectory.json。",
    )
    parser.add_argument(
        "--unity-output",
        type=Path,
        default=None,
        help="Unity JSON 输出路径。默认自动生成 *_camera_trajectory_unity.json。",
    )
    return parser


def resolve_images_dir(data_dir: Path, images_dir: Path | None) -> Path:
    if images_dir is not None:
        resolved = images_dir.expanduser().resolve()
        if not resolved.is_dir():
            raise FileNotFoundError(f"图像目录不存在: {resolved}")
        return resolved

    for candidate in (data_dir / "images", data_dir / "input"):
        if candidate.is_dir():
            return candidate.resolve()

    raise FileNotFoundError(
        f"在 {data_dir} 下找不到 images/ 或 input/，请用 --images-dir 显式指定。"
    )


def resolve_output_path(data_dir: Path, image_name: str, output_path: Path | None) -> Path:
    if output_path is not None:
        resolved = output_path.expanduser().resolve()
    else:
        resolved = (data_dir / f"{Path(image_name).stem}_camera_trajectory.json").resolve()
    resolved.parent.mkdir(parents=True, exist_ok=True)
    return resolved


def resolve_unity_output_path(output_path: Path, unity_output_path: Path | None) -> Path:
    if unity_output_path is not None:
        resolved = unity_output_path.expanduser().resolve()
    elif output_path.stem.endswith("_camera_trajectory"):
        resolved = output_path.with_name(
            f"{output_path.stem.replace('_camera_trajectory', '_camera_trajectory_unity')}{output_path.suffix}"
        )
    else:
        resolved = output_path.with_name(f"{output_path.stem}_unity{output_path.suffix}")
    resolved.parent.mkdir(parents=True, exist_ok=True)
    return resolved


def flatten_row_major(matrix: list[list[float]]) -> list[float]:
    return [float(value) for row in matrix for value in row]


def flatten_column_major(matrix: list[list[float]]) -> list[float]:
    array = np.asarray(matrix, dtype=np.float64)
    return array.T.reshape(-1).astype(float).tolist()


def rotation_matrix_to_quaternion_xyzw(rotation: np.ndarray) -> list[float]:
    r = np.asarray(rotation, dtype=np.float64)
    trace = float(np.trace(r))

    if trace > 0.0:
        s = math.sqrt(trace + 1.0) * 2.0
        qw = 0.25 * s
        qx = (r[2, 1] - r[1, 2]) / s
        qy = (r[0, 2] - r[2, 0]) / s
        qz = (r[1, 0] - r[0, 1]) / s
    elif r[0, 0] > r[1, 1] and r[0, 0] > r[2, 2]:
        s = math.sqrt(1.0 + r[0, 0] - r[1, 1] - r[2, 2]) * 2.0
        qw = (r[2, 1] - r[1, 2]) / s
        qx = 0.25 * s
        qy = (r[0, 1] + r[1, 0]) / s
        qz = (r[0, 2] + r[2, 0]) / s
    elif r[1, 1] > r[2, 2]:
        s = math.sqrt(1.0 + r[1, 1] - r[0, 0] - r[2, 2]) * 2.0
        qw = (r[0, 2] - r[2, 0]) / s
        qx = (r[0, 1] + r[1, 0]) / s
        qy = 0.25 * s
        qz = (r[1, 2] + r[2, 1]) / s
    else:
        s = math.sqrt(1.0 + r[2, 2] - r[0, 0] - r[1, 1]) * 2.0
        qw = (r[1, 0] - r[0, 1]) / s
        qx = (r[0, 2] + r[2, 0]) / s
        qy = (r[1, 2] + r[2, 1]) / s
        qz = 0.25 * s

    quat = np.asarray([qx, qy, qz, qw], dtype=np.float64)
    quat /= np.linalg.norm(quat)
    return quat.astype(float).tolist()


def intrinsics_from_colmap_camera(camera: Any) -> np.ndarray:
    params = np.asarray(camera.params, dtype=np.float64)
    model = str(camera.model)

    if model in {
        "SIMPLE_PINHOLE",
        "SIMPLE_RADIAL",
        "SIMPLE_RADIAL_FISHEYE",
        "RADIAL",
        "RADIAL_FISHEYE",
        "FOV",
    }:
        fx = fy = float(params[0])
        cx = float(params[1])
        cy = float(params[2])
    elif model in {
        "PINHOLE",
        "OPENCV",
        "OPENCV_FISHEYE",
        "FULL_OPENCV",
        "THIN_PRISM_FISHEYE",
    }:
        fx = float(params[0])
        fy = float(params[1])
        cx = float(params[2])
        cy = float(params[3])
    else:
        raise ValueError(f"暂不支持的 COLMAP 相机模型: {model}")

    return np.array(
        [
            [fx, 0.0, cx],
            [0.0, fy, cy],
            [0.0, 0.0, 1.0],
        ],
        dtype=np.float64,
    )


def build_camera_to_world(image_record: Any) -> np.ndarray:
    rotation_wc = image_record.qvec2rotmat()
    rotation_cw = rotation_wc.T
    center = -rotation_cw @ np.asarray(image_record.tvec, dtype=np.float64)

    camera_to_world = np.eye(4, dtype=np.float64)
    camera_to_world[:3, :3] = rotation_cw
    camera_to_world[:3, 3] = center
    return camera_to_world


def select_frame(
    *,
    extrinsics: dict[int, Any],
    intrinsics: dict[int, Any],
    images_dir: Path,
    image_name: str | None,
    image_index: int,
) -> FrameSelection:
    image_items = sorted(extrinsics.items(), key=lambda item: str(item[1].name))
    if not image_items:
        raise ValueError("COLMAP 模型中没有已注册图像。")

    if image_name is not None:
        normalized = Path(image_name).name
        for parser_index, (image_id, image_record) in enumerate(image_items):
            if Path(image_record.name).name == normalized:
                selected_parser_index = parser_index
                selected_image_id = image_id
                selected_record = image_record
                break
        else:
            raise FileNotFoundError(f"在 COLMAP 注册图像中找不到: {normalized}")
    else:
        if image_index < 0 or image_index >= len(image_items):
            raise IndexError(
                f"image_index 越界: index={image_index}, image_count={len(image_items)}"
            )
        selected_parser_index = image_index
        selected_image_id, selected_record = image_items[image_index]

    selected_name = Path(selected_record.name).name
    image_path = (images_dir / selected_name).resolve()
    if not image_path.is_file():
        raise FileNotFoundError(f"图像文件不存在: {image_path}")

    with Image.open(image_path) as image_file:
        width, height = image_file.size

    camera = intrinsics[selected_record.camera_id]
    return FrameSelection(
        parser_index=selected_parser_index,
        image_id=selected_image_id,
        image_name=selected_name,
        image_path=image_path,
        width=width,
        height=height,
        camera_to_world=build_camera_to_world(selected_record),
        intrinsics=intrinsics_from_colmap_camera(camera),
    )


def build_frame_record(
    *,
    frame_index: int,
    dataset_index: int,
    parser_index: int,
    fps: float,
    image_name: str,
    image_path: str,
    image_size: tuple[int, int],
    intrinsics: np.ndarray,
    camera_to_world: np.ndarray,
) -> dict[str, Any]:
    rotation = camera_to_world[:3, :3]
    position = camera_to_world[:3, 3]
    quaternion_xyzw = rotation_matrix_to_quaternion_xyzw(rotation)
    quaternion_wxyz = [
        float(quaternion_xyzw[3]),
        float(quaternion_xyzw[0]),
        float(quaternion_xyzw[1]),
        float(quaternion_xyzw[2]),
    ]

    return {
        "frame_index": frame_index,
        "time_sec": frame_index / fps,
        "dataset_index": dataset_index,
        "parser_index": parser_index,
        "image_name": image_name,
        "image_path": image_path,
        "image_size": [int(image_size[0]), int(image_size[1])],
        "position": position.astype(np.float64).tolist(),
        "rotation_matrix": rotation.astype(np.float64).tolist(),
        "quaternion_xyzw": quaternion_xyzw,
        "quaternion_wxyz": quaternion_wxyz,
        "camera_to_world": camera_to_world.astype(np.float64).tolist(),
        "intrinsics": intrinsics.astype(np.float64).tolist(),
    }


def build_payload(
    *,
    data_dir: Path,
    output_path: Path,
    selected: FrameSelection,
    fps: float,
    selection_mode: str,
) -> dict[str, Any]:
    frame_record = build_frame_record(
        frame_index=0,
        dataset_index=0,
        parser_index=selected.parser_index,
        fps=fps,
        image_name=selected.image_name,
        image_path=str(selected.image_path),
        image_size=(selected.width, selected.height),
        intrinsics=selected.intrinsics,
        camera_to_world=selected.camera_to_world,
    )

    return {
        "schema_version": 1,
        "exporter": "scripts.export_fastgs_frame_camera",
        "trajectory_source": "fastgs_colmap_single_frame",
        "video": {
            "path": str(selected.image_path),
            "name": selected.image_name,
            "width": selected.width,
            "height": selected.height,
            "fps": float(fps),
            "frame_count": 1,
        },
        "refine": {
            "data_dir": str(data_dir),
            "image_select_mode": selection_mode,
            "selected_image_name": selected.image_name,
            "selected_image_id": selected.image_id,
            "selected_parser_index": selected.parser_index,
            "load_step": None,
        },
        "output": {
            "path": str(output_path),
        },
        "frames": [frame_record],
    }


def build_unity_payload(
    *,
    source_payload: dict[str, Any],
    unity_output_path: Path,
) -> dict[str, Any]:
    unity_frames = []
    for frame in source_payload["frames"]:
        unity_frames.append(
            {
                "frameIndex": frame["frame_index"],
                "timeSec": frame["time_sec"],
                "datasetIndex": frame["dataset_index"],
                "parserIndex": frame["parser_index"],
                "imageName": frame["image_name"],
                "imagePath": frame["image_path"],
                "imageSize": frame["image_size"],
                "position": frame["position"],
                "quaternionXyzw": frame["quaternion_xyzw"],
                "cameraToWorldRowMajor": flatten_row_major(frame["camera_to_world"]),
                "cameraToWorldColumnMajor": flatten_column_major(frame["camera_to_world"]),
                "intrinsicsRowMajor": flatten_row_major(frame["intrinsics"]),
            }
        )

    return {
        "schemaVersion": 1,
        "exporter": "scripts.export_fastgs_frame_camera",
        "sourceJson": source_payload["output"]["path"],
        "outputPath": str(unity_output_path),
        "coordinateSpace": "colmap_world",
        "axisConversionApplied": False,
        "note": (
            "This Unity payload keeps the original COLMAP world space. "
            "Use it when your Unity scene uses the same imported geometry space."
        ),
        "video": source_payload["video"],
        "refine": source_payload["refine"],
        "frames": unity_frames,
    }


def main() -> None:
    args = build_arg_parser().parse_args()

    data_dir = args.data_dir.expanduser().resolve()
    images_dir = resolve_images_dir(data_dir, args.images_dir)
    sparse_dir = (data_dir / "sparse" / "0").resolve()
    images_bin = sparse_dir / "images.bin"
    cameras_bin = sparse_dir / "cameras.bin"

    if not images_bin.is_file():
        raise FileNotFoundError(f"找不到 COLMAP images.bin: {images_bin}")
    if not cameras_bin.is_file():
        raise FileNotFoundError(f"找不到 COLMAP cameras.bin: {cameras_bin}")
    if args.fps <= 0:
        raise ValueError(f"fps 必须大于 0，当前为 {args.fps}")

    extrinsics = read_extrinsics_binary(images_bin)
    intrinsics = read_intrinsics_binary(cameras_bin)
    selected = select_frame(
        extrinsics=extrinsics,
        intrinsics=intrinsics,
        images_dir=images_dir,
        image_name=args.image_name,
        image_index=args.image_index,
    )

    output_path = resolve_output_path(data_dir, selected.image_name, args.output)
    unity_output_path = resolve_unity_output_path(output_path, args.unity_output)
    source_payload = build_payload(
        data_dir=data_dir,
        output_path=output_path,
        selected=selected,
        fps=float(args.fps),
        selection_mode="explicit_name" if args.image_name is not None else "sorted_index",
    )
    unity_payload = build_unity_payload(
        source_payload=source_payload,
        unity_output_path=unity_output_path,
    )

    output_path.write_text(
        json.dumps(source_payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    unity_output_path.write_text(
        json.dumps(unity_payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    print(f"Exported source JSON: {output_path}")
    print(f"Exported Unity JSON: {unity_output_path}")
    print(f"Selected image: {selected.image_name}")
    print(f"Parser index: {selected.parser_index}")
    print(f"Image size: {selected.width}x{selected.height}")
    print(f"Position: {source_payload['frames'][0]['position']}")
    print(f"Quaternion xyzw: {source_payload['frames'][0]['quaternion_xyzw']}")


if __name__ == "__main__":
    main()

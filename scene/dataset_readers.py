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

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import NamedTuple

from PIL import Image, ImageChops
from scene.colmap_loader import read_extrinsics_text, read_intrinsics_text, qvec2rotmat, \
    read_extrinsics_binary, read_intrinsics_binary, read_points3D_binary, read_points3D_text
from utils.graphics_utils import getWorld2View2, focal2fov, fov2focal
import numpy as np
from plyfile import PlyData, PlyElement
from utils.sh_utils import SH2RGB
from scene.gaussian_model import BasicPointCloud

class CameraInfo(NamedTuple):
    uid: int
    R: np.array
    T: np.array
    FovY: np.array
    FovX: np.array
    image: np.array
    image_path: str
    image_name: str
    width: int
    height: int

class SceneInfo(NamedTuple):
    point_cloud: BasicPointCloud
    train_cameras: list
    test_cameras: list
    nerf_normalization: dict
    ply_path: str


class LyraViewAsset(NamedTuple):
    view_id: str
    scene_stem: str
    pose_path: Path
    intrinsics_path: Path
    rgb_path: Path


LYRA_VIDEO_EXTENSIONS = {".mp4", ".mov", ".avi", ".mkv", ".m4v", ".webm"}
MASK_IMAGE_EXTENSIONS = (".png", ".jpg", ".jpeg", ".webp", ".bmp", ".tif", ".tiff")
LYRA_CACHE_ROOT = ".fastgs_cache/lyra_generated"
LYRA_POINT_CLOUD_METADATA_NAME = "points3d_metadata.json"
LYRA_POINT_CLOUD_GENERATOR = "focus_center_v1"
LYRA_POINT_CLOUD_EXTENT_RATIO = 0.25
LYRA_POINT_CLOUD_MIN_EXTENT = 0.25
LYRA_POINT_CLOUD_RANDOM_SEED = 0

def getNerfppNorm(cam_info):
    def get_center_and_diag(cam_centers):
        cam_centers = np.hstack(cam_centers)
        avg_cam_center = np.mean(cam_centers, axis=1, keepdims=True)
        center = avg_cam_center
        dist = np.linalg.norm(cam_centers - center, axis=0, keepdims=True)
        diagonal = np.max(dist)
        return center.flatten(), diagonal

    cam_centers = []

    for cam in cam_info:
        W2C = getWorld2View2(cam.R, cam.T)
        C2W = np.linalg.inv(W2C)
        cam_centers.append(C2W[:3, 3:4])

    center, diagonal = get_center_and_diag(cam_centers)
    radius = diagonal * 1.1

    translate = -center

    return {"translate": translate, "radius": radius}

def _resolve_mask_root(scene_root, mask_dir):
    """解析 mask 根目录.

    规则尽量简单:
    - 显式传了 `mask_dir` 时,相对路径按 `scene_root` 解释.
    - 未显式传参时,若 `<scene_root>/masks` 存在, 自动启用.
    - 否则返回 `None`, 表示当前场景不使用 mask.
    """

    if mask_dir:
        candidate = Path(mask_dir).expanduser()
        if not candidate.is_absolute():
            candidate = Path(scene_root) / candidate
        candidate = candidate.resolve()
        if not candidate.is_dir():
            raise FileNotFoundError(f"Mask directory does not exist: {candidate}")
        return candidate

    auto_candidate = (Path(scene_root) / "masks").resolve()
    if auto_candidate.is_dir():
        return auto_candidate

    return None


def _find_mask_path(image_path, mask_root):
    """按 basename 为训练图匹配 mask 文件.

    允许 mask 扩展名与原图不同, 这样用户可以统一输出成 png.
    一旦启用 mask 目录, 默认要求每张训练图都能找到对应 mask.
    """

    if mask_root is None:
        return None

    image_path = Path(image_path)
    exact_match = mask_root / image_path.name
    if exact_match.is_file():
        return exact_match

    for extension in MASK_IMAGE_EXTENSIONS:
        candidate = mask_root / f"{image_path.stem}{extension}"
        if candidate.is_file():
            return candidate

    raise FileNotFoundError(f"Missing mask for image: {image_path.name} in {mask_root}")


def _load_training_image_with_optional_mask(image_path, mask_root):
    """读取训练图, 并在需要时把独立 mask 合并到 alpha 通道."""

    image_path = Path(image_path)
    with Image.open(image_path) as image_file:
        rgba_image = image_file.convert("RGBA")

    if mask_root is None:
        return rgba_image

    mask_path = _find_mask_path(image_path, mask_root)
    with Image.open(mask_path) as mask_file:
        mask = mask_file.convert("L")

    if mask.size != rgba_image.size:
        raise ValueError(
            f"Mask size mismatch for {image_path.name}: image={rgba_image.size}, mask={mask.size}"
        )

    # 如果原图已有 alpha, 这里保留“原 alpha 与外部 mask”的交集.
    combined_alpha = ImageChops.multiply(rgba_image.getchannel("A"), mask)
    red, green, blue, _ = rgba_image.split()
    return Image.merge("RGBA", (red, green, blue, combined_alpha))


def readColmapCameras(cam_extrinsics, cam_intrinsics, images_folder, mask_root=None):
    cam_infos = []
    for idx, key in enumerate(cam_extrinsics):
        sys.stdout.write('\r')
        # the exact output you're looking for:
        sys.stdout.write("Reading camera {}/{}".format(idx+1, len(cam_extrinsics)))
        sys.stdout.flush()

        extr = cam_extrinsics[key]
        intr = cam_intrinsics[extr.camera_id]
        height = intr.height
        width = intr.width

        uid = intr.id
        R = np.transpose(qvec2rotmat(extr.qvec))
        T = np.array(extr.tvec)

        if intr.model=="SIMPLE_PINHOLE":
            focal_length_x = intr.params[0]
            FovY = focal2fov(focal_length_x, height)
            FovX = focal2fov(focal_length_x, width)
        elif intr.model=="PINHOLE":
            focal_length_x = intr.params[0]
            focal_length_y = intr.params[1]
            FovY = focal2fov(focal_length_y, height)
            FovX = focal2fov(focal_length_x, width)
        else:
            assert False, "Colmap camera model not handled: only undistorted datasets (PINHOLE or SIMPLE_PINHOLE cameras) supported!"

        image_path = os.path.join(images_folder, os.path.basename(extr.name))
        image_name = os.path.basename(image_path).split(".")[0]
        image = _load_training_image_with_optional_mask(image_path, mask_root)

        cam_info = CameraInfo(uid=uid, R=R, T=T, FovY=FovY, FovX=FovX, image=image,
                              image_path=image_path, image_name=image_name, width=width, height=height)
        cam_infos.append(cam_info)
    sys.stdout.write('\n')
    return cam_infos

def fetchPly(path):
    plydata = PlyData.read(path)
    vertices = plydata['vertex']
    positions = np.vstack([vertices['x'], vertices['y'], vertices['z']]).T
    colors = np.vstack([vertices['red'], vertices['green'], vertices['blue']]).T / 255.0
    normals = np.vstack([vertices['nx'], vertices['ny'], vertices['nz']]).T
    return BasicPointCloud(points=positions, colors=colors, normals=normals)

def storePly(path, xyz, rgb):
    # Define the dtype for the structured array
    dtype = [('x', 'f4'), ('y', 'f4'), ('z', 'f4'),
            ('nx', 'f4'), ('ny', 'f4'), ('nz', 'f4'),
            ('red', 'u1'), ('green', 'u1'), ('blue', 'u1')]
    
    normals = np.zeros_like(xyz)

    elements = np.empty(xyz.shape[0], dtype=dtype)
    attributes = np.concatenate((xyz, normals, rgb), axis=1)
    elements[:] = list(map(tuple, attributes))

    # Create the PlyData object and write to file
    vertex_element = PlyElement.describe(elements, 'vertex')
    ply_data = PlyData([vertex_element])
    ply_data.write(path)


def generateRandomPointCloud(ply_path, num_pts=100_000, extent=1.3, center=None, seed=None):
    # 统一保留“随机点云初始化”这一条主路径,避免 synthetic 与 direct loader 各自维护一套逻辑.
    # 当调用方提供 center 时,点云会围绕该中心采样; 否则默认仍以原点为中心,兼容旧行为.
    ply_path = Path(ply_path)
    ply_path.parent.mkdir(parents=True, exist_ok=True)

    if center is None:
        center = np.zeros(3, dtype=np.float32)
    else:
        center = np.asarray(center, dtype=np.float32)
        if center.shape != (3,):
            raise ValueError(f"Point cloud center must have shape [3], got {center.shape}")

    if seed is None:
        random_xyz = np.random.random((num_pts, 3))
        random_shs = np.random.random((num_pts, 3))
    else:
        rng = np.random.default_rng(seed)
        random_xyz = rng.random((num_pts, 3))
        random_shs = rng.random((num_pts, 3))

    xyz = random_xyz * (2.0 * extent) - extent
    xyz = xyz.astype(np.float32) + center[None, :]
    shs = random_shs.astype(np.float32) / 255.0
    pcd = BasicPointCloud(points=xyz, colors=SH2RGB(shs), normals=np.zeros((num_pts, 3)))

    storePly(str(ply_path), xyz, SH2RGB(shs) * 255)
    return pcd


def _split_train_test_cameras(cam_infos, eval, llffhold=8):
    if eval:
        train_cam_infos = [c for idx, c in enumerate(cam_infos) if idx % llffhold != 0]
        test_cam_infos = [c for idx, c in enumerate(cam_infos) if idx % llffhold == 0]
    else:
        train_cam_infos = cam_infos
        test_cam_infos = []
    return train_cam_infos, test_cam_infos


def _load_npz_named_array(npz_path: Path, tensor_name: str):
    with np.load(npz_path, allow_pickle=False) as payload:
        if "data" not in payload or "inds" not in payload:
            raise ValueError(f"{tensor_name} npz must contain `data` and `inds`: {npz_path}")
        return np.asarray(payload["data"], dtype=np.float32), np.asarray(payload["inds"], dtype=np.int64)


def _discover_lyra_view_dirs(root: Path):
    view_dirs = []
    for candidate in sorted(root.iterdir()):
        if not candidate.is_dir():
            continue
        if (candidate / "pose").is_dir() and (candidate / "intrinsics").is_dir() and (candidate / "rgb").is_dir():
            view_dirs.append(candidate)
    return view_dirs


def _build_stem_map(directory: Path, suffixes):
    stem_map = {}
    for candidate in sorted(directory.iterdir()):
        if candidate.is_file() and candidate.suffix.lower() in suffixes:
            stem_map[candidate.stem] = candidate
    return stem_map


def discoverLyraGeneratedAssets(root_path):
    root = Path(root_path)
    if not root.is_dir():
        raise ValueError(f"Lyra generated root does not exist: {root}")

    view_dirs = _discover_lyra_view_dirs(root)
    if not view_dirs:
        raise ValueError(f"No Lyra view directories were found under: {root}")

    common_scene_stems = None
    per_view_asset_maps = {}
    for view_dir in view_dirs:
        pose_map = _build_stem_map(view_dir / "pose", {".npz"})
        intrinsics_map = _build_stem_map(view_dir / "intrinsics", {".npz"})
        rgb_map = _build_stem_map(view_dir / "rgb", LYRA_VIDEO_EXTENSIONS)

        shared_stems = set(pose_map.keys()) & set(intrinsics_map.keys()) & set(rgb_map.keys())
        if not shared_stems:
            raise RuntimeError(
                f"View `{view_dir.name}` does not contain a common scene stem across pose/intrinsics/rgb."
            )

        per_view_asset_maps[view_dir.name] = (pose_map, intrinsics_map, rgb_map)
        common_scene_stems = shared_stems if common_scene_stems is None else (common_scene_stems & shared_stems)

    if not common_scene_stems:
        raise RuntimeError(
            f"No common scene stem exists across all Lyra views under `{root}`."
        )

    if len(common_scene_stems) != 1:
        available_stems = ", ".join(sorted(common_scene_stems))
        raise RuntimeError(
            "Lyra generated root contains multiple shared scene stems. "
            f"Please keep one scene per root for FastGS direct loading. Found: {available_stems}"
        )

    scene_stem = sorted(common_scene_stems)[0]
    view_assets = []
    for view_id in sorted(per_view_asset_maps.keys()):
        pose_map, intrinsics_map, rgb_map = per_view_asset_maps[view_id]
        view_assets.append(
            LyraViewAsset(
                view_id=view_id,
                scene_stem=scene_stem,
                pose_path=pose_map[scene_stem],
                intrinsics_path=intrinsics_map[scene_stem],
                rgb_path=rgb_map[scene_stem],
            )
        )

    return scene_stem, view_assets


def isLyraGeneratedSceneRoot(root_path):
    try:
        _, view_assets = discoverLyraGeneratedAssets(root_path)
    except (ValueError, RuntimeError):
        return False
    return len(view_assets) > 0


def _lyra_cache_dir(root: Path, scene_stem: str, view_id: str):
    return root / LYRA_CACHE_ROOT / scene_stem / view_id


def _lyra_cache_metadata(video_path: Path, expected_frame_count: int):
    video_stat = video_path.stat()
    return {
        "source_path": str(video_path.resolve()),
        "source_size": int(video_stat.st_size),
        "source_mtime_ns": int(video_stat.st_mtime_ns),
        "expected_frame_count": int(expected_frame_count),
    }


def _lyra_cache_is_valid(cache_dir: Path, video_path: Path, expected_frame_count: int):
    metadata_path = cache_dir / "metadata.json"
    if not metadata_path.is_file():
        return False

    try:
        current_metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return False

    if current_metadata != _lyra_cache_metadata(video_path, expected_frame_count):
        return False

    return all((cache_dir / f"{frame_idx:05d}.png").is_file() for frame_idx in range(expected_frame_count))


def _extract_lyra_video_frames(video_path: Path, cache_dir: Path, expected_frame_count: int):
    ffmpeg_executable = shutil.which("ffmpeg")
    if ffmpeg_executable is None:
        raise RuntimeError(
            "Direct Lyra loading requires `ffmpeg` to extract RGB frames, but `ffmpeg` was not found in PATH."
        )

    cache_dir.mkdir(parents=True, exist_ok=True)
    for stale_png in cache_dir.glob("*.png"):
        stale_png.unlink()

    output_pattern = cache_dir / "%05d.png"
    command = [
        ffmpeg_executable,
        "-hide_banner",
        "-loglevel",
        "error",
        "-y",
        "-i",
        str(video_path),
        "-start_number",
        "0",
        str(output_pattern),
    ]

    try:
        subprocess.run(command, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    except subprocess.CalledProcessError as exc:
        raise RuntimeError(
            f"ffmpeg failed while extracting `{video_path}`: {exc.stderr.strip() or exc}"
        ) from exc

    extracted_frames = sorted(cache_dir.glob("*.png"))
    if len(extracted_frames) != expected_frame_count:
        raise RuntimeError(
            f"Extracted frame cache for `{video_path}` is incomplete under `{cache_dir}`: "
            f"expected {expected_frame_count}, got {len(extracted_frames)}."
        )


def _ensure_lyra_frame_cache(root: Path, scene_stem: str, view_asset: LyraViewAsset, expected_frame_count: int):
    cache_dir = _lyra_cache_dir(root, scene_stem, view_asset.view_id)
    if not _lyra_cache_is_valid(cache_dir, view_asset.rgb_path, expected_frame_count):
        _extract_lyra_video_frames(view_asset.rgb_path, cache_dir, expected_frame_count)
        metadata = _lyra_cache_metadata(view_asset.rgb_path, expected_frame_count)
        (cache_dir / "metadata.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    return cache_dir


def _recover_camera_center_and_forward(cam_info: CameraInfo):
    # CameraInfo 内部存的是 FastGS 训练口径下的 R/T.
    # 这里统一反推回 c2w, 这样 Lyra 初始化与训练读入使用的是同一份几何解释.
    w2c = getWorld2View2(cam_info.R, cam_info.T)
    c2w = np.linalg.inv(w2c)
    center = np.asarray(c2w[:3, 3], dtype=np.float64)
    forward = np.asarray(c2w[:3, 2], dtype=np.float64)
    forward_norm = np.linalg.norm(forward)
    if forward_norm <= 1e-8:
        raise ValueError(f"Camera `{cam_info.image_name}` has an invalid forward direction.")
    return center, forward / forward_norm


def _estimate_focus_centered_point_cloud(cam_infos):
    if not cam_infos:
        raise ValueError("Lyra point cloud initialization requires at least one training camera.")

    system = np.zeros((3, 3), dtype=np.float64)
    rhs = np.zeros(3, dtype=np.float64)
    camera_centers = []

    for cam_info in cam_infos:
        camera_center, forward = _recover_camera_center_and_forward(cam_info)
        camera_centers.append(camera_center)

        # 对每条视线构造垂直投影矩阵,累加后求“离所有视线都最近”的公共注视点.
        # 正常情况下 solve 即可; 若几何退化导致矩阵奇异,再回退到 lstsq 保持 loader 可用.
        projection = np.eye(3, dtype=np.float64) - np.outer(forward, forward)
        system += projection
        rhs += projection @ camera_center

    try:
        focus_center = np.linalg.solve(system, rhs)
    except np.linalg.LinAlgError:
        focus_center, _, _, _ = np.linalg.lstsq(system, rhs, rcond=None)

    if not np.all(np.isfinite(focus_center)):
        raise ValueError("Failed to estimate a finite shared focus point for Lyra cameras.")

    camera_centers = np.asarray(camera_centers, dtype=np.float64)
    focus_distances = np.linalg.norm(camera_centers - focus_center[None, :], axis=1)
    finite_distances = focus_distances[np.isfinite(focus_distances)]
    if finite_distances.size == 0:
        raise ValueError("Failed to estimate camera-to-focus distances for Lyra point cloud initialization.")

    extent = max(LYRA_POINT_CLOUD_MIN_EXTENT, float(np.median(finite_distances) * LYRA_POINT_CLOUD_EXTENT_RATIO))
    return np.asarray(focus_center, dtype=np.float32), extent


def _lyra_point_cloud_metadata(scene_stem: str, point_cloud_center, extent: float, num_pts: int):
    rounded_center = [round(float(value), 8) for value in np.asarray(point_cloud_center, dtype=np.float64).tolist()]
    return {
        "generator": LYRA_POINT_CLOUD_GENERATOR,
        "scene_stem": scene_stem,
        "num_points": int(num_pts),
        "center": rounded_center,
        "extent": round(float(extent), 8),
        "seed": LYRA_POINT_CLOUD_RANDOM_SEED,
    }


def _ensure_lyra_point_cloud(root: Path, scene_stem: str, cam_infos, num_pts=100_000):
    scene_cache_dir = root / LYRA_CACHE_ROOT / scene_stem
    ply_path = scene_cache_dir / "points3d.ply"
    metadata_path = scene_cache_dir / LYRA_POINT_CLOUD_METADATA_NAME

    point_cloud_center, point_cloud_extent = _estimate_focus_centered_point_cloud(cam_infos)
    expected_metadata = _lyra_point_cloud_metadata(
        scene_stem=scene_stem,
        point_cloud_center=point_cloud_center,
        extent=point_cloud_extent,
        num_pts=num_pts,
    )

    cached_metadata = None
    if metadata_path.is_file():
        try:
            cached_metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            cached_metadata = None

    if (not ply_path.is_file()) or (cached_metadata != expected_metadata):
        # 旧版 direct loader 已经在这里生成过“围绕原点”的错误缓存.
        # 现在用元数据做版本检查,确保升级后能自动重建到正确位置.
        print(f"Generating focus-centered point cloud ({num_pts}) for Lyra generated scene `{scene_stem}`...")
        generateRandomPointCloud(
            ply_path=ply_path,
            num_pts=num_pts,
            extent=point_cloud_extent,
            center=point_cloud_center,
            seed=LYRA_POINT_CLOUD_RANDOM_SEED,
        )
        metadata_path.write_text(json.dumps(expected_metadata, indent=2), encoding="utf-8")

    return ply_path


def _build_lyra_camera_infos(root: Path, view_assets):
    cam_infos = []

    for view_asset in view_assets:
        pose_data, pose_inds = _load_npz_named_array(view_asset.pose_path, "pose")
        intrinsics_data, intrinsics_inds = _load_npz_named_array(view_asset.intrinsics_path, "intrinsics")

        if pose_data.ndim != 3 or pose_data.shape[-2:] != (4, 4):
            raise ValueError(f"pose data must have shape [T, 4, 4], got {pose_data.shape} from {view_asset.pose_path}")

        if intrinsics_data.ndim != 2 or intrinsics_data.shape[-1] != 4:
            raise ValueError(
                f"intrinsics data must have shape [T, 4], got {intrinsics_data.shape} from {view_asset.intrinsics_path}"
            )

        if pose_data.shape[0] != intrinsics_data.shape[0]:
            raise ValueError(
                f"pose/intrinsics length mismatch for view `{view_asset.view_id}`: "
                f"{pose_data.shape[0]} vs {intrinsics_data.shape[0]}"
            )

        if pose_inds.shape != intrinsics_inds.shape or not np.array_equal(pose_inds, intrinsics_inds):
            raise ValueError(
                f"pose/intrinsics frame indices mismatch for view `{view_asset.view_id}`."
            )

        expected_frame_count = int(np.max(pose_inds)) + 1 if pose_inds.size > 0 else 0
        cache_dir = _ensure_lyra_frame_cache(root, view_asset.scene_stem, view_asset, expected_frame_count)

        for pose_idx, frame_idx in enumerate(pose_inds.tolist()):
            image_path = cache_dir / f"{int(frame_idx):05d}.png"
            if not image_path.is_file():
                raise FileNotFoundError(
                    f"Cached frame is missing for view `{view_asset.view_id}`, frame `{frame_idx}`: {image_path}"
                )

            c2w = pose_data[pose_idx]
            w2c = np.linalg.inv(c2w)
            rotation = np.transpose(w2c[:3, :3])
            translation = np.array(w2c[:3, 3])

            fx, fy, cx, cy = intrinsics_data[pose_idx]
            with Image.open(image_path) as image_file:
                image = image_file.copy()
            width, height = image.size

            cam_infos.append(
                CameraInfo(
                    uid=len(cam_infos),
                    R=rotation,
                    T=translation,
                    FovY=focal2fov(float(fy), height),
                    FovX=focal2fov(float(fx), width),
                    image=image,
                    image_path=str(image_path),
                    image_name=f"{view_asset.scene_stem}_v{view_asset.view_id}_f{int(frame_idx):05d}",
                    width=width,
                    height=height,
                )
            )

    return cam_infos

def readColmapSceneInfo(path, images, eval, llffhold=8, mask_dir=""):
    try:
        cameras_extrinsic_file = os.path.join(path, "sparse/0", "images.bin")
        cameras_intrinsic_file = os.path.join(path, "sparse/0", "cameras.bin")
        cam_extrinsics = read_extrinsics_binary(cameras_extrinsic_file)
        cam_intrinsics = read_intrinsics_binary(cameras_intrinsic_file)
    except:
        cameras_extrinsic_file = os.path.join(path, "sparse/0", "images.txt")
        cameras_intrinsic_file = os.path.join(path, "sparse/0", "cameras.txt")
        cam_extrinsics = read_extrinsics_text(cameras_extrinsic_file)
        cam_intrinsics = read_intrinsics_text(cameras_intrinsic_file)

    reading_dir = "images" if images == None else images
    mask_root = _resolve_mask_root(path, mask_dir)
    if mask_root is not None:
        print(f"Using mask directory: {mask_root}")
    cam_infos_unsorted = readColmapCameras(
        cam_extrinsics=cam_extrinsics,
        cam_intrinsics=cam_intrinsics,
        images_folder=os.path.join(path, reading_dir),
        mask_root=mask_root,
    )
    cam_infos = sorted(cam_infos_unsorted.copy(), key = lambda x : x.image_name)

    train_cam_infos, test_cam_infos = _split_train_test_cameras(cam_infos, eval, llffhold=llffhold)

    nerf_normalization = getNerfppNorm(train_cam_infos)

    ply_path = os.path.join(path, "sparse/0/points3D.ply")
    bin_path = os.path.join(path, "sparse/0/points3D.bin")
    txt_path = os.path.join(path, "sparse/0/points3D.txt")
    if not os.path.exists(ply_path):
        print("Converting point3d.bin to .ply, will happen only the first time you open the scene.")
        try:
            xyz, rgb, _ = read_points3D_binary(bin_path)
        except:
            xyz, rgb, _ = read_points3D_text(txt_path)
        storePly(ply_path, xyz, rgb)
    try:
        pcd = fetchPly(ply_path)
    except:
        pcd = None

    scene_info = SceneInfo(point_cloud=pcd,
                           train_cameras=train_cam_infos,
                           test_cameras=test_cam_infos,
                           nerf_normalization=nerf_normalization,
                           ply_path=ply_path)
    return scene_info

def readCamerasFromTransforms(path, transformsfile, white_background, extension=".png"):
    cam_infos = []

    with open(os.path.join(path, transformsfile)) as json_file:
        contents = json.load(json_file)
        fovx = contents["camera_angle_x"]

        frames = contents["frames"]
        for idx, frame in enumerate(frames):
            cam_name = os.path.join(path, frame["file_path"] + extension)

            # NeRF 'transform_matrix' is a camera-to-world transform
            c2w = np.array(frame["transform_matrix"])
            # change from OpenGL/Blender camera axes (Y up, Z back) to COLMAP (Y down, Z forward)
            c2w[:3, 1:3] *= -1

            # get the world-to-camera transform and set R, T
            w2c = np.linalg.inv(c2w)
            R = np.transpose(w2c[:3,:3])  # R is stored transposed due to 'glm' in CUDA code
            T = w2c[:3, 3]

            image_path = os.path.join(path, cam_name)
            image_name = Path(cam_name).stem
            image = Image.open(image_path)

            im_data = np.array(image.convert("RGBA"))

            bg = np.array([1,1,1]) if white_background else np.array([0, 0, 0])

            norm_data = im_data / 255.0
            arr = norm_data[:,:,:3] * norm_data[:, :, 3:4] + bg * (1 - norm_data[:, :, 3:4])
            image = Image.fromarray(np.array(arr*255.0, dtype=np.byte), "RGB")

            fovy = focal2fov(fov2focal(fovx, image.size[0]), image.size[1])
            FovY = fovy 
            FovX = fovx

            cam_infos.append(CameraInfo(uid=idx, R=R, T=T, FovY=FovY, FovX=FovX, image=image,
                            image_path=image_path, image_name=image_name, width=image.size[0], height=image.size[1]))
            
    return cam_infos

def readNerfSyntheticInfo(path, white_background, eval, extension=".png"):
    print("Reading Training Transforms")
    train_cam_infos = readCamerasFromTransforms(path, "transforms_train.json", white_background, extension)
    print("Reading Test Transforms")
    test_cam_infos = readCamerasFromTransforms(path, "transforms_test.json", white_background, extension)
    
    if not eval:
        train_cam_infos.extend(test_cam_infos)
        test_cam_infos = []

    nerf_normalization = getNerfppNorm(train_cam_infos)

    ply_path = os.path.join(path, "points3d.ply")
    if not os.path.exists(ply_path):
        num_pts = 100_000
        print(f"Generating random point cloud ({num_pts})...")
        pcd = generateRandomPointCloud(ply_path=ply_path, num_pts=num_pts, extent=1.3)
    try:
        pcd = fetchPly(ply_path)
    except:
        pcd = None

    scene_info = SceneInfo(point_cloud=pcd,
                           train_cameras=train_cam_infos,
                           test_cameras=test_cam_infos,
                           nerf_normalization=nerf_normalization,
                           ply_path=ply_path)
    return scene_info


def readLyraGeneratedSceneInfo(path, eval, llffhold=8):
    root = Path(path)
    scene_stem, view_assets = discoverLyraGeneratedAssets(root)
    cam_infos_unsorted = _build_lyra_camera_infos(root, view_assets)
    cam_infos = sorted(cam_infos_unsorted.copy(), key=lambda x: x.image_name)

    train_cam_infos, test_cam_infos = _split_train_test_cameras(cam_infos, eval, llffhold=llffhold)
    nerf_normalization = getNerfppNorm(train_cam_infos)

    ply_path = _ensure_lyra_point_cloud(root, scene_stem, train_cam_infos, num_pts=100_000)

    try:
        pcd = fetchPly(ply_path)
    except:
        pcd = None

    scene_info = SceneInfo(
        point_cloud=pcd,
        train_cameras=train_cam_infos,
        test_cameras=test_cam_infos,
        nerf_normalization=nerf_normalization,
        ply_path=str(ply_path),
    )
    return scene_info

sceneLoadTypeCallbacks = {
    "Colmap": readColmapSceneInfo,
    "Blender" : readNerfSyntheticInfo,
    "LyraGenerated": readLyraGeneratedSceneInfo,
}

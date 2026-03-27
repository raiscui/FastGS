"""COLMAP 训练图 alpha / mask 读取回归测试."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

import numpy as np
from PIL import Image

from scene.dataset_readers import CameraInfo, _resolve_mask_root, readColmapCameras
from utils.camera_utils import loadCam


def _build_fake_colmap_dicts(image_name: str, width: int, height: int):
    """构造最小可用的 COLMAP 相机内外参假对象."""

    extrinsics = {
        1: SimpleNamespace(
            camera_id=7,
            qvec=np.array([1.0, 0.0, 0.0, 0.0], dtype=np.float64),
            tvec=np.array([0.0, 0.0, 0.0], dtype=np.float64),
            name=image_name,
        )
    }
    intrinsics = {
        7: SimpleNamespace(
            id=7,
            height=height,
            width=width,
            model="SIMPLE_PINHOLE",
            params=np.array([10.0], dtype=np.float64),
        )
    }
    return extrinsics, intrinsics


class MaskLoadingTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name)

    def tearDown(self) -> None:
        self.tempdir.cleanup()

    def test_load_cam_extracts_alpha_channel_from_rgba_image(self) -> None:
        """RGBA 图进入 `loadCam` 后, 应该能把 alpha 单独提出来."""

        rgba_image = Image.new("RGBA", (8, 6), (32, 64, 96, 128))
        cam_info = CameraInfo(
            uid=1,
            R=np.eye(3, dtype=np.float32),
            T=np.zeros(3, dtype=np.float32),
            FovY=np.float32(0.8),
            FovX=np.float32(0.8),
            image=rgba_image,
            image_path="frame.png",
            image_name="frame",
            width=8,
            height=6,
        )
        args = SimpleNamespace(resolution=1, data_device="cpu")

        with mock.patch("utils.camera_utils.Camera", side_effect=lambda **kwargs: kwargs):
            camera_kwargs = loadCam(args=args, id=0, cam_info=cam_info, resolution_scale=1.0)

        alpha_mask = camera_kwargs["gt_alpha_mask"]
        self.assertIsNotNone(alpha_mask)
        self.assertEqual(tuple(alpha_mask.shape), (1, 6, 8))
        self.assertAlmostEqual(float(alpha_mask[0, 0, 0]), 128 / 255.0, places=4)

    def test_read_colmap_cameras_merges_external_mask_into_alpha(self) -> None:
        """独立 mask 目录应被合并进训练图的 alpha 通道."""

        images_dir = self.root / "images"
        masks_dir = self.root / "masks"
        images_dir.mkdir()
        masks_dir.mkdir()

        Image.new("RGB", (8, 6), (255, 0, 0)).save(images_dir / "frame.png")
        mask = Image.new("L", (8, 6), 255)
        mask.putpixel((0, 0), 0)
        mask.save(masks_dir / "frame.png")

        extrinsics, intrinsics = _build_fake_colmap_dicts("frame.png", width=8, height=6)
        cam_infos = readColmapCameras(extrinsics, intrinsics, str(images_dir), mask_root=masks_dir)

        self.assertEqual(len(cam_infos), 1)
        self.assertEqual(cam_infos[0].image.mode, "RGBA")
        self.assertEqual(cam_infos[0].image.getchannel("A").getpixel((0, 0)), 0)
        self.assertEqual(cam_infos[0].image.getchannel("A").getpixel((1, 0)), 255)

    def test_read_colmap_cameras_requires_full_mask_coverage(self) -> None:
        """一旦启用 mask 目录, 缺失对应 mask 时应明确报错, 避免静默脏训练."""

        images_dir = self.root / "images"
        masks_dir = self.root / "masks"
        images_dir.mkdir()
        masks_dir.mkdir()

        Image.new("RGB", (8, 6), (255, 0, 0)).save(images_dir / "frame.png")

        extrinsics, intrinsics = _build_fake_colmap_dicts("frame.png", width=8, height=6)

        with self.assertRaises(FileNotFoundError):
            readColmapCameras(extrinsics, intrinsics, str(images_dir), mask_root=masks_dir)

    def test_resolve_mask_root_ignores_empty_auto_mask_dir(self) -> None:
        """自动探测遇到空 `masks/` 目录时, 不应误进 mask 模式."""

        masks_dir = self.root / "masks"
        masks_dir.mkdir()

        self.assertIsNone(_resolve_mask_root(self.root, ""))

    def test_resolve_mask_root_accepts_nonempty_auto_mask_dir(self) -> None:
        """只有非空自动 mask 目录才应该被启用."""

        masks_dir = self.root / "masks"
        masks_dir.mkdir()
        Image.new("L", (4, 4), 255).save(masks_dir / "frame.png")

        self.assertEqual(_resolve_mask_root(self.root, ""), masks_dir.resolve())


if __name__ == "__main__":
    unittest.main()

"""室内颗粒亮点 mask 生成测试."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

from scripts.generate_particle_masks import (
    ParticleMaskConfig,
    build_keep_mask,
    process_image_directory,
)


def _make_image_with_particle_and_lamp(size: tuple[int, int] = (64, 48)) -> Image.Image:
    """构造一张含“小颗粒 + 大灯块”的测试图."""

    width, height = size
    image_array = np.full((height, width, 3), 30, dtype=np.uint8)

    # 小颗粒: 应该被抓到.
    image_array[10, 12] = np.array([255, 255, 255], dtype=np.uint8)

    # 大灯块: 应该被面积过滤排除.
    image_array[20:30, 40:52] = np.array([250, 250, 250], dtype=np.uint8)
    return Image.fromarray(image_array, mode="RGB")


def _make_image_with_particle_and_line(size: tuple[int, int] = (64, 48)) -> Image.Image:
    """构造一张含颗粒与细长灯带边缘的测试图."""

    width, height = size
    image_array = np.full((height, width, 3), 30, dtype=np.uint8)
    image_array[10, 12] = np.array([255, 255, 255], dtype=np.uint8)
    image_array[15, 20:32] = np.array([255, 255, 255], dtype=np.uint8)
    return Image.fromarray(image_array, mode="RGB")


class ParticleMaskGenerationTest(unittest.TestCase):
    def test_build_keep_mask_removes_small_particle_but_keeps_large_light(self) -> None:
        image = _make_image_with_particle_and_lamp()
        config = ParticleMaskConfig(
            min_brightness=220,
            min_residual=20,
            blur_radius=4.0,
            max_component_area=12,
            max_component_span=6,
            dilation_radius=1,
        )

        keep_mask, stats = build_keep_mask(image, config)
        keep_mask_array = np.asarray(keep_mask, dtype=np.uint8)

        self.assertEqual(int(keep_mask_array[10, 12]), 0)
        self.assertEqual(int(keep_mask_array[24, 46]), 255)
        self.assertGreater(stats["masked_pixels"], 0)

    def test_build_keep_mask_rejects_thin_long_edges(self) -> None:
        image = _make_image_with_particle_and_line()
        config = ParticleMaskConfig(
            min_brightness=220,
            min_residual=20,
            blur_radius=4.0,
            max_component_area=20,
            max_component_span=14,
            max_component_aspect_ratio=2.0,
            dilation_radius=1,
            max_local_std=80.0,
        )

        keep_mask, _ = build_keep_mask(image, config)
        keep_mask_array = np.asarray(keep_mask, dtype=np.uint8)

        self.assertEqual(int(keep_mask_array[10, 12]), 0)
        self.assertEqual(int(keep_mask_array[15, 24]), 255)

    def test_process_image_directory_outputs_png_masks_and_summary(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            root = Path(tempdir)
            images_dir = root / "images"
            masks_dir = root / "masks"
            debug_dir = root / "debug"
            images_dir.mkdir()

            for image_index in range(3):
                image = _make_image_with_particle_and_lamp()
                image.save(images_dir / f"{image_index:06d}.png")

            config = ParticleMaskConfig(
                min_brightness=220,
                min_residual=20,
                blur_radius=4.0,
                max_component_area=12,
                max_component_span=6,
                dilation_radius=1,
            )
            summary = process_image_directory(
                images_dir=images_dir,
                output_dir=masks_dir,
                config=config,
                debug_dir=debug_dir,
                debug_samples=2,
                overwrite=False,
            )

            mask_files = sorted(masks_dir.glob("*.png"))
            preview_files = sorted(debug_dir.glob("*_preview.png"))

            self.assertEqual(len(mask_files), 3)
            self.assertEqual(summary["image_count"], 3)
            self.assertGreater(summary["total_masked_pixels"], 0)
            self.assertGreaterEqual(len(preview_files), 2)

    def test_summary_is_json_serializable(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            root = Path(tempdir)
            images_dir = root / "images"
            masks_dir = root / "masks"
            images_dir.mkdir()
            _make_image_with_particle_and_lamp().save(images_dir / "frame.png")

            summary = process_image_directory(
                images_dir=images_dir,
                output_dir=masks_dir,
                config=ParticleMaskConfig(),
                overwrite=False,
            )

            payload = json.dumps(summary, ensure_ascii=False)
            self.assertIn("average_mask_ratio", payload)


if __name__ == "__main__":
    unittest.main()

"""mask 训练损失语义回归测试."""

from __future__ import annotations

from types import SimpleNamespace
from unittest import mock
import unittest

import torch

from utils.fast_utils import compute_photometric_loss
from utils.loss_utils import apply_loss_mask


class MaskLossTest(unittest.TestCase):
    def test_apply_loss_mask_zeros_masked_render_pixels(self) -> None:
        """被 mask 的 render 像素应退出 loss, 而不是继续拿去对黑色 GT 计误差."""

        render = torch.tensor(
            [[[1.0, 0.5], [0.25, 0.75]]],
            dtype=torch.float32,
        )
        alpha_mask = torch.tensor(
            [[[1.0, 0.0], [1.0, 0.0]]],
            dtype=torch.float32,
        )

        masked_render = apply_loss_mask(render, alpha_mask)

        self.assertAlmostEqual(float(masked_render[0, 0, 0]), 1.0)
        self.assertAlmostEqual(float(masked_render[0, 0, 1]), 0.0)
        self.assertAlmostEqual(float(masked_render[0, 1, 0]), 0.25)
        self.assertAlmostEqual(float(masked_render[0, 1, 1]), 0.0)

    def test_compute_photometric_loss_ignores_masked_pixels(self) -> None:
        """mask 区域外的亮点不应继续抬高 photometric loss."""

        alpha_mask = torch.tensor([[[1.0, 0.0]]], dtype=torch.float32)
        gt_image = torch.tensor(
            [
                [[1.0, 0.0]],
                [[0.0, 0.0]],
                [[0.0, 0.0]],
            ],
            dtype=torch.float32,
        )
        render_image = torch.tensor(
            [
                [[1.0, 1.0]],
                [[0.0, 1.0]],
                [[0.0, 1.0]],
            ],
            dtype=torch.float32,
        )
        viewpoint_cam = SimpleNamespace(
            original_image=gt_image,
            gt_alpha_mask=alpha_mask,
        )

        with mock.patch("utils.fast_utils.fast_ssim", return_value=torch.tensor(1.0)):
            loss = compute_photometric_loss(viewpoint_cam, render_image)

        self.assertAlmostEqual(float(loss), 0.0, places=6)


if __name__ == "__main__":
    unittest.main()

"""GaussianModel 续训状态回归测试."""

from __future__ import annotations

import unittest
from types import SimpleNamespace
from unittest import mock

import torch

from scene.gaussian_model import GaussianModel


class GaussianModelResumeTest(unittest.TestCase):
    def test_restore_keeps_tmp_radii_available_for_final_prune(self) -> None:
        """resume 后即使没有跑过 densify, 也应有可为空的 `tmp_radii` 字段."""

        gaussians = GaussianModel(sh_degree=0, optimizer_type="default")
        fake_optimizer = mock.Mock()
        fake_shoptimizer = mock.Mock()

        def fake_training_setup(self, _training_args):
            # 这里只验证 restore 的状态恢复契约.
            # 用假 optimizer 避免测试依赖 CUDA 分配与真实优化器实现.
            self.optimizer = fake_optimizer
            self.shoptimizer = fake_shoptimizer
            self.tmp_radii = None

        model_args = (
            0,
            torch.empty((0, 3)),
            torch.empty((0, 1, 1)),
            torch.empty((0, 1, 0)),
            torch.empty((0, 3)),
            torch.empty((0, 4)),
            torch.empty((0, 1)),
            torch.empty((0,)),
            torch.empty((0, 1)),
            torch.empty((0, 1)),
            torch.empty((0, 1)),
            {"adam": "state"},
            {"shadam": "state"},
            1.0,
        )

        with mock.patch.object(GaussianModel, "training_setup", new=fake_training_setup):
            gaussians.restore(model_args, SimpleNamespace(percent_dense=0))

        self.assertTrue(hasattr(gaussians, "tmp_radii"))
        self.assertIsNone(gaussians.tmp_radii)
        fake_optimizer.load_state_dict.assert_called_once_with({"adam": "state"})
        fake_shoptimizer.load_state_dict.assert_called_once_with({"shadam": "state"})


if __name__ == "__main__":
    unittest.main()

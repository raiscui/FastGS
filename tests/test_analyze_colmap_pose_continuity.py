"""`analyze_colmap_pose_continuity.py` 的 frame-gap 汇总口径回归测试."""

from __future__ import annotations

import importlib.util
import sys
import types
import unittest
from pathlib import Path

import numpy as np


def load_analyzer_module():
    # ------------------------------------------------------------
    # 这里的回归只验证 gap 统计逻辑, 不依赖真实绘图.
    # 测试环境里未必装有 matplotlib, 因此提前塞一个最小 stub.
    # ------------------------------------------------------------
    fake_matplotlib = types.ModuleType("matplotlib")
    fake_matplotlib.use = lambda *_args, **_kwargs: None
    fake_pyplot = types.ModuleType("matplotlib.pyplot")
    sys.modules.setdefault("matplotlib", fake_matplotlib)
    sys.modules.setdefault("matplotlib.pyplot", fake_pyplot)

    module_path = (
        Path(__file__).resolve().parents[1]
        / "scripts"
        / "analyze_colmap_pose_continuity.py"
    )
    spec = importlib.util.spec_from_file_location(
        "analyze_colmap_pose_continuity_for_test", module_path
    )
    if spec is None or spec.loader is None:
        raise RuntimeError(f"无法加载脚本模块: {module_path}")

    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


analyzer = load_analyzer_module()


class AnalyzeColmapPoseContinuityGapTest(unittest.TestCase):
    def make_pose_frame(self, *, image_id: int, view: int, frame: int, x: float):
        rotation = np.eye(3)
        return analyzer.PoseFrame(
            image_id=image_id,
            img_name=f"{image_id:03d}_{view}_demo_{frame:06d}.jpg",
            view=view,
            frame=frame,
            center=np.array([x, 0.0, 0.0], dtype=float),
            rotation_cw=rotation,
            right=np.array([1.0, 0.0, 0.0], dtype=float),
            up=np.array([0.0, 1.0, 0.0], dtype=float),
            forward=np.array([0.0, 0.0, 1.0], dtype=float),
            observed=100,
            observed_ratio=0.5,
        )

    def test_view_summary_can_ignore_gapped_transitions(self) -> None:
        frames_by_view = {
            7: [
                self.make_pose_frame(image_id=1, view=7, frame=1, x=0.0),
                self.make_pose_frame(image_id=2, view=7, frame=2, x=1.0),
                self.make_pose_frame(image_id=3, view=7, frame=4, x=4.0),
            ]
        }

        summary_all, details_all = analyzer.build_view_metrics(
            frames_by_view,
            transition_summary_mode="all",
        )
        summary_contiguous, details_contiguous = analyzer.build_view_metrics(
            frames_by_view,
            transition_summary_mode="contiguous",
        )

        self.assertEqual(summary_all[0]["transition_count"], 2)
        self.assertEqual(summary_all[0]["contiguous_transition_count"], 1)
        self.assertAlmostEqual(summary_all[0]["step_mean"], 2.0)

        self.assertEqual(summary_contiguous[0]["transition_count"], 1)
        self.assertEqual(summary_contiguous[0]["contiguous_transition_count"], 1)
        self.assertAlmostEqual(summary_contiguous[0]["step_mean"], 1.0)

        self.assertEqual(details_all[7][2]["frame_gap"], 2)
        self.assertFalse(details_all[7][2]["is_contiguous_transition"])
        self.assertEqual(details_contiguous[7][2]["frame_gap"], 2)

    def test_pair_summary_can_ignore_gapped_shared_frames(self) -> None:
        frames_by_view = {
            6: [
                self.make_pose_frame(image_id=1, view=6, frame=1, x=0.0),
                self.make_pose_frame(image_id=2, view=6, frame=2, x=1.0),
                self.make_pose_frame(image_id=3, view=6, frame=4, x=4.0),
            ],
            7: [
                self.make_pose_frame(image_id=4, view=7, frame=1, x=1.0),
                self.make_pose_frame(image_id=5, view=7, frame=2, x=3.0),
                self.make_pose_frame(image_id=6, view=7, frame=4, x=8.0),
            ],
        }

        pair_all, pair_details_all = analyzer.build_pair_metrics(
            frames_by_view,
            transition_summary_mode="all",
        )
        pair_contiguous, pair_details_contiguous = analyzer.build_pair_metrics(
            frames_by_view,
            transition_summary_mode="contiguous",
        )

        self.assertEqual(pair_all[0]["delta_transition_count"], 2)
        self.assertEqual(pair_all[0]["contiguous_delta_transition_count"], 1)
        self.assertAlmostEqual(pair_all[0]["delta_relative_distance_mean"], 1.5)

        self.assertEqual(pair_contiguous[0]["delta_transition_count"], 1)
        self.assertEqual(pair_contiguous[0]["contiguous_delta_transition_count"], 1)
        self.assertAlmostEqual(pair_contiguous[0]["delta_relative_distance_mean"], 1.0)

        self.assertEqual(pair_details_all["6-7"][2]["frame_gap"], 2)
        self.assertFalse(pair_details_all["6-7"][2]["is_contiguous_transition"])
        self.assertEqual(pair_details_contiguous["6-7"][2]["frame_gap"], 2)


if __name__ == "__main__":
    unittest.main()

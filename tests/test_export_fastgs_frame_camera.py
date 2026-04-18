import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "export_fastgs_frame_camera.py"
SPEC = importlib.util.spec_from_file_location("export_fastgs_frame_camera_test", SCRIPT_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class ExportFastGsFrameCameraTest(unittest.TestCase):
    def test_build_frame_record_contains_expected_pose_fields(self) -> None:
        camera_to_world = np.eye(4, dtype=np.float64)
        camera_to_world[:3, 3] = np.array([1.0, 2.0, 3.0], dtype=np.float64)
        intrinsics = np.array(
            [
                [1000.0, 0.0, 640.0],
                [0.0, 1000.0, 360.0],
                [0.0, 0.0, 1.0],
            ],
            dtype=np.float64,
        )

        record = MODULE.build_frame_record(
            frame_index=0,
            dataset_index=0,
            parser_index=7,
            fps=12.0,
            image_name="000001.jpg",
            image_path="/tmp/000001.jpg",
            image_size=(1280, 720),
            intrinsics=intrinsics,
            camera_to_world=camera_to_world,
        )

        self.assertEqual(record["parser_index"], 7)
        self.assertEqual(record["image_size"], [1280, 720])
        self.assertEqual(record["position"], [1.0, 2.0, 3.0])
        self.assertEqual(record["quaternion_xyzw"], [0.0, 0.0, 0.0, 1.0])
        self.assertEqual(record["quaternion_wxyz"], [1.0, 0.0, 0.0, 0.0])

    def test_build_unity_payload_uses_freefix_field_names(self) -> None:
        source_payload = {
            "output": {"path": "/tmp/000001_camera_trajectory.json"},
            "video": {
                "path": "/tmp/000001.jpg",
                "name": "000001.jpg",
                "width": 1280,
                "height": 720,
                "fps": 1.0,
                "frame_count": 1,
            },
            "refine": {"data_dir": "/tmp/demo"},
            "frames": [
                {
                    "frame_index": 0,
                    "time_sec": 0.0,
                    "dataset_index": 0,
                    "parser_index": 1,
                    "image_name": "000001.jpg",
                    "image_path": "/tmp/000001.jpg",
                    "image_size": [1280, 720],
                    "position": [1.0, 2.0, 3.0],
                    "quaternion_xyzw": [0.0, 0.0, 0.0, 1.0],
                    "camera_to_world": [
                        [1.0, 0.0, 0.0, 1.0],
                        [0.0, 1.0, 0.0, 2.0],
                        [0.0, 0.0, 1.0, 3.0],
                        [0.0, 0.0, 0.0, 1.0],
                    ],
                    "intrinsics": [
                        [1000.0, 0.0, 640.0],
                        [0.0, 1000.0, 360.0],
                        [0.0, 0.0, 1.0],
                    ],
                }
            ],
        }

        payload = MODULE.build_unity_payload(
            source_payload=source_payload,
            unity_output_path=Path("/tmp/000001_camera_trajectory_unity.json"),
        )

        self.assertEqual(payload["schemaVersion"], 1)
        frame = payload["frames"][0]
        self.assertEqual(frame["quaternionXyzw"], [0.0, 0.0, 0.0, 1.0])
        self.assertEqual(
            frame["cameraToWorldRowMajor"],
            [1.0, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0, 2.0, 0.0, 0.0, 1.0, 3.0, 0.0, 0.0, 0.0, 1.0],
        )
        self.assertEqual(
            frame["cameraToWorldColumnMajor"],
            [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0, 2.0, 3.0, 1.0],
        )
        self.assertEqual(
            frame["intrinsicsRowMajor"],
            [1000.0, 0.0, 640.0, 0.0, 1000.0, 360.0, 0.0, 0.0, 1.0],
        )

    def test_select_frame_defaults_to_sorted_first_image(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            images_dir = Path(tmp_dir)
            Image.new("RGB", (8, 6), color="white").save(images_dir / "000001.jpg")
            Image.new("RGB", (8, 6), color="black").save(images_dir / "000010.jpg")

            image_record_late = type(
                "ImageRecord",
                (),
                {
                    "name": "000010.jpg",
                    "camera_id": 1,
                    "qvec2rotmat": lambda self: np.eye(3, dtype=np.float64),
                    "tvec": np.zeros(3, dtype=np.float64),
                },
            )()
            image_record_early = type(
                "ImageRecord",
                (),
                {
                    "name": "000001.jpg",
                    "camera_id": 1,
                    "qvec2rotmat": lambda self: np.eye(3, dtype=np.float64),
                    "tvec": np.zeros(3, dtype=np.float64),
                },
            )()
            camera_record = type(
                "CameraRecord",
                (),
                {
                    "model": "PINHOLE",
                    "params": np.array([1000.0, 1000.0, 640.0, 360.0], dtype=np.float64),
                },
            )()

            selected = MODULE.select_frame(
                extrinsics={7: image_record_late, 3: image_record_early},
                intrinsics={1: camera_record},
                images_dir=images_dir,
                image_name=None,
                image_index=0,
            )

            self.assertEqual(selected.image_name, "000001.jpg")
            self.assertEqual(selected.parser_index, 0)
            self.assertEqual(selected.image_id, 3)
            self.assertEqual(selected.width, 8)
            self.assertEqual(selected.height, 6)


if __name__ == "__main__":
    unittest.main()

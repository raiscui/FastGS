import struct
import tempfile
import unittest
from pathlib import Path

import numpy as np

from scene.colmap_loader import read_extrinsics_binary, read_extrinsics_text


class ColmapLoaderUnicodeImageNameTest(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name)

    def tearDown(self):
        self.tempdir.cleanup()

    def test_read_extrinsics_binary_supports_utf8_image_names(self):
        image_name = "xhc_in the style of Makoto Shinkai,注意镜头移动时候,镜头光斑,灯光光影的正常,不要贴在墙上.png"
        image_path = self.root / "images.bin"

        with image_path.open("wb") as fid:
            fid.write(struct.pack("<Q", 1))
            fid.write(struct.pack("<idddddddi", 1, 1.0, 0.0, 0.0, 0.0, 0.1, 0.2, 0.3, 7))
            fid.write(image_name.encode("utf-8"))
            fid.write(b"\x00")
            fid.write(struct.pack("<Q", 1))
            fid.write(struct.pack("<ddq", 12.5, 24.5, -1))

        images = read_extrinsics_binary(image_path)
        image = images[1]

        self.assertEqual(image.name, image_name)
        self.assertEqual(image.camera_id, 7)
        self.assertTrue(np.allclose(image.qvec, np.array([1.0, 0.0, 0.0, 0.0])))
        self.assertTrue(np.allclose(image.tvec, np.array([0.1, 0.2, 0.3])))
        self.assertEqual(image.xys.shape, (1, 2))
        self.assertEqual(image.point3D_ids.tolist(), [-1])

    def test_read_extrinsics_text_supports_spaces_in_image_names(self):
        image_name = "xhc_in the style of Makoto Shinkai,注意镜头移动时候,镜头光斑,灯光光影的正常,不要贴在墙上.png"
        image_path = self.root / "images.txt"
        image_path.write_text(
            "\n".join(
                [
                    "# Image list with two lines of data per image:",
                    f"1 1 0 0 0 0.1 0.2 0.3 7 {image_name}",
                    "12.5 24.5 -1",
                ]
            )
            + "\n",
            encoding="utf-8",
        )

        images = read_extrinsics_text(image_path)
        image = images[1]

        self.assertEqual(image.name, image_name)
        self.assertEqual(image.camera_id, 7)
        self.assertTrue(np.allclose(image.qvec, np.array([1.0, 0.0, 0.0, 0.0])))
        self.assertTrue(np.allclose(image.tvec, np.array([0.1, 0.2, 0.3])))
        self.assertEqual(image.xys.shape, (1, 2))
        self.assertEqual(image.point3D_ids.tolist(), [-1])


if __name__ == "__main__":
    unittest.main()

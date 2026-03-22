import struct
import tempfile
import unittest
from pathlib import Path

from convert import read_text_image_count, select_best_sparse_model


class ConvertSparseModelSelectionTest(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name)
        self.sparse_root = self.root / "distorted" / "sparse"
        self.sparse_root.mkdir(parents=True, exist_ok=True)

    def tearDown(self):
        self.tempdir.cleanup()

    def write_binary_count(self, path: Path, count: int) -> None:
        path.write_bytes(struct.pack("<Q", count))

    def create_binary_model(
        self,
        name: str,
        *,
        camera_count: int = 1,
        registered_image_count: int = 0,
        point_count: int = 0,
    ) -> Path:
        model_path = self.sparse_root / name
        model_path.mkdir(parents=True, exist_ok=True)

        # 这里不需要写完整 COLMAP 模型.
        # 选择逻辑只读取二进制头里的记录数.
        self.write_binary_count(model_path / "cameras.bin", camera_count)
        self.write_binary_count(model_path / "images.bin", registered_image_count)
        self.write_binary_count(model_path / "points3D.bin", point_count)
        return model_path

    def test_select_best_sparse_model_prefers_registered_images(self):
        self.create_binary_model("0", registered_image_count=4, point_count=2)
        self.create_binary_model("1", registered_image_count=15, point_count=2581)
        self.create_binary_model("2", registered_image_count=360, point_count=92946)

        best_model = select_best_sparse_model(self.sparse_root)

        self.assertEqual(best_model.path.name, "2")
        self.assertEqual(best_model.registered_image_count, 360)
        self.assertEqual(best_model.point_count, 92946)

    def test_select_best_sparse_model_uses_points_as_tiebreaker(self):
        self.create_binary_model("0", registered_image_count=30, point_count=100)
        self.create_binary_model("1", registered_image_count=30, point_count=500)

        best_model = select_best_sparse_model(self.sparse_root)

        self.assertEqual(best_model.path.name, "1")
        self.assertEqual(best_model.point_count, 500)

    def test_read_text_image_count_uses_two_lines_per_image(self):
        image_text = "\n".join(
            [
                "# comment",
                "1 1 0 0 0 0 0 0 1 image_0001.jpg",
                "0 0 -1 1 1 -1",
                "2 1 0 0 0 0 0 0 1 image_0002.jpg",
                "2 2 -1 3 3 -1",
            ]
        )
        image_path = self.root / "images.txt"
        image_path.write_text(image_text + "\n", encoding="utf-8")

        self.assertEqual(read_text_image_count(image_path), 2)


if __name__ == "__main__":
    unittest.main()

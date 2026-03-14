import json
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

import scene.dataset_readers as dataset_readers


def write_direct_camera_inputs(pose_path: Path, intrinsics_path: Path, poses: np.ndarray, intrinsics: np.ndarray):
    inds = np.arange(poses.shape[0], dtype=np.int64)
    pose_path.parent.mkdir(parents=True, exist_ok=True)
    intrinsics_path.parent.mkdir(parents=True, exist_ok=True)
    np.savez(pose_path, data=poses.astype(np.float32), inds=inds)
    np.savez(intrinsics_path, data=intrinsics.astype(np.float32), inds=inds)


def make_look_at_pose(center: np.ndarray, focus: np.ndarray):
    center = np.asarray(center, dtype=np.float32)
    focus = np.asarray(focus, dtype=np.float32)

    forward = focus - center
    forward = forward / np.linalg.norm(forward)

    world_up = np.array([0.0, 1.0, 0.0], dtype=np.float32)
    if abs(float(np.dot(world_up, forward))) > 0.99:
        world_up = np.array([1.0, 0.0, 0.0], dtype=np.float32)

    right = np.cross(world_up, forward)
    right = right / np.linalg.norm(right)
    up = np.cross(forward, right)
    up = up / np.linalg.norm(up)

    pose = np.eye(4, dtype=np.float32)
    pose[:3, 0] = right
    pose[:3, 1] = up
    pose[:3, 2] = forward
    pose[:3, 3] = center
    return pose


class LyraGeneratedLoaderTest(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name)

    def tearDown(self):
        self.tempdir.cleanup()

    def create_view(self, view_id: str, scene_stem: str, poses: np.ndarray, intrinsics: np.ndarray):
        view_root = self.root / view_id
        rgb_dir = view_root / "rgb"
        rgb_dir.mkdir(parents=True, exist_ok=True)
        (rgb_dir / f"{scene_stem}.mp4").write_bytes(b"fake-mp4")

        write_direct_camera_inputs(
            pose_path=view_root / "pose" / f"{scene_stem}.npz",
            intrinsics_path=view_root / "intrinsics" / f"{scene_stem}.npz",
            poses=poses,
            intrinsics=intrinsics,
        )

    def fake_frame_cache(self, root: Path, scene_stem: str, view_asset, expected_frame_count: int):
        cache_dir = root / dataset_readers.LYRA_CACHE_ROOT / scene_stem / view_asset.view_id
        cache_dir.mkdir(parents=True, exist_ok=True)
        for frame_idx in range(expected_frame_count):
            image = Image.new(
                "RGB",
                (8, 6),
                color=((frame_idx * 40) % 255, (int(view_asset.view_id) * 50) % 255, 120),
            )
            image.save(cache_dir / f"{frame_idx:05d}.png")
        (cache_dir / "metadata.json").write_text("{}", encoding="utf-8")
        return cache_dir

    def test_discover_lyra_generated_assets(self):
        poses = np.repeat(np.eye(4, dtype=np.float32)[None, :, :], repeats=2, axis=0)
        intrinsics = np.array([[10.0, 11.0, 4.0, 3.0], [10.0, 11.0, 4.0, 3.0]], dtype=np.float32)
        self.create_view("0", "demo", poses, intrinsics)
        self.create_view("1", "demo", poses, intrinsics)

        scene_stem, view_assets = dataset_readers.discoverLyraGeneratedAssets(self.root)

        self.assertEqual(scene_stem, "demo")
        self.assertEqual([asset.view_id for asset in view_assets], ["0", "1"])
        self.assertTrue(dataset_readers.isLyraGeneratedSceneRoot(self.root))

    def test_read_lyra_generated_scene_info_converts_c2w_to_fastgs_camera(self):
        poses_view0 = np.repeat(np.eye(4, dtype=np.float32)[None, :, :], repeats=2, axis=0)
        poses_view0[1, 0, 3] = 1.0

        poses_view1 = np.repeat(np.eye(4, dtype=np.float32)[None, :, :], repeats=2, axis=0)
        poses_view1[1, 2, 3] = 2.0

        intrinsics = np.array([[10.0, 12.0, 4.0, 3.0], [10.0, 12.0, 4.0, 3.0]], dtype=np.float32)

        self.create_view("0", "demo", poses_view0, intrinsics)
        self.create_view("1", "demo", poses_view1, intrinsics)

        original = dataset_readers._ensure_lyra_frame_cache
        dataset_readers._ensure_lyra_frame_cache = self.fake_frame_cache
        try:
            scene_info = dataset_readers.readLyraGeneratedSceneInfo(self.root, eval=False)
        finally:
            dataset_readers._ensure_lyra_frame_cache = original

        self.assertEqual(len(scene_info.train_cameras), 4)
        self.assertEqual(len(scene_info.test_cameras), 0)

        moved_x_camera = scene_info.train_cameras[1]
        moved_z_camera = scene_info.train_cameras[3]

        self.assertTrue(np.allclose(moved_x_camera.R, np.eye(3)))
        self.assertTrue(np.allclose(moved_x_camera.T, np.array([-1.0, 0.0, 0.0])))
        self.assertTrue(np.allclose(moved_z_camera.T, np.array([0.0, 0.0, -2.0])))
        self.assertEqual(moved_x_camera.image_name, "demo_v0_f00001")
        self.assertTrue(Path(scene_info.ply_path).is_file())

    def test_discover_lyra_generated_assets_rejects_multiple_scene_stems(self):
        poses = np.repeat(np.eye(4, dtype=np.float32)[None, :, :], repeats=1, axis=0)
        intrinsics = np.array([[10.0, 11.0, 4.0, 3.0]], dtype=np.float32)

        self.create_view("0", "demo_a", poses, intrinsics)
        self.create_view("0", "demo_b", poses, intrinsics)
        self.create_view("1", "demo_a", poses, intrinsics)
        self.create_view("1", "demo_b", poses, intrinsics)

        with self.assertRaises(RuntimeError):
            dataset_readers.discoverLyraGeneratedAssets(self.root)

    def test_read_lyra_generated_scene_info_regenerates_focus_centered_point_cloud(self):
        focus = np.array([0.0, 0.0, 5.0], dtype=np.float32)
        intrinsics = np.array([[10.0, 10.0, 4.0, 3.0]], dtype=np.float32)

        self.create_view("0", "demo", make_look_at_pose(np.array([0.0, 0.0, 0.0]), focus)[None, :, :], intrinsics)
        self.create_view("1", "demo", make_look_at_pose(np.array([1.0, 0.0, 0.0]), focus)[None, :, :], intrinsics)
        self.create_view("2", "demo", make_look_at_pose(np.array([0.0, 1.0, 0.0]), focus)[None, :, :], intrinsics)

        stale_ply_path = self.root / dataset_readers.LYRA_CACHE_ROOT / "demo" / "points3d.ply"
        dataset_readers.generateRandomPointCloud(
            ply_path=stale_ply_path,
            num_pts=2_000,
            extent=0.25,
            center=np.zeros(3, dtype=np.float32),
            seed=123,
        )

        original = dataset_readers._ensure_lyra_frame_cache
        dataset_readers._ensure_lyra_frame_cache = self.fake_frame_cache
        try:
            scene_info = dataset_readers.readLyraGeneratedSceneInfo(self.root, eval=False)
        finally:
            dataset_readers._ensure_lyra_frame_cache = original

        point_cloud_center = np.mean(scene_info.point_cloud.points, axis=0)
        self.assertLess(np.linalg.norm(point_cloud_center - focus), 0.2)

        metadata_path = self.root / dataset_readers.LYRA_CACHE_ROOT / "demo" / dataset_readers.LYRA_POINT_CLOUD_METADATA_NAME
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        self.assertEqual(metadata["generator"], dataset_readers.LYRA_POINT_CLOUD_GENERATOR)
        self.assertEqual(metadata["seed"], dataset_readers.LYRA_POINT_CLOUD_RANDOM_SEED)


if __name__ == "__main__":
    unittest.main()

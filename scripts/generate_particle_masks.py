"""为室内空中颗粒 / 尘埃 / 小亮点生成训练 mask."""

from __future__ import annotations

import argparse
import json
from dataclasses import asdict, dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


SUPPORTED_IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp", ".bmp", ".tif", ".tiff"}


@dataclass(frozen=True)
class ParticleMaskConfig:
    """颗粒亮点检测配置.

    这套配置的目标不是抓住所有高光.
    它只针对“亮、局部突起、面积小、形状短促”的漂浮颗粒.
    """

    min_brightness: int = 215
    min_residual: int = 26
    blur_radius: float = 6.0
    max_background_brightness: int = 190
    peak_window: int = 5
    peak_slack: int = 2
    local_std_radius: int = 7
    max_local_std: float = 18.0
    min_component_area: int = 1
    max_component_area: int = 42
    max_component_span: int = 12
    max_component_aspect_ratio: float = 2.8
    dilation_radius: int = 2
    exclude_bottom_ratio: float = 0.0


def collect_image_paths(images_dir: Path) -> list[Path]:
    """收集输入图像列表."""

    image_paths = [
        path
        for path in sorted(images_dir.iterdir())
        if path.is_file() and path.suffix.lower() in SUPPORTED_IMAGE_EXTENSIONS
    ]
    if not image_paths:
        raise FileNotFoundError(f"No images found in {images_dir}")
    return image_paths


def ensure_odd_window(window_size: int) -> int:
    """Pillow 的 `MaxFilter` 需要奇数窗口."""

    if window_size < 3:
        return 3
    return window_size if window_size % 2 == 1 else window_size + 1


def _neighbors(y: int, x: int, height: int, width: int):
    """8 邻域遍历."""

    for delta_y in (-1, 0, 1):
        for delta_x in (-1, 0, 1):
            if delta_y == 0 and delta_x == 0:
                continue
            next_y = y + delta_y
            next_x = x + delta_x
            if 0 <= next_y < height and 0 <= next_x < width:
                yield next_y, next_x


def keep_small_components(candidate_mask: np.ndarray, config: ParticleMaskConfig) -> np.ndarray:
    """只保留“小而孤立”的亮点连通域.

    这样可以尽量避开:
    - 大灯
    - 窗户高光
    - 成片反射
    """

    height, width = candidate_mask.shape
    visited = np.zeros_like(candidate_mask, dtype=bool)
    kept_mask = np.zeros_like(candidate_mask, dtype=bool)

    positive_points = np.argwhere(candidate_mask)
    for start_y, start_x in positive_points:
        if visited[start_y, start_x]:
            continue

        stack = [(int(start_y), int(start_x))]
        visited[start_y, start_x] = True
        component_pixels: list[tuple[int, int]] = []
        min_y = max_y = int(start_y)
        min_x = max_x = int(start_x)

        while stack:
            current_y, current_x = stack.pop()
            component_pixels.append((current_y, current_x))

            if current_y < min_y:
                min_y = current_y
            if current_y > max_y:
                max_y = current_y
            if current_x < min_x:
                min_x = current_x
            if current_x > max_x:
                max_x = current_x

            for next_y, next_x in _neighbors(current_y, current_x, height, width):
                if visited[next_y, next_x] or not candidate_mask[next_y, next_x]:
                    continue
                visited[next_y, next_x] = True
                stack.append((next_y, next_x))

        component_area = len(component_pixels)
        span_y = max_y - min_y + 1
        span_x = max_x - min_x + 1
        short_span = max(1, min(span_y, span_x))
        long_span = max(span_y, span_x)
        aspect_ratio = long_span / float(short_span)

        if component_area < config.min_component_area:
            continue
        if component_area > config.max_component_area:
            continue
        if span_y > config.max_component_span or span_x > config.max_component_span:
            continue
        if aspect_ratio > config.max_component_aspect_ratio:
            continue

        for pixel_y, pixel_x in component_pixels:
            kept_mask[pixel_y, pixel_x] = True

    return kept_mask


def compute_local_std(gray_array: np.ndarray, radius: int) -> np.ndarray:
    """计算局部标准差, 用来压掉高纹理区域里的误检.

    这里用积分图做盒式统计, 避免额外引依赖.
    """

    if radius <= 0:
        return np.zeros_like(gray_array, dtype=np.float32)

    window_size = radius * 2 + 1
    gray_float = gray_array.astype(np.float32)
    padded = np.pad(gray_float, ((radius, radius), (radius, radius)), mode="reflect")
    padded_sq = padded * padded

    integral = np.pad(padded, ((1, 0), (1, 0)), mode="constant").cumsum(axis=0).cumsum(axis=1)
    integral_sq = np.pad(padded_sq, ((1, 0), (1, 0)), mode="constant").cumsum(axis=0).cumsum(axis=1)

    height, width = gray_array.shape
    ys = np.arange(height)[:, None]
    xs = np.arange(width)[None, :]
    y0 = ys
    x0 = xs
    y1 = ys + window_size
    x1 = xs + window_size

    sums = integral[y1, x1] - integral[y0, x1] - integral[y1, x0] + integral[y0, x0]
    sums_sq = integral_sq[y1, x1] - integral_sq[y0, x1] - integral_sq[y1, x0] + integral_sq[y0, x0]

    area = float(window_size * window_size)
    mean = sums / area
    mean_sq = sums_sq / area
    variance = np.maximum(mean_sq - mean * mean, 0.0)
    return np.sqrt(variance).astype(np.float32, copy=False)


def detect_particle_pixels(image: Image.Image, config: ParticleMaskConfig) -> tuple[np.ndarray, dict]:
    """检测可能属于空中颗粒的小亮点像素."""

    grayscale = image.convert("L")
    blurred = grayscale.filter(ImageFilter.GaussianBlur(config.blur_radius))
    local_max = grayscale.filter(ImageFilter.MaxFilter(ensure_odd_window(config.peak_window)))

    grayscale_array = np.asarray(grayscale, dtype=np.int16)
    blurred_array = np.asarray(blurred, dtype=np.int16)
    local_max_array = np.asarray(local_max, dtype=np.int16)
    residual_array = grayscale_array - blurred_array
    local_std_array = compute_local_std(grayscale_array.astype(np.float32), config.local_std_radius)

    candidate_mask = (
        (grayscale_array >= config.min_brightness)
        & (residual_array >= config.min_residual)
        & (blurred_array <= config.max_background_brightness)
        & (grayscale_array >= (local_max_array - config.peak_slack))
        & (local_std_array <= config.max_local_std)
    )

    if config.exclude_bottom_ratio > 0.0:
        height = candidate_mask.shape[0]
        cut_start = int(height * (1.0 - config.exclude_bottom_ratio))
        candidate_mask[cut_start:, :] = False

    small_component_mask = keep_small_components(candidate_mask, config)
    stats = {
        "candidate_pixels": int(candidate_mask.sum()),
        "kept_pixels_before_dilate": int(small_component_mask.sum()),
        "max_residual": int(residual_array.max(initial=0)),
        "max_local_std": float(local_std_array.max(initial=0.0)),
    }
    return small_component_mask, stats


def dilate_binary_mask(binary_mask: np.ndarray, dilation_radius: int) -> np.ndarray:
    """对待移除区域做轻微膨胀, 避免只抹掉亮点中心."""

    if dilation_radius <= 0:
        return binary_mask

    filter_size = ensure_odd_window(dilation_radius * 2 + 1)
    mask_image = Image.fromarray((binary_mask.astype(np.uint8) * 255), mode="L")
    dilated = mask_image.filter(ImageFilter.MaxFilter(filter_size))
    return np.asarray(dilated, dtype=np.uint8) > 0


def build_keep_mask(image: Image.Image, config: ParticleMaskConfig) -> tuple[Image.Image, dict]:
    """从原图生成训练用 keep mask.

    输出约定:
    - 白色(`255`)表示保留
    - 黑色(`0`)表示移除
    """

    particle_mask, stats = detect_particle_pixels(image, config)
    dilated_particle_mask = dilate_binary_mask(particle_mask, config.dilation_radius)

    keep_mask_array = np.full(particle_mask.shape, 255, dtype=np.uint8)
    keep_mask_array[dilated_particle_mask] = 0

    stats.update(
        {
            "masked_pixels": int(dilated_particle_mask.sum()),
            "keep_pixels": int((keep_mask_array > 0).sum()),
            "mask_ratio": float(dilated_particle_mask.mean()),
        }
    )
    keep_mask = Image.fromarray(keep_mask_array, mode="L")
    return keep_mask, stats


def build_debug_preview(image: Image.Image, keep_mask: Image.Image) -> Image.Image:
    """构造简单的调试预览图.

    左: 原图
    中: 红色叠加后的移除区域
    右: 二值 mask
    """

    original_rgb = image.convert("RGB")
    keep_mask_array = np.asarray(keep_mask, dtype=np.uint8)
    removed_mask = keep_mask_array == 0

    overlay_array = np.asarray(original_rgb, dtype=np.uint8).copy()
    overlay_array[removed_mask] = np.array([255, 48, 48], dtype=np.uint8)
    overlay_image = Image.fromarray(overlay_array, mode="RGB")
    mask_rgb = keep_mask.convert("RGB")

    width, height = original_rgb.size
    preview = Image.new("RGB", (width * 3, height), color=(0, 0, 0))
    preview.paste(original_rgb, (0, 0))
    preview.paste(overlay_image, (width, 0))
    preview.paste(mask_rgb, (width * 2, 0))
    return preview


def choose_debug_samples(image_paths: list[Path], sample_count: int) -> set[int]:
    """均匀抽一些样本做调试预览."""

    if sample_count <= 0 or not image_paths:
        return set()
    if sample_count >= len(image_paths):
        return set(range(len(image_paths)))

    indexes = {0, len(image_paths) - 1}
    if sample_count <= 2:
        return indexes

    step = (len(image_paths) - 1) / float(sample_count - 1)
    for sample_index in range(sample_count):
        indexes.add(round(sample_index * step))
    return indexes


def process_image_directory(
    images_dir: Path,
    output_dir: Path,
    *,
    config: ParticleMaskConfig,
    debug_dir: Path | None = None,
    debug_samples: int = 8,
    overwrite: bool = False,
) -> dict:
    """批量生成目录级 mask."""

    image_paths = collect_image_paths(images_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    if debug_dir is not None:
        debug_dir.mkdir(parents=True, exist_ok=True)

    if not overwrite:
        existing_masks = list(output_dir.glob("*"))
        if existing_masks:
            raise FileExistsError(f"Output directory is not empty: {output_dir}")

    summary_items = []
    debug_indexes = choose_debug_samples(image_paths, debug_samples)

    for image_index, image_path in enumerate(image_paths):
        with Image.open(image_path) as image_file:
            image = image_file.convert("RGB")

        keep_mask, stats = build_keep_mask(image, config)
        output_mask_path = output_dir / f"{image_path.stem}.png"
        keep_mask.save(output_mask_path)

        if debug_dir is not None and image_index in debug_indexes:
            preview = build_debug_preview(image, keep_mask)
            preview.save(debug_dir / f"{image_path.stem}_preview.png")

        summary_items.append(
            {
                "image_name": image_path.name,
                "mask_name": output_mask_path.name,
                **stats,
            }
        )

    masked_pixel_total = sum(item["masked_pixels"] for item in summary_items)
    mask_ratio_values = [item["mask_ratio"] for item in summary_items]
    summary = {
        "images_dir": str(images_dir),
        "output_dir": str(output_dir),
        "image_count": len(summary_items),
        "total_masked_pixels": int(masked_pixel_total),
        "average_mask_ratio": float(np.mean(mask_ratio_values) if mask_ratio_values else 0.0),
        "max_mask_ratio": float(np.max(mask_ratio_values) if mask_ratio_values else 0.0),
        "config": asdict(config),
        "images": summary_items,
    }
    return summary


def parse_args() -> argparse.Namespace:
    """命令行参数."""

    parser = argparse.ArgumentParser(description="Generate particle masks for indoor floating bright specks.")
    parser.add_argument("--images-dir", required=True, type=Path, help="输入图像目录, 通常是 COLMAP 场景下的 images/")
    parser.add_argument("--output-dir", required=True, type=Path, help="输出 mask 目录")
    parser.add_argument("--debug-dir", type=Path, default=None, help="可选: 输出调试预览目录")
    parser.add_argument("--summary-path", type=Path, default=None, help="可选: 输出 summary JSON")
    parser.add_argument("--debug-samples", type=int, default=8, help="调试预览采样数量, 默认 8")
    parser.add_argument("--overwrite", action="store_true", help="允许覆盖已有输出目录内容")

    parser.add_argument("--min-brightness", type=int, default=215, help="最小亮度阈值, 默认 215")
    parser.add_argument("--min-residual", type=int, default=26, help="相对局部模糊图的最小亮度残差, 默认 26")
    parser.add_argument("--blur-radius", type=float, default=6.0, help="局部背景估计的模糊半径, 默认 6.0")
    parser.add_argument("--max-background-brightness", type=int, default=190, help="局部背景允许的最大亮度, 默认 190")
    parser.add_argument("--peak-window", type=int, default=5, help="局部峰值窗口大小, 默认 5")
    parser.add_argument("--peak-slack", type=int, default=2, help="局部峰值松弛量, 默认 2")
    parser.add_argument("--local-std-radius", type=int, default=7, help="局部纹理统计半径, 默认 7")
    parser.add_argument("--max-local-std", type=float, default=18.0, help="允许保留的最大局部标准差, 默认 18.0")
    parser.add_argument("--min-component-area", type=int, default=1, help="保留连通域的最小面积, 默认 1")
    parser.add_argument("--max-component-area", type=int, default=42, help="保留连通域的最大面积, 默认 42")
    parser.add_argument("--max-component-span", type=int, default=12, help="保留连通域的最大宽或高, 默认 12")
    parser.add_argument("--max-component-aspect-ratio", type=float, default=2.8, help="保留连通域的最大长宽比, 默认 2.8")
    parser.add_argument("--dilation-radius", type=int, default=2, help="颗粒掩码膨胀半径, 默认 2")
    parser.add_argument(
        "--exclude-bottom-ratio",
        type=float,
        default=0.0,
        help="可选: 忽略底部区域的比例, 例如 0.1 表示忽略底部 10%%",
    )
    return parser.parse_args()


def build_config_from_args(args: argparse.Namespace) -> ParticleMaskConfig:
    """从命令行参数构造配置."""

    return ParticleMaskConfig(
        min_brightness=args.min_brightness,
        min_residual=args.min_residual,
        blur_radius=args.blur_radius,
        max_background_brightness=args.max_background_brightness,
        peak_window=args.peak_window,
        peak_slack=args.peak_slack,
        local_std_radius=args.local_std_radius,
        max_local_std=args.max_local_std,
        min_component_area=args.min_component_area,
        max_component_area=args.max_component_area,
        max_component_span=args.max_component_span,
        max_component_aspect_ratio=args.max_component_aspect_ratio,
        dilation_radius=args.dilation_radius,
        exclude_bottom_ratio=args.exclude_bottom_ratio,
    )


def main() -> None:
    """脚本入口."""

    args = parse_args()
    config = build_config_from_args(args)

    summary = process_image_directory(
        images_dir=args.images_dir,
        output_dir=args.output_dir,
        config=config,
        debug_dir=args.debug_dir,
        debug_samples=args.debug_samples,
        overwrite=args.overwrite,
    )

    if args.summary_path is not None:
        args.summary_path.parent.mkdir(parents=True, exist_ok=True)
        args.summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    print(
        json.dumps(
            {
                "image_count": summary["image_count"],
                "total_masked_pixels": summary["total_masked_pixels"],
                "average_mask_ratio": summary["average_mask_ratio"],
                "max_mask_ratio": summary["max_mask_ratio"],
                "output_dir": summary["output_dir"],
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()

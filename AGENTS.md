# Repository Guidelines

## Project Structure & Module Organization
- `train.py`: main training entrypoint (defaults to `./output/<uuid>/` unless `-m/--model_path` is set).
- `render.py`: renders train/test views for a trained run.
- `metrics.py`: computes PSNR/SSIM/LPIPS from rendered outputs.
- `arguments/`: argparse parameter groups shared by scripts.
- `gaussian_renderer/`, `scene/`, `utils/`: core training, rendering, and data utilities.
- `submodules/`: CUDA extensions (`diff-gaussian-rasterization_fastgs`, `simple-knn`, `fused-ssim`).
- `assets/`: images used by `README.md`.

Runtime data is expected under `./datasets/` (not tracked in git). Training outputs land in `./output/` (also untracked).

## Build, Test, and Development Commands
- Recommended (Pixi):
  - Install env from lockfile: `pixi install --frozen`
  - Build local CUDA extensions: `pixi run setup`
  - Run scripts: `pixi run python train.py ...`, `pixi run python render.py ...`, `pixi run python metrics.py ...`
- Alternative (Conda): `conda env create -f environment.yml && conda activate fastgs`
- Train one scene:
  - `python train.py -s ./datasets/mipnerf360/bicycle -i images --eval`
  - Quick smoke run: add `--iterations 100` to validate CUDA build + data loading.
- Paper presets (multi-scene, then render + metrics): `bash train_base.sh` or `bash train_big.sh`
- Render a run: `python render.py -m output/<run_id> --skip_train`
- Evaluate metrics: `python metrics.py -m output/<run_id>`

Note: first install/run may compile CUDA extensions from `submodules/`. Ensure `nvcc` and a C++ compiler match your PyTorch/CUDA setup.

## Coding Style & Naming Conventions
- Python: 4-space indentation, keep diffs small, and follow the existing file-local style.
- Naming: `snake_case` for functions/vars, `CamelCase` for classes (e.g., `GaussianModel`).
- No formatter/linter is enforced here; avoid reformat-only commits.

## Testing Guidelines
- This repo does not ship a unit test suite. Validate changes via an integration loop:
  1) run a short training (`--iterations 100`),
  2) `render.py` on the produced `output/<run_id>`,
  3) `metrics.py` to confirm outputs are sensible.

## Commit & Pull Request Guidelines
- Commit subjects in history are short and action-oriented (e.g., `Update README.md`, `clean`), sometimes with a scope tag like `[FastGS] ...`. Follow that convention.
- PRs should include: what changed, exact reproduction commands, dataset/scene used, hardware (GPU + CUDA), and before/after speed or quality metrics when relevant.

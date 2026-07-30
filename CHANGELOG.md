# Changelog

All notable changes to SparkyUI (Dataspar Fork) are documented here.

---

## [prod-sparkle] — 2026-07-30

### Added
- `Dockerfile`: onnxruntime built from source (v1.24.4, `CMAKE_CUDA_ARCHITECTURES=121`) with cuDNN 9 for CUDA 13 —
  onnxruntime-gpu has no aarch64 PyPI wheels, so comfyui_controlnet_aux's DWPose preprocessor was silently
  falling back to CPU/OpenCV inference.
- `Dockerfile`: llama-cpp-python built from source with CUDA (`GGML_CUDA=on`, `CMAKE_CUDA_ARCHITECTURES=121`) —
  abetlen's prebuilt wheel index is x86_64/win_amd64-only for every CUDA tag, so comfyui_llm_party's local-GGUF
  inference install was failing on every container start.
- `Dockerfile`: `uv` added to the venv's packaging tools — used by `entrypoint.sh` to resolve all custom node
  `requirements.txt` files together in a single pass instead of installing them one at a time with pip.

### Fixed
- `entrypoint.sh`: custom node dependency installation now uses a single unified `uv pip install` across every
  `custom_nodes/*/requirements.txt` file, constrained so torch/torchvision/torchaudio can never be swapped away
  from the pinned cu130/sm_121 build, falling back to per-node `uv` installs (still constrained) if the unified
  resolve fails outright. This replaces the previous per-line `pip install` approach, which avoided pip's
  "resolution-too-deep" abort but let installs silently drift out of sync with each other — which is what caused
  ComfyUI_LayerStyle's opencv-python 5.x (requires numpy>=2) to land next to an already-installed numpy 1.26.4,
  an ABI break that kept the container from ever finishing startup. This mirrors the fix the ComfyUI ecosystem
  itself adopted for the same systemic problem: comfy-cli's `--fast-deps` and ComfyUI-Manager's `use_uv` both
  batch-resolve core + all custom node dependencies together via uv rather than installing them independently.
- `Dockerfile`: onnxruntime source build now passes `--allow_running_as_root` — Docker `RUN` steps execute as
  root by default, and onnxruntime's `build.sh` has an explicit safety guard against that which was aborting the
  build immediately (`Running as root is not allowed`). Root inside an isolated Docker build stage is expected
  and fine; this is the flag onnxruntime ships for exactly that case.
- `docker-compose.yml`: added `pull_policy: build` to `comfyui` and `comfyuimini`. Both services are locally-built
  only and were never published to any registry; Portainer's GitOps redeploy runs `docker compose pull` before
  `up`, which was failing with "pull access denied ... repository does not exist" and aborting the deploy before
  it could even stage the stack directory (the same failure surfaced separately as a missing `stack.env` file when
  starting the stack manually).

---

## [prod-sparkle] — 2026-06-03

### Added
- `COMFYUI_LISTEN` environment variable to restrict which host network interface exposes the ComfyUI port.
  Set to a Tailscale IP (e.g. `100.x.x.x`) to limit external access to the tailnet only; defaults to `0.0.0.0` (all interfaces).
  Implemented as a Docker host-side port binding (`COMFYUI_LISTEN:PORT:8188`) rather than the ComfyUI `--listen` flag —
  the container always binds internally on `0.0.0.0` so healthchecks and internal routing remain unaffected.

### Changed
- `memory/` directory added to `.gitignore` — Claude Code memory files are host-specific and not tracked in the repo.

---

## [prod-sparkle] — 2026-06-01

Architecture pivot: strip all file-level monkey-patches and rely on native ComfyUI upstream support for Grace-Blackwell unified memory.

### Removed
- All static file patches (`patches/model_management.py`, `patches/utils.py`, `patches/sitecustomize.py`)
  and their volume mounts — upstream ComfyUI now handles `cudaMallocAsync` allocation natively.
- `sitecustomize` PYTHONPATH hook and associated Dockerfile injection (rendered obsolete by the patch removal).

### Fixed
- Removed `sitecustomize` monkey-patch that was causing `cudaMallocAsync` allocator crashes and drift-related pipeline failures.

### Changed
- `docker-compose.yml`: commented out `patches/` volume mounts for `utils.py` and `model_management.py`.
- `docker-compose.yml`: added explicit IPv4 healthcheck (`127.0.0.1`) for the `comfyuimini` container to prevent IPv6 loopback collision on Alpine/Node deployments.
- `README.md`: rewrote architecture section to reflect native Grace-Blackwell handling and Portainer GitOps deployment model.

---

## [prod-sparkle] — 2026-06-01 (Video / headless pipeline)

### Added
- `Dockerfile`: baked in `libxcb`, minimal X11 display libraries, and hardware-accelerated ARM64 FFmpeg to permanently resolve headless container `ImportError` crashes from nodes like `ComfyUI-VideoHelperSuite`.
- `IMAGEIO_FFMPEG_EXE` env var mapped to `/usr/local/bin/ffmpeg` for hardware-accelerated video encoding on Blackwell.
- `NVIDIA_VISIBLE_DEVICES`, `NVIDIA_DRIVER_CAPABILITIES` env vars for NVENC support.

---

## [prod-sparkle] — 2026-05-21

### Added
- `patches/utils.py`: full upstream `utils.py` with `copy=False` patch for unified memory — avoids redundant CPU→GPU tensor copies across the NVLink-C2C fabric.
- `CUDA_CACHE_MAXSIZE=4294967296` (4 GB) kernel cache for PTX→SASS compilation; eliminates repeated compile overhead after first run.
- `NORMAL_VRAM` mode with AIMDO (Attention in Mixed-Precision with Dynamic Offloading) enabled.

### Fixed
- `intermediate_device()` now correctly returns `cuda` on unified memory systems (reverts the earlier CPU revert; `cuda` is correct for Grace-Blackwell).

---

## [prod-sparkle] — 2026-05-20

### Added
- `patches/model_management.py`: Grace-Blackwell unified memory optimization — removes aggressive VRAM limits that misread the CPU/GPU shared fabric as a constraint.
- `SPARKY_REVIEW.md`: architecture review document for the unified memory approach.

### Fixed
- `intermediate_device()` reverted to return `cpu` as an intermediate fix for unified memory mis-detection (subsequently corrected in 2026-05-21).

---

## [prod-sparkle] — 2026-01-03

### Added
- `comfyuimini` service: lightweight, mobile-friendly web UI running in a separate container on port 3000.
  Connects to the `comfyui` container via the internal `sparky_net` Docker bridge network.
- `sparky_net` Docker bridge network isolating ComfyUI and ComfyUIMini traffic.
- `comfyuimini_workflows` named volume for persisting server-side workflows across restarts.

### Changed
- `COMFYUI_FLAGS` default updated with Grace-Blackwell-optimized launch flags:
  `--disable-pinned-memory`, `--dont-upcast-attention`, and related precision flags.
- `docker-compose.yml` restructured for absolute host path mounts and Portainer GitOps compatibility.

---

## [initial] — 2026-01-03

### Added
- Initial `SparkyUI` fork targeting NVIDIA DGX Spark (GB10, ARM64, sm_121 / Blackwell).
- `Dockerfile` based on CUDA 13.0 to enable sm_121 compilation support.
- PyTorch `cu130` ARM64 wheel installation.
- SageAttention compiled natively with `TORCH_CUDA_ARCH_LIST="12.1"`.
- `TORCHDYNAMO_DISABLE=1` / `TORCH_COMPILE_DISABLE=1` to skip Triton (no sm_121 support at launch).
- `entrypoint.sh` for ComfyUI startup with configurable flags and automatic ComfyUI-Manager bootstrap.
- `stack.env` template for Portainer environment variable management.

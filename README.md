# SparkyUI (Dataspar Fork) - Native DGX Spark Optimization

ComfyUI + SageAttention tailored for the NVIDIA DGX Spark (Blackwell GB10, ARM64, sm_121).

## 🚀 Dataspar Architecture Update (June 2026)
This branch (`prod-sparkle`) prioritizes clean infrastructure architecture over brittle workarounds. As of May 2026, the upstream ComfyUI repository natively integrated robust Grace-Blackwell unified memory handling. 

Therefore, this fork **strips out all legacy file monkey-patches** (e.g., static `model_management.py` and `utils.py` volume remaps) that were causing `cudaMallocAsync` allocator crashes and drift-related pipeline failures. By relying on native driver allocation, this stack allows ComfyUI to pull the absolute newest upstream code without interference.

### 🏗️ Key Infrastructure Enhancements
1. **Native Unified Memory:** Removed legacy `Triplany` and SparkyUI file-level VRAM patches. ComfyUI now dynamically scales across the NVLink-C2C fabric using its own updated internal safeguards.
2. **Headless Video Processing Support:** Baked `libxcb`, minimal X11 display libraries, and hardware-accelerated ARM64 FFmpeg natively into the `Dockerfile`. This permanently resolves the headless container traps and `ImportError` crashes when utilizing nodes like `ComfyUI-VideoHelperSuite`.
3. **Portainer GitOps Ready:** Streamlined `docker-compose.yml` to utilize absolute host paths and isolated health checks, making it fully compatible with automated Webhook/Polling deployments via Portainer Business Edition.

### ⚙️ Deployment Instructions (GitOps / Portainer)
When deploying this stack via Portainer or standard Compose, ensure you map the absolute paths to your physical storage using the environment variables.

**Required Environment Variables:**
* `COMFYUI_HOST_PATH=/path/to/your/ComfyUI/models`
* `SPARKYUI_DATA_PATH=/path/to/your/custom_nodes_and_outputs`

**Optional Environment Variables:**
* `COMFYUI_LISTEN=0.0.0.0` — IP address ComfyUI binds to. Set to your Tailscale IP (e.g. `100.x.x.x`) to restrict access to the tailnet only. Defaults to `0.0.0.0` (all interfaces).
* `COMFYUI_PORT=8188` — Port for the ComfyUI web UI.
* `COMFYUIMINI_PORT=3000` — Port for the ComfyUIMini mobile UI.
* `COMFYUI_FLAGS` — Full override for ComfyUI launch flags. When set, `COMFYUI_LISTEN` is ignored; include `--listen` explicitly.

*Note on Portainer:* Do **not** use the "Enable relative path volumes" toggle. Pass the absolute host directory paths directly through the Portainer environment variables panel to ensure your `.safetensors` and output videos remain accessible on the primary host filesystem.

---

*(Original Upstream Documentation Below)*

## Why This Exists
The NVIDIA DGX Spark uses the GB10 GPU with compute capability 12.1 (sm_121) - Blackwell architecture. This creates challenges:

| CUDA Version | Max Compute Capability | Can compile for GB10? |
|--------------|------------------------|-----------------------|
| CUDA 12.8    | sm_120                 | No                    |
| CUDA 13.0+   | sm_121                 | Yes                   |

Standard ComfyUI containers and PyTorch wheels don't support sm_121. SparkyUI solves this by:
* Using CUDA 13.0.2 base image (supports sm_121)
* Installing PyTorch cu130 ARM64 wheels (v2.9.1+)
* Compiling SageAttention natively with `TORCH_CUDA_ARCH_LIST="12.1"`
* Disabling Triton/torch.compile via `TORCHDYNAMO_DISABLE=1`
* Optimizing for Grace-Blackwell unified memory architecture

## Unified Memory Architecture
The DGX Spark's Grace-Blackwell architecture uses unified memory - a coherent memory fabric shared between CPU and GPU. 

**Key insight:** Don't fight the fabric. Forcing everything GPU-side (`--gpu-only`, `--cache-none`) hurts performance.

Optimized flags (default in SparkyUI):
* `--disable-pinned-memory`: Reduces overhead on unified fabric
* `--force-fp16`: Enables SageAttention optimization
* `--fp16-unet --fp16-vae --fp16-text-enc`: FP16 precision throughout
* `--dont-upcast-attention`: Keeps attention in FP16 for speed

## ComfyUIMini (Mobile UI)
SparkyUI includes ComfyUIMini - a lightweight, mobile-friendly web UI running in a separate container.
* Responsive design optimized for phones and tablets
* Access: `http://<your-dgx-ip>:3000`
* Note: Utilizes a hardcoded IPv4 healthcheck (`127.0.0.1`) to prevent IPv6 loopback collisions on Alpine Node deployments.

## Credits
* Unified memory architecture insights from the DGX Spark Community
* ComfyUIMini by ImDarkTom
* SageAttention by thu-ml
* ComfyUI by comfyanonymous

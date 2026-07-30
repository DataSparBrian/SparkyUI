# CUDA 13.0 for Blackwell GB10 (sm_121 / compute_121)
# CUDA 12.8 only supports up to sm_120, but GB10 is sm_121.
# "devel" includes nvcc so we can compile CUDA extensions like SageAttention.
FROM nvidia/cuda:13.0.2-devel-ubuntu24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG COMFYUI_REF=master
ARG SAGEATTN_REF=main

# Base system deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl ca-certificates \
    python3 python3-pip python3-venv python3-dev \
    build-essential ninja-build cmake pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Inject headless UI libraries for OpenCV and hardware-accelerated ARM64 FFmpeg
RUN apt-get update && apt-get install -y \
    libxcb1 \
    libxrender1 \
    libxext6 \
    libgl1 \
    libglib2.0-0 \
    wget \
    xz-utils \
    && wget https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linuxarm64-gpl.tar.xz -O /tmp/ffmpeg.tar.xz \
    && tar -xf /tmp/ffmpeg.tar.xz -C /tmp \
    && mv /tmp/ffmpeg-master-latest-linuxarm64-gpl/bin/ffmpeg /usr/local/bin/ffmpeg \
    && mv /tmp/ffmpeg-master-latest-linuxarm64-gpl/bin/ffprobe /usr/local/bin/ffprobe \
    && rm -rf /tmp/ffmpeg* /var/lib/apt/lists/*

# Create venv (keeps python deps isolated inside container)
ENV VENV=/opt/venv
RUN python3 -m venv $VENV
ENV PATH="$VENV/bin:$PATH"

# Upgrade packaging tools
RUN pip install -U pip setuptools wheel

# ---- PyTorch (ARM64 + CUDA 13.0) ----
# PyTorch cu130 wheels work with CUDA 13.0.x runtime.
# ARM64 wheels available: torch-2.9.1+cu130, torchvision-0.24.1
RUN pip install --index-url https://download.pytorch.org/whl/cu130 \
    torch torchvision

# ---- ComfyUI ----
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI && \
    cd /opt/ComfyUI && \
    git checkout ${COMFYUI_REF} || true

RUN pip install -r /opt/ComfyUI/requirements.txt

# ---- ComfyUI-Manager ----
# Handled at runtime by entrypoint.sh (clones if missing in mounted volume)
# This ensures latest version on each container start

# ---- SageAttention ----
# GB10 is compute capability 12.1 (sm_121).
# CUDA 13.0 NVCC supports sm_121, so we compile directly for it.
ENV TORCH_CUDA_ARCH_LIST="12.1"
ENV CUDA_HOME=/usr/local/cuda

# Build/install SageAttention from repo with sm_121 support
RUN pip install --no-build-isolation "git+https://github.com/thu-ml/SageAttention@${SAGEATTN_REF}" || true

# ---- ONNX Runtime GPU (built from source — no aarch64 wheels exist upstream) ----
# onnxruntime-gpu publishes x86_64/win_amd64 wheels only; without a GPU-enabled build here,
# comfyui_controlnet_aux's DWPose preprocessor silently falls back to slow CPU/OpenCV inference.
# cuDNN 9 for CUDA 13 is required by the build and isn't present in the base devel image.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libcudnn9-cuda-13 libcudnn9-dev-cuda-13 \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --recursive --branch v1.24.4 --depth 1 \
        https://github.com/microsoft/onnxruntime /opt/onnxruntime && \
    cd /opt/onnxruntime && \
    ./build.sh --config Release --build_wheel --update --build --skip_tests \
        --parallel --nvcc_threads 4 \
        --use_cuda --cuda_version 13 --cuda_home /usr/local/cuda --cudnn_home /usr \
        --cmake_generator Ninja \
        --cmake_extra_defines CMAKE_CUDA_ARCHITECTURES=121 onnxruntime_BUILD_UNIT_TESTS=OFF && \
    pip install /opt/onnxruntime/build/Linux/Release/dist/onnxruntime_gpu-*.whl && \
    cd / && rm -rf /opt/onnxruntime

# ---- llama-cpp-python (built from source with CUDA — abetlen's wheel index is x86_64-only) ----
# comfyui_llm_party tries to pip-install from https://abetlen.github.io/llama-cpp-python/whl/, which
# has never published ARM64 wheels for any CUDA version. Build it directly against sm_121 instead.
ENV CUDACXX=/usr/local/cuda/bin/nvcc
RUN CMAKE_ARGS="-DGGML_CUDA=on -DCMAKE_CUDA_ARCHITECTURES=121 -DGGML_CUDA_F16=ON" \
    FORCE_CMAKE=1 \
    pip install --no-cache-dir llama-cpp-python

# Expose ComfyUI
EXPOSE 8188

# Entry script handles runtime updates / flags
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

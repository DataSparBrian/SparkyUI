# SparkyUI app image - ComfyUI itself + entrypoint, built FROM the pre-built sparkyui-base image
# (CUDA/PyTorch/SageAttention/onnxruntime-gpu/llama-cpp-python -- see Dockerfile.base).
#
# Day-to-day changes here (entrypoint.sh, COMFYUI_REF) never re-trigger the slow compiles baked
# into the base image -- only changing Dockerfile.base itself does, and that's a deliberate,
# separate build+push step (see Dockerfile.base for instructions).
ARG SPARKYUI_BASE_IMAGE=ghcr.io/datasparbrian/sparkyui-base:cu130-1
FROM ${SPARKYUI_BASE_IMAGE}

ARG COMFYUI_REF=master

# ---- ComfyUI ----
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI && \
    cd /opt/ComfyUI && \
    git checkout ${COMFYUI_REF} || true

RUN pip install -r /opt/ComfyUI/requirements.txt

# ---- ComfyUI-Manager ----
# Handled at runtime by entrypoint.sh (clones if missing in mounted volume)
# This ensures latest version on each container start

# Expose ComfyUI
EXPOSE 8188

# Entry script handles runtime updates / flags
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

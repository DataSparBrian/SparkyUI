#!/usr/bin/env bash
set -euo pipefail

COMFY_DIR="/opt/ComfyUI"
PORT="${COMFYUI_PORT:-8188}"
FLAGS="${COMFYUI_FLAGS:---listen 0.0.0.0 --port ${PORT} --disable-pinned-memory --dont-upcast-attention}"

echo "[entrypoint] Python: $(python --version)"
echo "[entrypoint] Torch:  $(python -c 'import torch; print(torch.__version__)')"
echo "[entrypoint] CUDA:   $(python -c 'import torch; print(torch.version.cuda)')"
echo "[entrypoint] Flags:  ${FLAGS}"

# Ensure ComfyUI-Manager exists in mounted custom_nodes
# Check for __init__.py to detect corrupted/partial installs
if [[ ! -f "${COMFY_DIR}/custom_nodes/ComfyUI-Manager/__init__.py" ]]; then
    echo "[entrypoint] ComfyUI-Manager missing or corrupted, cloning latest..."
    rm -rf "${COMFY_DIR}/custom_nodes/ComfyUI-Manager" 2>/dev/null || true
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git \
        "${COMFY_DIR}/custom_nodes/ComfyUI-Manager" || true
fi

# Install custom node requirements one package at a time. A single
# `pip install -r requirements.txt` forces pip to resolve every package in
# the file at once — large/loosely-pinned node requirement files (e.g.
# ComfyUI_LayerStyle) can exceed pip's resolver depth limit
# ("resolution-too-deep") and abort the WHOLE file, silently skipping every
# package in it. torch/torchvision/torchaudio lines are skipped outright so
# a node's unpinned `torch` requirement can never clobber the pinned
# cu130/sm_121 PyTorch build.
for req in "${COMFY_DIR}"/custom_nodes/*/requirements.txt; do
    if [[ -f "$req" ]]; then
        echo "[entrypoint] Installing deps from: $req"
        grep -vE '^[[:space:]]*(#|torch([[:space:]<>=!~]|$)|torchvision([[:space:]<>=!~]|$)|torchaudio([[:space:]<>=!~]|$))' "$req" | \
        while IFS= read -r pkgline; do
            [[ -z "$(echo "$pkgline" | tr -d '[:space:]')" ]] && continue
            pip install -q "$pkgline" || echo "[entrypoint] WARN: failed to install '$pkgline' from $req" >&2
        done
    fi
done
pip check || true

exec python "${COMFY_DIR}/main.py" ${FLAGS}

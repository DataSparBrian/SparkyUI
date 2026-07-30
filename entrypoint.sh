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

# Install all custom node requirements together, resolved in one pass by uv
# (mirrors comfy-cli's `--fast-deps` / ComfyUI-Manager's `use_uv` approach).
# Installing each node's requirements.txt independently (an earlier fix)
# avoided pip's "resolution-too-deep" abort, but let each install drift out
# of sync with what earlier nodes had already installed with no cross-check.
# uv's resolver doesn't have pip's backtracking depth limit, so it can
# resolve core + every node's requirements.txt together instead, landing on
# mutually consistent versions across the whole graph.
#
# A unified resolve can still legitimately fail when two nodes want
# genuinely incompatible things (not a resolver limitation -- a real
# conflict). Falls back in two stages so one bad node -- or even one bad
# package within a node -- can't take down everything else:
#   1. Per-node: install each requirements.txt independently.
#   2. Per-package: if a single node's requirements.txt still fails as a
#      whole (e.g. it bundles one genuinely unsatisfiable package alongside
#      otherwise-fine ones), install that node's lines one at a time so only
#      the actually-broken package is skipped.
#
# torch/torchvision/torchaudio are pinned via a constraints file to whatever
# is already installed (the cu130/sm_121 build) at every stage, so no node's
# requirements.txt can cause uv to swap them for a generic PyPI build.
REQ_FILES=()
for req in "${COMFY_DIR}"/custom_nodes/*/requirements.txt; do
    [[ -f "$req" ]] && REQ_FILES+=(-r "$req")
done

if [[ ${#REQ_FILES[@]} -gt 0 ]]; then
    echo "[entrypoint] Resolving ${#REQ_FILES[@]} custom node requirements.txt files together via uv..."
    CONSTRAINTS_FILE=$(mktemp)
    pip freeze 2>/dev/null | grep -E '^(torch|torchvision|torchaudio)==' > "$CONSTRAINTS_FILE" || true

    if uv pip install --python "$(which python)" -c "$CONSTRAINTS_FILE" "${REQ_FILES[@]}"; then
        echo "[entrypoint] Unified custom node dependency install succeeded."
    else
        echo "[entrypoint] WARN: unified uv install failed - falling back to per-node installs so one bad node doesn't block the rest." >&2
        for req in "${COMFY_DIR}"/custom_nodes/*/requirements.txt; do
            if [[ -f "$req" ]]; then
                echo "[entrypoint] Installing deps from: $req"
                if uv pip install --python "$(which python)" -c "$CONSTRAINTS_FILE" -r "$req"; then
                    continue
                fi
                echo "[entrypoint] WARN: $req failed as a whole - falling back to per-package installs so one bad package doesn't block the rest of this node." >&2
                grep -vE '^[[:space:]]*(#|$)' "$req" | while IFS= read -r pkgline; do
                    uv pip install --python "$(which python)" -c "$CONSTRAINTS_FILE" "$pkgline" \
                        || echo "[entrypoint] WARN: failed to install '$pkgline' from $req" >&2
                done
            fi
        done
    fi
    rm -f "$CONSTRAINTS_FILE"
fi
pip check || true

exec python "${COMFY_DIR}/main.py" ${FLAGS}

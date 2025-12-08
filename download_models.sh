#!/bin/bash
set -e

BASE="/app/ComfyUI/models"
HF_REPO="umrrrrrr/UMRGEN"
MODELS_ZIP="core_models_content.zip"

echo "=============================================="
echo ">>> AIEGO Model Downloader"
echo ">>> Source: huggingface.co/datasets/$HF_REPO"
echo "=============================================="

# Check if models already exist (for Network Volume persistence)
if [ -f "$BASE/.models_ready" ]; then
    echo ">>> Models already downloaded, skipping..."
    exit 0
fi

mkdir -p "$BASE"
cd /tmp

# ==============================================================================
# Download with aria2 for speed (multi-connection)
# ==============================================================================
echo ">>> Downloading $MODELS_ZIP..."

# Try aria2 first (faster), fallback to wget
if command -v aria2c &> /dev/null; then
    aria2c -x 16 -s 16 -k 1M \
        "https://huggingface.co/datasets/$HF_REPO/resolve/main/$MODELS_ZIP" \
        -o "$MODELS_ZIP"
else
    wget -q --show-progress \
        "https://huggingface.co/datasets/$HF_REPO/resolve/main/$MODELS_ZIP" \
        -O "$MODELS_ZIP"
fi

echo ">>> Extracting models..."
unzip -o "$MODELS_ZIP" -d "$BASE"

echo ">>> Cleaning up..."
rm -f "$MODELS_ZIP"

# Mark as complete
touch "$BASE/.models_ready"

echo ">>> Models ready!"
echo "=============================================="

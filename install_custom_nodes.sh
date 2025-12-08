#!/bin/bash
set -e

NODES_DIR="/app/ComfyUI/custom_nodes"
HF_REPO="umrrrrrr/UMRGEN"
NODES_ZIP="custom_nodes.zip"

echo "=============================================="
echo ">>> AIEGO Custom Nodes Installer"
echo "=============================================="

# Check if already installed
if [ -f "$NODES_DIR/.nodes_ready" ]; then
    echo ">>> Custom nodes already installed, skipping..."
    exit 0
fi

mkdir -p "$NODES_DIR"
cd /tmp

# ==============================================================================
# Download custom nodes archive
# ==============================================================================
echo ">>> Downloading $NODES_ZIP..."

if command -v aria2c &> /dev/null; then
    aria2c -x 16 -s 16 -k 1M \
        "https://huggingface.co/datasets/$HF_REPO/resolve/main/$NODES_ZIP" \
        -o "$NODES_ZIP"
else
    wget -q --show-progress \
        "https://huggingface.co/datasets/$HF_REPO/resolve/main/$NODES_ZIP" \
        -O "$NODES_ZIP"
fi

echo ">>> Extracting custom nodes..."
unzip -o "$NODES_ZIP" -d "$NODES_DIR"

rm -f "$NODES_ZIP"

# ==============================================================================
# Install dependencies for each node
# ==============================================================================
echo ">>> Installing node dependencies..."

# Impact Pack
IMPACT_PACK_DIR="$NODES_DIR/ComfyUI-Impact-Pack"
if [ -d "$IMPACT_PACK_DIR" ]; then
    echo ">>> Installing Impact Pack..."
    cd "$IMPACT_PACK_DIR"
    pip3 install -r requirements.txt --break-system-packages --quiet 2>/dev/null || \
    pip3 install -r requirements.txt --quiet
    python3 install.py 2>/dev/null || true
    cd /tmp
fi

# ComfyUI-CRT
CRT_DIR="$NODES_DIR/ComfyUI-CRT"
if [ -d "$CRT_DIR" ] && [ -f "$CRT_DIR/requirements.txt" ]; then
    echo ">>> Installing ComfyUI-CRT..."
    pip3 install -r "$CRT_DIR/requirements.txt" --break-system-packages --quiet 2>/dev/null || \
    pip3 install -r "$CRT_DIR/requirements.txt" --quiet
fi

# Mark as complete
touch "$NODES_DIR/.nodes_ready"

echo ">>> Custom nodes ready!"
echo "=============================================="

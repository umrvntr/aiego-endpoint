#!/bin/bash
set -e

echo "=============================================="
echo ">>> AIEGO Endpoint v0.8"
echo ">>> Z-Image Turbo + FaceDetailer + CRT"
echo "=============================================="

# ==============================================================================
# 1. Download models from HuggingFace (if not already present)
# ==============================================================================
echo ">>> Step 1/4: Checking models..."
/app/download_models.sh

# ==============================================================================
# 2. Install custom nodes (if not already present)
# ==============================================================================
echo ">>> Step 2/4: Checking custom nodes..."
/app/install_custom_nodes.sh

# ==============================================================================
# 3. Start ComfyUI in background
# ==============================================================================
echo ">>> Step 3/4: Starting ComfyUI..."
cd /app/ComfyUI
python3 main.py --listen 127.0.0.1 --port 8188 --disable-auto-launch &

# Wait for ComfyUI to be ready
echo ">>> Waiting for ComfyUI to initialize..."
MAX_WAIT=120
for i in $(seq 1 $MAX_WAIT); do
    if curl -s http://127.0.0.1:8188/system_stats > /dev/null 2>&1; then
        echo ">>> ComfyUI ready after ${i}s"
        break
    fi
    if [ $i -eq $MAX_WAIT ]; then
        echo ">>> ERROR: ComfyUI failed to start!"
        exit 1
    fi
    sleep 1
done

# ==============================================================================
# 4. Start RunPod handler
# ==============================================================================
echo ">>> Step 4/4: Starting RunPod handler..."
echo "=============================================="
echo ">>> AIEGO Endpoint READY"
echo "=============================================="

cd /app
exec python3 -u rp_handler.py

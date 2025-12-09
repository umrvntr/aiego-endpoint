#!/bin/bash
set -e

echo "🚀 Starting ComfyUI..."

# Запуск ComfyUI как сервиса (headless mode)
python3 /app/ComfyUI/main.py --listen 0.0.0.0 --port 8188 &

# Ждём поднятия API
echo "⏳ Waiting for ComfyUI to start..."
sleep 8

echo "🚀 Starting RunPod handler..."
node /app/handler.mjs

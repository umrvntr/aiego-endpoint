FROM nvidia/cuda:12.2.0-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV HF_HUB_ENABLE_HF_TRANSFER=1

# ==============================================================================
# 1. System packages
# ==============================================================================
RUN apt-get update && apt-get install -y \
    git \
    wget \
    curl \
    python3 \
    python3-pip \
    ffmpeg \
    unzip \
    libgl1-mesa-glx \
    libglib2.0-0 \
    aria2 \
    && rm -rf /var/lib/apt/lists/*

# ==============================================================================
# 2. Working directory
# ==============================================================================
WORKDIR /app

# ==============================================================================
# 3. Clone ComfyUI
# ==============================================================================
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /app/ComfyUI

# ==============================================================================
# 4. Python dependencies
# ==============================================================================
RUN pip3 install --no-cache-dir --upgrade pip && \
    pip3 install --no-cache-dir \
    runpod \
    requests \
    websocket-client \
    hf_transfer \
    huggingface_hub \
    && pip3 install --no-cache-dir -r /app/ComfyUI/requirements.txt

# ==============================================================================
# 5. Copy all scripts
# ==============================================================================
COPY download_models.sh /app/download_models.sh
COPY install_custom_nodes.sh /app/install_custom_nodes.sh
COPY start.sh /app/start.sh
COPY rp_handler.py /app/rp_handler.py

RUN chmod +x /app/*.sh

# ==============================================================================
# 6. Models download at RUNTIME (not build time!)
#    This keeps the Docker image small (~3-4GB instead of 20GB+)
# ==============================================================================

# ==============================================================================
# 7. Start
# ==============================================================================
CMD ["bash", "/app/start.sh"]

FROM nvidia/cuda:12.1.1-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------
# 1. SYSTEM DEPS
# ---------------------------------------------------------
RUN apt-get update && apt-get install -y \
    git wget curl unzip python3 python3-venv python3-pip \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------
# 2. INSTALL COMFYUI
# ---------------------------------------------------------
WORKDIR /app
RUN git clone https://github.com/comfyanonymous/ComfyUI.git

WORKDIR /app/ComfyUI
RUN python3 -m venv venv
ENV PATH="/app/ComfyUI/venv/bin:$PATH"

RUN pip install --upgrade pip wheel setuptools
RUN pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
RUN pip install -r requirements.txt

# ---------------------------------------------------------
# 3. CREATE Z-IMAGE MODEL DIRECTORIES
# ---------------------------------------------------------
RUN mkdir -p models/diffusion_models \
    models/text_encoders \
    models/vae \
    models/upscale_models \
    models/ultralytics/bbox \
    models/sams \
    models/loras

# ---------------------------------------------------------
# 4. DOWNLOAD MODELS (ALL FROM HF)
# ---------------------------------------------------------

# --- Z-IMAGE UNET
RUN wget -O models/diffusion_models/z_image_turbo_bf16_nsfw_v2.safetensors \
  https://huggingface.co/tewea/z_image_turbo_bf16_nsfw/resolve/main/z_image_turbo_bf16_nsfw_v2.safetensors

# --- QWEN TEXT ENCODER
RUN wget -O models/text_encoders/qwen_3_4b.safetensors \
  https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors

# --- VAE
RUN wget -O models/vae/ae.safetensors \
  https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors

# --- UPSCALE Remacri
RUN wget -O models/upscale_models/4x_foolhardy_Remacri.pth \
  https://huggingface.co/FacehugmanIII/4x_foolhardy_Remacri/resolve/main/4x_foolhardy_Remacri.pth

# --- YOLOv8 Face Detector
RUN wget -O models/ultralytics/bbox/yolov8l.pt \
  https://huggingface.co/Ultralytics/YOLOv8/resolve/main/yolov8l.pt

# --- SAM Vit-B Model
RUN wget -O models/sams/sam_vit_b_01ec64.pth \
  https://huggingface.co/GleghornLab/sam_vit_b_01ec64.pth/resolve/main/sam_vit_b_01ec64.pth


# ---------------------------------------------------------
# 5. CUSTOM NODES — DOWNLOAD ZIP & EXTRACT
# ---------------------------------------------------------

WORKDIR /app/ComfyUI

# Download ZIP containing custom nodes
RUN wget -O umrgen.zip \
  https://huggingface.co/datasets/umrrrrrrr/UMRGEN/resolve/main/umrgen.zip

# Extract ZIP into folder "umrgen"
RUN unzip umrgen.zip -d umrgen

# Move ONLY custom_nodes into ComfyUI/custom_nodes
RUN mkdir -p custom_nodes && \
    cp -r umrgen/custom_nodes/* custom_nodes/

# Cleanup temp
RUN rm -rf umrgen umrgen.zip


# ---------------------------------------------------------
# 6. INSTALL SERVERLESS HANDLER (Node)
# ---------------------------------------------------------
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY handler.mjs .

CMD ["node", "handler.mjs"]

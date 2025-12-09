import runpod from "runpod";
import fetch from "node-fetch";
import WebSocket from "ws";
import { spawn } from "child_process";
import { randomUUID } from "node:crypto";

// ========== COMFY CONFIG ==========
const COMFY_PORT = 8188;
const COMFY_HOST = `127.0.0.1:${COMFY_PORT}`;
const COMFY_HTTP = `http://${COMFY_HOST}`;
const COMFY_WS = `ws://${COMFY_HOST}/ws`;

let comfyProcess = null;

// ======================================================
// START COMFYUI
// ======================================================
function startComfy() {
    if (comfyProcess && comfyProcess.exitCode === null) return comfyProcess;

    comfyProcess = spawn("python3", [
        "/app/ComfyUI/main.py",
        "--listen", "127.0.0.1",
        "--port", `${COMFY_PORT}`,
        "--nowebui"
    ]);

    comfyProcess.stdout.on("data", d => {
        const msg = d.toString();
        if (msg.includes("Listening")) console.log(">>> ComfyUI ready:", msg.trim());
    });

    comfyProcess.stderr.on("data", d => {
        console.error(">>> ComfyUI Error:", d.toString());
    });

    return comfyProcess;
}

// ======================================================
// WAIT FOR COMFYUI
// ======================================================
async function waitForComfyUI() {
    for (let i = 0; i < 40; i++) {
        try {
            const r = await fetch(`${COMFY_HTTP}/system_stats`);
            if (r.ok) return;
        } catch {}
        await new Promise(r => setTimeout(r, 500));
    }
    throw new Error("ComfyUI failed to start");
}

// ======================================================
// BUILD WORKFLOW (full pipeline with face detailer + upscale + CRT)
// ======================================================
function buildWorkflow(input) {
    // ---------- DEFAULT EXAMPLE PROMPT ----------
    const DEFAULT_PROMPT = "a woman in cat costume";

    const {
        prompt = DEFAULT_PROMPT,
        negativePrompt = "bad quality, blurry",
        seed = Math.floor(Math.random() * 1e12),
        width = 1024,
        height = 1024,
        loraName = "V8-zimage.safetensors",
        loraStrength = 0.7,
        useFaceDetailer = false,
        useUpscale = false,
        upscaleFactor = 1.5,
        pp = {}
    } = input;

    const STEPS = 9;
    const CFG = 1;

    const wf = {
        // Base loaders
        "1": { class_type: "UNETLoader", inputs: { unet_name: "z_image_turbo_bf16.safetensors", weight_dtype: "default" } },
        "2": { class_type: "CLIPLoader", inputs: { clip_name: "qwen_3_4b.safetensors", type: "lumina2", device: "default" } },
        "3": { class_type: "VAELoader", inputs: { vae_name: "ae.safetensors" } },

        // LORA
        "50": {
            class_type: "LoraLoader",
            inputs: {
                lora_name: loraName,
                strength_model: loraStrength,
                strength_clip: 1,
                model: ["1", 0],
                clip: ["2", 0]
            }
        },

        // Text encoders
        "4": { class_type: "CLIPTextEncode", inputs: { text: prompt, clip: ["50", 1] } },
        "5": { class_type: "CLIPTextEncode", inputs: { text: negativePrompt, clip: ["50", 1] } },

        // Latent init
        "11": { class_type: "EmptyFlux2LatentImage", inputs: { width, height, batch_size: 1 } },

        // KSampler base
        "6": {
            class_type: "KSampler",
            inputs: {
                seed, steps: STEPS, cfg: CFG,
                sampler_name: "euler", scheduler: "simple", denoise: 1,
                model: ["50", 0], positive: ["4", 0], negative: ["5", 0],
                latent_image: ["11", 0]
            }
        },

        // Decode base
        "7": { class_type: "VAEDecode", inputs: { samples: ["6", 0], vae: ["3", 0] } }
    };

    let lastImage = ["7", 0];

    // ---------------- UPSCALE ----------------
    if (useUpscale) {
        wf["38"] = {
            class_type: "CR Upscale Image",
            inputs: {
                upscale_model: "4x_foolhardy_Remacri.pth",
                mode: "rescale",
                rescale_factor: upscaleFactor,
                resize_width: 1024,
                resampling_method: "bilinear",
                supersample: "false",
                rounding_modulus: 8,
                image: lastImage
            }
        };

        wf["39"] = {
            class_type: "VAEEncode",
            inputs: {
                pixels: ["38", 0],
                vae: ["3", 0]
            }
        };

        wf["40"] = {
            class_type: "KSampler",
            inputs: {
                seed: seed + 1, steps: 4, cfg: 1,
                sampler_name: "euler", scheduler: "simple", denoise: 0.41,
                model: ["1", 0], positive: ["4", 0],
                negative: ["5", 0], latent_image: ["39", 0]
            }
        };

        wf["41"] = {
            class_type: "VAEDecode",
            inputs: { samples: ["40", 0], vae: ["3", 0] }
        };

        lastImage = ["41", 0];
    }

    // ---------------- FACE DETAILER ----------------
    if (useFaceDetailer) {
        wf["32"] = {
            class_type: "UltralyticsDetectorProvider",
            inputs: { model_name: "bbox/face_yolov8m.pt" }
        };

        wf["33"] = {
            class_type: "SAMLoader",
            inputs: { model_name: "sam_vit_b_01ec64.pth", device_mode: "Prefer GPU" }
        };

        wf["30"] = {
            class_type: "FaceDetailer",
            inputs: {
                guide_size: 1024, max_size: 1024,
                seed: seed + 2, steps: 4, cfg: 1,
                sampler_name: "dpmpp_2m", scheduler: "simple",
                denoise: 0.45,
                image: lastImage,
                model: ["50", 0], clip: ["50", 1], vae: ["3", 0],
                positive: ["4", 0], negative: ["5", 0],
                bbox_detector: ["32", 0], sam_model_opt: ["33", 0]
            }
        };

        lastImage = ["30", 0];
    }

    // ---------------- CRT SUITE ----------------
    const exposure = pp.exposure ?? 0;
    const contrast = pp.contrast ?? 1;
    const saturation = pp.saturation ?? 1;
    const vibrance = pp.vibrance ?? 0;

    const enableLevels = (exposure !== 0 || contrast !== 1 || saturation !== 1 || vibrance !== 0);

    wf["20"] = {
        class_type: "CRT Post-Process Suite",
        inputs: {
            image: lastImage,
            enable_levels: enableLevels,
            exposure, contrast, saturation, vibrance,
            enable_sharpen: pp.sharpness > 0,
            sharpen_strength: pp.sharpness || 0,
            enable_vignette: pp.vignette > 0,
            vignette_strength: pp.vignette || 0,
            enable_film_grain: pp.grain_amount > 0,
            grain_intensity: pp.grain_amount || 0,
            grain_size: pp.grain_size || 0.3
        }
    };

    lastImage = ["20", 0];

    // ---------- SAVE ----------
    wf["Save"] = {
        class_type: "SaveImage",
        inputs: {
            filename_prefix: "AIEGO",
            images: lastImage
        }
    };

    return wf;
}

// ======================================================
// QUEUE PROMPT
// ======================================================
async function queue(workflow) {
    const clientId = randomUUID();
    const r = await fetch(`${COMFY_HTTP}/prompt`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ prompt: workflow, client_id: clientId })
    });

    const data = await r.json();
    return { promptId: data.prompt_id, clientId };
}

// ======================================================
// WAIT EXECUTION
// ======================================================
async function wait(promptId, clientId) {
    return new Promise((resolve) => {
        const ws = new WebSocket(`${COMFY_WS}?clientId=${clientId}`);
        ws.on("message", (d) => {
            const msg = JSON.parse(d.toString());
            if (msg.type === "executing" && msg.data.node === null) {
                ws.close();
            }
        });
        ws.on("close", resolve);
    });
}

// ======================================================
// GET IMAGE
// ======================================================
async function getImage(filename, subfolder, type) {
    const params = new URLSearchParams({
        filename,
        subfolder: subfolder || "",
        type: type || "output"
    });

    const resp = await fetch(`${COMFY_HTTP}/view?${params}`);
    const buf = await resp.arrayBuffer();
    return `data:image/png;base64,${Buffer.from(buf).toString("base64")}`;
}

// ======================================================
// RUNPOD HANDLER
// ======================================================
runpod.serverless.handle(async (event) => {
    try {
        const input = event.input || {};

        // 1. Start ComfyUI
        startComfy();
        await waitForComfyUI();

        // 2. Build workflow
        const workflow = buildWorkflow(input);

        // 3. Queue
        const { promptId, clientId } = await queue(workflow);

        // 4. Wait
        await wait(promptId, clientId);

        // 5. Fetch outputs
        const history = await fetch(`${COMFY_HTTP}/history/${promptId}`).then(r => r.json());
        const outputs = history[promptId].outputs;

        const images = [];

        for (const key in outputs) {
            if (outputs[key].images) {
                for (const img of outputs[key].images) {
                    images.push(await getImage(img.filename, img.subfolder, img.type));
                }
            }
        }

        return { images };

    } catch (err) {
        console.error("HANDLER ERROR:", err);
        return { error: err.message || "Unknown error" };
    }
});

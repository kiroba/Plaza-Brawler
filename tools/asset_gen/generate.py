#!/usr/bin/env python3
"""Plaza Brawler AI art pipeline.

One CLI, three backends:
  cuda   NVIDIA GPU (Kaggle / Colab T4, P100, ...): diffusers + FLUX.1 [schnell] at fp16.
  intel  Intel GPU (integrated Iris Xe / Arc) through OpenVINO: FLUX.1 [schnell], INT4
         (OpenVINO/FLUX.1-schnell-int4-ov). On PCs with less than ~16 GB of RAM it falls back to
         LCM Dreamshaper v7, INT8. Pick by hand with --intel-model flux|lcm.
  cpu    Same OpenVINO models on the CPU. Slow, but works anywhere.

  python tools/asset_gen/generate.py --dry-run                 # print the plan, load nothing
  python tools/asset_gen/generate.py --backend auto            # pick cuda > intel > cpu
  python tools/asset_gen/generate.py --only "fighters/aries/*"  # just one fighter
  python tools/asset_gen/generate.py --backend intel --intel-model lcm   # low-RAM Intel PC
  python tools/asset_gen/generate.py --validate-manifest assets/generated/ASSET_MANIFEST.json

Everything it makes goes to assets/generated/ (git-ignored) together with ASSET_MANIFEST.json,
which records file, prompt, seed, model, model license, backend and sha256 for every image.
See tools/asset_gen/README.md for setup and the license table.
"""
from __future__ import annotations

import argparse
import datetime as _dt
import fnmatch
import hashlib
import json
import os
import platform
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parent.parent
SCHEMA_PATH = HERE / "asset_manifest.schema.json"
MANIFEST_NAME = "ASSET_MANIFEST.json"
SCHEMA_VERSION = 1

# --------------------------------------------------------------------------------------------
# Models and their licenses. Every license below was checked on the model's Hugging Face page
# or the project's LICENSE file on 2026-11-01 (OpenVINO/FLUX.1-schnell-int4-ov on 2026-11-02);
# re-check before shipping if you change a model.
# --------------------------------------------------------------------------------------------
LICENSES: dict[str, dict[str, str]] = {
    "black-forest-labs/FLUX.1-schnell": {
        "license": "Apache-2.0",
        "url": "https://huggingface.co/black-forest-labs/FLUX.1-schnell",
        "note": "Gated on Hugging Face: log in, accept the terms on the model page, use an HF token.",
    },
    "OpenVINO/FLUX.1-schnell-int4-ov": {
        "license": "Apache-2.0",
        "url": "https://huggingface.co/OpenVINO/FLUX.1-schnell-int4-ov",
        "note": "OpenVINO IR of black-forest-labs/FLUX.1-schnell (Apache-2.0), weights compressed to "
                "INT4 by NNCF (INT4_ASYM, ratio 1.0, group size 64). Not gated. Model card: needs "
                "OpenVINO 2025.0.0+ and Optimum Intel 1.22.0+.",
    },
    "OpenVINO/LCM_Dreamshaper_v7-int8-ov": {
        "license": "MIT (as tagged on Hugging Face); lineage CreativeML OpenRAIL-M",
        "url": "https://huggingface.co/OpenVINO/LCM_Dreamshaper_v7-int8-ov",
        "note": "INT8 OpenVINO build of SimianLuo/LCM_Dreamshaper_v7 (MIT), which was distilled "
                "from Lykon/dreamshaper-7, a Stable Diffusion v1.5 fine-tune (CreativeML OpenRAIL-M). "
                "Treat it as OpenRAIL-M: commercial use allowed, use-based restrictions apply, "
                "licensor claims no rights in the output (section 6).",
    },
    "stabilityai/stable-diffusion-xl-base-1.0": {
        "license": "CreativeML OpenRAIL++-M",
        "url": "https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0",
        "note": "Only used with --pose-mode controlnet on cuda. Commercial use allowed, use-based restrictions apply.",
    },
    "xinsir/controlnet-openpose-sdxl-1.0": {
        "license": "Apache-2.0",
        "url": "https://huggingface.co/xinsir/controlnet-openpose-sdxl-1.0",
        "note": "OpenPose ControlNet for SDXL. Only used with --pose-mode controlnet on cuda.",
    },
    "rembg": {
        "license": "MIT",
        "url": "https://github.com/danielgatis/rembg/blob/main/LICENSE.txt",
        "note": "Background removal library.",
    },
    "rembg:isnet-anime": {
        "license": "Apache-2.0",
        "url": "https://github.com/SkyTNT/anime-segmentation/blob/main/LICENSE",
        "note": "Weights from SkyTNT/anime-segmentation, served by rembg's GitHub release.",
    },
    "rembg:isnet-general-use": {
        "license": "Apache-2.0",
        "url": "https://github.com/xuebinqin/DIS",
        "note": "DIS weights.",
    },
    "rembg:u2net": {
        "license": "Apache-2.0",
        "url": "https://github.com/xuebinqin/U-2-Net",
        "note": "U^2-Net weights.",
    },
    "rembg:birefnet-general": {
        "license": "MIT",
        "url": "https://github.com/ZhengPeng7/BiRefNet",
        "note": "BiRefNet weights.",
    },
}
# Background-removal models we will not use: their licenses do not allow commercial use.
BLOCKED_REMBG = {"bria-rmbg"}

BACKENDS = {
    "cuda": {
        "model": "black-forest-labs/FLUX.1-schnell",
        "long_side": 1024, "stage_long_side": 1344, "multiple": 16, "steps": 4, "guidance": 0.0,
    },
    "cuda-controlnet": {
        "model": "stabilityai/stable-diffusion-xl-base-1.0",
        "controlnet": "xinsir/controlnet-openpose-sdxl-1.0",
        "long_side": 1024, "stage_long_side": 1344, "multiple": 64, "steps": 30, "guidance": 6.0,
    },
    # intel / cpu: the model settings come from INTEL_MODELS (--intel-model flux|lcm|auto).
    "intel": {"ov_device": "GPU"},
    "cpu": {"ov_device": "CPU"},
}

# OpenVINO models for the intel and cpu backends.
#   prompt: "long" = the full FLUX-length prompt (T5, up to 256 tokens);
#           "short" = the <= 77-token CLIP prompt (SD1.5-family models only).
INTEL_MODELS = {
    "flux": {
        "model": "OpenVINO/FLUX.1-schnell-int4-ov",
        "quantization": "INT4_ASYM weight compression (NNCF, ratio 1.0, group size 64)",
        "long_side": 1024, "stage_long_side": 1344, "multiple": 16, "steps": 4, "guidance": 0.0,
        "prompt": "long", "max_sequence_length": 256,
    },
    "lcm": {
        "model": "OpenVINO/LCM_Dreamshaper_v7-int8-ov",
        "quantization": "INT8",
        "long_side": 512, "stage_long_side": 768, "multiple": 64, "steps": 6, "guidance": 8.0,
        "prompt": "short",
    },
}
# auto picks lcm below this much physical RAM. 15 GiB rather than 16 so a nominal 16 GB PC
# (which reports ~15.7 GiB) still gets FLUX; the INT4 FLUX files alone are ~9.2 GB.
FLUX_MIN_RAM_GB = 15.0


def system_ram_gb() -> float | None:
    """Total physical RAM in GiB, or None if it can't be read. No extra packages needed."""
    try:
        import psutil  # type: ignore
        return psutil.virtual_memory().total / 1024 ** 3
    except Exception:
        pass
    if sys.platform == "win32":
        try:
            import ctypes

            class MEMORYSTATUSEX(ctypes.Structure):
                _fields_ = [("dwLength", ctypes.c_ulong), ("dwMemoryLoad", ctypes.c_ulong),
                            ("ullTotalPhys", ctypes.c_ulonglong), ("ullAvailPhys", ctypes.c_ulonglong),
                            ("ullTotalPageFile", ctypes.c_ulonglong), ("ullAvailPageFile", ctypes.c_ulonglong),
                            ("ullTotalVirtual", ctypes.c_ulonglong), ("ullAvailVirtual", ctypes.c_ulonglong),
                            ("ullAvailExtendedVirtual", ctypes.c_ulonglong)]
            st = MEMORYSTATUSEX()
            st.dwLength = ctypes.sizeof(MEMORYSTATUSEX)
            if ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(st)):
                return st.ullTotalPhys / 1024 ** 3
        except Exception:
            return None
        return None
    try:
        return os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES") / 1024 ** 3
    except (ValueError, OSError, AttributeError):
        return None


def pick_intel_model(choice: str, ram_gb: float | None = None) -> tuple[str, str]:
    """Return (flux|lcm, reason). ram_gb is for tests; None reads this machine."""
    if choice in INTEL_MODELS:
        return choice, f"--intel-model {choice}"
    ram = system_ram_gb() if ram_gb is None else ram_gb
    if ram is None:
        return "lcm", ("auto: could not read system RAM, so using the low-RAM model (LCM). "
                       "Use --intel-model flux if this PC has 16 GB or more.")
    if ram < FLUX_MIN_RAM_GB:
        return "lcm", (f"auto: {ram:.1f} GB RAM is under ~16 GB; FLUX.1 [schnell] INT4 needs ~9.2 GB "
                       "for its weights alone, so using LCM Dreamshaper v7 (INT8, 512 px) instead. "
                       "Force it with --intel-model flux.")
    return "flux", (f"auto: {ram:.1f} GB RAM, enough for FLUX.1 [schnell] INT4. "
                    "Use --intel-model lcm for the faster, lighter model.")

# OpenPose (COCO-18) keypoints for a right-facing fighter, in a unit square (x right, y down).
# Order: nose, neck, r_sho, r_elb, r_wri, l_sho, l_elb, l_wri, r_hip, r_knee, r_ank,
#        l_hip, l_knee, l_ank, r_eye, l_eye, r_ear, l_ear.  None = hidden.
# Only used by --pose-mode controlnet (and --dump-poses). Override per pose in assets.yaml
# with `keypoints: [[x, y] | null, ...]`.
POSE_KEYPOINTS: dict[str, list] = {
    "idle":  [[.57, .15], [.50, .25], [.45, .26], [.47, .37], [.57, .33], [.55, .26], [.60, .36], [.65, .28],
              [.47, .52], [.41, .70], [.37, .90], [.53, .52], [.58, .70], [.63, .90],
              [.56, .13], [.59, .13], [.52, .14], None],
    "walk":  [[.57, .15], [.50, .25], [.45, .26], [.46, .37], [.56, .34], [.55, .26], [.60, .36], [.65, .29],
              [.47, .52], [.40, .69], [.33, .88], [.53, .52], [.62, .68], [.66, .90],
              [.56, .13], [.59, .13], [.52, .14], None],
    "punch": [[.60, .16], [.52, .26], [.46, .27], [.47, .38], [.55, .33], [.58, .26], [.72, .26], [.88, .25],
              [.47, .52], [.39, .70], [.33, .90], [.54, .52], [.61, .70], [.67, .90],
              [.59, .14], [.62, .14], [.55, .15], None],
    "kick":  [[.40, .18], [.37, .28], [.33, .29], [.35, .40], [.43, .36], [.41, .28], [.47, .37], [.50, .30],
              [.38, .53], [.36, .72], [.35, .92], [.43, .52], [.62, .44], [.85, .38],
              [.39, .16], [.42, .16], [.35, .17], None],
    "block": [[.55, .16], [.49, .26], [.44, .27], [.50, .32], [.55, .17], [.54, .27], [.60, .30], [.60, .16],
              [.46, .52], [.40, .70], [.36, .90], [.52, .52], [.57, .70], [.61, .90],
              [.54, .14], [.57, .14], [.50, .15], None],
    "hit":   [[.42, .17], [.43, .27], [.38, .28], [.33, .37], [.30, .45], [.48, .28], [.52, .38], [.55, .46],
              [.48, .53], [.48, .71], [.50, .90], [.54, .53], [.60, .71], [.65, .90],
              [.41, .15], [.44, .14], [.38, .17], None],
    "ko":    [[.15, .83], [.24, .84], [.24, .81], [.31, .78], [.38, .80], [.24, .87], [.32, .89], [.38, .88],
              [.50, .85], [.66, .82], [.82, .86], [.50, .88], [.66, .89], [.82, .90],
              [.13, .81], [.13, .84], [.16, .80], None],
}
_LIMBS = [(1, 2), (1, 5), (2, 3), (3, 4), (5, 6), (6, 7), (1, 8), (8, 9), (9, 10), (1, 11), (11, 12),
          (12, 13), (1, 0), (0, 14), (14, 16), (0, 15), (15, 17)]
_COLORS = [(255, 0, 0), (255, 85, 0), (255, 170, 0), (255, 255, 0), (170, 255, 0), (85, 255, 0),
           (0, 255, 0), (0, 255, 85), (0, 255, 170), (0, 255, 255), (0, 170, 255), (0, 85, 255),
           (0, 0, 255), (85, 0, 255), (170, 0, 255), (255, 0, 255), (255, 0, 170), (255, 0, 85)]


# --------------------------------------------------------------------------------------------
# Plan
# --------------------------------------------------------------------------------------------
@dataclass
class Job:
    key: str                  # e.g. fighters/aries/punch_0
    category: str             # fighters | stage | fx | ui
    asset_id: str
    out: Path                 # absolute path of the final PNG
    prompt: str               # long prompt, for T5 (FLUX reads up to 256 tokens)
    prompt_short: str         # <= ~77 CLIP tokens, most important words first (SD1.5 / SDXL)
    negative: str
    seed: int
    size: tuple[int, int]     # final (w, h)
    transparent: bool
    anchor: str = "center"
    pose: str | None = None
    frame: int | None = None
    keypoints: list | None = None
    extra: dict = field(default_factory=dict)


def load_yaml(path: Path) -> dict:
    try:
        import yaml
    except ImportError:
        sys.exit("PyYAML is missing: pip install pyyaml")
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f)


def build_plan(cfg: dict, out_dir: Path, preset_override: str | None = None) -> tuple[list[Job], dict]:
    style = cfg.get("style", {})
    preset_name = preset_override or style.get("preset", "clean2d")
    presets = style.get("presets", {})
    if preset_name not in presets:
        sys.exit(f"style preset '{preset_name}' not in assets.yaml (have: {', '.join(presets)})")
    preset = presets[preset_name]
    style_prompt = preset.get("prompt", "").strip()
    style_short = preset.get("short_prompt", style_prompt).strip()
    negative = preset.get("negative", "").strip()
    bg_hint = style.get("background_hint", "").strip()
    poses = cfg.get("poses", {})
    jobs: list[Job] = []

    def join(*parts: str) -> str:
        return ", ".join(p.strip().rstrip(",") for p in parts if p and p.strip())

    for f in cfg.get("fighters", []) or []:
        palette = ", ".join(f.get("palette", []))
        for pose in f.get("poses", []):
            if pose not in poses:
                sys.exit(f"fighter {f['id']}: pose '{pose}' is not defined under poses:")
            p = poses[pose]
            for k in range(int(p.get("frames", 1))):
                bg = bg_hint if f.get("transparent", True) else ""
                prompt = join(style_prompt, f.get("style_notes", ""),
                              f"{f.get('element', '')} element theme".strip() if f.get("element") else "",
                              f"color palette {palette}" if palette else "",
                              p.get("prompt", ""), bg)
                # CLIP drops everything after 77 tokens, so the short prompt leads with the pose
                # and the character, and leaves out hex colours (CLIP can't use them).
                short = join(style_short, p.get("prompt", ""), f.get("style_notes", ""), bg)
                jobs.append(Job(
                    key=f"fighters/{f['id']}/{pose}_{k}", category="fighters", asset_id=f["id"],
                    out=out_dir / "fighters" / f["id"] / f"{pose}_{k}.png",
                    prompt=prompt, prompt_short=short, negative=negative, seed=int(f["seed"]) + k,
                    size=tuple(f.get("size", [512, 512])), transparent=bool(f.get("transparent", True)),
                    anchor=f.get("anchor", "bottom"), pose=pose, frame=k,
                    keypoints=p.get("keypoints") or POSE_KEYPOINTS.get(pose)))

    for cat in ("stage", "fx", "ui"):
        for a in cfg.get(cat, []) or []:
            transparent = bool(a.get("transparent", cat != "stage"))
            jobs.append(Job(
                key=f"{cat}/{a['id']}", category=cat, asset_id=a["id"],
                out=out_dir / cat / f"{a['id']}.png",
                prompt=join(a["prompt"], bg_hint if transparent else ""),
                prompt_short=join(a.get("short_prompt", a["prompt"]), bg_hint if transparent else ""),
                negative=a.get("negative", "blurry, text, watermark, logo, signature, frame, border"),
                seed=int(a["seed"]), size=tuple(a.get("size", [512, 512])), transparent=transparent,
                anchor=a.get("anchor", "center")))

    seen = set()
    for j in jobs:
        if j.key in seen:
            sys.exit(f"duplicate asset key {j.key} in assets.yaml")
        seen.add(j.key)
    return jobs, {"preset": preset_name, "pixelate": preset.get("pixelate"),
                  "prefixes": [style_prompt, style_short]}


def gen_size(size: tuple[int, int], long_side: int, multiple: int) -> tuple[int, int]:
    """Model drawing size with the final asset's aspect ratio."""
    w, h = size
    scale = long_side / max(w, h)
    rw = max(multiple, int(round(w * scale / multiple)) * multiple)
    rh = max(multiple, int(round(h * scale / multiple)) * multiple)
    return rw, rh


def draw_size_for(job: "Job", bcfg: dict, long_side_override: int | None) -> tuple[int, int]:
    """Stage art is wide, so it is drawn bigger; everything else at the model's native size."""
    if long_side_override:
        ls = long_side_override
    elif job.category == "stage":
        ls = bcfg.get("stage_long_side", bcfg["long_side"])
    else:
        ls = bcfg["long_side"]
    return gen_size(job.size, ls, bcfg["multiple"])


def filter_jobs(jobs: list[Job], only: list[str] | None, limit: int | None) -> list[Job]:
    if only:
        pats = [p if any(c in p for c in "*?[") else f"*{p}*" for p in only]
        jobs = [j for j in jobs if any(fnmatch.fnmatch(j.key, p) for p in pats)]
    if limit:
        jobs = jobs[:limit]
    return jobs


# --------------------------------------------------------------------------------------------
# Backend detection
# --------------------------------------------------------------------------------------------
def detect_backend(verbose: bool = True) -> str:
    try:
        import torch
        if torch.cuda.is_available():
            if verbose:
                print(f"[auto] CUDA GPU found: {torch.cuda.get_device_name(0)}")
            return "cuda"
    except ImportError:
        pass
    try:
        import openvino as ov
        devs = ov.Core().available_devices
        if any(d.startswith("GPU") for d in devs):
            if verbose:
                print(f"[auto] OpenVINO GPU found ({', '.join(devs)})")
            return "intel"
        if verbose:
            print(f"[auto] no GPU for OpenVINO ({', '.join(devs)}): using CPU")
        return "cpu"
    except ImportError:
        pass
    sys.exit("No backend available: install requirements-cuda.txt (NVIDIA) or requirements-intel.txt "
             "(Intel GPU / CPU). See tools/asset_gen/README.md.")


def _has_ov_ir(model: str) -> bool:
    p = Path(model)
    if p.is_dir():
        return any(p.rglob("openvino_model.xml"))
    return model.startswith("OpenVINO/") or model.endswith("-ov")


# --------------------------------------------------------------------------------------------
# Generators
# --------------------------------------------------------------------------------------------
class FluxGenerator:
    """NVIDIA: FLUX.1 [schnell] at fp16 via diffusers.

    Under 24 GB VRAM the transformer and T5 are loaded in 4-bit NF4 (bitsandbytes): the full
    fp16 weights (~33 GB) do not fit a T4/P100 or Kaggle's ~29 GB of RAM. Under 16 GB VRAM
    model CPU offload is on. T5 runs in bf16 (Ampere+) or fp32, because T5 overflows in fp16;
    its output is clamped to the fp16 range before it reaches the fp16 transformer.
    """

    def __init__(self, model: str, quant: str = "auto", offload: str = "auto", dtype: str = "fp16",
                 device: str = "cuda"):
        import torch
        from diffusers import FluxPipeline, FluxTransformer2DModel
        from transformers import T5EncoderModel

        self.torch = torch
        self.device = device
        on_cuda = device == "cuda" and torch.cuda.is_available()
        vram = torch.cuda.get_device_properties(0).total_memory / 1024 ** 3 if on_cuda else 0.0
        native_bf16 = on_cuda and torch.cuda.get_device_capability(0)[0] >= 8
        self.dtype = {"fp16": torch.float16, "bf16": torch.bfloat16, "fp32": torch.float32}[dtype]
        te_dtype = torch.bfloat16 if native_bf16 else torch.float32
        if not on_cuda:
            self.dtype = te_dtype = torch.float32
        use_quant = quant == "nf4" or (quant == "auto" and on_cuda and vram < 24)
        self.info = {"vram_gb": round(vram, 1), "dtype": str(self.dtype).replace("torch.", ""),
                     "text_encoder_2_dtype": str(te_dtype).replace("torch.", ""),
                     "quantization": "nf4 (bitsandbytes)" if use_quant else "none"}
        print(f"[cuda] {model}: VRAM {vram:.1f} GB, transformer {self.info['dtype']}, "
              f"T5 {self.info['text_encoder_2_dtype']}, quant {self.info['quantization']}")

        tkw: dict[str, Any] = {"subfolder": "transformer", "torch_dtype": self.dtype}
        ekw: dict[str, Any] = {"subfolder": "text_encoder_2", "torch_dtype": te_dtype}
        if use_quant:
            from diffusers import BitsAndBytesConfig as DiffusersBnb
            from transformers import BitsAndBytesConfig as TransformersBnb
            tkw["quantization_config"] = DiffusersBnb(load_in_4bit=True, bnb_4bit_quant_type="nf4",
                                                      bnb_4bit_compute_dtype=self.dtype)
            ekw["quantization_config"] = TransformersBnb(load_in_4bit=True, bnb_4bit_quant_type="nf4",
                                                         bnb_4bit_compute_dtype=te_dtype)
        transformer = FluxTransformer2DModel.from_pretrained(model, **tkw)
        text_encoder_2 = T5EncoderModel.from_pretrained(model, **ekw)
        self.pipe = FluxPipeline.from_pretrained(model, transformer=transformer,
                                                 text_encoder_2=text_encoder_2, torch_dtype=self.dtype)
        mode = offload
        if mode == "auto":
            mode = "model" if (on_cuda and vram < 16) else "none"
        if not on_cuda:
            mode = "none"
        if mode == "model":
            self.pipe.enable_model_cpu_offload()
        elif mode == "sequential":
            self.pipe.enable_sequential_cpu_offload()
        else:
            self.pipe.to(device if on_cuda else "cpu")
        self.info["offload"] = mode
        self.exec_device = "cuda" if on_cuda else "cpu"
        print(f"[cuda] CPU offload: {mode}")

    def generate(self, job: Job, w: int, h: int, steps: int, guidance: float):
        torch = self.torch
        with torch.no_grad():
            pe, pooled, _ = self.pipe.encode_prompt(prompt=job.prompt, prompt_2=job.prompt,
                                                    device=self.pipe._execution_device,
                                                    max_sequence_length=256)
        fmax = torch.finfo(torch.float16).max if self.dtype == torch.float16 else None
        if fmax is not None:
            pe = torch.nan_to_num(pe.float(), nan=0.0).clamp(-fmax, fmax)
            pooled = torch.nan_to_num(pooled.float(), nan=0.0).clamp(-fmax, fmax)
        pe, pooled = pe.to(self.dtype), pooled.to(self.dtype)
        g = torch.Generator(device="cpu").manual_seed(job.seed)
        out = self.pipe(prompt_embeds=pe, pooled_prompt_embeds=pooled, width=w, height=h,
                        num_inference_steps=steps, guidance_scale=guidance, generator=g,
                        max_sequence_length=256)
        return out.images[0]


class SDXLPoseGenerator:
    """NVIDIA, --pose-mode controlnet: SDXL base + xinsir OpenPose ControlNet (both commercial-OK).

    FLUX.1 [schnell] has no OpenPose ControlNet under a commercial-compatible license (the FLUX
    ControlNets we found are FLUX.1 [dev] derivatives under the non-commercial dev license), so
    pose-guided sprites use SDXL. Text-only assets (stage, fx, ui) still use whatever model the
    run loaded; in controlnet mode they go through the same SDXL pipeline with a blank pose.
    """

    def __init__(self, model: str, controlnet: str, offload: str = "auto"):
        import torch
        from diffusers import ControlNetModel, StableDiffusionXLControlNetPipeline

        self.torch = torch
        vram = torch.cuda.get_device_properties(0).total_memory / 1024 ** 3
        cn = ControlNetModel.from_pretrained(controlnet, torch_dtype=torch.float16)
        try:
            self.pipe = StableDiffusionXLControlNetPipeline.from_pretrained(
                model, controlnet=cn, torch_dtype=torch.float16, variant="fp16")
        except (OSError, ValueError):
            self.pipe = StableDiffusionXLControlNetPipeline.from_pretrained(
                model, controlnet=cn, torch_dtype=torch.float16)
        mode = ("model" if vram < 16 else "none") if offload == "auto" else offload
        if mode == "model":
            self.pipe.enable_model_cpu_offload()
        elif mode == "sequential":
            self.pipe.enable_sequential_cpu_offload()
        else:
            self.pipe.to("cuda")
        self.info = {"vram_gb": round(vram, 1), "dtype": "float16", "offload": mode,
                     "controlnet": controlnet}
        print(f"[cuda/controlnet] {model} + {controlnet}, offload {mode}")

    def generate(self, job: Job, w: int, h: int, steps: int, guidance: float):
        from PIL import Image
        torch = self.torch
        if job.keypoints:
            cond = draw_pose(job.keypoints, w, h)
            scale = 0.85
        else:
            cond, scale = Image.new("RGB", (w, h), (0, 0, 0)), 0.0
        g = torch.Generator(device="cpu").manual_seed(job.seed)
        out = self.pipe(prompt=job.prompt_short, negative_prompt=job.negative, image=cond,
                        controlnet_conditioning_scale=scale, width=w, height=h,
                        num_inference_steps=steps, guidance_scale=guidance, generator=g)
        return out.images[0]


class OVGenerator:
    """Intel GPU or CPU: OpenVINO through optimum-intel.

    Both default models (FLUX.1 [schnell] INT4, LCM Dreamshaper v7 INT8) are already converted to
    OpenVINO IR, so nothing is exported on your PC. A plain diffusers model id also works (it is
    exported to OpenVINO on first load). FLUX reads the long prompt (T5, 256 tokens) with no
    negative prompt and guidance 0; LCM reads the short CLIP prompt (77 tokens).
    The pipeline is reshaped to a static size per image size, and compiled models are cached
    in tools/asset_gen/.cache/ov so the second run starts faster.
    """

    def __init__(self, model: str, device: str, prompt_kind: str = "short",
                 max_sequence_length: int | None = None, quantization: str | None = None):
        from optimum.intel.openvino import OVDiffusionPipeline

        cache = HERE / ".cache" / "ov"
        cache.mkdir(parents=True, exist_ok=True)
        export = not _has_ov_ir(model)
        self.pipe = OVDiffusionPipeline.from_pretrained(
            model, device=device, compile=False, export=export, ov_config={"CACHE_DIR": str(cache)})
        self.device = device
        self.size: tuple[int, int] | None = None
        self._warned: dict[str, bool] = {}
        self.prompt_kind = prompt_kind
        self.max_seq = max_sequence_length
        # reshape() fixes T5's input to tokenizer_2.model_max_length (512 for FLUX), but FLUX.1
        # [schnell] runs with 256 tokens; without this the static T5 rejects the 256-token input.
        tok2 = getattr(self.pipe, "tokenizer_2", None)
        if prompt_kind == "long" and max_sequence_length and tok2 is not None:
            if getattr(tok2, "model_max_length", 0) > max_sequence_length:
                tok2.model_max_length = max_sequence_length
        self.info = {"ov_device": device, "exported_on_load": export,
                     "pipeline": type(self.pipe).__name__, "quantization": quantization}
        print(f"[openvino] {model} on {device} ({self.info['pipeline']})")

    def generate(self, job: Job, w: int, h: int, steps: int, guidance: float):
        import torch
        if self.size != (w, h):
            self.pipe.reshape(batch_size=1, height=h, width=w, num_images_per_prompt=1)
            self.pipe.compile()
            self.size = (w, h)
        long = self.prompt_kind == "long"
        prompt = job.prompt if long else job.prompt_short
        tok = getattr(self.pipe, "tokenizer_2" if long else "tokenizer", None)
        limit = (self.max_seq or 256) if long else 77
        if tok is not None and not self._warned.get(job.key):
            try:
                n = len(tok(prompt).input_ids)
                if n > limit:
                    print(f"  note: {job.key} prompt is {n} tokens; words after {limit} are ignored.")
            except Exception:
                pass
            self._warned[job.key] = True
        g = torch.Generator().manual_seed(job.seed)
        kw: dict[str, Any] = {}
        if long and self.max_seq:
            kw["max_sequence_length"] = self.max_seq
        out = self.pipe(prompt=prompt, width=w, height=h, num_inference_steps=steps,
                        guidance_scale=guidance, generator=g, **kw)
        return out.images[0]


# --------------------------------------------------------------------------------------------
# Post-processing
# --------------------------------------------------------------------------------------------
def draw_pose(kps: list, w: int, h: int):
    """OpenPose-style skeleton (black background, standard limb colours)."""
    from PIL import Image, ImageDraw
    img = Image.new("RGB", (w, h), (0, 0, 0))
    d = ImageDraw.Draw(img)
    lw = max(2, int(min(w, h) * 0.012))
    pts = [(p[0] * w, p[1] * h) if p else None for p in kps]
    for i, (a, b) in enumerate(_LIMBS):
        if a < len(pts) and b < len(pts) and pts[a] and pts[b]:
            c = tuple(int(v * 0.6) for v in _COLORS[i])
            d.line([pts[a], pts[b]], fill=c, width=lw * 2)
    for i, p in enumerate(pts):
        if p:
            r = lw * 1.2
            d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=_COLORS[i % len(_COLORS)])
    return img


class BackgroundRemover:
    def __init__(self, model_name: str):
        if model_name in BLOCKED_REMBG:
            sys.exit(f"rembg model '{model_name}' is non-commercial; pick isnet-anime, isnet-general-use, u2net or birefnet-general")
        from rembg import new_session
        self.name = model_name
        self.session = new_session(model_name)

    def __call__(self, img):
        from rembg import remove
        return remove(img, session=self.session).convert("RGBA")


def fit_to_canvas(img, size: tuple[int, int], transparent: bool, anchor: str, margin: float = 0.04):
    from PIL import Image
    W, H = size
    if not transparent:  # cover-crop to the exact size
        img = img.convert("RGB")
        s = max(W / img.width, H / img.height)
        img = img.resize((max(W, round(img.width * s)), max(H, round(img.height * s))), Image.LANCZOS)
        x, y = (img.width - W) // 2, (img.height - H) // 2
        return img.crop((x, y, x + W, y + H))
    img = img.convert("RGBA")
    alpha = img.getchannel("A").point(lambda a: 255 if a > 16 else 0)
    bbox = alpha.getbbox()
    if bbox:
        img = img.crop(bbox)
    mw, mh = W * (1 - 2 * margin), H * (1 - 2 * margin)
    s = min(mw / img.width, mh / img.height)
    img = img.resize((max(1, round(img.width * s)), max(1, round(img.height * s))), Image.LANCZOS)
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    x = (W - img.width) // 2
    y = (H - img.height - round(H * margin)) if anchor == "bottom" else (H - img.height) // 2
    canvas.alpha_composite(img, (x, max(0, y)))
    return canvas


def pixelate(img, grid: int, colors: int):
    from PIL import Image
    W, H = img.size
    s = grid / max(W, H)
    small = img.resize((max(1, round(W * s)), max(1, round(H * s))), Image.BOX)
    if small.mode == "RGBA":
        a = small.getchannel("A").point(lambda v: 255 if v >= 128 else 0)
        rgb = small.convert("RGB").quantize(colors=colors, method=Image.MEDIANCUT).convert("RGB")
        small = rgb.convert("RGBA")
        small.putalpha(a)
    else:
        small = small.quantize(colors=colors, method=Image.MEDIANCUT).convert("RGB")
    return small.resize((W, H), Image.NEAREST)


def sha256_file(p: Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def rel(p: Path) -> str:
    """Path for log lines: repo-relative when inside the repo."""
    try:
        return p.resolve().relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return p.as_posix()


OUT_DIR: Path = REPO_ROOT / "assets" / "generated"


def mrel(p: Path) -> str:
    """Path stored in the manifest: relative to the manifest's own folder, so the output zip
    can be unpacked anywhere and still validate."""
    return p.resolve().relative_to(OUT_DIR).as_posix()


def save_png(img, path: Path, meta: dict):
    from PIL.PngImagePlugin import PngInfo
    path.parent.mkdir(parents=True, exist_ok=True)
    info = PngInfo()
    info.add_text("plaza_brawler_provenance", json.dumps(meta, sort_keys=True))
    img.save(path, pnginfo=info)


# --------------------------------------------------------------------------------------------
# Sprite sheets
# --------------------------------------------------------------------------------------------
def pack_sheets(cfg: dict, jobs: list[Job], out_dir: Path, padding: int) -> list[dict]:
    from PIL import Image
    made = []
    for f in cfg.get("fighters", []) or []:
        fj = [j for j in jobs if j.category == "fighters" and j.asset_id == f["id"] and j.out.exists()]
        if not fj:
            continue
        cw, ch = tuple(f.get("size", [512, 512]))
        rows: dict[str, list[Job]] = {}
        for j in sorted(fj, key=lambda j: (f["poses"].index(j.pose), j.frame)):
            rows.setdefault(j.pose, []).append(j)
        cols = max(len(r) for r in rows.values())
        W = cols * (cw + padding) + padding
        H = len(rows) * (ch + padding) + padding
        sheet = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        frames, anims = {}, {}
        for ri, (pose, row) in enumerate(rows.items()):
            for ci, j in enumerate(row):
                x, y = padding + ci * (cw + padding), padding + ri * (ch + padding)
                with Image.open(j.out) as im:
                    sheet.alpha_composite(im.convert("RGBA").resize((cw, ch)), (x, y))
                name = f"{f['id']}/{pose}_{j.frame}"
                frames[name] = {"frame": {"x": x, "y": y, "w": cw, "h": ch}, "pose": pose,
                                "index": j.frame, "source": mrel(j.out)}
                anims.setdefault(pose, []).append(name)
        png = out_dir / "sheets" / f"{f['id']}.png"
        atlas = out_dir / "sheets" / f"{f['id']}.json"
        save_png(sheet, png, {"kind": "sprite_sheet", "fighter": f["id"]})
        atlas.write_text(json.dumps({
            "meta": {"image": png.name, "size": {"w": W, "h": H}, "cell": {"w": cw, "h": ch},
                     "padding": padding, "generator": "tools/asset_gen/generate.py"},
            "frames": frames, "animations": anims}, indent=2), encoding="utf-8")
        made.append({"png": png, "atlas": atlas, "sources": [frames[n]["source"] for n in frames]})
        print(f"[sheet] {rel(png)} ({len(frames)} frames) + {atlas.name}")
    return made


# --------------------------------------------------------------------------------------------
# Manifest
# --------------------------------------------------------------------------------------------
def tool_versions() -> dict:
    out = {"python": platform.python_version()}
    for mod in ("torch", "diffusers", "transformers", "optimum.intel", "openvino", "rembg",
                "bitsandbytes", "PIL"):
        try:
            m = __import__(mod, fromlist=["__version__"])
            v = getattr(m, "__version__", None)
            if v is None and mod == "openvino":
                v = m.get_version()
            if v:
                out[mod] = str(v)
        except Exception:
            pass
    return out


def git_commit() -> str | None:
    try:
        return subprocess.check_output(["git", "-C", str(REPO_ROOT), "rev-parse", "HEAD"],
                                       stderr=subprocess.DEVNULL, text=True).strip()
    except Exception:
        return None


def model_revision(model: str) -> str | None:
    if Path(model).is_dir():
        return None
    try:
        from huggingface_hub import HfApi
        return HfApi().model_info(model).sha
    except Exception:
        return None


def license_of(key: str) -> dict:
    lic = LICENSES.get(key)
    if lic:
        return {"id": key, "license": lic["license"], "url": lic["url"]}
    return {"id": key, "license": "UNKNOWN - check before shipping", "url": None}


def load_manifest(path: Path) -> dict:
    if path.exists():
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            print(f"[manifest] {path} is not valid JSON; starting a new one")
    return {"schema_version": SCHEMA_VERSION, "project": "kiroba/Plaza-Brawler",
            "generator": "tools/asset_gen/generate.py", "entries": []}


def write_manifest(path: Path, manifest: dict, new_entries: list[dict]):
    by_file = {e["file"]: e for e in manifest.get("entries", [])}
    for e in new_entries:
        by_file[e["file"]] = e
    manifest["entries"] = sorted(by_file.values(), key=lambda e: e["file"])
    manifest["updated_utc"] = _now()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def validate_manifest(path: Path) -> int:
    data = json.loads(path.read_text(encoding="utf-8"))
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    try:
        import jsonschema
    except ImportError:
        sys.exit("jsonschema is missing: pip install jsonschema")
    errors = sorted(jsonschema.Draft202012Validator(schema).iter_errors(data), key=lambda e: list(e.path))
    for e in errors:
        print(f"  {'/'.join(map(str, e.path)) or '(root)'}: {e.message}")
    missing = []
    for e in data.get("entries", []):
        f = path.parent / e["file"]
        if f.exists() and sha256_file(f) != e["sha256"]:
            missing.append(f"{e['file']}: sha256 does not match the file on disk")
        elif not f.exists():
            missing.append(f"{e['file']}: file not found (fine if you only copied the manifest)")
    for m in missing:
        print(f"  note: {m}")
    unknown = [e["file"] for e in data.get("entries", []) if "UNKNOWN" in e["model_license"]["license"]]
    for u in unknown:
        print(f"  license: {u} has an UNKNOWN model license")
    ok = not errors and not unknown
    print(f"[validate] {path}: {'OK' if ok else 'FAILED'} ({len(data.get('entries', []))} entries)")
    return 0 if ok else 1


def _now() -> str:
    return _dt.datetime.now(_dt.timezone.utc).replace(microsecond=0).isoformat()


# --------------------------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------------------------
def parse_args(argv=None):
    ap = argparse.ArgumentParser(description="Plaza Brawler AI art pipeline (NVIDIA / Intel / CPU).")
    ap.add_argument("--manifest", default=str(HERE / "assets.yaml"), help="assets.yaml to read")
    ap.add_argument("--backend", choices=["auto", "cuda", "intel", "cpu"], default="auto")
    ap.add_argument("--out", default=None, help="output dir (default: output_dir in assets.yaml)")
    ap.add_argument("--only", action="append", help="only keys matching this glob, e.g. 'fighters/aries/*', 'ui/*', 'scorpio'. Repeatable.")
    ap.add_argument("--limit", type=int, default=None, help="stop after N images")
    ap.add_argument("--style", default=None, help="style preset from assets.yaml (clean2d, pixel)")
    ap.add_argument("--pose-mode", choices=["prompt", "controlnet"], default="prompt",
                    help="prompt (default): poses from text. controlnet: OpenPose ControlNet (cuda only; SDXL + xinsir openpose)")
    ap.add_argument("--intel-model", choices=["auto", "flux", "lcm"], default="auto",
                    help="intel/cpu: flux = FLUX.1 [schnell] INT4 (1024 px, ~16 GB RAM), lcm = LCM "
                         "Dreamshaper v7 INT8 (512 px, low RAM). auto = lcm under ~16 GB RAM, else flux")
    ap.add_argument("--model", default=None, help="override the model id/path for the chosen backend")
    ap.add_argument("--steps", type=int, default=None)
    ap.add_argument("--guidance", type=float, default=None)
    ap.add_argument("--long-side", type=int, default=None, help="model drawing size (long side, px)")
    ap.add_argument("--quant", choices=["auto", "nf4", "none"], default="auto", help="cuda: 4-bit weights (auto = under 24 GB VRAM)")
    ap.add_argument("--offload", choices=["auto", "model", "sequential", "none"], default="auto", help="cuda: CPU offload (auto = under 16 GB VRAM)")
    ap.add_argument("--dtype", choices=["fp16", "bf16"], default="fp16", help="cuda: transformer dtype")
    ap.add_argument("--rembg-model", default=None, help="override rembg_model from assets.yaml")
    ap.add_argument("--no-rembg", action="store_true", help="skip background removal")
    ap.add_argument("--no-sheets", action="store_true", help="skip sprite sheets")
    ap.add_argument("--skip-existing", action="store_true", help="don't redo images that already exist")
    ap.add_argument("--dry-run", action="store_true", help="print the plan; load no models")
    ap.add_argument("--verbose", action="store_true", help="dry-run: print full prompts")
    ap.add_argument("--dump-poses", metavar="DIR", help="write the OpenPose skeleton PNGs to DIR and exit")
    ap.add_argument("--validate-manifest", metavar="PATH", help="validate an ASSET_MANIFEST.json and exit")
    return ap.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(argv)
    if args.validate_manifest:
        return validate_manifest(Path(args.validate_manifest))

    cfg = load_yaml(Path(args.manifest))
    out_dir = Path(args.out) if args.out else REPO_ROOT / cfg.get("output_dir", "assets/generated")
    out_dir = out_dir.resolve()
    global OUT_DIR
    OUT_DIR = out_dir
    jobs, style_info = build_plan(cfg, out_dir, args.style)
    jobs = filter_jobs(jobs, args.only, args.limit)
    if not jobs:
        print("Nothing to do (check --only).")
        return 1

    if args.dump_poses:
        d = Path(args.dump_poses)
        d.mkdir(parents=True, exist_ok=True)
        for pose, kps in {**POSE_KEYPOINTS, **{k: v["keypoints"] for k, v in cfg.get("poses", {}).items() if v.get("keypoints")}}.items():
            draw_pose(kps, 512, 512).save(d / f"pose_{pose}.png")
        print(f"wrote {len(POSE_KEYPOINTS)} skeletons to {d}")
        return 0

    if args.backend == "auto":
        backend = detect_backend(verbose=not args.dry_run) if not args.dry_run else _dry_detect()
    else:
        backend = args.backend
    if args.pose_mode == "controlnet" and backend != "cuda":
        print(f"[pose] No OpenPose ControlNet path for '{backend}' (optimum-intel has no OpenVINO "
              "ControlNet pipeline). Falling back to pose prompts.")
        args.pose_mode = "prompt"
    bkey = "cuda-controlnet" if (backend == "cuda" and args.pose_mode == "controlnet") else backend
    bcfg = dict(BACKENDS[bkey])
    intel_model = None
    if backend in ("intel", "cpu"):
        intel_model, why = pick_intel_model(args.intel_model)
        bcfg.update(INTEL_MODELS[intel_model])
        print(f"[intel-model] {intel_model}: {why}")
    elif args.intel_model != "auto":
        print(f"[intel-model] ignored: --intel-model only applies to the intel and cpu backends")
    long_prompt = bkey == "cuda" or bcfg.get("prompt") == "long"
    model = args.model or bcfg["model"]
    if intel_model and args.model and args.model != INTEL_MODELS[intel_model]["model"]:
        # Only the stock model's quantization is known; don't record it for a custom --model.
        bcfg["quantization"] = "unknown (custom --model)"
    steps = args.steps or bcfg["steps"]
    guidance = bcfg["guidance"] if args.guidance is None else args.guidance
    long_side = args.long_side or bcfg["long_side"]
    rembg_model = args.rembg_model or cfg.get("rembg_model", "isnet-general-use")
    needs_rembg = any(j.transparent for j in jobs) and not args.no_rembg

    print(f"Plan: {len(jobs)} images | backend {backend} | model {model} "
          f"[{license_of(model)['license']}] | style {style_info['preset']} | poses via {args.pose_mode}")
    print(f"      steps {steps}, guidance {guidance}, draw long side {long_side}px | "
          f"background removal: {('rembg ' + rembg_model) if needs_rembg else 'off'} | out {rel(out_dir)}")
    if bkey == "cuda-controlnet":
        print(f"      controlnet {bcfg['controlnet']} [{license_of(bcfg['controlnet'])['license']}]")
    if intel_model:
        print(f"      OpenVINO {intel_model}: {bcfg['quantization']} | prompts: "
              f"{'full FLUX-length (T5, 256 tokens)' if long_prompt else 'short (CLIP, 77 tokens)'}")

    if args.dry_run:
        print(f"{'key':34} {'final':>10} {'draw':>10} {'seed':>6}  bg      prompt")
        for j in jobs:
            gw, gh = draw_size_for(j, bcfg, args.long_side)
            jp = j.prompt if long_prompt else j.prompt_short
            if not args.verbose:  # hide the shared style words so the differences show
                for pre in style_info["prefixes"]:
                    if pre and jp.startswith(pre):
                        jp = "[style] " + jp[len(pre):].lstrip(", ")
                        break
            p = jp if args.verbose or len(jp) <= 80 else jp[:77] + "..."
            print(f"{j.key:34} {j.size[0]:>4}x{j.size[1]:<5} {gw:>4}x{gh:<5} {j.seed:>6}  "
                  f"{'alpha' if j.transparent else 'opaque':7} {p}")
        if not args.no_sheets and cfg.get("sheets", {}).get("enabled", True):
            fs = sorted({j.asset_id for j in jobs if j.category == "fighters"})
            if fs:
                print(f"sprite sheets + JSON atlas: {', '.join(fs)} -> {rel(out_dir / 'sheets')}")
        print(f"manifest: {rel(out_dir / MANIFEST_NAME)}")
        return 0

    # ---- real run ----
    t0 = time.time()
    if bkey == "cuda":
        gen = FluxGenerator(model, quant=args.quant, offload=args.offload, dtype=args.dtype)
    elif bkey == "cuda-controlnet":
        gen = SDXLPoseGenerator(model, bcfg["controlnet"], offload=args.offload)
    else:
        gen = OVGenerator(model, bcfg["ov_device"], prompt_kind=bcfg["prompt"],
                          max_sequence_length=bcfg.get("max_sequence_length"),
                          quantization=bcfg.get("quantization"))
    remover = BackgroundRemover(rembg_model) if needs_rembg else None
    print(f"[load] {time.time() - t0:.0f}s")

    manifest_path = out_dir / MANIFEST_NAME
    manifest = load_manifest(manifest_path)
    manifest["tool_versions"] = tool_versions()
    manifest["git_commit"] = git_commit()
    rev = model_revision(model)
    entries = []
    # Group by draw size so OpenVINO reshapes/compiles once per size.
    order = sorted(jobs, key=lambda j: draw_size_for(j, bcfg, args.long_side))
    for i, j in enumerate(order, 1):
        if args.skip_existing and j.out.exists():
            print(f"[{i}/{len(order)}] {j.key}: exists, skipped")
            continue
        gw, gh = draw_size_for(j, bcfg, args.long_side)
        t = time.time()
        raw = gen.generate(j, gw, gh, steps, guidance)
        img = remover(raw) if (j.transparent and remover) else raw
        img = fit_to_canvas(img, j.size, j.transparent and remover is not None, j.anchor)
        if style_info.get("pixelate"):
            px = style_info["pixelate"]
            img = pixelate(img, int(px.get("grid", 128)), int(px.get("colors", 32)))
        extra_models = []
        if bkey == "cuda-controlnet":
            extra_models.append(license_of(bcfg["controlnet"]))
        if j.transparent and remover:
            extra_models += [license_of("rembg"), license_of(f"rembg:{remover.name}")]
        used_prompt = j.prompt if long_prompt else j.prompt_short
        meta = {"prompt": used_prompt, "seed": j.seed, "model": model, "backend": backend}
        save_png(img, j.out, meta)
        e = {
            "file": mrel(j.out), "sha256": sha256_file(j.out), "key": j.key, "category": j.category,
            "asset_id": j.asset_id, "pose": j.pose, "frame": j.frame,
            "prompt": used_prompt,
            "negative_prompt": j.negative if bkey == "cuda-controlnet" else None,
            "seed": j.seed, "model": model, "model_revision": rev, "model_license": license_of(model),
            "extra_models": extra_models, "backend": backend,
            "quantization": gen.info.get("quantization"), "intel_model": intel_model,
            "pose_mode": args.pose_mode if j.pose else None,
            "style": style_info["preset"], "steps": steps, "guidance_scale": guidance,
            "draw_size": [gw, gh], "size": list(j.size), "transparent": j.transparent and remover is not None,
            "runtime": gen.info, "created_utc": _now(),
        }
        entries.append(e)
        write_manifest(manifest_path, manifest, entries)  # after every image, so a crash keeps provenance
        print(f"[{i}/{len(order)}] {j.key} {gw}x{gh} -> {j.size[0]}x{j.size[1]} in {time.time() - t:.1f}s")

    if not args.no_sheets and cfg.get("sheets", {}).get("enabled", True):
        all_jobs, _ = build_plan(cfg, out_dir, args.style)
        for s in pack_sheets(cfg, all_jobs, out_dir, int(cfg.get("sheets", {}).get("padding", 2))):
            for path, kind in ((s["png"], "sprite_sheet"), (s["atlas"], "atlas")):
                entries.append({
                    "file": mrel(path), "sha256": sha256_file(path), "key": f"sheets/{path.name}",
                    "category": "sheets", "asset_id": path.stem, "pose": None, "frame": None,
                    "prompt": None, "negative_prompt": None, "seed": None, "model": None,
                    "model_revision": None,
                    "model_license": {"id": "derived", "license": "Derived from the listed sources", "url": None},
                    "extra_models": [], "backend": backend, "quantization": None, "intel_model": None,
                    "pose_mode": None, "style": style_info["preset"],
                    "steps": None, "guidance_scale": None, "draw_size": None, "size": None,
                    "transparent": kind == "sprite_sheet", "runtime": {}, "created_utc": _now(),
                    "kind": kind, "sources": s["sources"]})
        write_manifest(manifest_path, manifest, entries)
    print(f"Done: {len(entries)} files in {time.time() - t0:.0f}s. Manifest: {rel(manifest_path)}")
    return 0


def _dry_detect() -> str:
    """Backend guess for --dry-run without loading heavy libraries when they're absent."""
    import importlib.util
    if importlib.util.find_spec("torch"):
        try:
            import torch
            if torch.cuda.is_available():
                return "cuda"
        except Exception:
            pass
    if importlib.util.find_spec("openvino"):
        try:
            import openvino as ov
            return "intel" if any(d.startswith("GPU") for d in ov.Core().available_devices) else "cpu"
        except Exception:
            pass
    print("[auto] neither torch+CUDA nor OpenVINO is installed here; showing the cpu plan")
    return "cpu"


if __name__ == "__main__":
    sys.exit(main())

# Plaza Brawler AI art pipeline

Makes first-draft art for the game from `assets.yaml`: the two fighters (Aries and the Scorpio
Shadow Alchemist) in seven poses each (idle, walk, punch, kick, block, hit, KO), the Halo Plaza
background, hit effects and UI icons. It also makes one sprite sheet plus a JSON atlas per
fighter, and an `ASSET_MANIFEST.json` that records where every image came from.

It runs on three kinds of hardware with one command:

| `--backend` | Hardware | Model | Speed (estimate, not measured yet) |
|---|---|---|---|
| `cuda` | NVIDIA GPU: free Kaggle T4 or Colab T4 | FLUX.1 [schnell], fp16 | roughly 20–60 s per image on a T4 |
| `intel` | Intel integrated GPU (Iris Xe, UHD, Arc) | LCM Dreamshaper v7, INT8, OpenVINO | roughly 5–30 s per image |
| `cpu` | Any PC | same as `intel`, on the CPU | roughly 1–3 min per image |
| `auto` (default) | picks `cuda`, then `intel`, then `cpu` | | |

Output goes to `assets/generated/` (ignored by git). Nothing generated and no model weights are
ever committed.

## The quality difference, plainly

- **Kaggle / Colab (FLUX.1 [schnell])** is the one to use for real art. It follows long prompts,
  keeps the character's colours and outfit much better, draws hands and poses more reliably and
  works at 1024 px.
- **Your Intel PC (LCM Dreamshaper v7)** is a smaller, older model at 512 px. It is good for quick
  drafts and trying prompt ideas offline, but expect simpler, less consistent characters. It only
  reads only about 77 word pieces (tokens) of a prompt, so it uses the shorter `short_prompt` lines.

## Option 1: Kaggle (free NVIDIA GPU) - recommended

One-time setup:

1. Make a free account at https://huggingface.co, open
   https://huggingface.co/black-forest-labs/FLUX.1-schnell and click **Agree and access**.
   FLUX.1 [schnell] is Apache-2.0 and free, but Hugging Face still asks you to log in for it.
2. Make a **Read** token at https://huggingface.co/settings/tokens.
3. On Kaggle, verify your phone number (Settings), or Kaggle won't let a notebook use the internet.

Each time:

1. Kaggle → **Create → New Notebook → File → Import Notebook**, and upload
   `tools/asset_gen/kaggle_plaza_brawler_assets.ipynb` (or paste its GitHub link).
2. Right panel → **Session options**: **Accelerator: GPU T4 x2** (or GPU T4), **Internet: On**.
   Skip P100: current PyTorch may not support it.
3. **Add-ons → Secrets → Add a new secret**: name `HF_TOKEN`, value = your token. Tick it for this notebook.
4. In the first code cell, keep `BRANCH = "feat/ai-asset-pipeline"` until this pull request is
   merged, then change it to `"main"`. Leave `ONLY = []` for everything, or e.g.
   `["fighters/aries/*"]` for one fighter.
5. **Run all**. The first run downloads about 34 GB of model files (a few minutes on Kaggle).
6. Download `plaza_brawler_assets.zip` from the last cells (or right panel → **Output**).

Colab works the same way: *Runtime → Change runtime type → T4 GPU*, put `HF_TOKEN` in the 🔑
Secrets panel, Run all. Colab's free tier has less RAM (about 12 GB) than Kaggle (about 29 GB),
so Kaggle is the safer choice.

On a 16 GB card the script loads FLUX in 4-bit (NF4, bitsandbytes) and turns on CPU offload
automatically; the full fp16 weights would not fit the card or Kaggle's RAM. Flags if you need them:
`--quant none`, `--offload none|model|sequential`.

## Option 2: Your Windows PC with Intel graphics

1. Install **Python 3.12** from https://www.python.org (tick *Add python.exe to PATH*).
   Keep the Intel graphics driver up to date (Windows Update or Intel Driver & Support Assistant);
   OpenVINO uses it to run on the GPU.
2. Open PowerShell in the repo folder:

   ```powershell
   py -3.12 -m venv .venv-art
   .venv-art\Scripts\Activate.ps1
   pip install -r tools\asset_gen\requirements-intel.txt
   python tools\asset_gen\generate.py --dry-run            # shows the plan, loads nothing
   python tools\asset_gen\generate.py --only ui/icon_punch  # one quick test image
   python tools\asset_gen\generate.py                       # everything
   ```

   The first real run downloads the model (about 1 GB) and compiles it for your GPU; compiled
   models are cached in `tools/asset_gen/.cache/` so later runs start faster.
3. If the GPU gives trouble, force the processor: `--backend cpu` (same model, slower).

## Useful flags

| Flag | What it does |
|---|---|
| `--dry-run` (`--verbose`) | Print every image it would make, its size, seed and prompt. Loads no model. |
| `--only "fighters/scorpio/*"` | Only some images (glob on the key; repeatable). |
| `--style pixel` | Pixel-art look: generated, then pixelated to 128 px and 32 colours. |
| `--pose-mode controlnet` | NVIDIA only: guide poses with an OpenPose skeleton (see below). |
| `--skip-existing` | Don't redo images that are already there. |
| `--no-sheets`, `--no-rembg` | Skip sprite sheets / background removal. |
| `--dump-poses DIR` | Save the OpenPose skeleton pictures, to check or edit the poses. |
| `--validate-manifest PATH` | Check an `ASSET_MANIFEST.json` against the schema, the files' sha256 and the licenses. |

Seeds are fixed per fighter (`seed:` in `assets.yaml`), so the same fighter comes back each run
and across poses. Change a seed to get a different design.

## Poses: honest status

- **Default (all backends): pose prompts.** The pose is described in words. This works, but the
  model can drift: the same fighter may change slightly between poses.
- **FLUX.1 [schnell] has no OpenPose ControlNet under a commercial-friendly license.** The FLUX
  pose ControlNets we found are built on FLUX.1 [dev], whose license is non-commercial.
- **`--pose-mode controlnet` (NVIDIA only)** switches to SDXL base 1.0 + `xinsir/controlnet-openpose-sdxl-1.0`
  (both allow commercial use) and draws each pose from a skeleton defined in `generate.py`
  (override with `keypoints:` under a pose in `assets.yaml`). Poses are more exact, but the art
  is SDXL's, not FLUX's, and it is slower (30 steps). This path has not been run on a GPU yet.
- **Intel / CPU:** OpenVINO's diffusers integration (optimum-intel) has no ControlNet pipeline,
  so these always use pose prompts.

## AI frames need hand cleanup

Treat the output as a strong first draft, not finished sprites. Expect to fix things in
**LibreSprite** (free) or **Aseprite**:

- outfit details and colours that change between poses; hands and feet;
- stray pixels or soft edges left by background removal;
- the feet line: sprites are bottom-aligned, but check each pose sits on the floor;
- animation: separate AI images are not real in-between frames. For smooth walk or punch cycles,
  draw or adjust the in-betweens by hand, using the AI pose as the key frame.

When a sprite is final, copy it into a committed folder (for example `assets/sprites/`), add it
to `pubspec.yaml`, and keep the matching `ASSET_MANIFEST.json` entries with it.

## Provenance for the Play Store

`assets/generated/ASSET_MANIFEST.json` lists, for every file: path, sha256, prompt (as actually
sent to the model), seed, model id and revision, model license, extra tools and their licenses
(ControlNet, rembg weights), backend, steps, sizes and time. Each PNG also carries the prompt,
seed, model and backend in a text chunk. Schema: `asset_manifest.schema.json`.

Keep the manifest with the final art so you can show where every image came from and under which
license, if a store review or anyone else asks.

## Licenses

Checked on each model's Hugging Face page or the project's LICENSE file on 2026-11-01.

| Used for | Model / tool | License | Commercial use | Link |
|---|---|---|---|---|
| Images, NVIDIA | FLUX.1 [schnell] (`black-forest-labs/FLUX.1-schnell`) | Apache-2.0 (gated: log in + agree) | Yes | https://huggingface.co/black-forest-labs/FLUX.1-schnell |
| Images, Intel/CPU | `OpenVINO/LCM_Dreamshaper_v7-int8-ov` → `SimianLuo/LCM_Dreamshaper_v7` | MIT on both model pages; distilled from Dreamshaper 7 / Stable Diffusion v1.5, which are **CreativeML OpenRAIL-M** | Yes, under OpenRAIL-M use restrictions (no harmful uses; the licensor claims no rights in your outputs, section 6) | https://huggingface.co/OpenVINO/LCM_Dreamshaper_v7-int8-ov |
| Poses, NVIDIA (optional) | `stabilityai/stable-diffusion-xl-base-1.0` | CreativeML OpenRAIL++-M | Yes, with use restrictions | https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0 |
| Poses, NVIDIA (optional) | `xinsir/controlnet-openpose-sdxl-1.0` | Apache-2.0 | Yes | https://huggingface.co/xinsir/controlnet-openpose-sdxl-1.0 |
| Background removal | rembg | MIT | Yes | https://github.com/danielgatis/rembg |
| Background removal weights (default) | `isnet-general-use` (DIS) | Apache-2.0 | Yes | https://github.com/xuebinqin/DIS |
| Background removal weights (option) | `isnet-anime` (SkyTNT anime-segmentation) | Apache-2.0 | Yes | https://github.com/SkyTNT/anime-segmentation |
| Runtime | diffusers, transformers, accelerate, optimum-intel | Apache-2.0 | Yes | github.com/huggingface |
| Runtime | OpenVINO | Apache-2.0 | Yes | https://github.com/openvinotoolkit/openvino |
| Runtime | PyTorch | BSD-3-Clause style | Yes | https://github.com/pytorch/pytorch |
| Runtime | bitsandbytes, ONNX Runtime, PyYAML | MIT | Yes | |
| Runtime | Pillow | MIT-CMU (HPND) | Yes | https://github.com/python-pillow/Pillow |

Not used, on purpose:

- **`stabilityai/sdxl-turbo` / `sd-turbo`**: Stability AI Community License (`sai-nc-community`).
  Free for research and non-commercial use; commercial use needs Stability's separate license
  (free under US $1M yearly revenue, with registration). We picked the LCM model instead so the
  Intel path has no extra sign-up or revenue cap.
- **FLUX.1 [dev] and its ControlNets**: non-commercial license.
- **`bria-rmbg`** background removal: non-commercial license; `generate.py` refuses it.

## Files

| File | What it is |
|---|---|
| `assets.yaml` | What to make: style, poses, fighters, stage, effects, icons, sizes, seeds. |
| `generate.py` | The CLI. |
| `asset_manifest.schema.json` | JSON Schema for `ASSET_MANIFEST.json`. |
| `kaggle_plaza_brawler_assets.ipynb` | Ready-to-run Kaggle / Colab notebook. |
| `requirements-cuda.txt` / `requirements-intel.txt` | Pinned dependencies for each path. |

## What has and hasn't been tested (2026-11-01)

- Tested in a Linux sandbox without a GPU: `--dry-run` for every backend and style; the OpenVINO
  path end to end on CPU with a tiny random test model (load, reshape, generate, rembg, fit, sheet,
  manifest); the FLUX code path end to end on CPU with a tiny random FLUX model and the pinned
  CUDA versions of diffusers and huggingface_hub; rembg + trimming + pixel-art on a test drawing;
  manifest validation; the notebook is valid nbformat.
- **Not tested yet:** a real FLUX.1 [schnell] run on a GPU (4-bit + offload on a T4), the SDXL
  ControlNet path, and a real LCM Dreamshaper image on an Intel GPU or CPU (the sandbox ran out
  of memory/time compiling the full model). Your first Kaggle run is the real test.

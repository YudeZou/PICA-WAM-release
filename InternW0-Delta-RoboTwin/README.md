# InternW0-Δ + PICA-WAM on RoboTwin 2.0 (preview)

This directory releases the training and evaluation code for the PICA-WAM RoboTwin 2.0 checkpoint, built on the InternW0-Δ backbone and trained on clean demonstrations only. It runs on its own, with the RoboTwin 2.0 simulator as the only external dependency. The model code is adapted from [InternW0-Delta](https://github.com/InternRobotics/InternW0-Delta) `90801ba`. The same model is also packaged as an [XPolicyLab](https://github.com/XPolicyLab/XPolicyLab/pull/212) adapter.

Checkpoint: [xdzouyd/PICA-WAM](https://huggingface.co/xdzouyd/PICA-WAM), `internw0_delta/robotwin.pt`.

Run every command from this directory.

## Installation

The model and the simulator use two environments.

**Model** (Linux, Python 3.11, CUDA 12.8): PyTorch 2.10.0, this package with its `[train,modelscope]` extras, and a conda-local gcc/g++ (for Triton) and FFmpeg (for `torchcodec`).

```bash
bash install.sh pica-wam
conda activate pica-wam
```

The checkpoint was trained and evaluated without the optional `flash-linear-attention` / `causal-conv1d` kernels, so `install.sh` leaves them out.

**Simulator** (Python 3.10, CUDA 12.1 toolkit, a C++ compiler, FFmpeg, and Vulkan/EGL with the NVIDIA graphics libraries; in NVIDIA containers set `NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics`):

```bash
python3.10 -m venv .venv-robotwin
.venv-robotwin/bin/python -m pip install torch==2.4.1 torchvision==0.19.1 \
  --index-url https://download.pytorch.org/whl/cu121 --extra-index-url https://pypi.org/simple
.venv-robotwin/bin/python -m pip install -r eval/robotwin/requirements-sim.txt
.venv-robotwin/bin/python -m pip install --no-build-isolation -r eval/robotwin/requirements-cuda.txt
.venv-robotwin/bin/python eval/robotwin/configure_simulator.py
```

Download `background_texture.zip`, `embodiments.zip` and `objects.zip` from [RoboTwin 2.0](https://huggingface.co/datasets/TianxingChen/RoboTwin2.0/tree/bf44be5) and extract them into `data/robotwin-assets/`. Then, from the model environment, clone RoboTwin at the pinned revision into `third_party/RoboTwin` and link the assets:

```bash
python -m eval.robotwin.setup --assets data/robotwin-assets
```

`ROBOTWIN_ROOT` and `ROBOTWIN_PYTHON` override the defaults `third_party/RoboTwin` and `.venv-robotwin/bin/python`.

## Model files

Weights are not in Git:

| Artifact | Source | Local path |
| --- | --- | --- |
| Wan2.2 VAE, UMT5 encoder, tokenizer | `Wan-AI/Wan2.2-TI2V-5B` on ModelScope | `checkpoints/Wan-AI/Wan2.2-TI2V-5B/` |
| RynnBrain | `Alibaba-DAMO-Academy/RynnBrain1.1-2B` on ModelScope | `checkpoints/RynnBrain1.1-2B/` |
| PICA-WAM RoboTwin checkpoint | [xdzouyd/PICA-WAM](https://huggingface.co/xdzouyd/PICA-WAM) | `checkpoints/robotwin.pt` |
| Training initialization (training only) | [InternRobotics/InternW0-Delta-Base](https://huggingface.co/InternRobotics/InternW0-Delta-Base) | `checkpoints/pretrain.pt` |

```bash
bash download_assets.sh            # add --train for pretrain.pt
bash download_checkpoint.sh        # or pass a local file / HTTPS URL; the SHA256 is checked
```

Only the VAE, UMT5 encoder and tokenizer of Wan2.2 are downloaded, because the checkpoint contains the video expert. Review the upstream licenses before downloading.

## Evaluation

All 50 tasks, `demo_clean` then `demo_randomized`, 100 episodes per task, scene seeds from 100000 and unseen instructions:

```bash
python -m eval.robotwin.run_robotwin MULTIRUN.num_gpus=8
```

One task, or one setting:

```bash
python -m eval.robotwin.run_robotwin EVALUATION.task_name=click_bell MULTIRUN.num_gpus=1
python -m eval.robotwin.run_robotwin MULTIRUN.phases=[random] MULTIRUN.num_gpus=8
```

Each GPU runs one policy server shared by up to six simulator clients. Results go to `runs/eval/robotwin/<time>/`: `summary.csv` and `summary.json`, plus one directory per task. Re-running with the same `EVALUATION.output_dir` resumes an interrupted run. Settings are in [`configs/sim_robotwin.yaml`](configs/sim_robotwin.yaml). The inference contract there (32-step action horizon, replanned after 10 steps, 10 denoising steps) matches the reported result.

## Training

The training data is the official RoboTwin 2.0 clean demonstrations ([`aloha-agilex_clean_50`](https://huggingface.co/datasets/TianxingChen/RoboTwin2.0), 50 tasks × 50, 14D joint actions), downloaded from the LeRobot v3.0 export [`OpenMOSS-Team/robotwin2.0-lerobot-v3.0`](https://huggingface.co/datasets/OpenMOSS-Team/robotwin2.0-lerobot-v3.0).

```bash
bash download_assets.sh --train
bash prepare_data.sh 0                    # download, export, text-embedding cache
bash train.sh 0,1,2,3,4,5,6,7             # extra Hydra overrides may follow
```

- `prepare_data.sh` checks the size and checksum of every downloaded file, then rewrites the export as the LeRobot v2.0 layout the loader reads in `data/robotwin_clean/`, with videos symlinked rather than re-encoded. It then encodes every instruction with the Wan2.2 UMT5 encoder into `.cache/internw0/text_embed/robotwin_clean/`.
- `train.sh` post-trains `checkpoints/pretrain.pt` with the [`robotwin_pica`](configs/task/robotwin_pica.yaml) task. The released checkpoint used 32 GPUs and a global batch of 1024, 5370 steps (10 epochs). On fewer GPUs, `train.sh` keeps that global batch through gradient accumulation. `PICA_WAM_GLOBAL_BATCH` and `PICA_WAM_MICRO_BATCH` (32) change the batch sizes. For several nodes, set `NNODES`, `NODE_RANK`, `MASTER_ADDR` and `MASTER_PORT` and run the same command on every node.
- Runs land in `runs/robotwin_pica/<time>/`, with weights in `checkpoints/weights/slot_*.pt`. To evaluate one, pass `ckpt=runs/robotwin_pica/<time>/checkpoints/weights/<slot>.pt` to `run_robotwin`.

## License

See [LICENSE](LICENSE) and [NOTICE](NOTICE). The RoboTwin evaluation code in `eval/robotwin/` is under the MIT license in [eval/robotwin/LICENSE](eval/robotwin/LICENSE). External models, datasets, simulators and robot assets keep their own licenses.

#!/usr/bin/env bash
set -euo pipefail

# PICA-WAM post-training of InternW0-Delta-Base on the RoboTwin 2.0 clean demonstrations.
# Usage: bash train.sh <gpu_ids> [hydra overrides...]
#   e.g. bash train.sh 0,1,2,3,4,5,6,7
# The paper run used 32 GPUs (4 nodes x 8) with a global batch of 1024; on fewer
# GPUs the same global batch is kept through gradient accumulation. For several
# nodes, set NNODES, NODE_RANK, MASTER_ADDR and MASTER_PORT on every node.
gpu_ids="${1:?Usage: bash train.sh <gpu_ids> [hydra overrides...]}"
shift
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

export ROBOTWIN_DATA_ROOT="${ROBOTWIN_DATA_ROOT:-data/robotwin_clean}"
export WAM_CACHE_ROOT="${WAM_CACHE_ROOT:-.cache/internw0}"
export ROBOTWIN_TEXT_CACHE="${ROBOTWIN_TEXT_CACHE:-${WAM_CACHE_ROOT}/text_embed/robotwin_clean}"
ckpt_root="${WAM_CHECKPOINT_ROOT:-checkpoints}"
for required in "${ROBOTWIN_DATA_ROOT}/meta/episodes.jsonl" "${ROBOTWIN_TEXT_CACHE}" \
    "${ckpt_root}/Wan-AI/Wan2.2-TI2V-5B/Wan2.2_VAE.pth" "${ckpt_root}/RynnBrain1.1-2B" \
    "${WAM_PRETRAIN_CHECKPOINT:-${ckpt_root}/pretrain.pt}"; do
  [[ -e "${required}" ]] || { echo "[train] missing ${required}; run download_assets.sh --train and prepare_data.sh first." >&2; exit 1; }
done

IFS=',' read -r -a gpu_arr <<< "${gpu_ids}"
num_gpus="${#gpu_arr[@]}"
nnodes="${NNODES:-1}"
world_size=$((nnodes * num_gpus))
global_batch="${PICA_WAM_GLOBAL_BATCH:-1024}"
micro_batch="${PICA_WAM_MICRO_BATCH:-32}"
if (( global_batch % (micro_batch * world_size) != 0 )); then
  echo "[train] global batch ${global_batch} is not divisible by ${micro_batch} x ${world_size} GPUs." >&2
  exit 1
fi
grad_accum=$((global_batch / (micro_batch * world_size)))

export CUDA_VISIBLE_DEVICES="${gpu_ids}"
export DIFFSYNTH_SKIP_DOWNLOAD=true
export PYTHONPATH="${SCRIPT_DIR}/src${PYTHONPATH:+:${PYTHONPATH}}"
export ACCELERATE_USE_DEEPSPEED=true
export ACCELERATE_DEEPSPEED_CONFIG_FILE="${SCRIPT_DIR}/scripts/ds_configs/ds_zero2_config.json"
export ACCELERATE_DEEPSPEED_ZERO3_INIT=false
export ACCELERATE_CONFIG_DS_FIELDS=""
export OMP_NUM_THREADS="${OMP_NUM_THREADS:-1}"
export HF_DATASETS_OFFLINE=1
export WANDB_MODE="${WANDB_MODE:-offline}"
export TORCH_NCCL_ASYNC_ERROR_HANDLING=1
export PYTORCH_CUDA_ALLOC_CONF="${PYTORCH_CUDA_ALLOC_CONF:-expandable_segments:True}"

echo "[train] nodes=${nnodes} gpus_per_node=${num_gpus} micro_batch=${micro_batch} grad_accum=${grad_accum} global_batch=${global_batch}"
exec python -m torch.distributed.run \
  --nnodes="${nnodes}" --nproc-per-node="${num_gpus}" --node-rank="${NODE_RANK:-0}" \
  --rdzv-backend=static --master-addr="${MASTER_ADDR:-127.0.0.1}" --master-port="${MASTER_PORT:-29500}" \
  --max-restarts=0 \
  scripts/train.py task=robotwin_pica \
  "batch_size=${micro_batch}" "gradient_accumulation_steps=${grad_accum}" \
  model.tokenizer_model_id=Wan-AI/Wan2.2-TI2V-5B model.redirect_common_files=false \
  "$@"

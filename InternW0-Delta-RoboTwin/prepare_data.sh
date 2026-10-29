#!/usr/bin/env bash
set -euo pipefail

# Download the RoboTwin 2.0 clean demonstrations, export them for training, and
# build the text-embedding cache.
# Usage: bash prepare_data.sh [gpu_ids]   (default: 0)
gpu_ids="${1:-0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

source_dir="${PICA_WAM_SOURCE_DIR:-data/robotwin2.0-lerobot-v3.0}"
export ROBOTWIN_DATA_ROOT="${ROBOTWIN_DATA_ROOT:-data/robotwin_clean}"
export WAM_CACHE_ROOT="${WAM_CACHE_ROOT:-.cache/internw0}"
export ROBOTWIN_TEXT_CACHE="${ROBOTWIN_TEXT_CACHE:-${WAM_CACHE_ROOT}/text_embed/robotwin_clean}"
wan_dir="${WAM_CHECKPOINT_ROOT:-checkpoints}/Wan-AI/Wan2.2-TI2V-5B"

if [[ -f "${ROBOTWIN_DATA_ROOT}/meta/episodes.jsonl" ]]; then
  echo "[prepare_data] existing export found: ${ROBOTWIN_DATA_ROOT}"
else
  prepare_args=(--source "${source_dir}" --output "${ROBOTWIN_DATA_ROOT}")
  [[ "${PICA_WAM_SKIP_DOWNLOAD:-0}" == "1" ]] && prepare_args+=(--skip-download)
  python tools/prepare_robotwin_data.py "${prepare_args[@]}"
fi

for required in "${wan_dir}/models_t5_umt5-xxl-enc-bf16.pth" "${wan_dir}/google/umt5-xxl"; do
  [[ -e "${required}" ]] || { echo "[prepare_data] missing ${required}; run download_assets.sh first." >&2; exit 1; }
done

IFS=',' read -r -a gpu_arr <<< "${gpu_ids}"
echo "[prepare_data] building the text-embedding cache at ${ROBOTWIN_TEXT_CACHE} on GPUs ${gpu_ids}"
export CUDA_VISIBLE_DEVICES="${gpu_ids}"
export DIFFSYNTH_SKIP_DOWNLOAD=true
export TOKENIZERS_PARALLELISM=false
python -m torch.distributed.run --standalone --nnodes=1 --nproc_per_node="${#gpu_arr[@]}" \
  tools/text_cache.py task=robotwin_pica \
  model.tokenizer_model_id=Wan-AI/Wan2.2-TI2V-5B \
  model.redirect_common_files=false \
  "+text_cache_batch_size=${TEXT_CACHE_BATCH_SIZE:-64}"
echo "[prepare_data] done. Next: bash train.sh <gpu_ids>"

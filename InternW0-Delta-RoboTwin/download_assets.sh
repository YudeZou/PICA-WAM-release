#!/usr/bin/env bash
set -euo pipefail

# Usage: bash download_assets.sh [--train]
#   Wan2.2 VAE + UMT5 text encoder/tokenizer -> checkpoints/Wan-AI/Wan2.2-TI2V-5B
#   RynnBrain1.1-2B                          -> checkpoints/RynnBrain1.1-2B
#   --train also fetches the InternW0-Delta-Base initialization -> checkpoints/pretrain.pt

WITH_TRAIN=0
if [[ "${1:-}" == "--train" ]]; then
  WITH_TRAIN=1
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CKPT_DIR="${SCRIPT_DIR}/checkpoints"

python -c "import modelscope, huggingface_hub" 2>/dev/null || {
  echo "Python packages 'modelscope' and 'huggingface_hub' are required. Activate the model environment first." >&2
  exit 1
}

download_model() {
  local model_id="$1"
  local destination="$2"
  local selection="$3"
  mkdir -p "${destination}"
  echo "Downloading ${model_id} to ${destination}"
  python - "${model_id}" "${destination}" "${selection}" <<'PY'
import sys
from modelscope import snapshot_download

patterns = None
if sys.argv[3] == "wan":
    patterns = [
        "Wan2.2_VAE.pth",
        "models_t5_umt5-xxl-enc-bf16.pth",
        "google/umt5-xxl/*",
    ]
kwargs = {"local_dir": sys.argv[2]}
if patterns:
    kwargs["allow_file_pattern"] = patterns
snapshot_download(sys.argv[1], **kwargs)
PY
}

download_model "Wan-AI/Wan2.2-TI2V-5B" "${CKPT_DIR}/Wan-AI/Wan2.2-TI2V-5B" "wan"
download_model "Alibaba-DAMO-Academy/RynnBrain1.1-2B" "${CKPT_DIR}/RynnBrain1.1-2B" "full"
echo "Backbone files are ready under ${CKPT_DIR}"

if [[ "${WITH_TRAIN}" == "1" ]]; then
  PRETRAIN_SHA="a6bcf7a1eb2cf3d303e02faca05579cf77f4ac90863a15ff896b7e85ef884a08"
  python - "${CKPT_DIR}" <<'PY'
import sys
from huggingface_hub import hf_hub_download

hf_hub_download(repo_id="InternRobotics/InternW0-Delta-Base", filename="pretrain.pt", local_dir=sys.argv[1])
PY
  actual_sha=$(sha256sum "${CKPT_DIR}/pretrain.pt" | awk '{print $1}')
  if [[ "${actual_sha}" != "${PRETRAIN_SHA}" ]]; then
    echo "pretrain.pt SHA256 mismatch: ${actual_sha}" >&2
    exit 1
  fi
  echo "Training initialization ready: ${CKPT_DIR}/pretrain.pt"
fi

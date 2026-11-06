#!/bin/sh
set -eu

omp_lib=$(find /opt/venv -name libiomp5.so -print -quit)
if [ -z "$omp_lib" ]; then
    echo "libiomp5.so not found in /opt/venv" >&2
    exit 1
fi

export LD_PRELOAD="$omp_lib"
python /app/download_model.py

export HF_HUB_OFFLINE=1
export TRANSFORMERS_OFFLINE=1
exec vllm serve "$@"

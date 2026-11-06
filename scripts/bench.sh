#!/usr/bin/env bash
set -euo pipefail

for trial in 1 2 3; do
  for input_len in 32 256; do
    printf '\n=== trial=%s input_len=%s ===\n' "$trial" "$input_len"

    minikube kubectl -- -n default exec deployment/vllm -- sh -c '
      export OPENAI_API_KEY="$VLLM_API_KEY"
      exec vllm bench serve \
        --backend openai-chat \
        --host vllm \
        --port 8000 \
        --endpoint /v1/chat/completions \
        --model Qwen/Qwen2.5-0.5B-Instruct \
        --tokenizer /models/qwen2.5-0.5b-instruct \
        --dataset-name random \
        --random-input-len "$1" \
        --random-output-len 32 \
        --random-range-ratio 0 \
        --temperature 0 \
        --ignore-eos \
        --num-warmups 2 \
        --num-prompts 30 \
        --max-concurrency 4 \
        --percentile-metrics ttft,e2el \
        --metric-percentiles 50,95
    ' bench "$input_len"
  done
done

echo 'ALL RUNS FINISHED'

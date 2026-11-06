FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    ca-certificates \
    python3-venv \
    python3.12-dev \
    g++ \
    libnuma1

WORKDIR /app
COPY requirements.txt .

RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

RUN python -m pip install --no-cache-dir \
    --extra-index-url https://download.pytorch.org/whl/cpu \
    -r requirements.txt \
    && python -m pip check
RUN useradd --create-home --uid 10001 --shell /bin/bash vllm
ENV HOME=/home/vllm
USER vllm
COPY --chmod=755 entrypoint.sh /app/entrypoint.sh
COPY download_model.py /app/download_model.py
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["/models/qwen2.5-0.5b-instruct", "--served-model-name", "Qwen/Qwen2.5-0.5B-Instruct", "--host", "0.0.0.0", "--port", "8000", "--dtype", "float32", "--max-model-len", "512", "--max-num-seqs", "1", "--gpu-memory-utilization", "0.5"]

import fcntl
from pathlib import Path

from huggingface_hub import snapshot_download


MODEL_ID = "Qwen/Qwen2.5-0.5B-Instruct"
MODEL_DIR = Path("/models/qwen2.5-0.5b-instruct")
PARTIAL_DIR = MODEL_DIR.with_name(f".{MODEL_DIR.name}.partial")


def main():
    with MODEL_DIR.with_suffix(".lock").open("a") as lock_file:
        fcntl.flock(lock_file, fcntl.LOCK_EX)

        if MODEL_DIR.is_dir():
            print(f"Using cached model: {MODEL_DIR}", flush=True)
            return

        print(f"Downloading {MODEL_ID} to {PARTIAL_DIR}", flush=True)
        snapshot_download(repo_id=MODEL_ID, local_dir=PARTIAL_DIR)
        PARTIAL_DIR.rename(MODEL_DIR)
        print(f"Model ready: {MODEL_DIR}", flush=True)


if __name__ == "__main__":
    main()

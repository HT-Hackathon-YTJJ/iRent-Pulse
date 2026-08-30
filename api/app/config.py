"""Runtime configuration, read from the repo-root .env.

The Flutter app and this service share one .env at the project root — the same
file that already holds GOOGLE_MAPS_API_KEY — so there is a single place to put
secrets and a single .gitignore rule covering it. An api/.env is read afterwards
and wins, for when the backend needs to be pointed somewhere else without
touching the app's file.
"""

import os
from pathlib import Path
from typing import Dict

API_DIR = Path(__file__).resolve().parent.parent
REPO_ROOT = API_DIR.parent


def _parse_env(path: Path) -> Dict[str, str]:
    if not path.exists():
        return {}
    values: Dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def _load() -> Dict[str, str]:
    merged = _parse_env(REPO_ROOT / ".env")
    merged.update(_parse_env(API_DIR / ".env"))
    # A real environment variable always wins over the files.
    merged.update({k: v for k, v in os.environ.items() if k in merged})
    return merged


_ENV = _load()


def env(key: str, default: str = "") -> str:
    return os.environ.get(key) or _ENV.get(key) or default


OPENROUTER_API_KEY = env("OPENROUTER_API_KEY")
OPENROUTER_BASE_URL = env("OPENROUTER_BASE_URL", "https://openrouter.ai/api/v1")

# L1 is the cheap high-recall screen; L2 is the expensive high-precision
# confirmation. Only L2's model is calibrated well enough for its confidence to
# be usable as a routing signal (spec §L2), which is why it is not a Gemini.
L1_MODEL = env("L1_MODEL", "google/gemini-3.7-flash")
L2_MODEL = env("L2_MODEL", "anthropic/claude-opus-5")

REQUEST_TIMEOUT_S = float(env("VLM_TIMEOUT_S", "60"))
MAX_ATTEMPTS = int(env("VLM_MAX_ATTEMPTS", "3"))

# Photos are downscaled before they reach a VLM: image tokens dominate cost and
# a 1024px long edge is well past what any of these checks resolve.
MAX_IMAGE_EDGE = int(env("MAX_IMAGE_EDGE", "1024"))
JPEG_QUALITY = int(env("JPEG_QUALITY", "85"))

PHOTO_DIR = API_DIR / "data" / "photos"
PHOTO_DIR.mkdir(parents=True, exist_ok=True)

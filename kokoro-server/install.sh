#!/bin/bash
# Install Kokoro-82M (via mlx-audio) as a localhost-only TTS server on an
# Apple Silicon Mac. Run on the machine that will host the server.
#   ./install.sh            install the tool, warm the model
#   ./install.sh --launchd  also install a launchd agent (start at login, keep alive)
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"
command -v uv >/dev/null || curl -LsSf https://astral.sh/uv/install.sh | sh

# misaki does the English text processing and needs the spaCy model preinstalled:
# at runtime it tries `uv pip install`, which fails outside a venv.
uv tool install --python 3.12 --force mlx-audio \
  --with "misaki[en]" --with num2words --with spacy \
  --with "en_core_web_sm @ https://github.com/explosion/spacy-models/releases/download/en_core_web_sm-3.8.0/en_core_web_sm-3.8.0-py3-none-any.whl" \
  --with uvicorn --with fastapi --with python-multipart --with webrtcvad-wheels

mkdir -p "$HOME/Library/Logs/kokoro"
if [[ "${1:-}" == --launchd ]]; then
  dst="$HOME/Library/LaunchAgents/local.kokoro-tts.plist"
  sed "s#__HOME__#$HOME#g" "$(dirname "$0")/kokoro-tts.plist.template" >"$dst"
  launchctl bootout "gui/$(id -u)/local.kokoro-tts" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$dst"
  echo "launchd agent installed: $dst"
else
  echo "start it with: mlx_audio.server --host 127.0.0.1 --port 8880"
fi

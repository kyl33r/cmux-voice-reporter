#!/bin/bash
# Install Kokoro-82M (via mlx-audio) as a localhost-only TTS server on an
# Apple Silicon Mac. Run on the machine that will host the server.
#   ./install.sh            install the tool, download and test the model
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

# The model (~340 MB: 312 MB weights + 54 voices) comes from Hugging Face on
# first use, into ~/.cache/huggingface/hub/. Fetch it now with one test line,
# so the first real headline isn't a slow download.
echo "downloading mlx-community/Kokoro-82M-bf16 and speaking a test line..."
tmp=$(mktemp -d)
mlx_audio.tts.generate --model mlx-community/Kokoro-82M-bf16 --voice af_nicole --lang_code a \
  --text "Kokoro is ready." --output_path "$tmp" --file_prefix warm --audio_format wav >/dev/null
[[ -s "$tmp/warm_000.wav" ]] && echo "model ready" || { echo "test line failed" >&2; exit 1; }

# Qwen3-TTS (the default voice, qwen:airy) clones the reference clips in voices/.
# The 0.6B Base model (4.7 GB on disk) also comes from Hugging Face on first use.
mkdir -p "$HOME/.local/share/cmux-voice/voices"
cp "$(dirname "$0")"/../voices/*.wav "$HOME/.local/share/cmux-voice/voices/"
echo "downloading mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16 and cloning a test line..."
mlx_audio.tts.generate --model mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16 \
  --ref_audio "$HOME/.local/share/cmux-voice/voices/airy.wav" \
  --text "Qwen is ready." --output_path "$tmp" --file_prefix qwen --audio_format wav >/dev/null
ls "$tmp"/qwen_*.wav >/dev/null 2>&1 && echo "qwen ready" || { echo "qwen test line failed" >&2; exit 1; }
rm -rf "$tmp"

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

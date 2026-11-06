#!/bin/bash
# Install Kokoro-82M (via mlx-audio) as a localhost-only TTS server on an
# Apple Silicon Mac. Run on the machine that will host the server.
#   ./install.sh               install Kokoro, download and test it; ask about Qwen
#   ./install.sh --qwen        also install the Qwen3-TTS voice without asking
#   ./install.sh --no-qwen     skip Qwen without asking
#   ./install.sh --launchd     also install a launchd agent (start at login, keep alive)
#
# Footprint on this Mac:
#   Kokoro (required): ~1.2 GB tools + ~340 MB model on disk; the server uses ~0.75 GB RAM.
#   Qwen3-TTS (optional, the breathy default voice qwen:airy): +4.7 GB on disk, and the
#   server grows to ~3.5 GB RAM (5 GB+ seen) once a Qwen line is spoken, until restart.
set -euo pipefail
qwen=ask launchd=
for arg in "$@"; do
  case $arg in
    --qwen) qwen=yes ;;
    --no-qwen) qwen=no ;;
    --launchd) launchd=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done
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

rm -rf "$tmp"

# Optional: Qwen3-TTS clones the breathy reference clips in voices/ (qwen:airy and
# the other presets). Without the clips on this Mac, a client asking for qwen:*
# gets a fast "reference audio not found" and falls back to Kokoro af_nicole;
# nothing downloads.
cat <<'MSG'

Optional: the breathy Qwen3-TTS voice (qwen:airy, the clients' default VOICE).
  Disk:    +4.7 GB  (mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16, from Hugging Face)
  Memory:  the server grows from ~0.75 GB to ~3.5 GB once a Qwen line is spoken
           (5 GB+ seen), and keeps it until the server restarts.
  Speed:   1-3 s per sentence, against ~0.8 s for Kokoro.
  Skip it on a Mac short of memory. Clients then fall back to Kokoro af_nicole;
  set VOICE=af_nicole on the clients to skip the attempt.
MSG
if [[ $qwen == ask ]]; then
  if [[ -t 0 ]]; then read -r -p "Install the Qwen voice? [y/N] " answer; else answer=n; fi
  [[ $answer == [yY]* ]] && qwen=yes || qwen=no
fi
if [[ $qwen == yes ]]; then
  mkdir -p "$HOME/.local/share/cmux-voice/voices"
  cp "$(dirname "$0")"/../voices/*.wav "$HOME/.local/share/cmux-voice/voices/"
  echo "downloading the Qwen3-TTS model and cloning a test line..."
  tmp=$(mktemp -d)
  mlx_audio.tts.generate --model mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16 \
    --ref_audio "$HOME/.local/share/cmux-voice/voices/airy.wav" \
    --text "Qwen is ready." --output_path "$tmp" --file_prefix qwen --audio_format wav >/dev/null
  ls "$tmp"/qwen_*.wav >/dev/null 2>&1 && echo "qwen ready" || { echo "qwen test line failed" >&2; exit 1; }
  rm -rf "$tmp"
else
  echo "skipped Qwen; run again with --qwen to add it later"
fi

mkdir -p "$HOME/Library/Logs/kokoro"
if [[ -n "$launchd" ]]; then
  dst="$HOME/Library/LaunchAgents/local.kokoro-tts.plist"
  sed "s#__HOME__#$HOME#g" "$(dirname "$0")/kokoro-tts.plist.template" >"$dst"
  launchctl bootout "gui/$(id -u)/local.kokoro-tts" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$dst"
  echo "launchd agent installed: $dst"
else
  echo "start it with: mlx_audio.server --host 127.0.0.1 --port 8880"
fi

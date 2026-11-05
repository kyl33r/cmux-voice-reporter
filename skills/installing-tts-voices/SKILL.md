---
name: installing-tts-voices
description: Use when a user wants more, different, cuter or better-sounding text-to-speech voices on a Mac, asks which open-source TTS engines exist, or wants to add a TTS engine or voice to cmux-voice-reporter or any script that speaks text aloud.
---

# Installing TTS voices

## Overview
Add a voice in three steps: install it, generate one sample file, then let the user choose. Generating audio is cheap. Playing audio interrupts the user, so play only on an explicit ask ("play them", "let me hear"). Otherwise list the clips and ask.

## Quick reference

| Source | Cost | Verified here | How to add |
|---|---|---|---|
| macOS `say` | free | yes | System Settings → Accessibility → Spoken Content → System Voice → Manage Voices. List with `say -v '?'`. There's no CLI to install or remove voices, and the built-in Eddy/Flo/Sandy/Shelley/Reed/Rocko/Grandma/Grandpa families can't be removed. |
| Kokoro-82M via mlx-audio | free, local | yes | `kokoro-server/install.sh` in this repo. Ships 54 voices, all downloaded with the model. Blend two with `"af_heart,jf_alpha"`. |
| Other mlx-audio models | free, local | **no** | Same server, different `model` in the request. See below. |
| ElevenLabs | paid | no | Needs an API key and per-character billing. Get the user's explicit yes and name the billing route first. |

**Kokoro voice names:** `<language><f|m>_<name>`. Language letters: `a` US English, `b` UK English, `j` Japanese, `z` Mandarin, `e` Spanish, `f` French, `h` Hindi, `i` Italian, `p` Portuguese. The second letter is female or male. UK female voices, for example, are `bf_alice`, `bf_emma`, `bf_isabella` and `bf_lily`. Non-English voices reading English text sound accented. To list the voices, run `ssh $KOKORO_HOST 'ls ~/.cache/huggingface/hub/models--mlx-community--Kokoro-82M-bf16/snapshots/*/voices/'`. For macOS voices by accent, run `say -v '?' | grep en_GB`.

## Trying another mlx-audio engine
mlx-audio 0.6.4 ships these TTS model families in `mlx_audio/tts/models/`: kokoro, kitten_tts, chatterbox, chatterbox_turbo, dia, outetts, spark, sesame, melotts, bark, zonos2, voxcpm, qwen3_tts, vibevoice, indextts, higgs_audio, and more. Only kokoro has been tested.

1. Find the converted weights on Hugging Face (usually `mlx-community/<Model>-…`). Read the model card's **license**: some are non-commercial.
2. Generate one clip with the CLI before touching any script:
   ```bash
   mlx_audio.tts.generate --model <repo-id> --voice <voice> --lang_code a \
     --text "Voice 1. agent paging finished: all checks green." \
     --output_path ~/tts-samples --file_prefix v1_<voice> --audio_format wav
   ```
   Kokoro example: `--model mlx-community/Kokoro-82M-bf16 --voice bf_emma`. Some models (Chatterbox, Sesame and other cloning models) want `--ref_audio <wav> --ref_text <words>` instead of a voice name. Check the model card. Number each sample so the user can answer "voice 3".
3. If it fails with an import error, add the missing package with `uv tool install --force mlx-audio --with <pkg> …`, repeating every earlier `--with`. A plain `uv pip install` fails outside a venv.
4. Time a warm request through the server, which listens on `127.0.0.1:8880` on `$KOKORO_HOST`:
   `jq -n '{model:"<repo-id>",input:"test",voice:"<voice>",response_format:"wav"}' | ssh $KOKORO_HOST 'curl -sf -X POST http://127.0.0.1:8880/v1/audio/speech -H content-type:application/json -d @-' > t.wav`
   The first request loads the model and is slow, so time the second.
5. Copy the clips back (`scp "$KOKORO_HOST:tts-samples/*.wav" ~/.cache/cmux-voice/samples/`), then report their paths and timings. Play them with `afplay` only on an explicit ask.

## Wiring a voice into cmux-voice-reporter
- The script is `~/.local/bin/cmux-voice-reporter`. Its default voice is the `voice=${VOICE:-…}` line near the top. For a one-off, start the pane with `--command "VOICE=bf_emma ~/.local/bin/cmux-voice-reporter"`.
- Kokoro names already route to the server (regex `^[a-z][fm]_[a-z]+`), and any other name goes to `say`.
- A new engine needs its own branch in `speak()` that sends a different `model`. Keep the `say` fallback.
- Restart the reporter pane after changing it (see cmux-voice-reporter-ops).

## Common mistakes
- Playing five samples in a row without being asked. Users rejected this repeatedly. Generate first, then ask.
- Installing an engine and declaring it works without generating a file.
- Recommending a voice that copies a real person or a named character. Offer generic voices, or voice cloning only from audio the user owns.
- Exposing the TTS server on the LAN by default. Bind it to `127.0.0.1` and reach it over ssh.

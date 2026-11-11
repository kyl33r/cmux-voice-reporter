# cmux-voice-reporter

Speaks a short headline aloud when a Claude Code session in a [cmux](https://cmux.dev) pane finishes a turn:

> "api tests finished: Rebased and pushed the fix, all checks green."

One speaker for all panes. Child sessions never speak. A single process reads cmux's notification stream and speaks one line at a time.

## Features

| Tool | What it does | Speaks? |
|---|---|---|
| `cmux-voice-reporter` | Speaks "<pane> finished: <first sentence>" each time a Claude Code turn ends in any cmux pane. | yes |
| `cmux-voice-say` | Speaks one headline you choose, in the same voice. Made for an orchestrator session that reads out only the reports that matter. | yes |
| `cmux-voice-nudge` | Every 3 minutes, speaks the top two items for you from an orchestrator's board file: "Next: 1, … 2, …". | yes |
| `cmux-status-since` | Prints only the pane updates since your last call, one line each (time, pane, headline). Made for an orchestrator that wants new reports without rereading everything. | no |

Shared by all of them:

- **Local, free voice.** A breathy Qwen3-TTS voice by default, with Kokoro-82M and then macOS `say` as fallbacks, all on an Apple Silicon Mac (this one or one you reach over ssh). No API keys, no cloud calls, no AI summarizing.
- **One line at a time.** The three speakers share a lock, so lines never overlap.
- **Pauses your music.** Whatever is playing (Spotify, Apple Music, YouTube in a browser, anything in the macOS Now Playing menu) pauses while a line is spoken and resumes after. Music you paused yourself stays paused. Needs `brew install media-control`; set `PAUSE_MEDIA=0` to turn it off.
- **Separate mute files.** Mute the per-pane announcements, the chosen headlines and the nudges on their own.
- **Read-only toward your sessions.** Everything reads cmux's existing turn-end events and notifications. Nothing types into a pane or changes a session's config.
- **Restart-safe.** Cursor files mean a restart resumes where it left off without replaying old events.

## How it works

1. **Trigger.** cmux launches `claude` through its own wrapper, which installs Stop/Notification hooks that report back to cmux. cmux then emits one `notification.created` event per finished top-level turn. Subagent turns are already suppressed (`CMUX_SUPPRESS_SUBAGENT_NOTIFICATIONS=1`), and idle repeats are deduplicated. The reporter subscribes with `cmux events --name notification.created --reconnect --cursor-file …`. No hook config is needed.
2. **Headline.** The event redacts the text, so the reporter looks the notification up in `cmux list-notifications`, which holds the last assistant message (about 200 chars). It takes the first sentence, strips markdown, and caps it at about 120 chars on a word boundary. The pane title comes from `cmux --id-format both tree --all --json`. The workspace name is added only when two panes share a title.
3. **Voice.** [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M), run through [mlx-audio](https://github.com/Blaizzy/mlx-audio) on an Apple Silicon Mac, is free, local and fast (about 0.8 s per headline once the model is loaded). Any macOS `say` voice also works, and `say` is the fallback when the Kokoro server doesn't answer.
4. **Queue.** The read loop is serial, so bursts queue in the pipe and each pane is spoken once. The cursor file means a restart resumes without replaying old events.

## Install

```bash
cp bin/cmux-voice-reporter ~/.local/bin/
brew install media-control            # optional: pause music while a line is spoken
# TTS server, on this Mac or another one you can ssh to:
kokoro-server/install.sh            # asks about Qwen; --qwen / --no-qwen to decide up front,
                                    # --launchd to keep the server running
```

> **Footprint, before you install.** Everything runs on the server Mac.
>
> | Part | Disk | Memory while the server runs | Required? |
> |---|---|---|---|
> | Kokoro-82M + mlx-audio tools | ~1.6 GB | ~0.75 GB | yes |
> | Qwen3-TTS 0.6B (the breathy default voice) | +4.7 GB | grows to ~3.5 GB once a Qwen line is spoken (5 GB+ seen), until the server restarts | no: `install.sh` asks first |
> | Japanese text support (optional, see below) | +0.8 GB | small | no |
>
> On a Mac that is short of memory or already runs heavy jobs, answer no to Qwen. The clients then fall back to Kokoro `af_nicole` on each line, because the server reports the voice clip missing straight away and downloads nothing. Set `VOICE=af_nicole` on the clients to skip that attempt.

Long lines are spoken a sentence at a time. Each sentence is generated while the one before it plays, so every request stays well under `QWEN_TIMEOUT` and speech starts sooner.

The `say` fallback voice, Samantha (US English), ships with macOS. To use another, set `FALLBACK_VOICE` to any name from `say -v '?'`; extra voices download from System Settings → Accessibility → Spoken Content → System Voice → Manage Voices.

Run the reporter in its own cmux pane:

```bash
cmux new-split right --command ~/.local/bin/cmux-voice-reporter --focus false
```

## Voice previews

Each pinned voice says the same line in `samples/`, so you can pick one by ear: "Hi, I'm <name>, reporting for duty. I'll read out each update as soon as your work finishes."

| Preview | `VOICE=` | Sound | Engine |
|---|---|---|---|
| [1-qwen-airy.m4a](samples/1-qwen-airy.m4a) | `qwen:airy` (default) | soft, breathy, airy | Qwen3-TTS (optional install) |
| [2-qwen-whisper.m4a](samples/2-qwen-whisper.m4a) | `qwen:whisper` | gentle, whispery, warm | Qwen3-TTS (optional install) |
| [3-qwen-airy-jp.m4a](samples/3-qwen-airy-jp.m4a) | `qwen:airy-jp` | soft and airy, light Japanese accent | Qwen3-TTS (optional install) |
| [4-kokoro-nicole.m4a](samples/4-kokoro-nicole.m4a) | `af_nicole` | soft, close, whispery | Kokoro (first fallback) |
| [5-kokoro-alpha.m4a](samples/5-kokoro-alpha.m4a) | `jf_alpha` | light Japanese voice reading English | Kokoro (second fallback) |

```bash
afplay samples/1-qwen-airy.m4a                       # play one on a Mac
for f in samples/*.m4a; do echo "$f"; afplay "$f"; done   # play them all, in order
say -v Samantha "The build finished and all tests passed."  # the last fallback, built into macOS
```

On GitHub, open a preview and choose **View raw** to play or download it. To use a voice, start the reporter with it, for example `VOICE=qwen:whisper ~/.local/bin/cmux-voice-reporter`, or change the `voice=${VOICE:-…}` default in your installed copy.

## Voice models: where they come from

The default voice, `qwen:airy`, is a soft, breathy female voice. Qwen3-TTS clones it from a short reference clip, so every line sounds the same. Two more clips are pinned: `qwen:whisper` (whispery, warm) and `qwen:airy-jp` (airy, with a light Japanese accent). To add one, design or record a clip you have the rights to, put it in `voices/<name>.wav`, copy it to the server, and use `VOICE=qwen:<name>`.

| What | Where it comes from | Size | When it downloads |
|---|---|---|---|
| Qwen3-TTS 0.6B Base (the default voice) | Hugging Face, [`mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16`](https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16) | 4.7 GB | `install.sh` clones one test line |
| Reference clips (`voices/airy.wav`, `whisper.wav`, `airy-jp.wav`) | this repo; each voice was designed with Qwen3-TTS 1.7B VoiceDesign from a text description, then cloned with the 0.6B Base model saying a short greeting | about 0.9 MB in all | copied to the server by `install.sh` |
| Kokoro-82M weights (`kokoro-v1_0.safetensors`) | Hugging Face, [`mlx-community/Kokoro-82M-bf16`](https://huggingface.co/mlx-community/Kokoro-82M-bf16) | 312 MB | `install.sh` speaks one test line, which fetches it into `~/.cache/huggingface/hub/` on the server Mac |
| The 54 Kokoro voices (`voices/*.safetensors`, `af_nicole` and the rest) | the same Hugging Face repo | 27 MB (about 0.5 MB each) | together with the weights; switching voices downloads nothing |
| mlx-audio and its Python dependencies | PyPI, through `uv tool install` in `install.sh` | about 1.2 GB in `~/.local/share/uv/tools/mlx-audio` | `install.sh` |
| spaCy `en_core_web_sm` (English text processing) | GitHub release wheel, pinned in `install.sh` | about 15 MB | `install.sh` |
| macOS `say` voices, such as the Samantha fallback | Apple, through System Settings → Accessibility → Spoken Content → Manage Voices | varies | when you pick one; there's no command-line install |
| Other mlx-audio models | Hugging Face, by repo id | varies | on first `mlx_audio.tts.generate --model <repo>`; see `skills/installing-tts-voices` |

Only the first download needs the internet. After that everything runs offline.

**Japanese text (optional).** Japanese voices (`jf_*`, `jm_*`) read English text through the English pipeline. To have them read Japanese text, add the Japanese text tools and the UniDic dictionary (about 780 MB) on the server Mac:

```bash
uv pip install --python ~/.local/share/uv/tools/mlx-audio/bin/python "misaki[ja]"
~/.local/share/uv/tools/mlx-audio/bin/python -m unidic download
```

Then send `"lang_code": "j"` with the request. The running server picks this up without a restart.

**Memory.** Measured on a 32 GB M-series Mac. Kokoro alone: the server's footprint is about 0.75 GB, and a line takes about 0.8 s. With Qwen3-TTS 0.6B also loaded: about 3.5 GB steady and 5.2 GB after first use, and a line takes 1–3 s. `DELETE /v1/models?model_name=<repo id>` unloads a model, but MLX keeps its freed buffers cached (about 3.3 GB stays). Only restarting the server returns it to Kokoro's 0.75 GB. Designing a new voice with the 1.7B VoiceDesign model peaked at 6.8 GB in a one-off process.

## Options (environment)

| Variable | Default | Meaning |
|---|---|---|
| `VOICE` | `qwen:airy` | `qwen:<name>` clones `voices/<name>.wav` with Qwen3-TTS (`qwen:airy`, `qwen:whisper`, `qwen:airy-jp`); a Kokoro voice (`af_nicole`, `bf_emma`, …, or a blend `"af_heart,jf_alpha"`); or any macOS `say` voice name |
| `FALLBACK_VOICE` | `af_nicole jf_alpha Samantha` | Voices tried in order when `VOICE` fails. A Qwen line gets one try within `QWEN_TIMEOUT`; a Kokoro first voice gets up to 60 s and one retry. After a failure the rest of that engine is skipped, and an unreachable server skips straight to the first `say` voice. Each fallback writes `kokoro fallback: <reason>; using <voice>` to `spoken.log`. |
| `QWEN_TIMEOUT` | `15` | seconds a Qwen line may take before the line falls back |
| `PAUSE_MEDIA` | `1` | `0` leaves music playing; `1` pauses whatever is in Now Playing while a line is spoken (needs `media-control`) |
| `QWEN_VOICE_DIR` | `~/.local/share/cmux-voice/voices` | folder of reference clips on the server (`install.sh` copies `voices/` there) |
| `QWEN_MODEL` | `mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16` | Qwen3-TTS model used for cloning |
| `KOKORO_HOST` | unset | ssh host running the server; unset means the server is on this machine |
| `VOICE_SKIP_SURFACE` | unset | cmux surface UUID to stay silent for, such as an orchestrator pane |
| `VOICE_ONLY_SURFACE` | unset | speak only for this surface (testing) |

- Log of spoken lines with timing: `~/.cache/cmux-voice/spoken.log`.
- `--once` exits after the first spoken line.

## Chosen headlines: cmux-voice-say

`cmux-voice-say` speaks one headline you pick, in the same voice as the reporter. An orchestrator session can call it to read out only the reports that matter, alongside the per-pane announcements or instead of them.

```bash
cp bin/cmux-voice-say ~/.local/bin/
cmux-voice-say "api tests pushed; the flaky case now passes"
```

- It reads the same `VOICE`, `FALLBACK_VOICE` and `KOKORO_HOST` settings as the reporter, and falls back to `say` the same way.
- Each line goes to `~/.cache/cmux-voice/spoken.log` with the tag `master` in the second column, where reporter lines carry `turn_end=…`.
- To speak only chosen headlines, mute the reporter and leave `cmux-voice-say` on.

## Nudges: cmux-voice-nudge

`cmux-voice-nudge` reads the top two items for you from an orchestrator's board every three minutes and speaks them: "Next: 1, Review the login PR. 2, Rerun the nightly tests."

```bash
cp bin/cmux-voice-nudge ~/.local/bin/
cmux new-split right --command ~/.local/bin/cmux-voice-nudge --focus false
```

- It reads items 1 and 2 of the numbered list under `## You` in `NUDGE_BOARD` (default `~/.cache/master-board/BOARD.md`). Markdown, inline code, `! command` text and the `, in <pane>:` suffix are stripped.
- `NUDGE_SECONDS` sets the interval (default 180). `--once` runs one tick and exits.
- It speaks through `cmux-voice-say` (tag `nudge` in `spoken.log`), so it uses the same voice settings.
- A tick is skipped when you are muted, when the list is empty, or when another line is playing.
- Run it in its own cmux pane, not as a Claude Code background task.

## One speaker at a time

The reporter, `cmux-voice-say` and the nudge share a lock directory, `~/.cache/cmux-voice/speaking.lock`, that holds the speaker's pid. The reporter and `cmux-voice-say` wait up to 30 s for it (`VOICE_LOCK_WAIT` for `cmux-voice-say`). The nudge doesn't wait: it skips the tick. A lock whose pid has exited, or that is older than two minutes, is cleared.

## Incremental updates: cmux-status-since

`cmux-status-since` prints one line per Claude Code turn that ended in any pane since the last call, then exits. It prints nothing when nothing is new.

```bash
cp bin/cmux-status-since ~/.local/bin/
cmux-status-since            # reader "master"
cmux-status-since nudge      # another reader, with its own cursor
```

```
16:19	docs site	The new install guide is ready for review.
16:20	release prep	The tag is pushed and the build is green.
```

- It uses cmux's own event cursor, `~/.cache/master-board/.cursor-<name>` (`STATUS_CURSOR_DIR` changes the folder), so it needs no other process running. A first call prints at most the last 20 updates.
- The pane title comes from `cmux tree` and the headline from `cmux list-notifications`. cmux keeps only queued notifications. When one was already dismissed or replaced, the line says `(text no longer in cmux)`; call it often to keep the text.
- `STATUS_SKIP_SURFACES` (space-separated UUIDs) leaves panes out, such as the caller's own.
- It doesn't speak, doesn't call any model, and reads nothing but cmux.

## Muting

Each speaker has its own mute file in `~/.cache/cmux-voice/`. Create the file to mute; delete it to unmute.

| File | Silences |
|---|---|
| `mute` | per-pane announcements from `cmux-voice-reporter` |
| `master-mute` | chosen headlines from `cmux-voice-say`, and the nudge |
| `nudge-mute` | the nudge only |

```bash
touch ~/.cache/cmux-voice/mute          # silence the reporter
rm ~/.cache/cmux-voice/master-mute      # unmute cmux-voice-say
```

The Kokoro server listens on `127.0.0.1:8880` only. A remote client reaches it over ssh, so nothing is exposed on the network. The API is OpenAI-compatible: `POST /v1/audio/speech`.

## Gotchas found while building it

- **Don't run the reporter as a Claude Code background task.** While a Claude-tracked background task is running, the owning session's Stop hook doesn't fire. Its own turns then never create a notification, so the reporter waits forever. Run it in its own cmux pane or under launchd.
- `cmux list-notifications` has no JSON output. The body can contain `|` (markdown tables), so the row is parsed from both ends instead of with `cut`.
- `cmux tree` shows only the current window by default; use `--all`. UUIDs need `--id-format both`.
- `cmux close-surface` refuses while a process is running in the surface. Stop the reporter first.
- macOS has no `timeout`; `perl -e 'alarm N; exec @ARGV' cmd` works instead.
- In zsh, `echo ===` fails (`== not found`) because `=word` is a command-path expansion.
- mlx-audio's Kokoro needs `misaki[en]` plus the spaCy `en_core_web_sm` model installed up front, or synthesis fails outside a venv.

## Skills for coding agents

`skills/` holds agent skills (SKILL.md format) learned while building this:

- `installing-tts-voices`: add macOS, Kokoro or other open-source mlx-audio voices, sample them, and wire them in.
- `cmux-voice-reporter-ops`: start, restart and debug the reporter, including why a headline never plays.

Copy them into `~/.claude/skills/` (Claude Code) or `~/.agents/skills/`.

## Options considered

| Voice | Cost | Notes |
|---|---|---|
| macOS `say` | free | Instant and offline. Robotic unless you download a premium voice. |
| Kokoro-82M (local) | free | Near cloud quality, 54 voices, about 0.8 s warm |
| ElevenLabs Flash | paid | Best quality. Needs an API key and per-character billing. |

For the headline, using the first sentence of the last message costs nothing and adds no delay. A small LLM summarizer (such as Claude Haiku) could rewrite long headlines, at extra cost and about 1–2 s.

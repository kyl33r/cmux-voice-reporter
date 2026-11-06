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

- **Local, free voice.** Kokoro-82M on an Apple Silicon Mac (this one or one you reach over ssh), with macOS `say` as the fallback. No API keys, no cloud calls, no AI summarizing.
- **One line at a time.** The three speakers share a lock, so lines never overlap.
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
# Kokoro server, on this Mac or another one you can ssh to:
kokoro-server/install.sh            # or --launchd to keep it running
```

On the Mac that speaks, download the `say` fallback voice once: System Settings → Accessibility → Spoken Content → System Voice → Manage Voices → Chinese (China mainland) → Tingting. Or set `FALLBACK_VOICE` to a voice you already have (`say -v '?'` lists them).

Run the reporter in its own cmux pane:

```bash
cmux new-split right --command ~/.local/bin/cmux-voice-reporter --focus false
```

## Voice models: where they come from

| What | Where it comes from | Size | When it downloads |
|---|---|---|---|
| Kokoro-82M weights (`kokoro-v1_0.safetensors`) | Hugging Face, [`mlx-community/Kokoro-82M-bf16`](https://huggingface.co/mlx-community/Kokoro-82M-bf16) | 312 MB | `install.sh` speaks one test line, which fetches it into `~/.cache/huggingface/hub/` on the server Mac |
| The 54 Kokoro voices (`voices/*.safetensors`, `af_nicole` and the rest) | the same Hugging Face repo | 27 MB (about 0.5 MB each) | together with the weights; switching voices downloads nothing |
| mlx-audio and its Python dependencies | PyPI, through `uv tool install` in `install.sh` | about 1.2 GB in `~/.local/share/uv/tools/mlx-audio` | `install.sh` |
| spaCy `en_core_web_sm` (English text processing) | GitHub release wheel, pinned in `install.sh` | about 15 MB | `install.sh` |
| macOS `say` voices, such as the Tingting fallback | Apple, through System Settings → Accessibility → Spoken Content → Manage Voices | varies | when you pick one; there's no command-line install |
| Other mlx-audio models | Hugging Face, by repo id | varies | on first `mlx_audio.tts.generate --model <repo>`; see `skills/installing-tts-voices` |

Only the first download needs the internet. After that everything runs offline.

**Memory.** Measured on a 32 GB M-series Mac running the server for a day: the server's memory footprint is about 750 MB once the model is loaded (167 MB resident; the rest is unified GPU memory). A headline takes about 0.8 s. Its recorded peak that day was about 9.6 GB; the cause is not confirmed (possibly larger models tried from the voice skill). A restart returns it to the steady size. The clients (`cmux-voice-reporter` and the rest) are small bash scripts plus `afplay`.

## Options (environment)

| Variable | Default | Meaning |
|---|---|---|
| `VOICE` | `af_nicole` | Kokoro voice (`af_heart`, `af_bella`, `bf_emma`, `bm_george`, …, or a blend `"af_heart,jf_alpha"`), or any macOS `say` voice name |
| `FALLBACK_VOICE` | `Tingting` | `say` voice used when Kokoro is unreachable |
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

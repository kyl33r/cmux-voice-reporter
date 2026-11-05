# cmux-voice-reporter

Speaks a short headline aloud when a Claude Code session in a [cmux](https://cmux.dev) pane finishes a turn:

> "agent paging finished: Rebased and pushed 2330, all checks green."

One speaker for all panes. Child sessions never speak. A single process reads cmux's notification stream and speaks one line at a time.

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

Run the reporter in its own cmux pane:

```bash
cmux new-split right --command ~/.local/bin/cmux-voice-reporter --focus false
```

## Options (environment)

| Variable | Default | Meaning |
|---|---|---|
| `VOICE` | `af_nicole` | Kokoro voice (`af_heart`, `af_bella`, `bf_emma`, `bm_george`, …, or a blend `"af_heart,jf_alpha"`), or any macOS `say` voice name |
| `FALLBACK_VOICE` | `Tingting` | `say` voice used when Kokoro is unreachable |
| `KOKORO_HOST` | unset | ssh host running the server; unset means the server is on this machine |
| `VOICE_SKIP_SURFACE` | unset | cmux surface UUID to stay silent for, such as an orchestrator pane |
| `VOICE_ONLY_SURFACE` | unset | speak only for this surface (testing) |

- Mute: `touch ~/.cache/cmux-voice/mute`; delete the file to unmute.
- Log of spoken lines with timing: `~/.cache/cmux-voice/spoken.log`.
- `--once` exits after the first spoken line.

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

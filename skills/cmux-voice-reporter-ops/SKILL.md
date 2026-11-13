---
name: cmux-voice-reporter-ops
description: Use when running, restarting, debugging or changing cmux-voice-reporter, when a spoken pane-finish headline never plays, when hooking anything to Claude Code turn ends inside cmux, or when parsing cmux events, list-notifications or tree output.
---

# Operating cmux-voice-reporter

## Overview
One process per machine reads `cmux events --name notification.created` and speaks one line per finished top-level Claude turn. Only the orchestrator owns this process; child sessions never speak.

## Start, restart, stop
```bash
# start in its own pane (never as a Claude Code background task).
# <ws>/<surface>: from `cmux identify` (caller.workspace_ref / caller.surface_ref)
cmux new-split right --workspace <ws> --surface <surface> \
  --command ~/.local/bin/cmux-voice-reporter --focus false
cmux tab-action --surface <new-surface> --action rename --title "voice reporter"

# restart = stop the process first; close-surface refuses while it runs
pkill -f cmux-voice-reporter; pkill -f -- '--cursor-file .*cmux-voice/seq'
cmux close-surface --surface <old-surface>
```
- Mute: `touch ~/.cache/cmux-voice/mute`.
- Proof that something was spoken: `~/.cache/cmux-voice/spoken.log`, which records turn end and speech start for each line.
- To test against one pane only, run with `VOICE_ONLY_SURFACE=<uuid> … --once`.

## Volume

When the user asks for the voice louder, quieter or at a level, run `cmux-voice-volume` (in `~/.local/bin`): no argument prints the level, `N` sets 0–200 (default 100), `+N` / `-N` steps and stops at 0 and 200. Over 100 is a digital boost that can make the voice crackle; only go above 100 when the user asks, and suggest stepping back down if they hear distortion. It exits 2 on anything else. It changes only the spoken lines and applies from the next line, with no restart. Do not change the Mac's system volume for this.

## Diagnosing "nothing was spoken"
First check that the reporter is running (`pgrep -fl cmux-voice-reporter`) and read the end of `spoken.log`. Then read the event journal for the pane. Get `<seq>` from `cmux events --snapshot` (`resume.latest_seq` minus about 2000), and the pane UUID from `cmux --id-format both tree --all --json`. The stream retains a few thousand events, so filter by name or a short replay times out:
```bash
cmux events --after <seq> --name agent.hook.Stop --name agent.notification.decision \
  --name notification.created --limit 300 --timeout 4 --no-heartbeat --no-ack |
  jq -c 'select(.surface_id=="<uuid>") | {seq,name,t:.occurred_at,k:.payload.kind,r:.payload.reason}'
```
| What you see | Cause |
|---|---|
| No `agent.hook.Stop` after a turn | The session has a running Claude-tracked background task, which stops the Stop hook from firing. Run the reporter (or any long watcher) in a cmux pane, under launchd, or with `nohup … & disown`. The reporter itself needs no restart: once the task is gone, the next turn end fires. |
| `decision` with `reason: deduplicated` | An idle repeat, correctly dropped. |
| `notification.created` but no log line | The surface matches `VOICE_SKIP_SURFACE`, the mute file exists, or the notification row lookup failed. |

## Parsing facts
- Events redact title and body. Text comes from `cmux list-notifications`: `idx:nid|workspace|surface|state|title|subtitle|BODY|ts|pct:<workspace title>`. There's no JSON form, and BODY can contain `|`, so strip the 6 leading fields and the last 2 instead of using `cut`.
- `cmux tree` shows only the current window. Use `cmux --id-format both tree --all --json` to map a surface UUID to its title.

## Shell traps on macOS
- There's no `timeout`. Use `perl -e 'alarm 900; exec @ARGV' cmd`.
- In zsh, `echo ===` fails with `== not found` and stops the rest of a `;` chain. Use `---` as a separator.
- `/bin/bash` is 3.2, where `$!` isn't reliable after `< <(…)`. Kill the stream with `pkill -f` instead.

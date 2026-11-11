#!/bin/bash
# Runs cmux-voice-say against a stand-in `say` that records what it would speak.
# No audio, no TTS server, no cmux; HOME is a throwaway folder.
set -u
repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home"
printf '#!/bin/bash\nprintf "%%s\\n" "${@: -1}" >>"%s/said"\n' "$tmp" >"$tmp/bin/say"
chmod +x "$tmp/bin/say"
fails=0

speak() {  # $1: text; prints what was said, one line per chunk
  rm -f "$tmp/said"
  HOME="$tmp/home" PATH="$tmp/bin:$PATH" VOICE=Samantha FALLBACK_VOICE=Samantha \
    PAUSE_MEDIA=0 VOICE_LOCK_WAIT=5 "$repo/bin/cmux-voice-say" "$1"
  cat "$tmp/said" 2>/dev/null
}
check() {  # $1: name, $2: expected, $3: actual
  if [[ "$2" == "$3" ]]; then echo "ok   $1"
  else echo "FAIL $1"; printf '  expected: %s\n  actual:   %s\n' "$2" "$3"; fails=$((fails + 1)); fi
}

check "plain line is spoken as is" "The build finished." "$(speak "The build finished.")"

phrases=$tmp/home/.config/cmux-voice; mkdir -p "$phrases"
printf '# comment\n\n  Heads up.  \n' >"$phrases/prefix.txt"
printf 'Over.\n' >"$phrases/suffix.txt"
check "prefix and suffix come from the phrase files" \
  "Heads up. The build finished. Over." "$(speak "The build finished.")"

printf -- '-\n' >"$phrases/prefix.txt"; rm "$phrases/suffix.txt"
check "a '-' line and a missing file add nothing" "The build finished." "$(speak "The build finished.")"
rm "$phrases/prefix.txt"

long="The first part of this report is long enough to stand on its own as a sentence. The second part is also long enough that it should be spoken separately from the first."
check "a long line is spoken a sentence at a time" 2 "$(speak "$long" | wc -l | tr -d ' ')"

check "spoken.log records each line without phrases" 3 \
  "$(grep -c $'\tThe build finished.$' "$tmp/home/.cache/cmux-voice/spoken.log")"

touch "$tmp/home/.cache/cmux-voice/master-mute"
check "master-mute silences cmux-voice-say" "" "$(speak "Muted line.")"

exit $((fails > 0))

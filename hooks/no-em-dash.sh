#!/bin/bash
# Prose-quality hook: blocks AI-signal writing in papers and documents.
#
# Modes:
#   post         PostToolUse on Write|Edit. Checks prose files.
#   bash         PostToolUse on Bash. Checks Word-type files (docx, doc, rtf, odt)
#                that the command created or changed in the last 3 minutes.
#   check FILE   Run the checks on one file by hand. Prints problems. Exit 1 if any.
#   stop         Checks the last chat reply. NOT wired in settings.json
#                (chat replies follow the STE rule only).
#
# Checks: em dash (U+2014), contractions, banned AI-signal words and phrases.
# Banned words are skipped for files under /.claude/ (rule files list them on purpose).
# Fenced code and inline code are ignored.
# Text files: .md .mdx .txt .rst .tex .adoc. Word-type files: .docx .doc .rtf .odt (need macOS textutil).
mode="$1"
dash="$(printf '\xe2\x80\x94')"

strip_code() { printf '%s' "$1" | perl -0pe 's/```.*?```//gs; s/`[^`\n]*`//g'; }

has_contraction() {
  strip_code "$1" \
    | grep -Eiq "[a-z]n('|’)t\b|[a-z]('|’)(re|ve|ll|m|d)\b|\b(it|that|there|here|what|let|he|she|who|where|how|when|why)('|’)s\b"
}

BANNED='\b(delv(e|es|ed|ing)|tapestry|pivotal|showcas(e|es|ed|ing)|underscor(e|es|ed|ing)|testament|nestled|meticulous(ly)?|intricate|intricacies|multifaceted|garner(s|ed|ing)?|elucidat(e|es|ed|ing)|bolster(s|ed|ing)?|fostering|crucial|moreover|furthermore|additionally|commendable|beacon|cornerstone|paradigm shift|game-changer|holistic|seamless(ly)?|invaluable|unparalleled|groundbreaking|ever-evolving|ever-changing)\b|in the realm of|stands as a|plays a (pivotal|crucial|vital|key|significant) role|in today.{1,3}s (fast-paced|digital|modern|world)|it is (important|worth) (to )?not(e|ing)|in conclusion|in summary|at the end of the day|i hope this helps|let me know if you|great question|as an ai (language )?model|knowledge cutoff|\bnot (just|only|merely)\b[^.!?]{0,100}\bbut\b'

banned_hits() {
  strip_code "$1" | grep -Eioh "$BANNED" | tr '[:upper:]' '[:lower:]' | sort -u | head -8 | paste -sd ',' - | sed 's/,/, /g'
}

# run_checks TEXT FILE : prints one problem per line. Returns 1 if any.
run_checks() {
  local text="$1" file="$2" bad=0 hits
  case "$text" in
    *"$dash"*)
      echo "Em dash found. Rewrite without the em dash. Use a period, comma, colon or parentheses."; bad=1 ;;
  esac
  if has_contraction "$text"; then
    echo "Contraction found. Rewrite without contractions. Write 'do not', 'it is', 'cannot'."; bad=1
  fi
  case "$file" in
    */.claude/*) ;;
    *)
      hits="$(banned_hits "$text")"
      if [ -n "$hits" ]; then
        echo "Banned AI-signal words or phrases found: $hits. State the fact plainly. See ~/.claude/rules/writing-style.md."; bad=1
      fi ;;
  esac
  return $bad
}

# gather_office_files CMD CWD : candidate Word-type files from the command text and recent files in CWD.
gather_office_files() {
  local cmd="$1" cwd="$2" t
  printf '%s' "$cmd" | grep -Eio "[^[:space:]\"'\`;|&<>=()]+\.(docx|doc|rtf|odt)" | while read -r t; do
    if [ "${t#\~}" != "$t" ]; then t="$HOME${t#\~}"
    elif [ "${t#/}" = "$t" ]; then t="$cwd/$t"; fi
    printf '%s\n' "$t"
  done
  if [ -n "$cwd" ]; then
    find "$cwd" -maxdepth 3 -type f \( -iname '*.docx' -o -iname '*.doc' -o -iname '*.rtf' -o -iname '*.odt' \) -mmin -3 2>/dev/null
  fi
}

extract_text() {
  case "$1" in
    *.docx|*.doc|*.rtf|*.odt) textutil -convert txt -stdout "$1" 2>/dev/null ;;
    *) cat "$1" 2>/dev/null ;;
  esac
}

case "$mode" in
  post)
    input="$(cat)"
    text="$(printf '%s' "$input" | jq -r '.tool_input.content // .tool_input.new_string // empty' 2>/dev/null)"
    file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
    case "$file" in
      *.md|*.mdx|*.txt|*.rst|*.tex|*.adoc)
        out="$(run_checks "$text" "$file")" || { printf 'In %s: %s\n' "$file" "$out" >&2; exit 2; }
        ;;
    esac
    exit 0
    ;;

  bash)
    input="$(cat)"
    cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
    cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
    printf '%s' "$cmd" | grep -Eiq '\.(docx|doc|rtf|odt)\b' || exit 0
    command -v textutil >/dev/null || exit 0
    files="$(gather_office_files "$cmd" "$cwd")"
    msgs=""
    while IFS= read -r f; do
      [ -f "$f" ] || continue
      case "$(basename "$f")" in '~$'*) continue ;; esac
      find "$f" -mmin -3 2>/dev/null | grep -q . || continue
      out="$(run_checks "$(extract_text "$f")" "$f")" || msgs="${msgs}In ${f}: ${out}"$'\n'
    done <<< "$files"
    if [ -n "$msgs" ]; then
      printf '%s' "$msgs" >&2
      echo "Fix the document text and save the file again." >&2
      exit 2
    fi
    exit 0
    ;;

  check)
    f="$2"
    [ -f "$f" ] || { echo "No such file: $f" >&2; exit 2; }
    out="$(run_checks "$(extract_text "$f")" "$f")" && { echo "PASS: $f"; exit 0; }
    printf '%s\n' "$out"; exit 1
    ;;

  stop)
    input="$(cat)"
    [ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false')" = "true" ] && exit 0
    text="$(printf '%s' "$input" | jq -r '.last_assistant_message // empty' 2>/dev/null)"
    out="$(run_checks "$text" "")" || jq -n --arg r "$out" '{decision:"block", reason:$r}'
    exit 0
    ;;
esac
exit 0

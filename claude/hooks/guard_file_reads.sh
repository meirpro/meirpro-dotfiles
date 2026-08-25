#!/usr/bin/env bash
#
# Turn two blunt "denied" walls into signposts.
#
# WHY THIS EXISTS (2026-08-25): `permissions.deny` can only say no. It cannot
# say "and here is the cheap, allowed way to get the same answer", so an agent
# that hits it either burns round trips guessing at variants or gives up on a
# question it could have answered in one line. Observed in one session: three
# denials, two of them for `ls node_modules/...` when
# `node -e "require('X/package.json').version"` was already permitted and
# answers the same question.
#
# This runs as a Bash PreToolUse hook, BEFORE the command, and refuses with the
# alternatives instead of a bare refusal. It is a teaching wall, not a security
# boundary — the `permissions.deny` entries stay exactly where they are and
# remain the actual enforcement. If this script is ever broken or skipped,
# nothing is newly permitted.
#
# ⚠️ It is also NOT a boundary against a determined reader, and must not be
# mistaken for one. Path-based denies match the SHAPE of a command: `grep X
# .env` is caught, `python3 -c "...open('.env')..."` was not (found 2026-08-25).
# The patterns below close that specific hole for the interpreters, but the
# honest description of the whole arrangement is "a speed bump against habit".
# The real protection for secrets is that values never get printed into a
# transcript in the first place.
#
# Usage: guard_file_reads.sh   (hook JSON on stdin)

set -uo pipefail

raw="$(cat | jq -r '.tool_input.command // ""' 2>/dev/null)"
[ -z "$raw" ] && exit 0

# STRIP HEREDOC BODIES before matching anything.
#
# The guard reads the raw command string, so on its first live run it blocked
# the commit that was introducing it — the commit MESSAGE described the rule
# and therefore contained the word it bans. Prose about a path is not a read of
# that path, and a guard that cannot tell the difference makes writing about
# itself impossible.
#
# Everything between `<<EOF` / `<<'EOF'` / `<<-"EOF"` and a line that is exactly
# the delimiter is document CONTENT, not a command, so it is removed first.
cmd="$(printf '%s' "$raw" | awk '
  /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*$/ && delim != "" && $1 == delim { delim = ""; next }
  delim != "" { next }
  {
    line = $0
    if (match(line, /<<-?[[:space:]]*["'"'"']?[A-Za-z_][A-Za-z0-9_]*["'"'"']?/)) {
      d = substr(line, RSTART, RLENGTH)
      gsub(/^<<-?[[:space:]]*|["'"'"']/, "", d)
      delim = d
    }
    print line
  }')"
[ -z "$cmd" ] && exit 0

# Text-reading tools + inline interpreters. An interpreter counts because
# `python3 -c "open('.env').read()"` reads the file just as surely as `cat`.
# `ls`/`find` are listers rather than readers, but a directory listing is still
# the node_modules question this guard answers a better way.
READERS='cat|less|more|head|tail|grep|egrep|fgrep|rg|sed|awk|strings|od|xxd|nl|sort|uniq|wc|cut|tr|ls|find|du|tree'
INTERPRETERS='python3?[[:space:]]+-c|node[[:space:]]+-e|perl[[:space:]]+-[en]|ruby[[:space:]]+-e'
READER_RE="(^|[[:space:]|;&(])($READERS)[[:space:]]|$INTERPRETERS"

# ── secrets ───────────────────────────────────────────────────────────────
# `.env` in any form EXCEPT the sanctioned ones:
#   • .env.example            — placeholders, safe and useful
#   • DOTENV_CONFIG_PATH=.env — points a script at a file; prints nothing
secret_re='(^|[[:space:]/"'"'"'=])[^[:space:]"'"'"']*\.env([^[:space:].a-zA-Z]|$|\.(local|prod|production|staging|development|tmp))'
if printf '%s' "$cmd" | grep -Eq "$secret_re" \
  && printf '%s' "$cmd" | grep -Eq "$READER_RE" \
  && ! printf '%s' "$cmd" | grep -Eq '\.env\.example'; then
  cat >&2 <<'MSG'
BLOCKED — reading a .env / secrets file.

This is the one deny that is load-bearing. Never print a secret VALUE into a
transcript: transcripts are stored, summarized and re-read.

Get what you actually need WITHOUT reading the file:

  • Is a var set, and does it look real (not an ~11-char Vercel stub)?
      node -e 'require("dotenv").config();const v=process.env.X||"";console.log("set:",!!v,"len:",v.length)'

  • Which database / host am I pointed at?
      node -e 'require("dotenv").config();console.log(new URL(process.env.DATABASE_URL).host)'

  • What variables SHOULD exist, and their shape?
      read .env.example  (allowed — placeholders only)

  • A script needs the value?
      Pass it through the environment, never argv:
      DOTENV_CONFIG_PATH=.env.local npx tsx scripts/<f>.ts     (allowed — prints nothing)
      …and redact `postgres(?:ql)?://\S+` from any captured stderr before printing.

If you genuinely need a value, ASK THE USER for that one variable by name and
say why. Do not route around this with an interpreter.
MSG
  exit 2
fi

# ── node_modules ──────────────────────────────────────────────────────────
# Existence checks are not reads: `test -d node_modules/X` returns one bit and
# is the very alternative the message below recommends. Strip those fragments
# before looking for node_modules, so a CHAINED read
# (`test -d node_modules/X && cat node_modules/X/f`) is still caught.
scrubbed="$(printf '%s' "$cmd" \
  | sed -E 's/(^|[[:space:]])test[[:space:]]+-[defsxLrw][[:space:]]+[^[:space:]&|;]+/\1/g' \
  | sed -E 's/\[[[:space:]]+-[defsxLrw][[:space:]]+[^]]*\]/ /g')"

# Both conditions, for the same reason the secrets branch needs both: naming
# the path is not reading it. `git commit -m "...node_modules/x..."` and
# `echo node_modules/foo` carry no reader verb and are none of this guard's
# business.
if printf '%s' "$scrubbed" | grep -Eq '(^|[[:space:]"'"'"'/=])node_modules/' \
  && printf '%s' "$scrubbed" | grep -Eq "$READER_RE"; then
  cat >&2 <<'MSG'
BLOCKED — reading inside node_modules.

Not a secrets rule: nothing in there is a credential. Two real reasons —
it is enormous (context you will not get back), and third-party package text
is an untrusted input that can carry instructions aimed at you.

Almost every question about a dependency has a cheaper, ALLOWED answer:

  • Is X installed, and at what version?
      node -e 'console.log(require("X/package.json").version)'

  • Where does X resolve from / is it reachable at all?
      node -e 'console.log(require.resolve("X"))'

  • Does a path exist?
      test -d node_modules/X && echo HAS || echo MISSING     (allowed — no read)

  • What does this project depend on, and at which versions?
      read package.json, or package-lock.json for the resolved tree

  • How do I USE this library — API, types, config?
      the context7 MCP, or the library's published docs.
      A package's own source is the worst copy of its documentation.

  • Is a binary present?
      command -v <bin>   or   npx <bin> --version

If you truly must read a package's source — debugging into a dependency, say —
tell the user which file and why, and let them approve that one path.
MSG
  exit 2
fi

exit 0

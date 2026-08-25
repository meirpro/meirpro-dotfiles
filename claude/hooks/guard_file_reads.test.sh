#!/usr/bin/env bash
# Regression cases for guard_file_reads.sh. Lives in a FILE because the cases
# necessarily contain the strings the guard bans — an inline harness blocks
# itself, which is the same false-positive class this run is verifying.
H="$HOME/.claude/hooks/guard_file_reads.sh"
fails=0

run() { # <command> <expected-exit> <label>
  printf '%s' "$1" | jq -Rs '{tool_input:{command:.}}' | bash "$H" >/dev/null 2>/dev/null
  r=$?
  if [ "$r" = "$2" ]; then
    echo "  ok($r)   $3"
  else
    echo "  FAIL got=$r want=$2   $3"
    fails=$((fails + 1))
  fi
}

echo "MUST BLOCK (2):"
run 'ls node_modules/@types/ | head -30'                      2 'ls a package dir'
run 'cat node_modules/jsdom/README.md'                        2 'cat package source'
run 'tail -n 5 node_modules/foo/CHANGELOG.md'                 2 'tail package file'
run 'test -d node_modules/x && cat node_modules/x/index.js'   2 'chained: check then read'
run 'grep -c "X" .env'                                        2 'grep .env'
run 'python3 -c "print(open(\".env\").read())"'               2 'interpreter reads .env'
run 'cat .env.local'                                          2 'cat .env.local'
run 'head -5 .env.prod.tmp'                                   2 'head a pulled prod env'

echo "MUST ALLOW (0) — naming a path is not reading it:"
run 'git commit -m "fix: stop scanning node_modules/foo"'     0 'commit message names the path'
run 'echo "see node_modules/x for details"'                   0 'echo names the path'
run 'git commit -F /tmp/msg.txt'                              0 'commit from a message file'

echo "MUST ALLOW (0) — the recommended alternatives:"
run 'test -d node_modules/@types/jsdom && echo HAS'           0 'existence check'
run '[ -d node_modules/foo ] && echo yes'                     0 'bracket existence check'
run 'node -e "console.log(require(\"j/package.json\").version)"' 0 'version probe'
run 'cat .env.example'                                        0 '.env.example'
run 'DOTENV_CONFIG_PATH=.env.local npx tsx scripts/f.ts'      0 'dotenv pass-through'

echo "MUST ALLOW (0) — ordinary work must stay silent:"
run 'npm run verify'                                          0 'npm run verify'
run 'git status --short'                                      0 'git status'
run 'grep -rn "environment" src/'                             0 'grep the source tree'
run 'cat package.json'                                        0 'cat package.json'
run 'sed -n 1,40p src/lib/db.ts'                              0 'sed a source file'
run 'gh pr view 1842 --json state'                            0 'gh'

echo
[ "$fails" = 0 ] && echo "ALL PASS" || echo "$fails FAILED"
exit "$fails"

# cc.meir.pro Track-Key Rotation

This doc covers everything for rotating the `X-Track-Key` shared secret
that hooks use to authenticate against `cc.meir.pro`. The rotation is
fully automated by `~/.claude/bin/rotate-track-key`; this file
explains *when* you'd run it, *what* it does, and *how to recover*
if any step fails.

## TL;DR

```bash
~/.claude/bin/rotate-track-key
```

Generates a fresh 64-char hex key, writes it to macOS Keychain, pushes
it to Cloudflare Workers as the `TRACK_KEY` secret on `command-center`,
verifies CF edge propagation by polling `/api/projects` until 2xx,
then deletes the legacy `~/.claude/track-key` file.

The key is never printed, never written to a file, never appears in
shell history. The full operation typically completes in 5–15 seconds
(most of that is CF edge propagation).

## When to rotate

- **After a leak.** Any time the key has been visible in a transcript,
  log file, screenshot, pasted snippet, etc. Rotate immediately and
  the leaked value becomes inert.
- **After a person change.** When someone with shell access on this
  Mac no longer needs CC access.
- **Periodically.** No hard requirement; quarterly is reasonable for
  a single-user dev install. Less frequent is fine if the threat
  surface hasn't changed.
- **On suspicion of compromise.** Unexplained CC writes, weird
  `wrapup_segments` rows, or any other "did I do that?" moment.

## What gets stored where

After a successful rotation, the key lives in exactly two places:

| Location | Read by | Write via |
|---|---|---|
| macOS Keychain — service `claude-track-key`, account `$USER` | `cc_client.py` (Python) and `cc-call` (bash) | `security add-generic-password -a $USER -s claude-track-key -A -U -w "$KEY"` |
| Cloudflare Workers secret `TRACK_KEY` on `command-center` | `requireTrackKey()` in `command-center/src/middleware/auth.ts` | `wrangler secret put TRACK_KEY` (stdin) |

The legacy plaintext file `~/.claude/track-key` is deleted by
`rotate-track-key`. If you find one again, it means either:
- a manual restoration happened (don't — use Keychain), or
- a fresh dotfiles install hasn't finished setup yet.

The `cc_client._load_key()` function still has a file fallback for
that second case so the rotation tool can run on a fresh install.

## How `rotate-track-key` works (5 steps)

1. **Preflight.** Confirms `command-center` repo exists, `wrangler.toml`
   is present, and `wrangler whoami` succeeds. Bails with exit 4 if
   anything's off.
2. **Generate.** `secrets.token_hex(32)` → 256 bits / 64 hex chars.
3. **Keychain write.** `security add-generic-password -A -U -w "$KEY"`.
   `-A` grants read access to all apps on this user account (no
   per-binary prompt for unattended hooks). `-U` updates the existing
   entry instead of erroring on conflict.
4. **Wrangler push.** `wrangler secret put TRACK_KEY` with the key on
   stdin (never argv). Cloudflare propagates to all edges typically
   within 5–60 seconds.
5. **Verify + cleanup.** Polls `GET /api/projects` through `cc-call`
   (which now reads from Keychain) every 2s until a 2xx confirms
   propagation. Then deletes `~/.claude/track-key`.

## Verifying after rotation

```bash
# Confirm Keychain entry exists (metadata only — never use -g).
security find-generic-password -s claude-track-key | grep '"svce"'
# → "svce"<blob>="claude-track-key"

# Confirm legacy file is gone.
ls ~/.claude/track-key 2>/dev/null && echo "STILL THERE — investigate" \
                                   || echo "OK — absent"

# End-to-end auth check.
~/.claude/bin/cc-call --timeout 5 GET /api/projects | head -c 100
# → {"projects":[...
```

## Troubleshooting

### Wrangler push failed (exit 1)

The Keychain has the new key, but the server still has the old one.
Every consumer using `cc_client` (which prefers Keychain) is sending
the new key against an old-key server → 401s.

Fix: re-run `rotate-track-key`. The `-U` flag means a second Keychain
write replaces the entry from step 1; the script will then retry the
Wrangler push. If the Wrangler push keeps failing, debug it standalone:

```bash
cd ~/Documents/GitHub/command-center
wrangler whoami     # must succeed
wrangler secret list  # must show TRACK_KEY
```

### Propagation didn't verify within 60s (exit 2)

The Keychain has the new key, Wrangler accepted the secret, but
`cc-call GET /api/projects` is still failing. Could be:
- CF propagation genuinely slow (rare; bumps to 2–5 minutes are
  possible during edge incidents).
- Browser/DNS cache holding stale resolver state.
- A different `TRACK_KEY` on a different worker handling the request.

Wait a minute and re-run the verify step:

```bash
~/.claude/bin/cc-call --timeout 10 GET /api/projects
```

If it succeeds, manually delete the legacy file:

```bash
rm -f ~/.claude/track-key
```

### Keychain write failed (exit 3)

Usually means the login keychain is locked or `security` couldn't be
called. Unlock with `security unlock-keychain ~/Library/Keychains/login.keychain-db`
and retry.

### `cc-call` returns exit 3 ("no track key")

`cc_client._load_key()` tried Keychain and the legacy file, both empty.
Either rotation hasn't happened yet on this machine, or the Keychain
entry was deleted. Re-run `rotate-track-key`.

## Manual rotation (if `rotate-track-key` isn't available)

You shouldn't need this — but for full transparency, here's the
equivalent five-line sequence:

```bash
NEW_KEY=$(python3 -c 'import secrets; print(secrets.token_hex(32))')
security add-generic-password -a "$USER" -s claude-track-key -A -U -w "$NEW_KEY"
( cd ~/Documents/GitHub/command-center && echo -n "$NEW_KEY" | wrangler secret put TRACK_KEY )
~/.claude/bin/cc-call --timeout 10 GET /api/projects   # confirm 2xx
unset NEW_KEY
rm -f ~/.claude/track-key
```

The `unset NEW_KEY` matters — leaving the value in a shell variable
means it's visible to any subprocess spawned in that shell. The
`rotate-track-key` script never exposes the value to a parent shell
in the first place.

## Don't leak the new key

The way the previous key got leaked (and forced this whole rotation):
a debug `curl -v` against `cc.meir.pro` echoed the `X-Track-Key`
request header into the stdout of the calling agent. The header
ended up in the conversation transcript.

Rules to avoid a repeat:

1. **Never** use `curl -v`, `curl --trace`, or `wireshark` against
   `cc.meir.pro` — they print full request headers including
   `X-Track-Key`. If you need to debug, log the response body
   (`curl -i` is fine; `-v` is not).
2. **Never** use `security find-generic-password -g` (the `-g` flag
   prints the password to stderr). For verification, the metadata
   from the no-flag form is enough.
3. **Always** route HTTP traffic through `cc_client.request()` (Python)
   or `~/.claude/bin/cc-call` (bash). They never write the key to
   stdout, stderr, or argv of any subprocess.
4. If you find yourself wanting the raw key value for any reason,
   stop and ask: "could I do this through `cc-call` instead?"
   The answer is almost always yes.

## Related files

- `claude/bin/rotate-track-key` — the rotation tool
- `claude/hooks/cc_client.py` — Python module that loads + uses the key
- `claude/bin/cc-call` — bash wrapper around `cc_client.request()`
- `command-center/src/middleware/auth.ts` — server-side validation
- `claude/hooks/KNOWN_ISSUES.md` — broader CC-tracking issue history

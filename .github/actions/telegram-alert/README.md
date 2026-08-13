# telegram-alert

One CI alarm for every project. Posts to a Telegram channel, never fails the build.

```yaml
- uses: meirpro/meirpro-dotfiles/.github/actions/telegram-alert@main
  with:
    title: "main is RED"
    body: |
      Test (shard 2/2) failed
      ${{ github.event.head_commit.message }}
  env:
    TELEGRAM_BOT_TOKEN: ${{ secrets.TELEGRAM_BOT_TOKEN }}
```

## The channel

Precedence, first non-empty wins:

1. the `chat_id` input — a project that wants its own channel,
2. the `TELEGRAM_CHAT_ID` secret in the calling repo,
3. `DEFAULT_CHAT_ID` in `send.py` — the shared error channel.

The default lives in this public repo on purpose: GitHub has no account-level
Actions variables for personal repos, so a constant here is the only thing that
is genuinely *global*. A chat id is an identifier, not a credential — posting
needs the bot **token**, which lives in each repo's secrets and never here.

## When it can't deliver

It does **not** fail the job. It writes a `::error::` annotation *and* a badge
at the top of the run's Summary page:

> ### 🔕 CI alert NOT delivered to Telegram
> **Telegram HTTP 400 — check the chat id, and that the bot is an ADMIN of that channel**

An alarm that can break CI is an alarm someone disables, and then nobody is told
anything. A silent alarm is the same failure with none of the noise, so the
undelivered case gets a badge where a human will actually meet it.

## Setup per repo

```bash
gh secret set TELEGRAM_BOT_TOKEN --repo <owner>/<repo>   # paste the BotFather token
```

That is all, unless the project wants a different channel (then also
`TELEGRAM_CHAT_ID`, or pass `chat_id:`).

## Notes

- Every value is HTML-escaped. Bodies carry commit messages and branch names —
  attacker-controlled by anyone who can push. The shell-interpolated version of
  this idea was a remote-code-execution hole in `sweetcrm` (2026-08-13):
  `sed -e "s|{{X}}|$COMMIT_MSG|"`, where GNU sed's `e` command runs a shell.
  Values reach `send.py` through the environment, never argv.
- Messages over Telegram's 4096-character limit are truncated, not dropped.
- `dry_run: true` prints the message and sends nothing — use it to test wiring
  before the secrets exist.

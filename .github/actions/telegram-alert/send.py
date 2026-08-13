#!/usr/bin/env python3
"""Post a CI alert to Telegram. Never fails the caller.

Two rules this file exists to keep in one place:

1. EVERY value is HTML-escaped. Alert bodies carry commit messages and branch
   names — attacker-controlled by anyone who can push. Telegram's HTML parse
   mode would otherwise reject the message (or render injected markup), and the
   shell-interpolated version of this idea was a remote-code-execution hole in
   sweetcrm on 2026-08-13 (`sed -e "s|{{X}}|$COMMIT_MSG|"` — GNU sed's `e`
   command runs a shell). Values arrive via the ENVIRONMENT, never argv.

2. An alarm may never break the build. Anything that goes wrong here — no
   token, network down, Telegram 4xx — is a ::warning::, exit 0. An alarm that
   can fail CI is an alarm someone disables, and then nobody is told anything.
"""

import html
import json
import os
import sys
import urllib.error
import urllib.request

TELEGRAM_MAX = 4096

# The ONE channel every project reports to, unless it says otherwise.
# Precedence: `chat_id` input → TELEGRAM_CHAT_ID secret → this constant.
#
# A chat id is an identifier, not a credential: posting needs the bot TOKEN,
# which lives in each repo's secrets and never here. That is what makes it safe
# to keep the default in a public repo — and what makes "set it once, globally"
# possible at all, since GitHub has no account-level Actions variables for
# personal repos.
DEFAULT_CHAT_ID = ""


def summary(markdown: str) -> None:
    """Write to the run's Summary page — the badge a human actually sees.

    A ::warning:: scrolls away inside a log nobody opens. The summary is the
    first thing on the run page, so a silently-undelivered alert is visible
    without knowing to look for it.
    """
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not path:
        return
    try:
        with open(path, "a", encoding="utf-8") as handle:
            handle.write(markdown + "\n")
    except OSError:
        pass


def warn(message: str) -> None:
    print(f"::warning::telegram-alert: {message}")


def failed_badge(reason: str, detail: str = "") -> int:
    """Announce loudly, block nothing. ALWAYS returns 0 — see the module docstring."""
    print(f"::error::telegram-alert: {reason}")
    summary(
        "### 🔕 CI alert NOT delivered to Telegram\n\n"
        f"**{html.escape(reason)}**\n\n"
        + (f"```\n{detail[:500]}\n```\n\n" if detail else "")
        + "_The build was not failed by this — an alarm that can break CI is an "
        "alarm someone disables. But nobody got told, so treat this as the "
        "alert._\n"
    )
    return 0


def main() -> int:
    token = os.environ.get("TELEGRAM_BOT_TOKEN", "").strip()
    chat_id = (
        os.environ.get("ALERT_CHAT_ID", "").strip()
        or os.environ.get("TELEGRAM_CHAT_ID", "").strip()
        or DEFAULT_CHAT_ID
    )
    dry_run = os.environ.get("ALERT_DRY_RUN", "false").lower() == "true"

    if not dry_run:
        if not token:
            return failed_badge("TELEGRAM_BOT_TOKEN is not set in this repository's secrets")
        if not chat_id:
            return failed_badge("no channel: pass chat_id, set TELEGRAM_CHAT_ID, or fill DEFAULT_CHAT_ID")

    esc = lambda value: html.escape(os.environ.get(value, "") or "")
    emoji = os.environ.get("ALERT_EMOJI", "🟥")
    link = os.environ.get("ALERT_LINK", "").strip() or os.environ.get("ALERT_RUN_URL", "")

    lines = [
        f"{emoji} <b>{esc('ALERT_TITLE')}</b>",
        f"<code>{esc('ALERT_REPO')}</code> · <code>{esc('ALERT_REF')}</code>",
    ]
    body = esc("ALERT_BODY")
    if body:
        lines += ["", body]
    actor = esc("ALERT_ACTOR")
    if actor:
        lines += ["", f"by {actor}"]
    if link:
        # The URL is built from GitHub-controlled parts; escape it anyway.
        lines += [f'<a href="{html.escape(link, quote=True)}">open the run</a>']

    text = "\n".join(lines)
    if len(text) > TELEGRAM_MAX:
        text = text[: TELEGRAM_MAX - 20] + "\n… (truncated)"

    if dry_run:
        print("--- dry run, would send ---")
        print(text)
        return 0

    payload = json.dumps(
        {
            "chat_id": chat_id,
            "text": text,
            "parse_mode": "HTML",
            "disable_web_page_preview": True,
        }
    ).encode()

    request = urllib.request.Request(
        f"https://api.telegram.org/bot{token}/sendMessage",
        data=payload,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            if response.status == 200:
                print(f"alert sent to {chat_id}")
                return 0
            return failed_badge(f"Telegram returned HTTP {response.status}")
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", "replace")
        hint = ""
        if error.code == 400:
            # Nearly always the first-run mistake: wrong chat id, or the bot was
            # never added to the channel as an admin.
            hint = " — check the chat id, and that the bot is an ADMIN of that channel"
        elif error.code == 401:
            hint = " — the bot token is wrong or was revoked"
        return failed_badge(f"Telegram HTTP {error.code}{hint}", detail)
    except Exception as error:  # noqa: BLE001 — an alarm must not raise
        return failed_badge(f"could not reach Telegram: {error}")


if __name__ == "__main__":
    sys.exit(main())

"""cc_client — single source of truth for talking to cc.meir.pro.

The X-Track-Key is loaded from macOS Keychain (service:
"claude-track-key"), with fallback to legacy ~/.claude/track-key
during the rotation window. Once Keychain is populated and the
legacy file is deleted, every consumer goes through this module.

Why this exists:
  - The legacy plaintext file at ~/.claude/track-key was a leak vector
    (any tool that cat'd it surfaced the secret to its caller).
  - Six different scripts used to embed their own urllib/curl POSTs
    with their own headers, retry logic, and error handling. One of
    them forgot to set User-Agent and got silently CF-1010-banned for
    days, filling a 50-entry queue.
  - This module concentrates: secret loading, User-Agent, retries,
    error classification, and output shape. Callers never see the
    secret. Callers never set headers. Callers never spawn curl with
    -v / --trace flags that could echo the secret.
"""
import json
import os
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Optional

CC_BASE = os.environ.get("CC_BASE_URL", "https://cc.meir.pro")
KEYCHAIN_SERVICE = "claude-track-key"
LEGACY_KEY_FILE = os.path.expanduser("~/.claude/track-key")
USER_AGENT = "claude-cc-client/1 (+meirpro-dotfiles)"
DEFAULT_TIMEOUT = 15
DEFAULT_RETRIES = 3
BACKOFF_SCHEDULE = [0.5, 1.5, 4.0]


def _load_key() -> Optional[str]:
    """Return the track key, or None if no source is available.

    Order:
      1. macOS Keychain (security find-generic-password -w -s claude-track-key)
      2. Legacy file ~/.claude/track-key  (rotation-window fallback only)
    """
    try:
        out = subprocess.run(
            ["security", "find-generic-password", "-w", "-s", KEYCHAIN_SERVICE],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if out.returncode == 0:
            key = out.stdout.strip()
            if key:
                return key
    except (FileNotFoundError, subprocess.TimeoutExpired):
        # `security` missing or hung — fall through to file fallback.
        pass

    if os.path.isfile(LEGACY_KEY_FILE):
        try:
            with open(LEGACY_KEY_FILE) as f:
                key = f.read().strip()
            return key or None
        except Exception:
            return None
    return None


def has_key() -> bool:
    """True if a key is reachable. Doesn't perform any network call."""
    return _load_key() is not None


def request(
    method: str,
    path: str,
    *,
    query: Optional[dict] = None,
    body: Optional[Any] = None,
    timeout: int = DEFAULT_TIMEOUT,
    retries: int = DEFAULT_RETRIES,
) -> dict:
    """Send an authenticated request to cc.meir.pro.

    Returns a dict (never raises):
      {
        "status": int | None,        # HTTP status, or None on network failure
        "body":   dict|list|str|None, # parsed JSON if possible, else raw text
        "delivered": bool,            # True on 2xx
        "attempts":  int,             # number of attempts actually made
        "error":     str | None,      # short error tag if not delivered
      }

    Retries: up to `retries` attempts with 0.5s/1.5s/4s backoff for
    transient failures (5xx, network errors, 408, 429). Non-retryable
    4xx errors (e.g. 401, 403, 404) bail immediately.

    The track key is never returned to the caller, never logged, never
    placed in argv or visible env. If you need to debug, log the
    response body — never the headers.
    """
    key = _load_key()
    if not key:
        return {
            "status": None,
            "body": None,
            "delivered": False,
            "attempts": 0,
            "error": "no_track_key",
        }

    url = CC_BASE.rstrip("/") + path
    if query:
        url = url + "?" + urllib.parse.urlencode(query)

    headers = {"User-Agent": USER_AGENT, "X-Track-Key": key}

    data: Optional[bytes] = None
    if body is not None:
        if isinstance(body, (dict, list)):
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
        elif isinstance(body, bytes):
            data = body
        else:
            data = str(body).encode()
            headers["Content-Type"] = "application/json"

    last_err: Optional[str] = None
    last_status: Optional[int] = None
    attempts_made = 0

    for attempt_idx in range(max(1, retries)):
        attempts_made = attempt_idx + 1
        try:
            req = urllib.request.Request(url, data=data, headers=headers, method=method)
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                last_status = resp.status
                raw = resp.read().decode()
                try:
                    parsed: Any = json.loads(raw) if raw else None
                except Exception:
                    parsed = raw
                if 200 <= resp.status < 300:
                    return {
                        "status": resp.status,
                        "body": parsed,
                        "delivered": True,
                        "attempts": attempts_made,
                        "error": None,
                    }
                last_err = f"HTTP {resp.status}"
        except urllib.error.HTTPError as e:
            last_status = e.code
            last_err = f"HTTP {e.code}"
            # Non-retryable client errors — bail immediately.
            if 400 <= e.code < 500 and e.code not in (408, 429):
                return {
                    "status": e.code,
                    "body": None,
                    "delivered": False,
                    "attempts": attempts_made,
                    "error": last_err,
                }
        except Exception as e:
            last_err = f"{type(e).__name__}: {e}"

        if attempt_idx < retries - 1:
            time.sleep(BACKOFF_SCHEDULE[min(attempt_idx, len(BACKOFF_SCHEDULE) - 1)])

    return {
        "status": last_status,
        "body": None,
        "delivered": False,
        "attempts": attempts_made,
        "error": last_err,
    }

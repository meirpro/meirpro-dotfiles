#!/usr/bin/env python3
"""fetch_sticker_pack.py — download every sticker in a Telegram pack via the Bot API.

This is the scriptable alternative to using a third-party download bot.
Reproducible and CI-friendly, at the cost of needing a Telegram bot token.

Setup:
  1. DM @BotFather on Telegram, run /newbot, save the token it gives you.
  2. The bot does not need to be added to any chat — it just needs the
     token to call the public Bot API. getStickerSet is unrestricted.

Usage:
  python fetch_sticker_pack.py --token <BOT_TOKEN> --pack AnimatedEmojies --output ./stickers/
  python fetch_sticker_pack.py --token <BOT_TOKEN> --pack AnimatedEmojies --output ./stickers/ --convert

  --convert  also runs tgs_to_lottie.sh on each downloaded .tgs and
             writes the .json alongside.

Environment:
  TELEGRAM_BOT_TOKEN  may be set instead of passing --token explicitly.

Notes:
  - The pack name is the slug from the URL: t.me/addstickers/<PACK> → <PACK>.
  - Animated packs return .tgs files. Static packs return .webp. Video
    packs return .webm. This script downloads whatever the API returns
    and preserves the extension; it only --converts .tgs files.
  - Files are saved as 0.tgs, 1.tgs, ... in the order returned by the
    API, matching the visual order in the Telegram pack.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import urllib.parse
import urllib.request
import urllib.error
import json
from pathlib import Path


API_BASE = "https://api.telegram.org"


def api_call(token: str, method: str, **params) -> dict:
    """Call a Telegram Bot API method, return the result dict. Raises on API error."""
    qs = urllib.parse.urlencode(params)
    url = f"{API_BASE}/bot{token}/{method}?{qs}"
    try:
        with urllib.request.urlopen(url, timeout=30) as resp:
            payload = json.load(resp)
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"{method} HTTP {exc.code}: {body}") from exc
    if not payload.get("ok"):
        raise RuntimeError(f"{method} failed: {payload}")
    return payload["result"]


def download_file(token: str, file_path: str, dest: Path) -> None:
    """Download a Telegram file (the `file_path` returned by getFile)."""
    url = f"{API_BASE}/file/bot{token}/{file_path}"
    with urllib.request.urlopen(url, timeout=60) as resp, dest.open("wb") as out:
        out.write(resp.read())


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--token", default=os.environ.get("TELEGRAM_BOT_TOKEN"), help="Telegram bot token (or set TELEGRAM_BOT_TOKEN)")
    parser.add_argument("--pack", required=True, help="Sticker pack name (the slug from the t.me/addstickers/<NAME> URL)")
    parser.add_argument("--output", required=True, help="Output directory (created if missing)")
    parser.add_argument("--convert", action="store_true", help="Also convert .tgs → .json via tgs_to_lottie.sh in the same directory")
    args = parser.parse_args()

    if not args.token:
        print("Error: provide --token or set TELEGRAM_BOT_TOKEN.", file=sys.stderr)
        return 1

    out_dir = Path(args.output)
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"Fetching pack '{args.pack}'...", file=sys.stderr)
    pack = api_call(args.token, "getStickerSet", name=args.pack)
    stickers = pack.get("stickers", [])
    print(f"  {pack.get('title', '?')} — {len(stickers)} sticker(s)", file=sys.stderr)
    print(f"  is_animated={pack.get('is_animated')} is_video={pack.get('is_video')}", file=sys.stderr)

    tgs_files: list[Path] = []
    for idx, sticker in enumerate(stickers):
        file_id = sticker["file_id"]
        file_info = api_call(args.token, "getFile", file_id=file_id)
        file_path = file_info["file_path"]
        ext = Path(file_path).suffix or ".bin"
        dest = out_dir / f"{idx}{ext}"
        print(f"  [{idx + 1}/{len(stickers)}] {dest.name}", file=sys.stderr)
        download_file(args.token, file_path, dest)
        if ext == ".tgs":
            tgs_files.append(dest)

    if args.convert and tgs_files:
        script_dir = Path(__file__).resolve().parent
        converter = script_dir / "tgs_to_lottie.sh"
        if not converter.exists():
            print(f"Warning: --convert requested but {converter} not found", file=sys.stderr)
            return 0
        print(f"Converting {len(tgs_files)} .tgs file(s) to .json...", file=sys.stderr)
        for tgs in tgs_files:
            json_path = tgs.with_suffix(".json")
            with json_path.open("wb") as out:
                subprocess.run([str(converter), str(tgs)], stdout=out, check=True)

    print(f"Done. Files in {out_dir}/", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())

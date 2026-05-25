#!/usr/bin/env python3
"""inspect_lottie.py — report Lottie JSON metadata.

Two modes:

  Single/multi-file inspection:
    python inspect_lottie.py file1.json [file2.json ...]

    For each file, prints name, fps, in/out frames, loop duration, layer
    count (shapes vs images), and on-disk size. Useful for picking which
    extracted Telegram sticker to use, or for catching corrupt files.

  LCM mode (loop alignment for video work):
    python inspect_lottie.py --lcm --video-fps 30 file1.json file2.json ...

    Computes the least common multiple, in video frames, of every file's
    loop length. The result is the minimum composition duration where
    every Lottie loops cleanly to its last frame. Use this when planning
    Remotion / Motion Canvas / FFmpeg composition lengths.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys
from typing import Iterable


def load_lottie(path: str) -> dict:
    with open(path, "rb") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise ValueError(f"{path}: not a Lottie JSON object")
    return data


def summarize_layers(layers: list[dict]) -> tuple[int, int, int]:
    """Return (total, image_layers, shape_layers). ty=2 is image, ty=4 is shape."""
    total = len(layers)
    images = sum(1 for layer in layers if layer.get("ty") == 2)
    shapes = sum(1 for layer in layers if layer.get("ty") == 4)
    return total, images, shapes


def format_size(num_bytes: int) -> str:
    if num_bytes < 1024:
        return f"{num_bytes} B"
    if num_bytes < 1024 * 1024:
        return f"{num_bytes / 1024:.1f} KB"
    return f"{num_bytes / (1024 * 1024):.2f} MB"


def inspect(path: str) -> dict:
    data = load_lottie(path)
    size = os.path.getsize(path)
    fr = data.get("fr", 0) or 0
    ip = data.get("ip", 0) or 0
    op = data.get("op", 0) or 0
    nm = data.get("nm", "(no name)")
    v = data.get("v", "?")
    w = data.get("w", "?")
    h = data.get("h", "?")
    layers = data.get("layers", []) or []
    assets = data.get("assets", []) or []
    total, images, shapes = summarize_layers(layers)
    duration_frames = op - ip
    duration_seconds = duration_frames / fr if fr else float("nan")
    return {
        "path": path,
        "nm": nm,
        "v": v,
        "fr": fr,
        "ip": ip,
        "op": op,
        "duration_frames": duration_frames,
        "duration_seconds": duration_seconds,
        "w": w,
        "h": h,
        "layers": total,
        "image_layers": images,
        "shape_layers": shapes,
        "asset_count": len(assets),
        "size_bytes": size,
        "tgs_marker": data.get("tgs"),
    }


def print_inspection(info: dict) -> None:
    print(os.path.basename(info["path"]))
    print(f"  nm:         {info['nm']}")
    print(f"  v:          {info['v']}  (tgs marker: {info['tgs_marker']!r})")
    print(f"  canvas:     {info['w']}x{info['h']}")
    print(f"  fr:         {info['fr']} fps")
    print(
        f"  ip → op:    {info['ip']} → {info['op']}  "
        f"({info['duration_frames']} frames, {info['duration_seconds']:.2f}s loop)"
    )
    print(
        f"  layers:     {info['layers']} "
        f"({info['image_layers']} images, {info['shape_layers']} shapes)"
    )
    print(f"  assets:     {info['asset_count']}")
    print(f"  size:       {format_size(info['size_bytes'])} minified")
    if info["duration_frames"] <= 0:
        print("  WARNING: op <= ip — animation is static or corrupt")
    if not info["layers"]:
        print("  WARNING: no layers — file is empty or corrupt")
    print()


def lcm_of(numbers: Iterable[int]) -> int:
    nums = [n for n in numbers if n > 0]
    if not nums:
        return 0
    result = nums[0]
    for n in nums[1:]:
        result = result * n // math.gcd(result, n)
    return result


def loop_in_video_frames(info: dict, video_fps: float) -> int:
    """Convert loop length from native fps to video fps, rounded to nearest int."""
    native_fr = info["fr"] or 1
    return round(info["duration_frames"] * (video_fps / native_fr))


def cmd_lcm(paths: list[str], video_fps: float) -> None:
    infos = [inspect(p) for p in paths]
    per_file = []
    for info in infos:
        vf = loop_in_video_frames(info, video_fps)
        per_file.append((os.path.basename(info["path"]), vf, info["duration_seconds"]))
        print(
            f"{os.path.basename(info['path'])}: "
            f"{info['duration_frames']} native frames @ {info['fr']} fps "
            f"= {vf} video frames @ {video_fps} fps "
            f"({info['duration_seconds']:.3f}s)"
        )
    common = lcm_of(vf for _, vf, _ in per_file)
    print()
    print(f"LCM of loop lengths in video frames: {common}")
    if common and video_fps:
        print(f"  = {common / video_fps:.3f}s at {video_fps} fps")
        print(
            "  Pick a composition duration that is a whole multiple of "
            f"{common} video frames so every animation ends on a clean frame."
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("files", nargs="+", help="Lottie JSON file(s) to inspect")
    parser.add_argument("--lcm", action="store_true", help="LCM mode: compute the least common multiple of loop lengths in video frames")
    parser.add_argument("--video-fps", type=float, default=30.0, help="Video composition fps for LCM mode (default: 30)")
    args = parser.parse_args()

    if args.lcm:
        cmd_lcm(args.files, args.video_fps)
        return 0

    for path in args.files:
        try:
            info = inspect(path)
            print_inspection(info)
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            print(f"{path}: ERROR — {exc}", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

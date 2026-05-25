# Lottie JSON anatomy

Just enough format detail to debug a broken file or write a custom optimizer. The full spec lives at airbnb.io/lottie (Bodymovin) and lottie.io.

## Top-level fields

```json
{
  "v": "5.5.2",
  "fr": 60,
  "ip": 0,
  "op": 180,
  "w": 512,
  "h": 512,
  "nm": "fire",
  "ddd": 0,
  "assets": [],
  "layers": [],
  "tgs": 1
}
```

| Field | Meaning | Notes |
|---|---|---|
| `v` | Lottie schema version | `5.x` is standard for After Effects exports. Telegram packs are typically `5.5.x`. |
| `fr` | Frame rate (fps) | Telegram `.tgs` files are always 60. Native Lottie can be any value. |
| `ip` | In-point (first frame) | Almost always 0. |
| `op` | Out-point (last frame, exclusive) | Loop length = `op - ip`. |
| `w`, `h` | Canvas width / height in px | Telegram `.tgs` files are always 512×512. Web Lottie can be any. |
| `nm` | Name | Cosmetic. Used by `lottie.goToAndStop(name)` if present. Safe to strip. |
| `ddd` | 3D flag (0 or 1) | Almost always 0. |
| `assets` | Array of image / pre-composition assets | Empty for vector-only icons. Heavy if present. |
| `layers` | Array of layer objects | Where the actual content lives. |
| `tgs` | Telegram spec marker | Indicates Telegram-specific compliance (512×512, 60fps, ≤3s). Safe to leave or strip in non-Telegram contexts. |
| `markers` | Named time markers | Optional. Strip if not used by code. |
| `meta` | Author / generator info | Optional. Safe to strip. |

## Layer types (`layers[].ty`)

| `ty` value | Layer type | Notes |
|---|---|---|
| 0 | Pre-composition | Reference to another composition in `assets[]`. |
| 1 | Solid | Colored rectangle. |
| 2 | Image | Reference to a raster asset. **Heavy.** |
| 3 | Null | Empty layer used for parenting / transforms. |
| 4 | Shape | Vector shape layer. **The cheap, common one.** |
| 5 | Text | Animated text. |
| 6 | Audio | Audio layer. Not rendered by web players. |
| 13 | Camera | 3D camera. Requires `"ddd": 1`. |

A vector-only icon should be 100% `ty: 4` (shape) and `ty: 3` (null, for transform parenting). A file with `ty: 2` layers contains raster images and will be much heavier — see optimization.md for mitigation.

## Layer common fields

```json
{
  "ddd": 0,
  "ind": 1,
  "ty": 4,
  "nm": "Fire shape",
  "sr": 1,
  "ks": { "o": {...}, "p": {...}, "a": {...}, "s": {...}, "r": {...} },
  "ao": 0,
  "ip": 0,
  "op": 180,
  "st": 0,
  "bm": 0,
  "shapes": [...]
}
```

| Field | Meaning |
|---|---|
| `ind` | Layer index (unique within composition). |
| `nm` | Name. Cosmetic. |
| `sr` | Stretch / time-remap factor (1.0 = normal). |
| `ks` | **Transform**: opacity, position, anchor, scale, rotation. Object of property keyframe definitions. |
| `ip`, `op` | Per-layer in/out points. Can be shorter than the composition's `ip`/`op`. |
| `st` | Start time offset. |
| `bm` | Blend mode (0 = normal, 1 = multiply, 2 = screen, etc.). |
| `shapes` | Array of shape items (for `ty: 4`). |
| `hd` | If `true`, layer is hidden. Safe to strip during optimization. |

## Keyframe value shape

Both static and animated properties use the same envelope:

```json
"o": { "a": 0, "k": 100 }                 // static — opacity 100, no animation
"p": { "a": 1, "k": [                     // animated position
  { "t": 0, "s": [256, 256], "e": [256, 100] },
  { "t": 90, "s": [256, 100] }
]}
```

| Field | Meaning |
|---|---|
| `a` | 0 = static (just `k`), 1 = animated (keyframe array in `k`). |
| `k` | The value (scalar, vector, or array of keyframe objects). |
| `t` | Keyframe time (in frames). |
| `s` | Start value at this keyframe. |
| `e` | End value (deprecated in newer schemas — usually omitted, with the next keyframe's `s` implied). |
| `i`, `o` | In/out tangent for the easing curve. Object with `x`, `y` arrays. Bezier handle positions. |

This is where float-precision optimization hits: tangent and value arrays often have 10+ decimal places. Rounding to 3 is invisible in a 64×64 render.

## Debugging a broken file

| Symptom | Look at |
|---|---|
| Player renders blank | `op - ip <= 0` → static or corrupt. Check `op`. |
| Player renders one frame and stops | `loop: false` in the player, OR `op == ip + 1`. |
| Animation plays at wrong speed | `fr` mismatch between file and your assumption. Lottie player respects file's `fr`; if you assume 30 and the file is 60, it plays at half speed on platforms that re-time. |
| Huge file size | `assets[]` has image entries, or layers contain raster references. Open in a Lottie viewer to confirm. |
| Player throws on load | `v` field references a schema feature the player doesn't support. Try a newer `lottie-web` version, or re-export from source. |

## Useful programmatic checks

```python
import json

with open("fire.json") as f:
    d = json.load(f)

# Sanity checks
assert d["op"] > d["ip"], "Static or corrupt"
assert d["layers"], "No layers"
assert all(layer["ty"] != 2 for layer in d["layers"]), "Contains raster images"
print(f"Loop: {(d['op'] - d['ip']) / d['fr']:.2f}s at {d['fr']} fps")
print(f"Layers: {len(d['layers'])}")
```

`scripts/inspect_lottie.py` in this skill does these checks and more, formatted for human reading.

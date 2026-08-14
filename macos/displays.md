# External displays

How this machine drives its monitors, and why the previous arrangement was
replaced. No software here — this is a record of a hardware decision that took
a week to get right and would be expensive to re-derive.

## Current setup

**MacBook Pro `Mac17,9` (M5 Pro) → Kensington SD5000T5 EQ over one Thunderbolt
5 cable → 3 external displays, natively.**

No DisplayLink, no driver, no purple screen-capture indicator. The dock is a
plain Thunderbolt 5 dock; the Mac's own GPU drives every display.

Installed 2026-08-14 and confirmed working. (Topology not independently
verified here — the dock was disconnected when this was written. Re-check with
`system_profiler SPDisplaysDataType` while docked if it ever matters.)

### Why three displays work now

**The M5 Pro drives 3 external displays natively over a single Thunderbolt
port.** M4 Pro/Max capped at 2 per port — that limit is the entire reason
DisplayLink was ever needed here. Confirmed by [Apple's
documentation](https://support.apple.com/en-us/101571).

This also settles a spec dispute that nearly cost an extra $130. Kensington's
product page lists dual 6K for Macs and enumerates only *"M1/M2/M3/M4 Pro"* and
*"M1/M2/M3/M4 Max"* — the Pro/Max list stops at M4, so M5 Pro appears nowhere.
That read as pre-M5-Pro copy rather than an exclusion, and their [M5 Pro blog
post](https://www.kensington.com/news/docking-connectivity-blog/macbook-pro-m5-pro-and-m5-max-unlock-triple-displays-with-thunderbolt-5-docking-stations/)
said three. **The optimistic read was correct** — three displays work.

Lesson worth keeping: when a vendor spec *omits* your hardware rather than
*excluding* it, that's stale copy, not a limitation. A competing product
(Plugable TBT-UDH2) actively listed "M4/M5 Pro/Max: 2× 6K", which is a real
claim about this chip and a different situation entirely.

### The port budget

On a Thunderbolt dock a downstream port (**DFP**) is *either* a display *or* a
device, never both. The host port (**UFP**) is the single cable to the Mac and
isn't usable for peripherals; power flows backwards through it (dock → Mac,
140W via PD 3.1).

The SD5000T5 EQ has exactly three DFPs, so three monitors consume all of them:

```
UFP        Thunderbolt 5 host   → MacBook, 140W in    (not usable for devices)
DFP 1      60W  (front)         → display 1
DFP 2      15W  (rear)          → display 2
DFP 3      15W  (rear)          → display 3
           3× USB-A, SD+microSD, 2.5GbE, audio        ← all that remains
```

**Two consequences that are easy to forget later:**

1. **Zero USB-C ports free.** The old Anker dock left three USB-C at 100W,
   because its monitors hung off dedicated HDMI/DP outputs rather than
   general-purpose ports. This is a real regression in exchange for native
   video.
2. **The 60W port is consumed by a display**, so that headline feature is
   unusable in a three-monitor setup.

If USB-C at the desk becomes a problem, a USB-C multiport hub on a DFP carries
DP Alt Mode video *and* USB data over the same connection — one monitor plus
several ports from one DFP. Put it on the 60W front port; the rear ones only
supply 15W.

**Hard limit if you go that route: one display per DFP, always.** A hub with
two HDMI ports will *not* drive two extended displays — that needs MST, which
**macOS does not support**, and you get mirrored output. Avoid dual-HDMI hubs.
Also check any hub does DP Alt Mode rather than DisplayLink, or you land right
back at the indicator. Don't buy a *large* hub — its Ethernet, card readers and
PD passthrough would duplicate the dock.

## History: the DisplayLink era (removed 2026-08-14)

The previous dock was an **Anker Prime DL7400** ($270), a USB-C DisplayLink
dock. Its upstream was a 10Gb/s USB-C *data* port — not Thunderbolt, not DP Alt
Mode — so the 2×HDMI + 1×DP on its back were DisplayLink outputs, not GPU
outputs. Every pixel was screen-captured, compressed over USB, and decompressed
by the dock.

That required `DisplayLink Manager` running whenever the dock was in use, which
meant macOS showed the purple screen-capture indicator constantly. Accurately:
the screen genuinely was being captured.

Costs that came with it, beyond the indicator: a driver dependency that breaks
on macOS upgrades, DRM black screens on Netflix/Prime/Disney+, compression
latency, and continuous CPU overhead.

Removed along with the dock: the app, its login item, a
`pro.meir.displaylink` LaunchAgent that supervised it, and a
`verify-displaylink.sh` health check. All deleted from this repo — see git
history if any of it is ever needed again.

### Hiding the purple indicator: does not work on macOS 26

Recorded so nobody burns another afternoon on it. **Tested and failed on macOS
26.6 (Tahoe, build 25G72), 2026-07-30**, with the dock attached and displays
live.

The [widely-circulated workaround](https://niclake.me/mac-displaylink/) launches
`DisplayLinkUserAgent` directly instead of letting LaunchServices boot the
`.app`, on the theory that Control Center can't resolve a bundle identity and
therefore draws no menu bar entry. It worked on Sequoia. It does not work now.

macOS 26 resolves capture to the **responsible process** — the ancestor GUI app
that spawned the tree — and falls back to the binary's own code signature when
there isn't one. No launch path yields *no* identity:

| Launch method | Attributed to | Result |
|---|---|---|
| LaunchServices (`open`, login item) | DisplayLink's signature | icon shown |
| launchd agent (ppid 1) | DisplayLink's signature | icon shown |
| `screen` from Terminal/WezTerm | **the terminal's** signature | icon shown, + prompts to grant *the terminal* Screen Recording |

**Never grant a terminal emulator Screen Recording** to make the third row
"work". Every script, `npm postinstall` and shell one-liner you run would
inherit the ability to capture the screen under the terminal's grant, with the
indicator naming only "Terminal". Strictly worse than the icon.

Supporting evidence: an [Apple developer forum
thread](https://developer.apple.com/forums/thread/807323) reports macOS 26.1
changed how background Unix executables register for Screen Recording.
`RecordingIndicatorUtility` lists no Tahoe support and requires disabling SIP.
`YellowDot` only makes the dot blend in — and needs Screen Recording itself.

**What the indicator actually guarantees.** Two independent layers, and the
trick only ever defeated one: TCC permission is the *gate* (nothing captures
without an explicit grant, never bypassed by any of this), and the menu bar icon
is the *reminder* that capture is happening now. Suppression, when it worked,
was per-process. Treat the icon as a signal, not a guarantee — the Screen
Recording list in System Settings is what actually enumerates what can watch
you.

## Docks evaluated (2026-07/08)

Kept for the next time this comes up. Prices as seen at the time.

| Dock | Price | HDMI | DP | Downstream TB5 | Adapters | USB-C power |
|---|---|---|---|---|---|---|
| **Kensington SD5000T5 EQ** ← chosen | **$219.99** | 0 | 0 | 3 | 3 | 15W |
| Anker DL7400 (previous) | $270 | 2 | 1 | none | 0 | 100W |
| Plugable TBT-UDT3 | $299.95 | 0 | 0 | 3 | 3 | 15W |
| Plugable TBT-UDH2 | $349.95 | 2 | 0 | 1 | 1 | 30W |
| CalDigit TS5 | $399 | 0 | 0 | 3 | 3 | 15–20W |
| CalDigit TS5 Plus | $499 | 0 | 1 | 2 | 2 | 36W |
| Sonnet Echo 21 SuperDock | $499 | 1 | 1 | 3 | 1–2 | 15W |

Almost no TB5 dock has HDMI — Apple caps dock HDMI at 4K/75Hz, so vendors drop
it in favour of Thunderbolt ports and leave adapters to the buyer. The
Kensington was bought at $219.99 (part `K35201NA`, Amazon-fulfilled; `K35202NA`
is the same dock in a different finish, both "SD5000T5 EQ").

Ports: 3× TB5 downstream (one 60W), 1× TB5 host (140W), 3× USB-A 10Gbps, combo
audio jack, UHS-II SD + microSD, 2.5GbE. Requires macOS 14.5+.

## Sources

- [Apple — how many displays connect to MacBook Pro](https://support.apple.com/en-us/101571)
- [Macworld — M5 Pro/Max enable 3–4 displays over one cable](https://www.macworld.com/article/3088215/m5-pro-max-macbooks-finally-break-apples-multi-monitor-shackles.html)
- [Kensington — M5 Pro triple displays over TB5](https://www.kensington.com/news/docking-connectivity-blog/macbook-pro-m5-pro-and-m5-max-unlock-triple-displays-with-thunderbolt-5-docking-stations/)
- [Macworld — SD5000T5 EQ review](https://www.macworld.com/article/3127228/kensington-sd5000t5-eq-thunderbolt-5-dock-review.html)
- [Anker DL7400 product page](https://www.anker.com/products/a83b3-anker-prime-charging-docking-station-14-in-1-triple-display-140w)
- [Nic Lake — the indicator workaround that no longer works](https://niclake.me/mac-displaylink/)
- [Apple Developer Forums — Tahoe 26.1 background executable Screen Recording registration](https://developer.apple.com/forums/thread/807323)

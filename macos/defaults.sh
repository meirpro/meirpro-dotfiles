#!/usr/bin/env bash
#
# macOS system defaults
#
# Settings that aren't exposed in System Settings (or are buried) but change
# how the machine feels every day. Run explicitly — this is NOT called by
# install.sh, because it restarts Finder/Dock and the menu bar piece needs a
# full logout.
#
#   ./macos/defaults.sh          apply
#   ./macos/defaults.sh --revert remove everything this script sets
#
# Every setting records its stock value in a comment, so `--revert` stays
# honest and future-you can tell "I chose this" from "that's just default".
#
# This script deliberately only manages keys it sets itself. Settings changed
# through System Settings (Dock autohide, Dock tile size, Finder view style,
# Finder sort-folders-first, show-all-extensions, tap-to-click, reduce
# transparency, hot corners) are left alone in both directions — applying
# won't overwrite them and --revert won't clobber them.

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

REVERT=false
[[ "${1:-}" == "--revert" ]] && REVERT=true

if [[ "$(uname)" != "Darwin" ]]; then
    echo "Not macOS — nothing to do."
    exit 0
fi

# set <domain> <key> <type> <value>   — honours --revert
# Prefix domain with "ch:" for ByHost (per-machine) preferences.
set_default() {
    local dom="$1" key="$2" type="$3" val="$4" host=""
    [[ "$dom" == ch:* ]] && { host="-currentHost"; dom="${dom#ch:}"; }
    if $REVERT; then
        defaults $host delete "$dom" "$key" 2>/dev/null || true
    else
        defaults $host write "$dom" "$key" "$type" "$val"
    fi
}

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if $REVERT; then
    echo -e "${GREEN}  Reverting macOS defaults to stock${NC}"
else
    echo -e "${GREEN}  Applying macOS defaults${NC}"
fi
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

# ============================================================================
# MENU BAR  — reclaim horizontal space on a 14" screen
# ============================================================================
echo -e "${BLUE}Menu bar${NC}"

# Gap between menu bar items, and the padding around the highlight box drawn
# when an item is clicked.   Stock: spacing 12, padding 16.
#
# On a 14" MacBook the notch eats the middle of the menu bar and any items
# that overflow are silently hidden behind it. Tightening these reclaims
# roughly half the horizontal footprint per item — the difference between
# seeing every icon and losing the leftmost ones.
#
# Both keys MUST be written with `-currentHost`. They are ByHost (per-machine)
# preferences: a plain `defaults write -globalDomain` lands in
# ~/Library/Preferences/.GlobalPreferences.plist, which the menu bar never
# reads, and the setting silently does nothing.
#
# 0 is the minimum — maximum density, icons nearly touching. If the click
# highlight feels cramped against the icon, raise padding to 4-6 and leave
# spacing at 0.
set_default ch:-globalDomain NSStatusItemSpacing -int 0
set_default ch:-globalDomain NSStatusItemSelectionPadding -int 0

# Menu bar clock: time only, no date, no day of week.
# Stock: ShowDate 0, ShowDayOfWeek true.
#
# ShowDate is a tri-state, not a bool — 0 = show when space allows,
# 1 = always show, 2 = never show. It has to be 2; leaving it at the
# default 0 means the date reappears whenever macOS decides there's room.
#
# "Wed 23 Jul 18:44" vs "18:44" is a large chunk of the right-hand menu bar,
# which is the same space the status icons are fighting over.
#
# 24-hour drops the trailing " PM" for another ~3 characters. Show24Hour
# overrides the region's 12/24h default without changing the region itself.
set_default com.apple.menuextra.clock ShowDate -int 2
set_default com.apple.menuextra.clock ShowDayOfWeek -bool false
set_default com.apple.menuextra.clock Show24Hour -bool true
echo -e "${GREEN}  ✓ Menu bar spacing, padding, and 24h time-only clock${NC}"
echo

# ============================================================================
# KEYBOARD  — the highest-impact section in this file
# ============================================================================
echo -e "${BLUE}Keyboard${NC}"

# Key repeat rate and the delay before repeating kicks in.
# Stock: KeyRepeat 6, InitialKeyRepeat 25. Lower is faster; 2/15 is the
# common developer setting and 1/10 is faster than System Settings can go.
# This is the change you feel most — every held arrow key, every backspace.
set_default -globalDomain KeyRepeat -int 2
set_default -globalDomain InitialKeyRepeat -int 15

# Stock: true. When true, holding a key shows the accent-picker popup (é è ê)
# instead of repeating the character — actively hostile in vim, VS Code, or
# anywhere you hold j/k to move. Turning it off restores key repeat.
# Note: takes effect per-app on next launch.
set_default -globalDomain ApplePressAndHoldEnabled -bool false

# Stock: 0. Mode 3 = full keyboard access, so Tab moves between every control
# in a dialog, not just text fields and lists.
set_default -globalDomain AppleKeyboardUIMode -int 3

# Text substitutions. Stock: all true.
# Smart quotes and smart dashes are the dangerous pair — they silently turn
# " into " and -- into —, which breaks code, JSON, and shell commands the
# moment you type them outside an editor (Slack, Notes, browser fields).
set_default -globalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
set_default -globalDomain NSAutomaticDashSubstitutionEnabled -bool false
set_default -globalDomain NSAutomaticSpellingCorrectionEnabled -bool false
set_default -globalDomain NSAutomaticCapitalizationEnabled -bool false
set_default -globalDomain NSAutomaticPeriodSubstitutionEnabled -bool false
echo -e "${GREEN}  ✓ Fast key repeat, no accent popup, no smart substitutions${NC}"
echo

# ============================================================================
# UI SPEED  — moderate: quicker, still recognisably macOS
# ============================================================================
echo -e "${BLUE}UI speed${NC}"

# Stock: 0.2s. Window resize animation — 0.001 makes resizing feel instant.
# (Window open/close animations and smooth scrolling are deliberately left
# ON here; killing those makes transitions feel abrupt rather than fast.)
set_default -globalDomain NSWindowResizeTime -float 0.001

# Stock: 0.5s delay, 1.0 animation. The Dock is set to auto-hide, so every
# single reveal pays that half-second stall. Zero delay plus a faster slide
# is the difference between "the Dock appears" and "I waited for the Dock".
set_default com.apple.dock autohide-delay -float 0
set_default com.apple.dock autohide-time-modifier -float 0.15

# Stock: 0.2s. Mission Control transition.
set_default com.apple.dock expose-animation-duration -float 0.1

# Stock: genie / true. Scale minimises faster than genie; the launch bounce
# is pure latency theatre.
set_default com.apple.dock mineffect -string scale
set_default com.apple.dock launchanim -bool false

# Stock: true — macOS reorders Spaces by most-recent-use, which breaks the
# muscle memory of "my terminal is Space 3".
set_default com.apple.dock mru-spaces -bool false

# Stock: true. The "Recent applications" divider section in the Dock.
set_default com.apple.dock show-recents -bool false

# Stock: 2 (medium). 1 = compact sidebar icons — same 14" density goal as the
# menu bar change, applied to every Finder and Mail sidebar.
set_default -globalDomain NSTableViewDefaultSizeMode -int 1

# Stock: 0.5s. Delay before a folder springs open while drag-hovering.
set_default -globalDomain com.apple.springing.delay -float 0

# --- Dock density (from mathiasbynens' .macos) -------------------------------
# Stock: false. Minimised windows fold into their app's existing Dock icon
# instead of piling up as separate tiles on the right side. On a 14" screen
# that's the difference between a Dock that stays put and one that shrinks
# every icon as you minimise things.
set_default com.apple.dock minimize-to-application -bool true

# Stock: false. Cmd-H'd apps get a translucent Dock icon, so "hidden" is
# visible at a glance instead of guesswork.
set_default com.apple.dock showhidden -bool true

# Stock: true. Mission Control shows every window separately rather than
# stacking them per-app — more useful when you have many windows of one app.
set_default com.apple.dock expose-group-by-app -bool false
echo -e "${GREEN}  ✓ Instant Dock, faster resize/Mission Control, compact sidebars${NC}"
echo

# ============================================================================
# FINDER
# ============================================================================
echo -e "${BLUE}Finder${NC}"

# Stock: both off. The path bar (bottom strip showing where you are) and
# status bar (item count + free space) make Finder navigable instead of
# guesswork.
set_default com.apple.finder ShowPathbar -bool true
set_default com.apple.finder ShowStatusBar -bool true

# Stock: true. The "are you sure you want to change the extension" nag —
# pointless once extensions are always visible.
set_default com.apple.finder FXEnableExtensionChangeWarning -bool false

# Stock: icnv (icon). Nlsv = list view — denser, sortable, and shows size and
# date without hovering. Other values: clmv column, Flwv gallery.
#
# Only affects folders with no saved view preference. Finder writes per-folder
# state into .DS_Store, so folders already visited keep the view they have. To
# force it everywhere: open a folder in list view, then
# View -> Show View Options -> Use as Defaults.
set_default com.apple.finder FXPreferredViewStyle -string Nlsv

# NOT set: FXDefaultSearchScope. Currently SCsp ("use previous search scope"),
# chosen deliberately in Finder settings. The alternative SCcf always searches
# the current folder. Left as a System Settings choice.

# Stock: false. Stops macOS writing .DS_Store turds onto network shares and
# USB drives, which is what makes them show up in other people's repos and
# on colleagues' Windows machines.
set_default com.apple.desktopservices DSDontWriteNetworkStores -bool true
set_default com.apple.desktopservices DSDontWriteUSBStores -bool true

# Stock: false / false. Expanded save and print dialogs by default, instead
# of the collapsed one-line version that hides the folder picker.
set_default -globalDomain NSNavPanelExpandedStateForSaveMode -bool true
set_default -globalDomain PMPrintingExpandedStateForPrint -bool true

# Stock: true. Default new documents to the local disk, not iCloud Drive.
set_default -globalDomain NSDocumentSaveNewDocumentsToCloud -bool false
echo -e "${GREEN}  ✓ Path + status bar, no .DS_Store on network/USB, expanded dialogs${NC}"
echo

# ============================================================================
# SCREENSHOTS
# ============================================================================
echo -e "${BLUE}Screenshots${NC}"

# Stock: ~/Desktop, png, shadow enabled.
# Desktop accumulates "Screenshot 2026-07-23 at 14.02.11.png" forever; a
# dedicated folder keeps it clean. The window drop shadow adds ~60px of
# transparent margin on every windowed capture, which wrecks them for docs.
SCREENSHOT_DIR="$HOME/Pictures/Screenshots"
if $REVERT; then
    defaults delete com.apple.screencapture location 2>/dev/null || true
    defaults delete com.apple.screencapture disable-shadow 2>/dev/null || true
else
    mkdir -p "$SCREENSHOT_DIR"
    defaults write com.apple.screencapture location -string "$SCREENSHOT_DIR"
    defaults write com.apple.screencapture disable-shadow -bool true
fi
echo -e "${GREEN}  ✓ Saved to ~/Pictures/Screenshots, no window shadow${NC}"
echo

# ============================================================================
# KEYBOARD SHORTCUTS — hand the screenshot keys to CleanShot X
# ============================================================================
echo -e "${BLUE}Keyboard shortcuts${NC}"

# macOS owns Cmd-Shift-3/4/5 by default. CleanShot X wants those same keys,
# and when both are bound macOS wins — CleanShot appears "broken" for no
# visible reason. Disabling the built-ins is what makes CleanShot work, and
# it's exactly the kind of setting that's invisible until you rebuild a
# machine and can't work out why the screenshot key stopped doing the right
# thing.
#
# These live in com.apple.symbolichotkeys as numeric IDs:
#   28  Cmd-Shift-3        whole screen  -> file
#   29  Cmd-Ctrl-Shift-3   whole screen  -> clipboard
#   30  Cmd-Shift-4        selected area -> file
#   31  Cmd-Ctrl-Shift-4   selected area -> clipboard
#  184  Cmd-Shift-5        screenshot & recording options
#
# Written via `defaults export | edit | defaults import` rather than editing
# the plist file directly: cfprefsd caches these, and a direct file write gets
# silently overwritten. Existing key bindings are preserved so that
# re-enabling them in System Settings still produces the right shortcut.
if $REVERT; then
    HOTKEY_STATE=true
else
    HOTKEY_STATE=false
fi
python3 - "$HOTKEY_STATE" <<'PYEOF'
import plistlib, subprocess, sys

enable = sys.argv[1] == "true"
# id: (charCode, keyCode, modifierMask) — used only when the entry is absent
DEFAULTS = {
    "28":  (51, 20, 1179648), "29":  (51, 20, 1441792),
    "30":  (52, 21, 1179648), "31":  (52, 21, 1441792),
    "184": (53, 23, 1179648),
}
DOMAIN = "com.apple.symbolichotkeys"

raw = subprocess.run(["defaults", "export", DOMAIN, "-"],
                     capture_output=True).stdout
try:
    root = plistlib.loads(raw) if raw.strip() else {}
except Exception:
    root = {}
hotkeys = root.setdefault("AppleSymbolicHotKeys", {})

for hid, (char, code, mods) in DEFAULTS.items():
    entry = hotkeys.get(hid)
    if not isinstance(entry, dict):
        entry = {"value": {"type": "standard",
                           "parameters": [char, code, mods]}}
        hotkeys[hid] = entry
    entry["enabled"] = enable          # keep existing parameters untouched

subprocess.run(["defaults", "import", DOMAIN, "-"],
               input=plistlib.dumps(root), check=True)
PYEOF
if $REVERT; then
    echo -e "${GREEN}  ✓ Built-in screenshot shortcuts re-enabled${NC}"
else
    echo -e "${GREEN}  ✓ Cmd-Shift-3/4/5 released for CleanShot X${NC}"
fi
echo

# ============================================================================
# APP ANNOYANCES
# ============================================================================
echo -e "${BLUE}App annoyances${NC}"

# Stock: false. Stops Photos.app (or Image Capture) launching itself every
# time you plug in an iPhone, camera or SD card. ByHost, so it's per-machine.
set_default ch:com.apple.ImageCapture disableHotPlug -bool true

# Stock: true. Two-finger horizontal swipe navigates back/forward in Chrome.
# It fires constantly by accident while scrolling sideways in a wide table or
# a diff, and losing a filled-in form to a stray swipe is the usual way people
# discover it exists.
#
# ON TRIAL — if you miss swipe-navigation, this is the one-liner to undo it,
# no need to revert anything else:
#     defaults delete com.google.Chrome AppleEnableSwipeNavigateWithScrolls
#     defaults delete com.google.Chrome AppleEnableMouseSwipeNavigateWithScrolls
# Then quit and reopen Chrome. Cmd-[ / Cmd-] still go back and forward either
# way, so nothing is actually lost.
set_default com.google.Chrome AppleEnableSwipeNavigateWithScrolls -bool false
set_default com.google.Chrome AppleEnableMouseSwipeNavigateWithScrolls -bool false

# Stock: RichText 1. TextEdit opens new documents as plain text in UTF-8
# (encoding 4) instead of RTF — so it behaves like a scratch editor rather
# than a word processor that silently smart-quotes your config snippet.
set_default com.apple.TextEdit RichText -int 0
set_default com.apple.TextEdit PlainTextEncoding -int 4
set_default com.apple.TextEdit PlainTextEncodingForWrite -int 4
echo -e "${GREEN}  ✓ No Photos on plug-in, no Chrome swipe-back, plain-text TextEdit${NC}"
echo

# ============================================================================
# TERMINALS
# ============================================================================
echo -e "${BLUE}Terminals${NC}"

# Applied to both Terminal.app and iTerm2 deliberately — which terminal is in
# use is still undecided, and these are cheap and harmless on the one that
# isn't. Add Ghostty/WezTerm/Alacritty here if the answer changes; those
# configure via files in ~/.config rather than `defaults`.

# --- Terminal.app ---
# Stock: false. Secure Keyboard Entry stops other processes on the machine
# from reading what you type into the terminal — the same protection the
# password field in a login window gets. Worth having anywhere you type
# production credentials or sudo passwords.
#
# Trade-off worth knowing: while it's on, some text-expansion and clipboard
# utilities can't see terminal input. If a snippet tool stops working
# in Terminal, this is why.
set_default com.apple.Terminal SecureKeyboardEntry -bool true

# Stock: 1. The small chevron marks in the left gutter at each prompt.
set_default com.apple.Terminal ShowLineMarks -int 0

# --- iTerm2 (currently in use: $TERM_PROGRAM reports iTerm.app) ---
# Stock: true. The "are you sure you want to quit?" dialog on Cmd-Q.
set_default com.googlecode.iterm2 PromptOnQuit -bool false
echo -e "${GREEN}  ✓ Terminal secure input, no line marks, no iTerm quit prompt${NC}"
echo

# ============================================================================
# NAGS
# ============================================================================
echo -e "${BLUE}Nags${NC}"

# Stock: 0. Auto-quit the printer app once the queue finishes.
set_default com.apple.print.PrintingPrefs "Quit When Finished" -bool true

# Stock: false. Stops Help windows floating above every other window.
set_default com.apple.helpviewer DevMode -bool true

# Stock: false. Stops the "use this disk as a Time Machine backup?" prompt on
# every new external drive.
set_default com.apple.TimeMachine DoNotOfferNewDisksForBackup -bool true
echo -e "${GREEN}  ✓ Printer auto-quit, help viewer, Time Machine prompt${NC}"
echo

# Deliberately NOT set, and why:
#
#   LSQuarantine=false          Disables the "downloaded from the internet,
#                               are you sure?" check. That's a real safety
#                               net, not a nag. Left on.
#   WarnOnEmptyTrash=false      Confirmation on a destructive, irreversible
#                               action. Left on.
#   AppleShowScrollBars=Always  Permanent scrollbars eat horizontal space —
#                               works against the 14" density goal.
#   swipescrolldirection        "Natural" vs not is pure muscle memory; no
#                               correct answer, so it stays untouched.
#   NSAutomaticWindowAnimations Chosen: moderate. Killing these makes windows
#   NSScrollAnimationEnabled    pop in/out abruptly rather than feeling fast.

# ============================================================================
# RESTART AFFECTED PROCESSES
# ============================================================================
echo -e "${YELLOW}Restarting Finder, Dock and ControlCenter...${NC}"
killall Finder 2>/dev/null || true
killall Dock 2>/dev/null || true
# ControlCenter owns the menu bar clock, so this picks the clock format up
# immediately. It does NOT pick up the item spacing above — that genuinely
# needs a logout.
killall ControlCenter 2>/dev/null || true
echo -e "${GREEN}  ✓ Finder, Dock and clock settings are live now${NC}"
echo

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Done${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo
echo -e "${YELLOW}Log out and back in to finish.${NC}"
echo "  • Menu bar spacing — ControlCenter/SystemUIServer reads those prefs"
echo "    once at login. killall is not reliable on macOS 26; a real logout is."
echo "  • Key repeat + press-and-hold — applies per-app on next launch."
echo
echo "  Apple menu →  Log Out, or:  osascript -e 'tell app \"System Events\" to log out'"
echo

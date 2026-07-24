-- WezTerm configuration.
--
-- Primary reason this exists: RTL / bidirectional text (Hebrew, Arabic).
-- iTerm2 and Terminal.app cannot reorder bidi text — Hebrew shows in
-- logical (left-to-right) order, visually reversed. WezTerm can, via
-- bidi_enabled. This is the terminal to use for hayom / sefer-ocr / any
-- Hebrew work where you need to READ the text correctly.
--
-- Symlinked to ~/.wezterm.lua by install.sh.

local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- ── Bidirectional text ───────────────────────────────────────────────
-- The whole point. Reorders Hebrew/Arabic runs for correct display.
-- AutoLeftToRight: base direction LTR (English prompts), but RTL runs
-- (Hebrew words) are reordered within the line. Use 'AutoRightToLeft'
-- if you want the base paragraph direction RTL instead.
config.bidi_enabled = true
config.bidi_direction = 'AutoLeftToRight'

-- ── Font ─────────────────────────────────────────────────────────────
-- Menlo (macOS built-in) covers Hebrew; the fallback guarantees glyphs
-- for anything it misses. Add a Nerd Font first if you want icons.
config.font = wezterm.font_with_fallback {
  'Menlo',
  'Arial Hebrew',
  'Noto Sans Hebrew',
}
config.font_size = 13.0

-- ── Appearance ───────────────────────────────────────────────────────
-- Change this string and SAVE — WezTerm hot-reloads, the window updates
-- instantly. Names must match EXACTLY (a wrong name silently falls back
-- to default). Browse all 1078 at https://wezfurlong.org/wezterm/
-- colorschemes/index.html, or list them: see the probe note below.
-- Lighter picks that exist in this build:
--   'Builtin Solarized Light'  (matches the rest of the Solarized setup)
--   'Catppuccin Latte'  'Builtin Light'  'One Light (base16)'
--   'Gruvbox light, soft (base16)'  'PaperColor Light (base16)'
-- Softer DARKs (if you want dark but less harsh):
--   'Catppuccin Frappe'  'Gruvbox Dark'  'Builtin Solarized Dark'
config.color_scheme = 'Builtin Solarized Light'
-- Prefer to hand-tune instead of a preset? Comment out color_scheme and
-- set colors directly:
--   config.colors = { background = '#1c1c2b', foreground = '#e0e0e0' }
config.window_decorations = 'RESIZE'
config.enable_tab_bar = true
config.hide_tab_bar_if_only_one_tab = true
config.window_padding = { left = 6, right = 6, top = 4, bottom = 4 }

return config

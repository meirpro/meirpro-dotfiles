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

-- ── Appearance (Solarized Dark, matching the rest of the dotfiles) ───
config.color_scheme = 'Solarized Dark (base16)'
config.window_decorations = 'RESIZE'
config.enable_tab_bar = true
config.hide_tab_bar_if_only_one_tab = true
config.window_padding = { left = 6, right = 6, top = 4, bottom = 4 }

return config

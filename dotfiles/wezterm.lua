-- ~/.config/wezterm/wezterm.lua — managed by macos-setup
--
-- Mirrors dotfiles/ghostty-config and dotfiles/kitty.conf: same font, same
-- Vesper palette, same cursor and scrollback, so a side-by-side comparison is
-- about the terminal rather than the theme.
--
-- WezTerm earns its place here for the one thing Ghostty does not do: built-in
-- multiplexing with domains that survive a dropped connection. On the hostile
-- networks of hotels, trains and conferences, a Wi-Fi drop kills the
-- session; a mux domain does not. That is also why tmux and zellij are in the
-- Brewfile -- three different answers to the same problem, kept so they can be
-- compared rather than guessed about.

local wezterm = require("wezterm")
local config = wezterm.config_builder()

-- ── Font ─────────────────────────────────────────────────────
config.font = wezterm.font("Geist Mono")
config.font_size = 14.0
-- Ghostty sets -calt -liga -dlig; harfbuzz_features is the equivalent.
config.harfbuzz_features = { "calt=0", "liga=0", "dlig=0" }
config.line_height = 1.10 -- Ghostty's adjust-cell-height = 10%

-- ── Colours (Vesper) ─────────────────────────────────────────
-- Copied from Ghostty's bundled theme file rather than retyped from a
-- screenshot, so the palettes cannot drift.
config.colors = {
  foreground = "#ffffff",
  background = "#101010",
  cursor_bg = "#acb1ab",
  cursor_fg = "#ffffff",
  cursor_border = "#acb1ab",
  selection_bg = "#988049",
  selection_fg = "#b9beb8",
  ansi = {
    "#101010", "#f5a191", "#90b99f", "#e6b99d",
    "#aca1cf", "#e29eca", "#ea83a5", "#a0a0a0",
  },
  brights = {
    "#7e7e7e", "#ff8080", "#99ffe4", "#ffc799",
    "#b9aeda", "#ecaad6", "#f591b2", "#ffffff",
  },
}

-- ── Window ───────────────────────────────────────────────────
config.window_padding = { left = 10, right = 10, top = 8, bottom = 8 }
config.window_close_confirmation = "NeverPrompt"
config.window_decorations = "RESIZE"
config.use_fancy_tab_bar = false
config.hide_tab_bar_if_only_one_tab = true
config.adjust_window_size_when_changing_font_size = false

-- ── Cursor & scrollback ──────────────────────────────────────
config.default_cursor_style = "SteadyBlock"
config.cursor_blink_rate = 0
config.scrollback_lines = 100000

-- ── macOS ────────────────────────────────────────────────────
-- Norwegian layout: Option composes | @ \ { } [ ] $ -- Option-7 is the pipe.
-- "composed" means the macOS character, so both stay true: neither Option key is
-- given up to Meta. Nothing on this machine binds Alt, and losing composition
-- costs characters every shell command needs.
config.send_composed_key_when_left_alt_is_pressed = true
config.send_composed_key_when_right_alt_is_pressed = true

-- ── Panes ────────────────────────────────────────────────────
-- The defaults (Cmd-Shift-Option-% and -") are unreachable on a Norwegian
-- layout, and a tmux-style | or [ ] needs Option. So: Cmd plus letters,
-- arrows and Enter only -- keys that sit in the same place on every layout --
-- matching Ghostty's defaults so both terminals share the muscle memory.
-- WezTerm's naming is inverted: SplitHorizontal puts panes side by side.
local act = wezterm.action
config.keys = {
  { key = "d", mods = "CMD", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
  { key = "d", mods = "CMD|SHIFT", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
  { key = "w", mods = "CMD", action = act.CloseCurrentPane({ confirm = false }) },
  { key = "Enter", mods = "CMD|SHIFT", action = act.TogglePaneZoomState },

  { key = "LeftArrow", mods = "CMD|OPT", action = act.ActivatePaneDirection("Left") },
  { key = "RightArrow", mods = "CMD|OPT", action = act.ActivatePaneDirection("Right") },
  { key = "UpArrow", mods = "CMD|OPT", action = act.ActivatePaneDirection("Up") },
  { key = "DownArrow", mods = "CMD|OPT", action = act.ActivatePaneDirection("Down") },

  { key = "LeftArrow", mods = "CMD|CTRL", action = act.AdjustPaneSize({ "Left", 5 }) },
  { key = "RightArrow", mods = "CMD|CTRL", action = act.AdjustPaneSize({ "Right", 5 }) },
  { key = "UpArrow", mods = "CMD|CTRL", action = act.AdjustPaneSize({ "Up", 5 }) },
  { key = "DownArrow", mods = "CMD|CTRL", action = act.AdjustPaneSize({ "Down", 5 }) },
}

-- Right-click menu. WezTerm has no native context menu, so this opens the
-- InputSelector overlay instead: pick with the digit, j/k + Enter, or Esc.
-- Programs that grab the mouse (vim, htop) get the click; Shift-right-click
-- reaches the menu anyway.
local pane_menu = {
  { label = "Split side by side   Cmd-D", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
  { label = "Split top/bottom     Cmd-Shift-D", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
  { label = "Zoom pane            Cmd-Shift-Enter", action = act.TogglePaneZoomState },
  { label = "Close pane           Cmd-W", action = act.CloseCurrentPane({ confirm = false }) },
  { label = "Copy                 Cmd-C", action = act.CopyTo("Clipboard") },
  { label = "Paste                Cmd-V", action = act.PasteFrom("Clipboard") },
}
local pane_menu_choices = {}
for i, item in ipairs(pane_menu) do
  pane_menu_choices[i] = { id = tostring(i), label = item.label }
end

config.mouse_bindings = {
  {
    event = { Down = { streak = 1, button = "Right" } },
    mods = "NONE",
    action = act.InputSelector({
      title = "Pane",
      choices = pane_menu_choices,
      action = wezterm.action_callback(function(window, pane, id)
        if id then
          window:perform_action(pane_menu[tonumber(id)].action, pane)
        end
      end),
    }),
  },
}

-- ── Multiplexing ─────────────────────────────────────────────
-- The reason WezTerm is installed. `wezterm connect unix` attaches to a mux
-- server that outlives the GUI, so closing the window -- or losing Wi-Fi on a
-- venue network -- does not take the shells with it.
config.unix_domains = { { name = "unix" } }

return config

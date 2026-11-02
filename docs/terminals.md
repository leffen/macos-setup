# Terminals

Four emulators and two multiplexers, installed deliberately so they can be
compared rather than argued about. Ghostty is the daily driver; the rest are
here to be tried.

## The one rule that makes a comparison possible

Every config in `dotfiles/` is derived from `ghostty-config`: the same
**Geist Mono at 14pt**, ligatures off, 10% extra cell height, a non-blinking
block cursor, 100 000 lines of scrollback, copy-on-select, and Option sending
Esc+.

They also share one palette — **Vesper** — and that palette is *copied from
Ghostty's own bundled theme file*
(`Ghostty.app/Contents/Resources/ghostty/themes/Vesper`) rather than retyped
into each config. Transcribing sixteen hex values five times is a guaranteed
source of drift, and the drift would be invisible: a slightly wrong blue in one
terminal reads as "this terminal renders colours differently".

The point of all that sameness: **switching terminals should tell you which
terminal you prefer, not which theme you prefer.** If one of them feels better,
that difference is real.

## What is installed

| | Version | Config | Why it is here |
| --- | --- | --- | --- |
| [Ghostty](#ghostty) | 1.3.1 | `dotfiles/ghostty-config` | daily driver |
| [kitty](#kitty) | 0.48.2 | `dotfiles/kitty.conf` | the mature GPU alternative |
| [WezTerm](#wezterm) | 20240203 | `dotfiles/wezterm.lua` | multiplexing that survives a drop |
| [iTerm2](#iterm2) | 3.6.11 | `dotfiles/iterm2/` + `steps/16-iterm2.sh` | the macOS incumbent |
| [tmux](#tmux) | 3.7c | `dotfiles/tmux.conf` | the standard multiplexer |
| [zellij](#zellij) | 0.45.1 | `dotfiles/zellij-config.kdl` | the discoverable one |

All except iTerm2 are symlinked by `steps/06-dotfiles.sh`.

---

## Ghostty

The default, and the one the others are calibrated against. Zig, GPU-rendered,
native macOS, with shell integration that reports the working directory so new
splits open where you were.

Nothing here changes it. It is the reference.

## kitty

The closest comparison to Ghostty: GPU-rendered, fast, long-established, with a
larger feature surface (`kittens` for SSH, image display, diffing) and a remote
control protocol.

```sh
kitty
```

Honest assessment: it overlaps Ghostty almost entirely. If Ghostty works for
you, kitty's advantage is maturity and the kitten ecosystem rather than
anything you will feel day to day. It is here because that judgement is worth
checking rather than taking on trust.

One config note — Ghostty's three font-feature lines become a single
`disable_ligatures always`, and `adjust-cell-height = 10%` becomes
`modify_font cell_height 110%`. Same result, different spelling.

## WezTerm

**The one with a capability the others lack.** WezTerm has a built-in
multiplexer whose server outlives the GUI:

```sh
wezterm connect unix     # attach to the mux domain
```

Close the window, or lose Wi-Fi on a venue network, and the shells keep
running. That matters most on hotel, train and conference networks, where a dropped
connection otherwise takes the session with it.

`config.unix_domains = { { name = "unix" } }` is already set, so the domain
exists without further setup.

Configured in Lua, which is either the appeal or the objection depending on
taste. It is the least macOS-native of the four.

!!! note "No native Claude Code notifications"
    Claude Code's `preferredNotifChannel` supports `ghostty`, `kitty` and
    `iterm2`, but not WezTerm — it falls back to the terminal bell. A small
    thing, but it is the kind of detail that only shows up after you have
    switched.

## iTerm2

The macOS incumbent: mature, enormously configurable, and the one every guide
assumes. It was installed here for years and **never configured** — about
100 MB that a rebuilt machine reinstalled and then ignored.

### Why it is not a symlink

Every other terminal reads a config file. iTerm2 does not: it reads its own
`defaults` domain and rewrites the plist whenever any setting changes.
Symlinking that into the repo would mean iTerm2 editing tracked files as a side
effect of opening its preferences window.

Its supported answer is a **custom prefs folder**, which `steps/16-iterm2.sh`
sets:

```sh
defaults write com.googlecode.iterm2 PrefsCustomFolder -string "<repo>/dotfiles/iterm2"
defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true
```

iTerm2 copies prefs *from* the folder at launch and offers to write changes
back when it quits. For tinkering that is the good outcome: change something in
the GUI, quit, then `git diff` to see exactly which key moved.

!!! warning "Quit iTerm2 before re-running the step"
    Setting this while iTerm2 is running is a coin flip — it may write its
    in-memory prefs back over the repo copy on quit, and the change then looks
    like it silently did nothing. The step checks and warns.

The plist is **generated**, not captured: a script converts the Vesper hex
values to iTerm2's `Red/Green/Blue Component` floats, so the profile matches
the other four exactly rather than approximately.

## tmux

The standard answer to session survival, and the one with the most muscle
memory attached to it.

```sh
tmux            # new session
tmux a          # attach
```

The prefix is deliberately left as **`C-b`**. Remapping to `C-a` is the common
advice and it is wrong on this machine: `C-a` is beginning-of-line in every zsh
prompt here, and stealing it makes every shell slightly worse to save one
keystroke.

What is changed from stock: mouse on, 100k history, windows numbered from 1,
`escape-time 10` (the 500 ms default makes vim's Esc feel broken), vi copy mode
yanking to `pbcopy`, and splits rebound to `|` and `-` that open in the current
directory rather than `~`.

!!! tip "Truecolour needs both lines"
    ```
    set -g default-terminal "tmux-256color"
    set -ga terminal-overrides ",*256col*:Tc,xterm-ghostty:Tc,xterm-kitty:Tc"
    ```
    Without the override tmux flattens truecolour to 256 and Vesper renders as
    approximations — which reads as "my theme is broken inside tmux".

## zellij

The same job as tmux, with the opposite philosophy: the keybindings are
displayed at the bottom of the screen, so it is usable before you have
memorised anything.

```sh
zellij
zellij attach
```

`pane_frames` is off — the status bar already shows the layout, and one source
of chrome is enough. `copy_command "pbcopy"` is set, without which yanking goes
to a buffer nothing else on the machine can read. Sessions are serialized, so
they outlive the terminal window.

---

## In the Dock

The stock Dock ships twenty Apple apps and no terminal, which is a poor default
here — the point of installing four is trying them, and that does not happen if
reaching for one means Spotlight every time. `steps/17-dock.sh` adds all four as
a group after Claude.

It uses [`dockutil`](https://github.com/kcrawford/dockutil) rather than
`defaults write com.apple.dock persistent-apps -array-add`. The raw form takes a
nested plist dict as a string, silently no-ops on a malformed entry, and has no
notion of "is it already there" — so a second `setup.sh` run would leave you
with two of every terminal. The step is idempotent, and restarts the Dock once
at the end rather than after each addition.

It also prunes the stock set — TV, Music, Games, iPhone Mirroring, Maps,
FaceTime, App Store, Photos, Phone, Contacts, Reminders, and Terminal.app.
Nothing is uninstalled; all of it stays one Spotlight keystroke away.
Terminal.app is in that list on purpose: with four better emulators two slots to
the left, the stock one is mainly a way to end up in the wrong terminal by
accident.

!!! warning "`dockutil --find` searches sections you did not mean"
    The Dock has three: `persistentApps` (what you pinned), `persistentOthers`
    (folders like Downloads), and **`recentApps`** — the transient group macOS
    repopulates by itself.

    `--find` matches all three. Using it as the idempotency guard made this step
    report `removed Terminal` on *every* run and restart the Dock each time,
    because macOS put Terminal back into `recentApps` the moment it was next
    launched. The Dock was never wrong; the check was asking the wrong question.

    `--list` emits `label<tab>path<tab>section<tab>plist`, so the fix is to
    filter on field 3 and act only on `persistentApps`.

A related surprise from the same output: `Activity Monitor` and `VSCodium`
looked like Dock fixtures but were never pinned at all — both were sitting in
`recentApps`. What is actually pinned here is thirteen apps plus Downloads.

Five `small-spacer` tiles then divide the result into six groups:

```
Apps │ Safari  Chrome │ Messages  Claude │ Ghostty  iTerm  kitty  WezTerm │ Mail  Calendar  Notes │ System Settings
```

Four terminals in a row is hard to aim at without a break either side.

!!! danger "`dockutil --remove spacer-tiles` crashes"
    In dockutil 3.1.3 that command exits **133** (SIGTRAP), prints nothing at
    all, and removes nothing.

    This matters because "clear the spacers, then add five fresh ones" is the
    obvious way to make the step idempotent, and it *looks* like it works —
    written with `|| true` after it, the step would add five more spacers on top
    of the existing ones on every run.

    So the step counts instead: five means leave it alone, zero means build
    them, and anything else warns and changes nothing. Spacers have no label,
    so they cannot be removed by name either — an unexpected count has to be
    fixed by dragging them off the Dock.

## Scrollback is not the same unit everywhere

kitty, tmux and zellij all count scrollback in **lines**. Ghostty counts it in
**bytes**, and its key is `scrollback-limit` — there is no
`scrollback-limit-lines`. Ghostty rejects unknown keys rather than ignoring
them, so the wrong spelling is a startup error, not a setting that quietly does
nothing.

The two units do not convert: a wide line costs far more than a short one, so
any line-to-byte figure would be invented. Ghostty is simply set generously
(100 MB) and the others to 100 000 lines. Scrollback is allocated lazily, so the
byte figure is a ceiling rather than an upfront cost.

## Option, and the disappearing pipe

This machine uses a **Norwegian** layout, where `|` is Option-7 — along with
`@`, `\`, `{`, `}`, `[`, `]` and `$` on other Option combinations. Almost
everything a shell needs is behind that key.

Every terminal here offers to turn Option into Meta, so that Alt-b and Alt-f do
word motion. Turning it on costs every one of those characters. The failure does
not look like a setting: the pipe key simply stops working, and nothing connects
that to a terminal preference you changed days ago.

So Option is **not** remapped here. Both keys compose, in all three
repo-managed terminals:

| Terminal | Setting |
| --- | --- |
| Ghostty | `macos-option-as-alt = false` |
| kitty | `macos_option_as_alt no` |
| WezTerm | `send_composed_key_when_left_alt_is_pressed = true` (and right) |

The trade is real but one-sided on this machine. Meta buys Alt-b/Alt-f word
motion — and there is not a single `bindkey` line in the zsh config, so almost
nothing was using it. Composition is needed in every other shell command.

A right-Option-only compromise (`right` in Ghostty and kitty) exists if Meta
ever becomes worth having; it keeps composition on the left key.

!!! warning "Apple Terminal has its own copy of this setting"
    `Terminal.app`'s profile carries `useOptionAsMetaKey`, and it is not
    managed by this repo. If the pipe is missing in Terminal specifically, it is
    that checkbox: **Settings → Profiles → Keyboard → Use Option as Meta key**.

## Which to use for what

* **Day to day:** Ghostty. It is configured, fast, and native.
* **Shells that must survive a network drop:** WezTerm's mux domain, or tmux
  inside any of them. Three answers exist here precisely so the choice can be
  made from experience.
* **A GUI you can click through:** iTerm2, now that it finally has a profile.

## A finding worth repeating

While checking all this, the session running the work was in **Apple Terminal**
with `TERM=xterm-color` — the *8-colour* terminfo, not `xterm-256color`.
Everything emitting 256-colour or truecolour output was being silently degraded,
including the shell prompt and the status line.

Nothing warns about this. The terminal simply renders approximate colours, and
approximate colours look like a theme you do not much like. If something looks
subtly wrong, check `echo $TERM` before rewriting the theme.

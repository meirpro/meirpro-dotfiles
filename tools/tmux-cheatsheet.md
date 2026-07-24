# tmux cheatsheet

Tailored to **this repo's `.tmux.conf`**: prefix is **`Ctrl-A`** (not the default
`Ctrl-B`), and copy mode uses **vi keys**.

> **How to read this:** "**prefix** then `X`" means press `Ctrl-A`, let go, then
> press `X`. The prefix is a doorbell — you ring it, then give the command.

---

## The mental model

- **Session** — a whole workspace. Keeps running even when you close the
  terminal. This is the point of tmux.
- **Window** — like a browser tab inside a session.
- **Pane** — a split within a window.

So: sessions contain windows, windows contain panes.

---

## iTerm2 control mode (`-CC`) — try this

In **iTerm2 only**, start tmux like this:

```bash
tmux -CC              # new control-mode session
tmux -CC attach       # reattach to an existing one in control mode
```

iTerm2 then draws tmux windows as **native iTerm2 tabs** and panes as **native
iTerm2 splits**. You control them with normal iTerm2 shortcuts and the mouse,
but they're backed by tmux — so they survive a disconnect and you can reattach
from anywhere. Best of both worlds, and unique to iTerm2.

Plain `tmux` (below) works in every terminal; `-CC` is the iTerm2 bonus.

To leave control mode: just close the iTerm2 window (the session keeps running —
`tmux -CC attach` brings it back).

---

## Sessions — the persistence layer

| Command (in shell) | Does |
|---|---|
| `tmux` | start a new unnamed session |
| `tmux new -s work` | start a session named "work" |
| `tmux ls` | list running sessions |
| `tmux attach` / `tmux a` | reattach to the last session |
| `tmux attach -t work` | reattach to "work" |
| `tmux kill-session -t work` | end "work" |

| Inside tmux (prefix then…) | Does |
|---|---|
| **prefix** `d` | **detach** — leave it running in the background |
| **prefix** `s` | visual list of sessions to switch between |
| **prefix** `$` | rename current session |

> **The core loop:** `tmux` → work → **prefix** `d` (detach) → close laptop →
> later → `tmux attach` → it's all still there. Over SSH this means a dropped
> connection never kills your work.

---

## Windows (tabs)

| prefix then… | Does |
|---|---|
| `c` | create a new window |
| `n` / `p` | next / previous window |
| `0`–`9` | jump to window by number |
| `w` | visual list of windows |
| `,` | rename current window |
| `&` | close current window (asks to confirm) |
| `f` | find a window by name |

---

## Panes (splits)

| prefix then… | Does |
|---|---|
| `%` | split **left/right** (vertical divider) |
| `"` | split **top/bottom** (horizontal divider) |
| arrow keys | move to the pane in that direction |
| `o` | cycle to the next pane |
| `z` | **zoom** — toggle current pane fullscreen (great for focus) |
| `x` | close current pane (asks to confirm) |
| `{` / `}` | swap pane with previous / next |
| `Space` | cycle through preset layouts |
| hold `Ctrl-A` + arrow | resize the pane (if resize binding is set) |

> `z` (zoom) is the one people miss — blow a pane up to fullscreen to read
> something, hit `z` again to snap back to the split.

---

## Copy mode (vi keys — this repo's config)

Copy mode lets you scroll back and select text with the keyboard.

| Key | Does |
|---|---|
| **prefix** `[` | **enter** copy mode (now you can scroll) |
| arrows / `h j k l` | move around |
| `Ctrl-U` / `Ctrl-D` | half-page up / down |
| `/` then text | search forward (like vim) |
| `Space` | start selection |
| `v` | begin a visual (character) selection |
| `y` | yank (copy) the selection and exit |
| **prefix** `]` | **paste** what you yanked |
| `q` | leave copy mode |

---

## Handy admin

| prefix then… | Does |
|---|---|
| `?` | **list every keybinding** (your built-in cheatsheet) |
| `:` | tmux command prompt (type commands directly) |
| `t` | show a big clock (fun / screensaver) |

Reload the config after editing `.tmux.conf`, without restarting:

```
prefix  :  source-file ~/.tmux.conf
```

---

## First things to actually try

1. `tmux` — you're in a session.
2. **prefix** `%` then **prefix** `"` — you now have three panes.
3. **prefix** arrows — hop between them.
4. **prefix** `z` on one — fullscreen, then **prefix** `z` back.
5. **prefix** `d` — detach. Notice your programs keep running.
6. `tmux attach` — you're back exactly where you left off.
7. In iTerm2: exit, then `tmux -CC attach` — same session, now as native tabs.

Once that feels natural, ask and we'll add mouse support + friendlier split
keys to `.tmux.conf`.

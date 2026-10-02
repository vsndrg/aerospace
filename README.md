# aerospace

My [AeroSpace](https://github.com/nikitabobko/AeroSpace) config and the patches it is built with — the window manager
half of [vsnd-setup](https://github.com/vsndrg/vsnd-setup), which installs all of it (with
[VsndBar](https://github.com/vsndrg/vsndbar), the glass bar) in one command:

```sh
curl -fsSL https://raw.githubusercontent.com/vsndrg/vsnd-setup/main/install.sh | bash
```

Keys: see [vsnd-setup](https://github.com/vsndrg/vsnd-setup#keys).

## Patches

Against AeroSpace **0.20.3-Beta** (`6dde91ba`). Details are in the header of [`patches/build.sh`](patches/build.sh).

| Patch | |
|---|---|
| `bar-state` | pushes what the bar shows (workspaces, their monitors, apps, focus) over a socket — no process per event |
| `switch-flicker` | a workspace switch places the new windows before hiding the old ones: no empty desktop or wrong window for a frame |
| `back-and-forth` | `cmd-N` pressed on N goes back to the previous workspace only if it still exists |
| `menu-bar` | the usable area ignores the menu bar, so windows stay put when the system menu bar is shown |
| `monitors` | workspaces remember their monitor: a disconnected monitor's (Sidecar iPad's) workspaces come back to it |
| `queries` | `list-*` answer straight from the model instead of a full refresh per query |
| `window-hiding` | hidden windows go to the corner that covers the least of the other monitors (an iPad above the Mac) |

## Building by hand

```sh
patches/build.sh             # build only
patches/build.sh --install   # build and swap into /Applications/AeroSpace.app (the original is kept)
patches/build.sh --restore   # put windows back on their workspaces after a restart
```

Needs the Command Line Tools (no Xcode), the AeroSpace 0.20.3-Beta CLI on `PATH` and an unpatched
`AeroSpace.app` of the same version (`/Applications` or `~/.cache/aerospace-original.app`). Signs with the
`aerospace-local-codesign` certificate if there is one, so the Accessibility grant survives rebuilds.

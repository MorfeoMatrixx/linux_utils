# Claude Desktop embedded terminal fix (Linux)

## Symptom

Opening the terminal panel inside the Claude Desktop app (the "Local
Sessions" feature) always fails immediately:

```
execvp(3) failed.: No such file or directory
```

shown above/below the command in the terminal pane, and the shell exits
right away every time, regardless of restarts, app updates, or environment
fixes (`SHELL`, `PATH`, etc. are all fine — this is not a host config issue).

## Root cause

Confirmed by inspecting the unpacked app bundle
(`/usr/lib/claude-desktop/node_modules/electron/dist/resources/app.asar`):
the function that decides which shell binary to launch for this feature is
hardcoded:

```js
function _7e(){return{shell:"powershell.exe",args:[]}}
```

There's no Linux/macOS branch — it always tries to exec `powershell.exe`,
which doesn't exist outside Windows, so `execvp()` fails with ENOENT every
time. This is a packaging bug in the app itself, not something fixable via
local shell/env configuration.

## Workaround: PATH shim

`execvp("powershell.exe", ...)` has no slash in the filename, so it does a
`PATH` search. Drop an executable file literally named `powershell.exe`
earlier in `PATH` than anything else, and it gets found and exec'd instead.

```bash
mkdir -p ~/.local/bin
cat > ~/.local/bin/powershell.exe <<'EOF'
#!/bin/bash
exec "${SHELL:-/bin/bash}" -l
EOF
chmod +x ~/.local/bin/powershell.exe
```

Make sure `~/.local/bin` is ahead of other dirs in `PATH` (it is by default
on most Debian/Ubuntu-based desktop setups — check with `echo $PATH`).

The PTY's master/slave fds and controlling terminal are already set up by
`fork()` before `exec()` runs, so the shim just needs to `exec` into a real
shell — it inherits a fully working terminal.

Fully quit and relaunch Claude Desktop after creating the shim.

## Caveats

- This only fixes the embedded terminal panel feature, nothing else.
- `args` is always `[]` from the app's side, so shell flags can't be passed
  through — hardcode them in the shim script if needed (`-l` here for a
  login shell).
- If a future app update fixes the underlying bug and starts passing a real
  shell path, this shim becomes inert — safe to leave or delete.
- Reported upstream: https://github.com/anthropics/claude-code/issues
  (mention app version, e.g. `1.15962.1-2.0.22`, and the hardcoded
  `powershell.exe` finding above).

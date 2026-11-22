# Fedora 45 agent sandbox

## Build and run

Use rootless Podman with a Compose provider. From the directory containing `compose.yaml`, build the image and start the container.

```sh
podman compose build dev-env &&
  podman compose up -d --no-build dev-env
```

- `build dev-env` builds the image for the `dev-env` service and reuses cached build steps.
- `up` creates and starts the service. `-d` runs it in the background.
- `--no-build` uses the existing local image. Build once before using this option.
- `--force-recreate` replaces the container immediately and closes open sessions.

Open Bash or start an agent in its own terminal.

```sh
podman exec -it dev-env bash
podman exec -it dev-env codex -c 'cli_auth_credentials_store="file"'
podman exec -it dev-env claude
podman exec -it dev-env grok
```

`exec` runs a command in the running container, and `-it` gives it an interactive terminal. All four commands run as the same user in `/workspace` with `HOME=/home/agent`.

The Codex `-c` option stores credentials in a file in its persistent home. Use `podman stop dev-env` to stop the container.

On first use, sign in from the agent’s terminal. For device-code login, append `login --device-auth` to the Codex or Grok command. For Claude, append `auth login`.

## What persists

- **Project files** in `/workspace` live directly in the mounted host directory, `~/Projects` by default.
- **Credentials, saved sessions, and settings** live in one Podman volume mounted at `/home/agent`. Each agent uses its own app directories within that home. The default volume is `ai-sandbox-home`. Set `SANDBOX_HOME` to an absolute host path if you prefer a bind mount.

Recreating the container discards changes made only in its writable layer, such as files in `/tmp` or packages installed by hand. `podman compose down` keeps the named home volume. Adding `--volumes` removes it.

If you already use the former shared volume and want to keep its data, set `SANDBOX_HOME_VOLUME=ai-sandbox-codex` before recreating.

## Bash aliases

Add these to your host’s `~/.bashrc`, adjust `DEV_ENV_DIR` to your clone, then run `source ~/.bashrc`.

```bash
DEV_ENV_DIR="$HOME/Projects/dev-env"
alias deb='(cd -- "$DEV_ENV_DIR" && podman compose build dev-env)'
alias des='(cd -- "$DEV_ENV_DIR" && podman compose up -d --no-build dev-env)'
alias der='(cd -- "$DEV_ENV_DIR" && podman compose up -d --no-build --force-recreate dev-env)'
alias dex='podman exec -it dev-env bash'
```

Use `deb && des` for first setup, `des` to start, `der` to replace the container, and `dex` to open Bash. The `des` and `der` aliases start the base configuration. If you use voice or skills, add the same `-f compose.yaml -f <overlay>` flags to those aliases so the mounts are applied on every start.

## When to rebuild or recreate

| What changed | Command |
| --- | --- |
| First setup or missing image | `podman compose build dev-env`, then `podman compose up -d --no-build dev-env` |
| Just start the service | `podman compose up -d --no-build dev-env` |
| Ports, workspace, or overlays changed, or you want a fresh container | `podman compose up -d --no-build --force-recreate dev-env` |
| Containerfile, bundled editor config, or bundled skills changed | `podman compose build dev-env`, then recreate |
| Deliberately rerun every installer and the Fedora package step | `podman compose build --no-cache dev-env`, then recreate |

To **check one build phase**, use `podman build --layers --target agents -f Containerfile .`. Replace `agents` with `base` for Fedora packages, `tools` for uv/Python, Bun, Herdr Core or agent-browser, or `editors` for LazyVim and Roslyn. The `agents` phase groups Codex, Claude, and Grok. `--layers` caches steps, `--target` selects the phase, `-f` selects the file, and `.` supplies the current directory as the build context. Use the full Compose build to update the service image.

To **check for new upstream releases** while reusing the Fedora base, run the following and then recreate. Change only the refresh arguments for phases you want to refresh. Reuse the same values on subsequent builds to reuse those layers. A plain build uses its default cache keys, which may point to older releases.

```sh
refresh=$(date +%s)
podman compose build \
  --build-arg REFRESH_AGENTS="$refresh" \
  --build-arg REFRESH_TOOLS="$refresh" \
  --build-arg REFRESH_EDITORS="$refresh" dev-env
```

## Codex voice

Build the image once to install the bundled audio clients. Each `-f` selects a Compose file. Put `compose.yaml` first, followed by one voice overlay and the skills overlay if you use it.

### Linux desktop

Run from the desktop session that owns the PulseAudio or PipeWire socket.

```sh
podman compose -f compose.yaml -f compose.voice.linux.yaml up -d --no-build --force-recreate dev-env
```

The default socket is `$XDG_RUNTIME_DIR/pulse/native`. Set `SANDBOX_PULSE_SOCKET` if the host uses a different path.

### WSL2 or Podman on Windows

1. **Windows:** Run `wsl --update` in PowerShell and use WSL2 with WSLg enabled. Allow desktop apps to use the microphone in Windows Settings. WSLg provides the audio server. [Microsoft WSLg setup](https://learn.microsoft.com/en-us/windows/wsl/tutorials/gui-apps)
2. **Inside WSL:** If you run Podman locally in the distro, install Podman and a Compose provider there. On Ubuntu, the package names are `podman` and `podman-compose`. For audio diagnostics, optionally run `sudo apt install pulseaudio-utils` to get `pactl`. Check `test -S /mnt/wslg/PulseServer`. [Podman installation](https://podman.io/docs/installation) · [WSLg container audio](https://github.com/microsoft/wslg/blob/main/samples/container/Containers.md)
3. **Podman from PowerShell:** Use a WSL-backed Podman machine. Check the socket with `podman machine ssh podman-machine-default "test -S /mnt/wslg/PulseServer"` after starting the machine. Replace the name if needed. Hyper-V needs a separate audio bridge. If Windows Compose rewrites the socket as a drive path, run Compose from WSL using the same machine connection. [Windows bind path issue](https://github.com/containers/podman-compose/issues/1352) · [Connect from WSL](https://podman-desktop.io/docs/podman/accessing-podman-from-another-wsl-instance)

```sh
podman compose -f compose.yaml -f compose.voice.yaml up -d --no-build --force-recreate dev-env
```

### Test audio

```sh
podman exec dev-env pactl info
podman exec -it dev-env codex
```

Look for a default source and sink. On WSLg these are typically `RDPSource` and `RDPSink`. Sign in to Codex and enter `/voice` to test microphone capture and playback.

## Workspace, skills, and editors

- **Workspace:** The container starts in `/workspace`. To choose the host folder mounted there, set `SANDBOX_WORKSPACE` to an absolute path in your shell or the repository’s `.env`, then recreate. If unset, Compose uses your host’s `~/Projects`. PowerShell uses `USERPROFILE` when `HOME` is unset.
- **Skills:** Set `SANDBOX_SKILLS_DIR` to an absolute host directory containing `skill-name/SKILL.md` folders, then add `-f compose.skills.yaml` to your Compose files. It mounts the supplied skills read-only.
- **Editors:** Run `uv sync` inside Python projects, generate `compile_commands.json` for C/C++, and open Rust projects from a directory with `Cargo.toml`. Check Helix with `hx --health <language>` and LazyVim with `:LspInfo`.
- **Existing LazyVim profiles:** Enable Python, Clangd, and Rust in `:LazyExtras`. Set `vim.g.lazyvim_python_lsp = "ty"` in `lua/config/options.lua` and merge the entries from `/opt/sandbox/lazyvim/lua/plugins/sandbox-languages.lua`. Fresh profiles get those settings automatically.
- **Port:** Apps listening on `0.0.0.0:5005` inside the container are reachable at `127.0.0.1:5005` on the host.

## Checks

Run `podman exec dev-env cat /usr/local/share/sandbox-tools.txt` to see the versions installed in the running container. For the credential-free integration test, first bring your regular stack down with `podman compose down` using its usual overlay files, then run `./tests/smoke`. The test uses the same container name and host port.

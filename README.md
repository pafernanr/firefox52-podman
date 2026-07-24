# firefox52-podman

> *Do you remember when browsers were browsers and ran their own Flash and Java plugins?*

Run Firefox 52 ESR with Flash Player and Java (NPAPI) in an isolated
Podman container, accessible through your modern browser via noVNC.

Some legacy web interfaces (ILO, IPMI, old SCADA panels, internal enterprise
tools) still require Java applets or Flash to function. Modern browsers dropped
NPAPI plugin support years ago, making these interfaces inaccessible. This
project gives you a contained, disposable way to reach them without compromising
your host system.

## What's inside

- **Firefox 52.9.0 ESR** — last Firefox with NPAPI plugin support
- **Adobe Flash Player 32.0.0.371** — NPAPI plugin (`libflashplayer.so`)
- **Oracle JRE 8u191** — Java NPAPI plugin (`libnpjp2.so`)
- **noVNC** — browser-based VNC client, no extra software needed
- Everything runs inside a rootless Podman container (Ubuntu 22.04)

## Requirements

- Linux x86_64
- [Podman](https://podman.io/) (rootless, no Docker needed)

## Quick start

```bash
chmod +x firefox52-podman.sh
./firefox52-podman.sh
```

On first run the script asks for confirmation, builds the image, starts the
container, and prints the noVNC URL. On subsequent runs it detects the current
state — if the container is already running it shows the URL, otherwise it
offers an interactive menu.

The host port is selected automatically from the 6080-6099 range.

## Usage

Run the script without arguments for auto-detection, or pass a command directly:

```
./firefox52-podman.sh {start|start-exposed|stop|uninstall}
```

| Command   | Description                                        |
|-----------|----------------------------------------------------|
| `start`   | Build image (first time) and start on localhost only |
| `start-exposed` | Start accessible from all network interfaces |
| `stop`    | Stop the container (frees RAM/CPU)                 |
| `uninstall` | Remove container, data, and image             |

> **Note:** `start-exposed` binds to `0.0.0.0`, making the noVNC session
> reachable from the network. The session has no authentication — use only
> on trusted networks.

## How it works

```
┌─────────────────────────────────────────────┐
│  Podman container (Ubuntu 22.04)            │
│                                             │
│  Xvfb (:1)  →  openbox  →  Firefox 52      │
│     ↓                       ├ Flash 32      │
│  x11vnc                     └ Java 8        │
│     ↓                                       │
│  websockify (noVNC)  ← port 6080            │
└──────────────────────┬──────────────────────┘
                       │
        http://127.0.0.1:<auto>
                       │
              ┌────────┴────────┐
              │  Your browser   │
              └─────────────────┘
```

The container builds a single image with all dependencies baked in.
On start, it runs a virtual X display, launches Firefox 52, and exposes
it via noVNC on an automatically selected port (6080-6099). Your browser
connects over plain HTTP — no VNC client needed.

Profile data (bookmarks, settings) persists in `~/firefox52-podman/profile/`
across container restarts.

## Verifying plugins

Inside Firefox 52, navigate to `about:plugins`. You should see:

- **Shockwave Flash** — Version 32.0.0.371
- **Java(TM) Plug-in** — Version 1.8.0_191

## Files

| Path | Description |
|------|-------------|
| `~/firefox52-podman/profile/` | Firefox profile (persisted) |
| `~/firefox52-podman/plugins/` | Extra plugins (bind-mounted) |
| `localhost/firefox52` | Podman image |
| `firefox52-podman` | Podman container name |

## Cleanup

```bash
./firefox52-podman.sh uninstall
```

## License

This project packages third-party software under their respective licenses:

- Firefox 52 ESR — [Mozilla Public License](https://www.mozilla.org/en-US/MPL/)
- Adobe Flash Player — proprietary, EOL since December 2020
- Oracle JRE 8 — [Oracle Binary Code License](https://www.oracle.com/java/technologies/javase/jdk-faqs.html)

## Disclaimer

Adobe Flash Player and Oracle JRE 8 are proprietary software. Their licenses
prohibit redistribution, so they are not included in this repository. During
the image build, the script downloads them from [archive.org](https://archive.org),
which hosts them under a digital preservation rationale. These URLs may break
at any time if the rights holders request removal. This project does not claim
any right to redistribute these files.

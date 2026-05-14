# PrepperGrid N.O.M.A.D. macOS Apple Silicon Install

## Prerequisites

- Apple Silicon Mac running macOS.
- Homebrew installed from https://brew.sh.
- Docker Desktop for Mac installed from https://www.docker.com/products/docker-desktop and running before installation.
- Bash, `curl`, `python3`, `diskutil`, `df`, and `xmllint`; these are normally available on macOS or through Xcode Command Line Tools.

The installer does not install Homebrew, does not install Docker Desktop, and does not execute remote shell installer scripts.

## Installation

From the repository root:

```bash
bash install/install_preppergrid_nomad_macos.sh
```

By default, files are installed under:

```text
/Users/$USER/.preppergrid-nomad
```

To install somewhere else, set `NOMAD_DIR` before running the installer:

```bash
NOMAD_DIR=/Users/$USER/nomad-data bash install/install_preppergrid_nomad_macos.sh
```

The installer generates `install/compose.macos.env` and copies it to the installed N.O.M.A.D. directory as `compose.macos.env`. That generated file contains local paths and must not be committed.

The launchd agent template is installed with `REPLACE_WITH_USERNAME` substituted for your macOS username.

## Starting/Stopping

Start manually:

```bash
/Users/$USER/.preppergrid-nomad/start_preppergrid_nomad_macos.sh
```

Stop manually:

```bash
/Users/$USER/.preppergrid-nomad/stop_preppergrid_nomad_macos.sh
```

Update manually:

```bash
/Users/$USER/.preppergrid-nomad/update_preppergrid_nomad_macos.sh
```

The installer writes a launchd agent to:

```text
/Users/$USER/Library/LaunchAgents/com.preppergrid.nomad.agent.plist
```

Load it without rebooting:

```bash
launchctl bootstrap "gui/$(id -u)" "/Users/$USER/Library/LaunchAgents/com.preppergrid.nomad.agent.plist"
```

Unload it:

```bash
launchctl bootout "gui/$(id -u)" "/Users/$USER/Library/LaunchAgents/com.preppergrid.nomad.agent.plist"
```

Open the admin UI at:

```text
http://localhost:8080
```

## Troubleshooting

If the installer prints that Homebrew is required, install it from https://brew.sh and rerun the installer.

If the installer prints that Docker Desktop is required, install Docker Desktop, open it, wait for it to finish starting, and rerun the installer.

If containers fail to start, check Docker Desktop is running and inspect logs:

```bash
docker compose -p preppergrid-nomad -f /Users/$USER/.preppergrid-nomad/compose.yml --env-file /Users/$USER/.preppergrid-nomad/compose.macos.env logs
```

launchd logs are written to:

```text
/Users/$USER/.preppergrid-nomad/storage/logs/launchd.log
/Users/$USER/.preppergrid-nomad/storage/logs/launchd-error.log
```

Validate the launchd plist:

```bash
xmllint --noout install/com.preppergrid.nomad.agent.plist
```

## ARM64 Availability Note

The upstream Project N.O.M.A.D. image is amd64 only. This fork uses:

```text
ghcr.io/blakek96-dev/preppergrid-nomad:arm64-latest
```

If the ARM64 image is unavailable, edit the installed compose file and add this to the `admin` service to run under Rosetta 2:

```yaml
platform: linux/amd64
```

Docker Desktop must have Rosetta support enabled for amd64 containers on Apple Silicon.

## Building ARM64 Image Locally

The repository includes local ARM64 build helpers for Apple Silicon and other ARM64-capable Docker Buildx environments.

Build the local image:

```bash
scripts/build-arm64.sh
```

The script builds the repository root Docker context for `linux/arm64` and tags the result as:

```text
preppergrid-nomad:local-arm64
preppergrid-nomad:local-arm64-$(git describe --tags --always)
```

On success, it prints the image ID and size from Docker inspect. It also verifies the built image architecture is `arm64`.

To publish the image to GitHub Container Registry, provide GitHub Actions-style credentials in the environment:

```bash
GITHUB_ACTOR=your-github-username GITHUB_TOKEN=your-token scripts/build-and-push.sh
```

The push script logs in to `ghcr.io`, re-tags the local ARM64 image, and publishes:

```text
ghcr.io/blakek96-dev/preppergrid-nomad:arm64-latest
ghcr.io/blakek96-dev/preppergrid-nomad:arm64-$(git describe --tags --always)
```

Do not commit generated auth files, Docker credentials, build logs, or temporary artifacts.

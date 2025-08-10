## Quick Install (Stable Channel)

Installs or upgrades to the latest released version (GitHub Releases). Default install path is `/opt/ticket-printer` (override with `INSTALL_DIR=`):

```sh
curl -fsSL https://raw.githubusercontent.com/mccannical/ticket-printer/main/install.sh | bash
```

## Alternate Channels & Pinning

Channel / version selection is persisted in `~/.ticket-printer/.install_env`.

1. Track development branch (main):
```sh
CHANNEL=main curl -fsSL https://raw.githubusercontent.com/mccannical/ticket-printer/main/install.sh | bash
```

2. Pin a specific release (no auto-upgrades unless you change VERSION):
```sh
VERSION=v1.0.8 curl -fsSL https://raw.githubusercontent.com/mccannical/ticket-printer/main/install.sh | bash
```

3. Switch an existing install:
```sh
cd ~/ticket-printer
CHANNEL=stable ./install.sh          # move to stable
CHANNEL=main ./install.sh            # move to main
VERSION=v1.0.8 ./install.sh          # pin exact version
```

## What the Installer Does
- Clones (or updates) repo under `/opt/ticket-printer` (or custom `INSTALL_DIR`)
- Selects branch/tag based on CHANNEL or VERSION
- Creates/updates Python virtualenv `.venv`
- Installs dependencies from `requirements.txt`
- Prints a diagnostic test ticket
- Installs cron jobs:
	- Hourly self-update (respecting channel/pin)
	- `@reboot` diagnostic ticket
	- Daily 06:00 chores placeholder

Remove cron jobs by deleting lines containing `# ticket-printer managed`:
```sh
crontab -l | grep -v 'ticket-printer managed' | crontab -
```

## Runtime
Service entrypoint (example if installed to /opt):
```sh
PYTHONPATH=/opt/ticket-printer /opt/ticket-printer/.venv/bin/python -m src.main
```

## Project Overview
Python service that identifies a printer instance, gathers environment and printer status, and checks in to a backend endpoint. (Future roadmap: queue consumption & print job handling.)

### Structure
- `src/` – Source code
- `config/` – Generated/persistent data (printer UUID)
- `logs/` – Placeholder for future log routing

### Current Features
- Persistent UUID (stored in `config/printer_uuid.txt`)
- Environment & printer status gathering (lpstat, external IP)
- Payload schema validation (jsonschema)
- Resilient network posting with retries
- Release awareness & update advice
- Startup test ticket
- Channel/version aware installer & auto-update

### Planned / Potential
- Print job queue integration (MQTT/AMQP)
- Structured JSON logging & log shipping
- Health endpoint / watchdog integration
- Graceful shutdown & systemd unit template

### Security & Hardening
- UUID stored in `config/` with 600 file perms (attempted) and directory 700; override with `TICKET_PRINTER_CONFIG_DIR=/var/lib/ticket-printer`.
- Systemd unit template under `systemd/ticket-printer.service` includes restrictive sandboxing directives.
- Installer enforces ownership/user guidance and warns on unsafe invocation patterns.
- Installer sets umask 027, validates remote origin URL, tightens directory/script permissions (750), and separates runtime vs dev dependency files.

## Development

Create environment & run tests:
```sh
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
mise run test
```

Format & lint:
```sh
mise run format
mise run lint
```

Cut new patch release (after tests pass):
```sh
mise run bump-release
```

## Support & Troubleshooting
View current version (git tag):
```sh
git -C ~/ticket-printer describe --tags --abbrev=0 || echo 'on main'
```
Re-run installer with explicit channel:
```sh
CHANNEL=stable /opt/ticket-printer/install.sh
Force reinstall into /opt overwriting existing directory (avoid process substitution with sudo):
```sh
curl -fsSL https://raw.githubusercontent.com/mccannical/ticket-printer/main/install.sh | sudo FORCE_REPLACE=1 PRINTER_USER=printer bash
```
Process substitution form (sudo bash <(curl ...)) can fail on some systems (/dev/fd not propagated); prefer the pipe form above.

Override detected version/user-agent (packaging scenarios):
```sh
TICKET_PRINTER_VERSION=1.2.3 python -m src.main
```

User-Agent automatically reflects the current git tag (without a leading `v`) or the short commit hash if untaged.
```
Ensure system user access (installer will chown recursively if run as root and user exists):
```sh
sudo PRINTER_USER=printer bash install.sh
# or manually after install:
sudo chown -R printer:printer /opt/ticket-printer
```
Check logs (journalctl example if wrapped as a service):
```sh
journalctl -u ticket-printer.service -f
```

## License
MIT (add LICENSE file if distributing).

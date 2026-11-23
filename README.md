# Calagopus-Installer

One command that installs [Calagopus](https://calagopus.com) with Docker: the panel and Wings together
(All-in-One), the panel alone, or a Wings node. It follows the official guides
([Your first VPS](https://calagopus.com/docs/panel/installation/first-vps),
[Docker panel](https://calagopus.com/docs/panel/installation/docker),
[Docker Wings](https://calagopus.com/docs/wings/installation/docker),
[reverse proxy](https://calagopus.com/docs/panel/next-steps/reverse-proxy)) step by step, and can add
free Caloptreyx themes and extensions at the end.

> **Unofficial.** This project is not affiliated with or endorsed by the Calagopus project. Report installer
> problems here, not to Calagopus.

```bash
bash <(curl -sSL https://install.caloptreyx.com)
```

Run it as root: `sudo -i` first. (`sudo bash <(curl ...)` does not work, because sudo closes the descriptor
`<(...)` uses; `curl -sSL https://install.caloptreyx.com | sudo bash` does, with options after `bash -s --`.)
If the short URL is unreachable, use GitHub directly:

```bash
bash <(curl -sSL https://raw.githubusercontent.com/Caloptreyx/Calagopus-Installer/main/install.sh)
```

The script downloads the installer from this repository as one tarball (branch `main`, or the tag in
`CALA_INSTALLER_REF`, e.g. `CALA_INSTALLER_REF=v0.1.0`), so every file comes from the same commit. Everything
it does is logged to `/var/log/calagopus-installer.log` (passwords are never written there).

## Menu

| Option | What it does |
| --- | --- |
| **All-in-One** (default) | Panel and Wings in one container (`compose.aio.yml`). The recommended setup for one server. |
| **Panel only** | The standalone panel (`compose.yml`), for setups with Wings on other hosts. |
| **Wings node** | Wings in Docker (`compose.local.yml`), paired with an existing panel. |
| **Extensions** | Adds Caloptreyx themes/extensions to a panel installed with the heavy image. |
| **Update** | Dumps the database, pulls new images and recreates the containers. `compose.yml` (with its key) and all data stay. |
| **Uninstall** | Stops and removes the containers. Deleting the data needs a second confirmation: typing `DELETE`. |

### All-in-One and Panel only

1. Checks the OS, CPU architecture, RAM, disk and virtualization, and installs `curl`, `openssl`,
   `ca-certificates`, `dig`, `jq`, `unzip` and `ss` if they are missing.
2. Asks for the install directory (default `/opt/calagopus-panel`), time zone, an optional domain, the
   administrator account, the firewall and extensions, then shows a summary.
3. Installs Docker with [get.docker.com](https://get.docker.com) if it is missing.
4. Downloads the official compose file, generates the encryption key with `openssl rand -hex 16`, binds the
   panel to `127.0.0.1:8000`, sets the time zone, and makes `compose.yml` and `wings-config.yml` mode 600.
5. Starts the stack and waits for the panel.
6. Creates the administrator account through the panel's own API while it only listens on `127.0.0.1`, then
   completes the wizard's Configuration step: **Application URL** set to the real address, public
   registration off, passkeys on for a domain. The wizard resumes at **Egg Repositories** when you sign in.
7. Makes the panel reachable:
   - **With a domain**: checks the A/AAAA records against the server's public IP (warns on a mismatch, a
     Cloudflare-proxied record or a stray AAAA record), sets `APP_TRUSTED_PROXIES` to the Docker gateway,
     installs Caddy and writes the reverse-proxy site from the docs. Caddy gets the certificate.
   - **Without a domain**: publishes port 8000 on all addresses (`http://<ip>:8000`) and reminds you that the
     password then crosses the internet in plain text.
8. Optionally configures the firewall, builds the chosen extensions, and prints a summary: the URL, where the
   files are, how to update, the backup reminder and the next steps (allocation, egg, server).

It never regenerates the key: if `compose.yml` already exists, the install stops and offers Update instead.
**Back up `compose.yml`**: it holds the key that decrypts the panel's stored secrets.

If you answer *no* to creating the administrator, the panel stays on `127.0.0.1` and the summary shows the
SSH-tunnel steps from the docs. The panel is never left publicly reachable without an administrator.

### Wings node

Installs Wings to `/opt/calagopus-wings` (config in `config/`, game data in `/var/lib/calagopus-wings`). By
default Wings starts without a configuration and waits for pairing: the installer prints the pairing code
from its log, and you add the node with **Admin → Nodes → Create → Pair a Waiting Node** using
`http://<node-ip>:8080`. Alternatively, paste the Panel URL and enrollment code from the node's
**Configuration → Generate Enrollment Command**: Wings then enrolls on its first start, and the installer
removes the used code from `compose.yml` afterwards.

## Caloptreyx themes and extensions

At the end of the questions for a panel, the installer offers the free themes and extensions published by
[Caloptreyx](https://github.com/Caloptreyx) (Mint Theme, Zoron Theme, Extension Updater, World Map, ...;
[`extensions.tsv`](extensions.tsv) is the list). Choosing any switches the install to the panel's **heavy**
image, which compiles extensions into the panel inside its container:

- The build takes several minutes and needs about **4 GB of RAM** (swap counts). With less, the installer
  refuses unless you confirm (or set `CALA_LOW_MEMORY_OK=yes`), and tells you how to add swap.
- Only one theme can be active: if you pick both Mint and Zoron, it asks which one to install.
- Each pick is the latest GitHub release's `.c7s.zip`, verified against its `.sha256` asset or GitHub's own
  checksum, and checked to contain the expected package.
- The archives go into the panel's `build/extensions` directory, the way the docs describe for Docker; the
  panel builds them and switches to the new build by itself. The installer waits for the build and reports
  the result (the panel keeps running on its previous build if it fails).

The list is kept current by CI: a weekly check fails when a Caloptreyx extension release is missing from
`extensions.tsv` or a listed one disappears.

## Supported systems

| OS | Versions | Architectures |
| --- | --- | --- |
| Ubuntu | 22.04, 24.04, 26.04 | x86_64, ARM64 |
| Debian | 12, 13 | x86_64, ARM64 |
| Rocky Linux, AlmaLinux | 9, 10 | x86_64, ARM64 |

Other systems are refused with a message; `CALA_SKIP_OS_CHECK=yes` tries anyway. The installer warns on
OpenVZ and LXC (Docker in LXC needs nesting). Minimum: 1 GB RAM and 5 GB free disk (15 GB with extensions);
the docs' example VPS has 2 vCPUs, 4 GB RAM and 40 GB disk.

## Firewall

Optional. On Debian/Ubuntu it uses `ufw`, on the RHEL family `firewalld`, and opens: the SSH port(s) it
detects (or `CALA_SSH_PORT`), 80/443 with a domain or 8000 without, 2022 for SFTP (All-in-One and Wings), 8080
for Wings nodes, and the game ports you enter (TCP and UDP). Note that **Docker's published ports bypass the
host firewall**, as the docs say: your provider's firewall is what really protects them.

## Non-interactive use

Every question has a `CALA_*` variable and an option (`--domain x` is the same as `CALA_DOMAIN=x`). With
`--non-interactive` (or no terminal) the installer never prompts and stops if a required answer is missing.

```bash
curl -sSL https://install.caloptreyx.com | sudo CALA_ADMIN_EMAIL=me@example.com CALA_ADMIN_USERNAME=admin \
  CALA_ADMIN_PASSWORD='a long password' bash -s -- aio --non-interactive --domain panel.example.com
```

| Variable | Meaning |
| --- | --- |
| `CALA_ACTION` | `aio`, `panel`, `wings`, `extensions`, `update`, `uninstall` (or the first argument) |
| `CALA_PANEL_DIR` / `CALA_WINGS_DIR` | Install directories (`/opt/calagopus-panel`, `/opt/calagopus-wings`) |
| `CALA_TIMEZONE` | Container time zone (default: the host's) |
| `CALA_DOMAIN` | Domain for HTTPS; empty = no domain |
| `CALA_PUBLIC_IP` | Public IPv4 (default: detected) |
| `CALA_IGNORE_DNS` | `yes` = continue when DNS does not point here |
| `CALA_CREATE_ADMIN` | `yes` (default) or `no` (panel stays on 127.0.0.1) |
| `CALA_ADMIN_EMAIL`, `CALA_ADMIN_USERNAME`, `CALA_ADMIN_PASSWORD` | The first administrator |
| `CALA_FIREWALL` | `yes` / `no` (default no) |
| `CALA_SSH_PORT`, `CALA_GAME_PORTS` | Ports for the firewall, e.g. `22`, `25565,25570-25580` |
| `CALA_EXTENSIONS` | Comma list of keys from `extensions.tsv`, `all` or `none` |
| `CALA_THEME` | The theme to keep when `CALA_EXTENSIONS` names two |
| `CALA_LOW_MEMORY_OK` | `yes` = build extensions with less than 4 GB |
| `CALA_EXTENSION_TIMEOUT` | Seconds to wait for the extension build (3600) |
| `CALA_WINGS_PANEL_URL`, `CALA_WINGS_ENROLL_CODE` | Enroll a Wings node instead of pairing |
| `CALA_UPDATE_BACKUP` | `yes` (default) / `no`: database dump before an update |
| `CALA_UNINSTALL_CONFIRM` | `yes` is required to uninstall without prompts |
| `CALA_REMOVE_DATA`, `CALA_REMOVE_DATA_CONFIRM` | `yes` and `DELETE` to delete all data |
| `CALA_SKIP_OS_CHECK`, `CALA_SKIP_REQUIREMENTS` | `yes` = run on an unsupported OS / below the minimum |
| `CALA_PANEL_TIMEOUT` | Seconds to wait for the panel to start (900) |
| `CALA_INSTALLER_REF` | Branch or tag of this repository the one-liner downloads (`main`) |
| `CALA_LOG_FILE` | Log file (`/var/log/calagopus-installer.log`) |
| `--dry-run` | Detect the system and install the prerequisites, then stop before Docker |

`install.sh --help` prints the same list.

## Security notes

- The panel listens only on `127.0.0.1` until the administrator exists; the installer creates the account
  over that loopback address, then turns public registration off before opening the port.
- The admin password is passed to the panel in a request body read from a private temporary file, never on a
  command line, and is not logged.
- `compose.yml` (encryption key) and `wings-config.yml` are mode 600, as is the log.
- Downloads come from the official sources (get.docker.com, the calagopus/panel and calagopus/wings
  repositories, Caddy's package repositories, Caloptreyx GitHub releases) over HTTPS; extension archives are
  checksum-verified when the release publishes a checksum.
- Without a domain the panel is plain HTTP: limit port 8000 to your IP in the provider's firewall and enable
  two-factor authentication.

## Uninstall

Choose **Uninstall** in the menu (or `install.sh uninstall`). It removes the containers and, with the
installer's Caddy site, takes that site out of the Caddyfile. Data is kept unless you also answer yes to
deleting it **and** type `DELETE`; then the install directory, the database, Wings' configuration and every
game server's files (`/var/lib/calagopus-wings`) are deleted. Docker, the Caddy package and firewall rules stay.

## Development

```bash
bash tests/run.sh          # unit tests of the pure functions (no root, Docker or network)
bash tests/upstream.sh     # the compose edits still apply to the live upstream files
bash tests/catalog.sh      # extensions.tsv matches the released Caloptreyx extensions
shellcheck install.sh tests/run.sh && shellcheck -e SC2034 lib/*.sh installers/*.sh ui/*.sh
shfmt -d .
```

Never run the installer itself on a machine you care about. CI (`.github/workflows/check.yml`) runs the dry run
in Debian 12/13, Ubuntu 22.04/24.04/26.04, Rocky Linux 9 and AlmaLinux 9/10 containers, and real All-in-One,
Wings and extension installs (with update and uninstall) on a fresh runner.

To try it on a real, disposable machine for free: a local VM with [Multipass](https://multipass.run)
(`multipass launch 24.04 --cpus 2 --memory 4G --disk 30G`) or the cloud images of Debian/Rocky in QEMU or
VirtualBox.

## License

[MIT](LICENSE)

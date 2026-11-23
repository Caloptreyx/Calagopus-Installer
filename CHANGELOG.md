# Changelog

## Unreleased

- The one-liner exited with status 1 (and printed `tmp: unbound variable`) after the installer finished,
  whatever the installer's own status, and left its download in `/tmp`. It now passes the installer's exit
  status through and removes the download.

## 0.1.0 (2026-11-23)

First version.

- One-command installer: `bash <(curl -sSL https://install.caloptreyx.com)`, which always serves the latest
  published release (the `stable` branch, moved by `.github/workflows/stable.yml`). The bootstrapper downloads
  the installer as one tarball at its own release tag (`CALA_INSTALLER_REF` overrides it, e.g. `main`).
- Menu: All-in-One (default), Panel only, Wings node, Extensions, Update, Uninstall. Docker only.
- Follows the official guides: Docker from get.docker.com, the official compose files, `openssl rand -hex 16`
  encryption key, panel bound to 127.0.0.1 until the administrator exists, `chmod 600` on compose.yml and
  wings-config.yml, refuses to install over an existing install.
- Creates the first administrator over the loopback API and sets the Application URL, turns public
  registration off and enables passkeys for a domain.
- Optional HTTPS: DNS checks (A/AAAA against the public IP, Cloudflare proxy, stray AAAA), Caddy with the docs'
  reverse-proxy site, `APP_TRUSTED_PROXIES` set to the Docker gateway.
- Optional firewall: ufw (Debian/Ubuntu) or firewalld (Rocky/AlmaLinux), keeping the detected SSH port(s) open.
- Wings node: pairing-code mode, or enrollment with the panel URL and code.
- Optional Caloptreyx themes/extensions on the heavy image: checksum-verified latest releases, one theme at
  a time, memory check (about 4 GB), waits for the build and reports its result.
- Update with a database dump first; uninstall with a typed second confirmation before deleting data.
- Supported: Ubuntu 22.04/24.04/26.04, Debian 12/13, Rocky Linux and AlmaLinux 9/10, x86_64 and ARM64.
- Non-interactive mode: every prompt has a `CALA_*` variable and `--option`; `--dry-run` stops before Docker.
- Log at `/var/log/calagopus-installer.log`; on failure the last lines and the troubleshooting link are shown.

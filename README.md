# OpenWRT Telegram Bot

[![shellcheck](https://github.com/Danrrodrigues/OpenWRT-Telegram-Bot/actions/workflows/lint.yml/badge.svg)](https://github.com/Danrrodrigues/OpenWRT-Telegram-Bot/actions/workflows/lint.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Control and monitor your home network directly from Telegram. Runs as a lightweight shell script on the router itself — no external server required.

**[🇧🇷 Leia em Português](README.pt-BR.md)**

---

## Features

- [x] 🔔 Alert when a new device joins the network
- [x] 📋 List all connected devices (name, IP, MAC)
- [x] ⚡ Disconnect (kick) a device from Wi-Fi
- [x] 🚫 Block a device permanently (persists across reboots)
- [x] 📶 Limit a device's download/upload speed
- [x] 📊 Router status (CPU, RAM, uptime)
- [x] 🔄 Update and rollback the bot remotely via Telegram
- [ ] 📈 Per-device bandwidth usage (planned)
- [ ] ⏰ Scheduled blocks (planned)

---

## Requirements

- OpenWRT 23.05 or later
- `curl` (installed automatically if missing)
- `jsonfilter` (usually pre-installed on OpenWRT)
- A Telegram bot token from [@BotFather](https://t.me/BotFather)

---

## Quick Start

```sh
# 1. SSH into your router
ssh root@192.168.1.1

# 2. Install curl (not present by default on OpenWRT)
opkg update && opkg install curl

# 3. Download
cd /tmp
curl -L https://github.com/Danrrodrigues/OpenWRT-Telegram-Bot/archive/refs/heads/main.tar.gz -o bot.tar.gz
tar xzf bot.tar.gz
cd OpenWRT-Telegram-Bot-main

# 4. Install
sh install.sh
```

**To update via Telegram** (no SSH needed):
```
/update
/update confirm
```

**To update via SSH** (config is preserved):
```sh
cd /tmp
curl -L https://github.com/Danrrodrigues/OpenWRT-Telegram-Bot/archive/refs/heads/main.tar.gz -o bot.tar.gz
tar xzf bot.tar.gz
cd OpenWRT-Telegram-Bot-main && sh install.sh update
```

**To reconfigure** (change token, chat ID, or run mode):
```sh
sh /usr/lib/telegram-bot/install.sh reconfigure
```

See [docs/installation.md](docs/installation.md) for the full guide.

---

## Commands

| Command | Description |
|---------|-------------|
| `/devices` | List connected devices |
| `/kick <MAC or IP>` | Disconnect from Wi-Fi |
| `/name <MAC> <hostname>` | Save a friendly device name by MAC |
| `/block <MAC>` | Block permanently |
| `/unblock <MAC>` | Remove block |
| `/limit <MAC> <↓Mbps> <↑Mbps>` | Set speed limit |
| `/unlimit <MAC>` | Remove speed limit |
| `/status` | Router status |
| `/alerts off\|known\|unknown\|all` | Set device alert mode |
| `/update` | Check for updates (`/update confirm` to apply) |
| `/rollback` | Restore previous version (`/rollback confirm` to apply) |
| `/help` | Show all commands |

Example:

```sh
/name 92:27:f0:1a:66:6c celular-marcia
```

Device names resolve in this order: static OpenWRT DHCP host name for the MAC, DHCP lease hostname, then `Unknown`.

See [docs/commands.md](docs/commands.md) for examples.

---

## Architecture

```
src/
├── bot.sh            — Entry point: daemon loop or cron runner
├── core/
│   ├── device_identity.sh — Static DHCP host names + hostname rendering
│   ├── telegram.sh   — Telegram API (getUpdates, sendMessage)
│   ├── config.sh     — UCI config read/write
│   └── logger.sh     — Logging to syslog + file
└── modules/
    ├── monitor.sh    — New device detection (/tmp/dhcp.leases)
    ├── devices.sh    — List / kick / block / status
    ├── bandwidth.sh  — Speed limiting (nft-qos or tc)
    └── updater.sh    — Remote update and rollback via Telegram
```

- **Zero extra packages** — only `curl` and `jsonfilter` are required
- **UCI config** at `/etc/config/telegram-bot` (chmod 600)
- **Daemon or cron** — configurable at install time
- **nft-qos or tc fallback** for speed limiting

---

## Configuration

```sh
# View config
uci show telegram-bot

# Change alert mode (off / known / unknown / all)
uci set telegram-bot.bot.alert_mode='unknown'
uci commit telegram-bot

# Restart service
/etc/init.d/telegram-bot restart

# View logs
logread -e telegram-bot
```

See [docs/configuration.md](docs/configuration.md) for all options.

---

## Changelog

- `v0.2.2` — Fixed all shellcheck warnings across the codebase (real `A && B || C` bugs, non-POSIX `echo -n`, dead test code), pinned CI shellcheck to v0.11.0 to match the local pre-push hook, and added a pre-push hook that runs shellcheck before pushing.
- `v0.2.1` — Added device alert modes (`off|known|unknown|all`), active Wi-Fi presence detection for reconnect alerts, `/name <MAC> <hostname>`, static OpenWRT hostname priority, and the installer fix for `core/device_identity.sh`.

---

## Tested Hardware

| Router | OpenWRT | Status |
|--------|---------|--------|
| Xiaomi AX3000T (RD03) | 24.10.2 | ✅ |

Contributions for other routers are welcome.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). All scripts must pass `shellcheck --shell=sh` with zero warnings.

---

## License

[MIT](LICENSE)

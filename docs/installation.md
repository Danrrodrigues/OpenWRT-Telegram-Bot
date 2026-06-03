# Installation Guide

## Prerequisites

- A router running **OpenWRT 23.05 or later**
- SSH access to the router
- A Telegram account

## Step 1 — Create a Telegram Bot

1. Open Telegram and search for **@BotFather**
2. Send `/newbot` and follow the prompts
3. Copy the **bot token** (format: `123456789:ABCdef...`)

## Step 2 — Get Your Chat ID

1. Search for **@userinfobot** on Telegram
2. Send `/start`
3. Copy your **chat ID** (a number like `987654321`)

## Step 3 — Install curl

`curl` is not installed by default on OpenWRT. Install it first:

```sh
opkg update && opkg install curl
```

> **Note:** `opkg update` requires internet access on the router (WAN connected).

## Step 4 — Download the Bot

```sh
cd /tmp
curl -L https://github.com/Danrrodrigues/OpenWRT-Telegram-Bot/archive/refs/tags/v0.1.0.tar.gz | tar xz
cd OpenWRT-Telegram-Bot-0.1.0
```

> GitHub strips the `v` from tag names in archive folders — the directory will be `OpenWRT-Telegram-Bot-0.1.0`, not `v0.1.0`.

## Step 5 — Run the Installer

```sh
sh install.sh
```

The installer will:
- Check for `jsonfilter` (installs via opkg if missing)
- Ask for your bot token and chat ID
- Ask whether to run as a daemon or cron job
- Copy scripts to `/usr/lib/telegram-bot/`
- Write config to `/etc/config/telegram-bot` (with restricted permissions)
- Set up the service or cron job

## Step 6 — Test

Send `/start` to your bot on Telegram. You should receive the welcome message.

```sh
# Check logs if something doesn't work
logread -e telegram-bot
```

## Run Modes

### Daemon (recommended)

The bot runs as a persistent background service managed by procd:

```sh
/etc/init.d/telegram-bot status
/etc/init.d/telegram-bot restart
```

Response time: ~2 seconds.

### Cron

The bot runs every minute via cron:

```sh
crontab -l | grep telegram
```

Response time: up to 60 seconds.

## Manual Configuration

Config is stored in UCI format at `/etc/config/telegram-bot`:

```sh
# View current config (token is hidden)
uci show telegram-bot

# Change poll interval
uci set telegram-bot.bot.poll_interval=15
uci commit telegram-bot

# Toggle alerts
uci set telegram-bot.bot.alerts=0
uci commit telegram-bot
```

## Uninstall

```sh
sh /tmp/bot/uninstall.sh
```

## Tested Hardware

| Router | OpenWRT | Status |
|--------|---------|--------|
| Xiaomi AX3000T (RD03) | 24.10.2 | ✅ Tested |
| Generic (MT7981) | 23.05+ | ✅ Expected to work |

Contributions for other hardware are welcome!

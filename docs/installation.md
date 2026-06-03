# Installation Guide

## Prerequisites

- A router running **OpenWRT 23.05 or later**
- SSH access to the router
- A Telegram account

---

## Step 1 — Create a Telegram Bot

1. Open Telegram and search for **@BotFather**
2. Send `/newbot` and follow the prompts
3. Copy the **bot token** (format: `123456789:ABCdef...`)

## Step 2 — Get Your Chat ID

1. Open Telegram and search for **@userinfobot**
2. Send `/start`
3. Copy your **chat ID** (a number like `987654321`)

## Step 3 — Install curl

`curl` is not installed by default on OpenWRT:

```sh
opkg update && opkg install curl
```

## Step 4 — Download and Install

```sh
cd /tmp
curl -L https://github.com/Danrrodrigues/OpenWRT-Telegram-Bot/archive/refs/heads/main.tar.gz -o bot.tar.gz
tar xzf bot.tar.gz
cd OpenWRT-Telegram-Bot-main
sh install.sh
```

The installer will ask for:
1. **Bot Token** — from @BotFather
2. **Chat ID** — from @userinfobot
3. **Run mode** — `d` for daemon (recommended) or `c` for cron

## Step 5 — Test

Send `/start` to your bot on Telegram. You should receive the welcome message.

```sh
# View logs
logread -e telegram-bot
```

---

## Updating

Download the latest version and run `update` — your config is preserved:

```sh
cd /tmp
curl -L https://github.com/Danrrodrigues/OpenWRT-Telegram-Bot/archive/refs/heads/main.tar.gz -o bot.tar.gz
tar xzf bot.tar.gz
cd OpenWRT-Telegram-Bot-main
sh install.sh update
```

## Reconfiguring

Change token, chat ID, or run mode without reinstalling:

```sh
sh /usr/lib/telegram-bot/install.sh reconfigure
```

## Uninstalling

```sh
sh /usr/lib/telegram-bot/uninstall.sh
```

---

## Run Modes

| Mode | How it works | Response time |
|------|-------------|---------------|
| **daemon** (recommended) | Runs as a persistent service (procd) | ~2 seconds |
| **cron** | Runs once per minute via cron | up to 60 seconds |

```sh
# Daemon: start / stop / restart
/etc/init.d/telegram-bot start
/etc/init.d/telegram-bot stop
/etc/init.d/telegram-bot restart
```

---

## Manual Configuration

Config is stored at `/etc/config/telegram-bot`:

```sh
# View current config
uci show telegram-bot

# Change a value
uci set telegram-bot.bot.poll_interval=15
uci commit telegram-bot
/etc/init.d/telegram-bot restart
```

See [configuration.md](configuration.md) for all available options.

---

## Tested Hardware

| Router | OpenWRT | Status |
|--------|---------|--------|
| Xiaomi AX3000T (RD03) | 24.10.2 | ✅ Tested |

Contributions for other hardware are welcome!

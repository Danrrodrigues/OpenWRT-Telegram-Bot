# Security Policy

## Supported Versions

Only the latest release on the `main` branch receives security fixes.

| Version | Supported          |
| ------- | ------------------ |
| latest (`main`) | :white_check_mark: |
| older releases  | :x:                |

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues.**

This bot runs with `root` privileges on your router and handles a Telegram bot
token, so security reports are taken seriously.

Instead, report privately through one of these channels:

1. **Preferred:** GitHub's private vulnerability reporting —
   [open a draft advisory](https://github.com/Danrrodrigues/OpenWRT-Telegram-Bot/security/advisories/new).
2. Email the maintainer: **danrrodrigues@gmail.com**.

Please include:

- A description of the vulnerability and its impact
- Steps to reproduce (router model, OpenWRT version, config if relevant)
- Any suggested fix, if you have one

You can expect an initial response within **7 days**. Once the issue is
confirmed, a fix will be prepared and released, and you will be credited in the
advisory unless you prefer to remain anonymous.

## Hardening Notes

When running this bot, keep in mind:

- The config file at `/etc/config/telegram-bot` holds your bot token and is
  created with `chmod 600`. Do not loosen those permissions.
- Restrict the bot to known chat IDs (`BOT_CHAT_IDS`); never leave it open.
- Treat your Telegram bot token like a password. If it leaks, revoke it via
  [@BotFather](https://t.me/BotFather) immediately.

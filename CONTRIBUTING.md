# Contributing

Thank you for your interest in contributing to OpenWRT Telegram Bot!

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/OpenWRT-Telegram-Bot`
3. Create a branch: `git checkout -b feat/my-feature`

## Development Setup

You don't need a physical router to develop. You can test shell logic locally:

```sh
# Install shellcheck (required)
# macOS: brew install shellcheck
# Ubuntu: apt install shellcheck
# Windows: choco install shellcheck

# Check all scripts
shellcheck --shell=sh src/**/*.sh install.sh uninstall.sh
```

To test Telegram API calls without a router, you can mock the dependencies:

```sh
# Create a mock curl that logs calls instead of making HTTP requests
cat > /tmp/curl <<'EOF'
#!/bin/sh
echo "[mock curl] $*" >&2
echo '{"ok":true,"result":[]}'
EOF
chmod +x /tmp/curl

# Override PATH
export PATH="/tmp:$PATH"
export BOT_TOKEN="test_token"
export BOT_CHAT_IDS="12345"
export FALLBACK_CONFIG="/tmp/bot-test.conf"
```

## Code Standards

- **POSIX sh only** — no bashisms (`[[ ]]`, arrays, `source`, etc.)
- **Zero shellcheck warnings** — run before every commit
- **Single responsibility** — one function does one thing
- **Input validation** — sanitize all arguments from Telegram messages
- **No credentials** — never hardcode tokens or chat IDs

See `.github/AGENTS.md` for the full style guide.

## Adding a New Command

1. Decide which module it belongs to (`devices.sh`, `bandwidth.sh`, `monitor.sh`) or create a new one in `src/modules/`
2. Implement the function following the `<module>_<action>` naming convention
3. Add the command to the `_bot_dispatch` case statement in `src/bot.sh`
4. Document it in `docs/commands.md` (English + Portuguese)
5. Update `_bot_send_help` in `src/bot.sh`
6. Update `README.md` and `README.pt-BR.md`

## Pull Request Process

1. Ensure `shellcheck` passes with zero warnings
2. Update documentation for any changed behavior
3. Fill out the PR template
4. Request review from maintainers

## Reporting Bugs

Use the [bug report template](.github/ISSUE_TEMPLATE/bug_report.md).
Include your router model, OpenWRT version, and `logread -e telegram-bot` output.

## Questions

Open a [Discussion](https://github.com/Danrrodrigues/OpenWRT-Telegram-Bot/discussions) for questions, ideas, or general feedback.

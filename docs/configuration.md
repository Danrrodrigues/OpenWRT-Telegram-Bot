# Configuration Reference

Config is stored in OpenWRT UCI format at `/etc/config/telegram-bot`.

## Full Config File

```
config telegram 'bot'
    option token        'YOUR_BOT_TOKEN'
    option chat_ids     '123456789'
    option mode         'daemon'
    option alerts       '1'
    option alert_mode   'all'
    option poll_interval '30'
    option log_level    'info'

config rules 'rules'
    list blocked        'aa:bb:cc:dd:ee:ff'
    list limited        'aa:bb:cc:dd:ee:ff:10000:5000'
```

## Options

### `token` (required)

Your Telegram bot token from @BotFather.

```sh
uci set telegram-bot.bot.token='123456789:ABCdef...'
uci commit telegram-bot
```

### `chat_ids` (required)

Space-separated list of authorized Telegram chat IDs. Only these IDs can send commands.

```sh
# Single user
uci set telegram-bot.bot.chat_ids='987654321'

# Multiple users
uci set telegram-bot.bot.chat_ids='987654321 111222333'

uci commit telegram-bot
```

### `mode`

`daemon` (default) or `cron`.

- **daemon**: bot runs as a persistent service. Response time ~2 seconds.
- **cron**: bot runs once per minute. Response time up to 60 seconds.

```sh
uci set telegram-bot.bot.mode='daemon'
uci commit telegram-bot
/etc/init.d/telegram-bot restart
```

### `alerts`

`1` (enabled, default) or `0` (disabled). Controls new device join notifications.

Can also be toggled at runtime with `/alerts on` or `/alerts off`.

### `alert_mode`

- `all` (default): alert for every new DHCP lease.
- `unknown`: alert only for devices never seen before (persistent list in `/etc/telegram-bot-seen-devices`).

```sh
uci set telegram-bot.bot.alert_mode='unknown'
uci commit telegram-bot
```

### `poll_interval`

Seconds between device monitoring checks in daemon mode (default: `30`).

### `log_level`

`debug`, `info` (default), `warn`, or `error`.

```sh
# Enable debug logging temporarily
uci set telegram-bot.bot.log_level='debug'
uci commit telegram-bot
/etc/init.d/telegram-bot restart
logread -f -e telegram-bot
```

## Viewing Logs

```sh
# All bot logs
logread -e telegram-bot

# Follow logs in real time
logread -f -e telegram-bot

# Log file (if configured)
cat /var/log/telegram-bot.log
```

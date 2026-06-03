# Command Reference

All commands are sent as Telegram messages to your bot.

| Command | Description (EN) | Descrição (PT-BR) |
|---------|-----------------|-------------------|
| `/start` | Show welcome message and command list | Exibe boas-vindas e lista de comandos |
| `/help` | Show command reference | Exibe referência de comandos |
| `/devices` | List all connected devices | Lista dispositivos conectados |
| `/status` | Show router status (CPU, RAM, uptime) | Status do roteador (CPU, RAM, tempo ligado) |
| `/alerts on` | Enable new device notifications | Ativa alertas de novo dispositivo |
| `/alerts off` | Disable new device notifications | Desativa alertas de novo dispositivo |
| `/kick <MAC or IP>` | Disconnect device from Wi-Fi | Desconecta dispositivo do Wi-Fi |
| `/block <MAC>` | Block device permanently | Bloqueia dispositivo permanentemente |
| `/unblock <MAC>` | Remove permanent block | Remove bloqueio permanente |
| `/limit <MAC> <↓Mbps> <↑Mbps>` | Set download/upload speed limit | Define limite de velocidade de download/upload |
| `/unlimit <MAC>` | Remove speed limit | Remove limite de velocidade |

## Examples / Exemplos

### /devices

```
Connected Devices

1. MyPhone
   IP: 192.168.1.100
   MAC: aa:bb:cc:dd:ee:ff

2. SmartTV
   IP: 192.168.1.101
   MAC: 11:22:33:44:55:66
```

### /kick

```sh
# By MAC
/kick aa:bb:cc:dd:ee:ff

# By IP
/kick 192.168.1.100
```

### /block and /unblock

```sh
# Block
/block aa:bb:cc:dd:ee:ff

# Unblock
/unblock aa:bb:cc:dd:ee:ff
```

Blocks persist across reboots.

### /limit and /unlimit

```sh
# Limit to 10 Mbps down, 5 Mbps up
/limit aa:bb:cc:dd:ee:ff 10 5

# Remove limit
/unlimit aa:bb:cc:dd:ee:ff
```

Speed values are in **Mbps** (megabits per second).

Limits persist across reboots.

### /status

```
Router Status

Uptime: 3 days, 14:22:07
Load: 0.12 0.08 0.05
Memory: 45/256 MB
Connected devices: 8
```

## New Device Alert / Alerta de Novo Dispositivo

When a new device joins the network:

```
🔔 New device connected

Name: Johns-iPhone
IP: 192.168.1.115
MAC: de:ad:be:ef:00:01
Time: 2026-06-03 14:35:22
```

Toggle with `/alerts on` or `/alerts off`.

# Command Reference

All commands are sent as Telegram messages to your bot.

| Command | Description (EN) | Descrição (PT-BR) |
|---------|-----------------|-------------------|
| `/start` | Show welcome message and command list | Exibe boas-vindas e lista de comandos |
| `/help` | Show command reference | Exibe referência de comandos |
| `/devices` | List all connected devices | Lista dispositivos conectados |
| `/status` | Show router status (CPU, RAM, uptime) | Status do roteador (CPU, RAM, tempo ligado) |
| `/alerts off` | Disable device notifications | Desativa notificações de dispositivos |
| `/alerts known` | Notify only known device reconnections | Notifica apenas reconexões de dispositivos conhecidos |
| `/alerts unknown` | Notify only first-time devices | Notifica apenas dispositivos vistos pela primeira vez |
| `/alerts all` | Notify first-time devices and reconnections | Notifica dispositivos novos e reconexões |
| `/kick <MAC or IP>` | Disconnect device from Wi-Fi | Desconecta dispositivo do Wi-Fi |
| `/name <MAC> <hostname>` | Save a friendly device name by MAC | Salva um nome amigável de dispositivo por MAC |
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

### /name

```sh
/name 92:27:f0:1a:66:6c celular-marcia
```

Saves a friendly device name by MAC in the OpenWRT DHCP config, without assigning a fixed IP.

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

Modes:

```sh
/alerts off
/alerts known
/alerts unknown
/alerts all
```

Compatibility shortcut: `/alerts on` still maps to `/alerts all`.

## Hostname Resolution / Resolucao de Nome

Device names are resolved in this order:

1. Static OpenWRT DHCP host name for the MAC
2. DHCP lease hostname
3. `Unknown`

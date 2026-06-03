# OpenWRT Telegram Bot

[![shellcheck](https://github.com/Danrrodrigues/OpenWRT-Telegram-Bot/actions/workflows/lint.yml/badge.svg)](https://github.com/Danrrodrigues/OpenWRT-Telegram-Bot/actions/workflows/lint.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Controle e monitore sua rede doméstica diretamente pelo Telegram. Roda como um script shell leve no próprio roteador — sem necessidade de servidor externo.

**[🇺🇸 Read in English](README.md)**

---

## Funcionalidades

- [x] 🔔 Alerta quando um novo dispositivo entra na rede
- [x] 📋 Lista todos os dispositivos conectados (nome, IP, MAC)
- [x] ⚡ Desconectar (kick) um dispositivo do Wi-Fi
- [x] 🚫 Bloquear um dispositivo permanentemente (persiste após reinicialização)
- [x] 📶 Limitar velocidade de download/upload de um dispositivo
- [x] 📊 Status do roteador (CPU, RAM, tempo ligado)
- [ ] 📈 Uso de banda por dispositivo (planejado)
- [ ] ⏰ Bloqueios agendados (planejado)

---

## Requisitos

- OpenWRT 23.05 ou superior
- `curl` (instalado automaticamente se ausente)
- `jsonfilter` (geralmente pré-instalado no OpenWRT)
- Token de bot Telegram do [@BotFather](https://t.me/BotFather)

---

## Instalação Rápida

```sh
# 1. Acesse o roteador via SSH
ssh root@192.168.1.1

# 2. Instale o curl (não vem instalado por padrão no OpenWRT)
opkg update && opkg install curl

# 3. Baixe o projeto (use a tag de release — mais confiável que a URL da branch)
cd /tmp
curl -L https://github.com/Danrrodrigues/OpenWRT-Telegram-Bot/archive/refs/tags/v0.1.0.tar.gz | tar xz
cd OpenWRT-Telegram-Bot-v0.1.0

# 4. Execute o instalador
sh install.sh

# 5. Siga os passos (token + chat ID) e envie /start ao seu bot
```

Veja o guia completo em [docs/installation.md](docs/installation.md).

---

## Comandos

| Comando | Descrição |
|---------|-----------|
| `/devices` | Lista dispositivos conectados |
| `/kick <MAC ou IP>` | Desconecta do Wi-Fi |
| `/block <MAC>` | Bloqueia permanentemente |
| `/unblock <MAC>` | Remove o bloqueio |
| `/limit <MAC> <↓Mbps> <↑Mbps>` | Define limite de velocidade |
| `/unlimit <MAC>` | Remove o limite |
| `/status` | Status do roteador |
| `/alerts on\|off` | Ativa/desativa alertas de novo dispositivo |
| `/help` | Mostra todos os comandos |

Veja exemplos em [docs/commands.md](docs/commands.md).

---

## Arquitetura

```
src/
├── bot.sh            — Ponto de entrada: loop daemon ou execução por cron
├── core/
│   ├── telegram.sh   — API do Telegram (getUpdates, sendMessage)
│   ├── config.sh     — Leitura/escrita de config UCI
│   └── logger.sh     — Log para syslog e arquivo
└── modules/
    ├── monitor.sh    — Detecção de novo dispositivo (/tmp/dhcp.leases)
    ├── devices.sh    — Listar / kick / bloquear / status
    └── bandwidth.sh  — Limite de velocidade (nft-qos ou tc)
```

- **Zero pacotes extras** — apenas `curl` e `jsonfilter` são necessários
- **Config UCI** em `/etc/config/telegram-bot` (chmod 600)
- **Daemon ou cron** — configurável na instalação
- **nft-qos ou fallback tc** para limitação de velocidade

---

## Configuração

```sh
# Ver configuração atual
uci show telegram-bot

# Mudar modo de alerta (all = todos / unknown = apenas novos)
uci set telegram-bot.bot.alert_mode='unknown'
uci commit telegram-bot

# Reiniciar serviço
/etc/init.d/telegram-bot restart

# Ver logs
logread -e telegram-bot
```

Veja todas as opções em [docs/configuration.md](docs/configuration.md).

---

## Hardware Testado

| Roteador | OpenWRT | Status |
|----------|---------|--------|
| Xiaomi AX3000T (RD03) | 24.10.2 | ✅ |

Contribuições para outros roteadores são bem-vindas.

---

## Contribuindo

Veja [CONTRIBUTING.md](CONTRIBUTING.md). Todos os scripts devem passar no `shellcheck --shell=sh` sem avisos.

---

## Licença

[MIT](LICENSE)

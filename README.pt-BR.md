# OpenWRT Telegram Bot

[![shellcheck](https://github.com/Danrrodrigues/OpenWRT-Telegram-Bot/actions/workflows/lint.yml/badge.svg)](https://github.com/Danrrodrigues/OpenWRT-Telegram-Bot/actions/workflows/lint.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Controle e monitore sua rede doméstica diretamente pelo Telegram. Roda como um script shell leve no próprio roteador — sem necessidade de servidor externo.

**[🇺🇸 Read in English](README.md)**

---

> ## ⚠️ Beta — use por sua conta e risco
>
> Este projeto está em **beta** e em desenvolvimento ativo. Ele escreve nas
> configurações de **firewall** (`nftables`/`fw4`), Wi-Fi e sistema do seu
> roteador. Uma alteração ruim pode derrubar sua rede — incluindo a internet de
> todos os dispositivos conectados.
>
> **Use por sua conta e risco.** É altamente recomendável que você tenha bom
> **domínio técnico** do OpenWRT: saber acessar o roteador por **SSH**, ler e
> recarregar o **firewall** (`fw4`/`nft`) e recuperar o aparelho manualmente
> (ex.: modo failsafe) caso algo dê errado. Garanta sempre uma forma de voltar a
> acessar o roteador antes de instalar. Sem nenhuma garantia — veja o
> [LICENSE](LICENSE).

---

## Funcionalidades

- [x] 🔔 Alerta quando um novo dispositivo entra na rede
- [x] 📋 Lista todos os dispositivos conectados (nome, IP, MAC)
- [x] ⚡ Desconectar (kick) um dispositivo do Wi-Fi
- [x] 🌙 Acordar um dispositivo com Wake-on-LAN
- [x] 🚫 Bloquear um dispositivo permanentemente (persiste após reinicialização)
- [x] 📶 Limitar velocidade de download/upload de um dispositivo
- [x] 📊 Status do roteador (CPU, RAM, tempo ligado)
- [x] 🔄 Atualizar e fazer rollback do bot remotamente pelo Telegram
- [ ] 📈 Uso de banda por dispositivo (planejado)
- [ ] ⏰ Bloqueios agendados (planejado)

---

## Requisitos

- OpenWRT 23.05 ou superior
- `curl` (instalado automaticamente se ausente)
- `jsonfilter` (geralmente pré-instalado no OpenWRT)
- `etherwake` (opcional, necessário para `/wake`)
- Token de bot Telegram do [@BotFather](https://t.me/BotFather)

---

## Instalação Rápida

```sh
# 1. Acesse o roteador via SSH
ssh root@192.168.1.1

# 2. Instale o curl (não vem instalado por padrão no OpenWRT)
opkg update && opkg install curl

# 3. Baixe o projeto
cd /tmp
curl -L https://github.com/Danrrodrigues/OpenWRT-Telegram-Bot/archive/refs/heads/main.tar.gz -o bot.tar.gz
tar xzf bot.tar.gz
cd OpenWRT-Telegram-Bot-main

# 4. Execute o instalador
sh install.sh
```

**Para atualizar pelo Telegram** (sem necessidade de SSH):
```
/update
/update confirm
```

**Para atualizar via SSH** (config é preservada):
```sh
cd /tmp
curl -L https://github.com/Danrrodrigues/OpenWRT-Telegram-Bot/archive/refs/heads/main.tar.gz -o bot.tar.gz
tar xzf bot.tar.gz
cd OpenWRT-Telegram-Bot-main && sh install.sh update
```

**Para reconfigurar** (token, chat ID ou modo):
```sh
sh /usr/lib/telegram-bot/install.sh reconfigure
```

Veja o guia completo em [docs/installation.md](docs/installation.md).

---

## Comandos

| Comando | Descrição |
|---------|-----------|
| `/devices` | Lista dispositivos conectados |
| `/kick <MAC ou IP>` | Desconecta do Wi-Fi |
| `/wake <MAC ou IP>` | Acorda dispositivo com Wake-on-LAN |
| `/name <MAC> <hostname>` | Salva um nome amigável de dispositivo por MAC |
| `/block <MAC>` | Bloqueia permanentemente |
| `/unblock <MAC>` | Remove o bloqueio |
| `/limit <MAC> <↓Mbps> <↑Mbps>` | Define limite de velocidade |
| `/unlimit <MAC>` | Remove o limite |
| `/status` | Status do roteador |
| `/alerts off\|known\|unknown\|all` | Define o modo de alerta de dispositivos |
| `/update` | Verifica atualizações (`/update confirm` para aplicar) |
| `/rollback` | Restaura versão anterior (`/rollback confirm` para aplicar) |
| `/fix` | Repara o firewall e os bloqueios (usar após `fw4 reload` manual) |
| `/restartdns` | Reinicia o cache de DNS (dnsmasq) |
| `/reboot` | Reinicia o roteador (`/reboot confirm` para aplicar) |
| `/help` | Mostra todos os comandos |

Exemplo:

```sh
/name 92:27:f0:1a:66:6c celular-marcia
```

Wake-on-LAN usa `etherwake` em `br-lan` por padrão. Instale com:

```sh
opkg update && opkg install etherwake
```

Os nomes dos dispositivos sao resolvidos nesta ordem: nome estatico do host DHCP do OpenWRT para o MAC, hostname do lease DHCP e, por fim, `Unknown`.

Veja exemplos em [docs/commands.md](docs/commands.md).

### Menu de comandos e notificações automáticas

- **Menu de comandos automático** — ao instalar/atualizar, o bot registra a lista
  de comandos no Telegram (via `setMyCommands`), no idioma configurado. Não
  precisa configurar comandos manualmente no BotFather.
- **Aviso pós-atualização** — quando uma versão nova é instalada (por SSH ou por
  `/update`), o bot envia uma mensagem confirmando: *"✅ Bot atualizado para vX"*.
- **Aviso diário de versão nova** — todo dia às **8h** (horário local do roteador),
  o bot verifica se há versão mais recente e, se houver, sugere atualizar. Ele
  apenas avisa; nunca atualiza sozinho.

---

## Arquitetura

```
src/
├── bot.sh            — Ponto de entrada: loop daemon ou execução por cron
├── core/
│   ├── device_identity.sh   — Nomes estáticos DHCP + renderização de hostname
│   ├── telegram.sh   — API do Telegram (getUpdates, sendMessage, setMyCommands)
│   ├── config.sh     — Leitura/escrita de config UCI
│   ├── i18n.sh       — Carregador de idioma (en/pt)
│   └── logger.sh     — Log para syslog e arquivo
├── lang/
│   ├── en.sh         — Textos em inglês + descrições dos comandos
│   └── pt.sh         — Textos em português + descrições dos comandos
└── modules/
    ├── monitor.sh    — Detecção de novo dispositivo (/tmp/dhcp.leases)
    ├── devices.sh    — Listar / kick / wake / bloquear / status
    ├── bandwidth.sh  — Limite de velocidade (nft-qos ou tc)
    ├── updater.sh    — Atualização e rollback remotos via Telegram
    └── notify.sh     — Menu de comandos automático + aviso diário de versão
```

- **Pacotes obrigatórios mínimos** — apenas `curl` e `jsonfilter` são necessários; `/wake` também precisa de `etherwake`
- **Config UCI** em `/etc/config/telegram-bot` (chmod 600)
- **Daemon ou cron** — configurável na instalação
- **nft-qos ou fallback tc** para limitação de velocidade

---

## Configuração

```sh
# Ver configuração atual
uci show telegram-bot

# Mudar modo de alerta (off / known / unknown / all)
uci set telegram-bot.bot.alert_mode='unknown'
uci commit telegram-bot

# Mudar idioma (en / pt)
uci set telegram-bot.bot.lang='pt'
uci commit telegram-bot

# Reiniciar serviço
/etc/init.d/telegram-bot restart

# Ver logs
logread -e telegram-bot
```

Veja todas as opções em [docs/configuration.md](docs/configuration.md).

---

## Mudancas Recentes

- `v0.3.8` — Adiciona `/restartdns` para reiniciar o cache de DNS do dnsmasq e `/reboot confirm` para reiniciar o roteador remotamente via Telegram.
- `v0.3.7` — Adiciona `/wake <MAC ou IP>` para Wake-on-LAN via `etherwake` em `br-lan`, incluindo resolução de MAC por lease DHCP, entradas no menu de comandos do Telegram e documentação.
- `v0.3.1` — Corrige o `/update` e o `/rollback` remotos que abortavam no meio: o atualizador rodava como filho do serviço do bot, então reiniciar o serviço matava o próprio atualizador antes de terminar, deixando o bot parado e atualizado pela metade. Agora a atualização copia os arquivos antes de reiniciar e roda desacoplada da árvore de processos do serviço (`setsid`).
- `v0.3.0` — Menu de comandos automático (`setMyCommands`), aviso pós-atualização, aviso diário de versão nova às 8h e base de internacionalização (en/pt) com a opção `lang`.
- `v0.2.2` — Corrige todos os avisos do shellcheck no projeto (bugs reais de `A && B || C`, `echo -n` não-POSIX, código de teste morto), fixa o shellcheck do CI na v0.11.0 para casar com o hook de pre-push local e adiciona um hook de pre-push que roda o shellcheck antes do push.
- `v0.2.1` — Adiciona modos de alerta (`off|known|unknown|all`), detecção ativa de presença Wi-Fi para alertas de reconexão, `/name <MAC> <hostname>`, prioridade para nome estático do OpenWRT e a correção do instalador para `core/device_identity.sh`.

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

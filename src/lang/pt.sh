#!/bin/sh
# Portuguese (pt-BR) strings (i18n base).
# Values for T_* are printf templates. Keep command descriptions free of
# double quotes and backslashes — they are embedded directly into setMyCommands JSON.
# shellcheck disable=SC2034

# --- notify / updater messages ---
T_UPDATED="✅ Bot atualizado para v%s"
T_UPDATE_AVAILABLE="📦 Versão nova disponível: v%s (você tem v%s).
Envie /update confirm para atualizar."

# --- command menu (command|description per line) ---
# --- updater messages ---
T_CHECKING="Verificando atualizações..."
T_CHECK_FAIL="Não foi possível verificar atualizações. O roteador está conectado à internet?"
T_UP_TO_DATE="Já está na versão mais recente (<code>%s</code>)."
T_UPDATE_AVAILABLE_CMD="<b>Atualização disponível!</b>

Atual:       <code>%s</code>
Disponível:  <code>%s</code>

Envie /update confirm para atualizar."
T_UPDATING="Atualizando... o bot reiniciará em instantes.
Envie /status para confirmar quando voltar."
T_UPDATE_FAIL_EXTRACT="Falha na atualização: arquivo de instalação não encontrado."
T_UPDATE_FAIL_DOWNLOAD="Falha na atualização: não foi possível baixar o pacote. Verifique a conexão."
T_ROLLBACK_NONE="Nenhum backup disponível. Faça /update primeiro para criar um ponto de restauração."
T_ROLLBACK_AVAILABLE="<b>Rollback disponível</b>

Backup: <code>%s</code>
Atual:  <code>%s</code>

Envie /rollback confirm para restaurar."
T_ROLLBACK_RUNNING="Restaurando versão <code>%s</code>... o bot reiniciará em instantes."

# --- fix command ---
T_FIX_OK="🛠️ Firewall reparado. Regras de bloqueio recarregadas e bloqueios/limites ativos restaurados."
T_FIX_REVERTED="⚠️ Reparo cancelado: as novas regras do firewall não carregariam, então nada foi alterado e sua internet está segura. Verifique os logs."
T_FIX_NONFT="Nada a reparar: este roteador não tem <code>nft</code> disponível."

# --- wake command ---
T_WAKE_USAGE="Uso: <code>/wake &lt;MAC ou IP&gt;</code>"
T_WAKE_NOT_FOUND="❌ Dispositivo não encontrado: <code>%s</code>"
T_WAKE_MISSING_ETHERWAKE="❌ etherwake não está instalado. Instale com: <code>opkg update &amp;&amp; opkg install etherwake</code>"
T_WAKE_SENT="✅ Pacote Wake-on-LAN enviado para <b>%s</b> (<code>%s</code>)."
T_WAKE_FAILED="❌ Não foi possível enviar o pacote Wake-on-LAN para <b>%s</b> (<code>%s</code>)."

# --- lang command ---
T_LANG_CURRENT="Idioma atual: %s
Envie /lang en ou /lang pt para alterar."
T_LANG_CHANGED="Idioma alterado para %s"
T_LANG_SAME="O idioma já está definido como %s"
T_LANG_INVALID="Idioma desconhecido: %s. Disponíveis: en, pt"

# --- system command (restartdns / reboot) ---
T_RESTARTDNS_OK="✅ Cache de DNS reiniciado (dnsmasq)."
T_RESTARTDNS_FAIL="❌ Falha ao reiniciar o dnsmasq. Verifique os logs."
T_RESTARTDNS_MISSING="Nada a reiniciar: este roteador não tem o script de init do <code>dnsmasq</code>."
T_REBOOT_CONFIRM="⚠️ Isso vai reiniciar o roteador e derrubar a rede por cerca de 1 minuto.
Envie /reboot confirm para continuar."
T_REBOOT_RUNNING="🔄 Reiniciando agora... o bot voltará em breve.
Envie /status em um minuto para confirmar."

I18N_COMMANDS='start|Mostrar ajuda e comandos disponíveis
devices|Listar dispositivos conectados
status|Status do roteador (CPU, RAM, uptime)
alerts|Configurar alertas (off/known/unknown/all)
kick|Desconectar dispositivo (MAC ou IP)
wake|Acordar dispositivo com Wake-on-LAN
block|Bloquear dispositivo permanentemente (MAC)
unblock|Remover bloqueio (MAC)
name|Salvar nome para um dispositivo (MAC nome)
limit|Definir limite de velocidade (MAC down up em Mbps)
unlimit|Remover limite de velocidade (MAC)
update|Verificar atualizações (use confirm para aplicar)
rollback|Restaurar versão anterior (use confirm para aplicar)
fix|Reparar firewall e bloqueios
restartdns|Reiniciar cache de DNS (dnsmasq)
reboot|Reiniciar o roteador (use confirm para aplicar)
lang|Alterar idioma do bot (en ou pt)
help|Mostrar esta mensagem'

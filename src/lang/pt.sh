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
I18N_COMMANDS='start|Mostrar ajuda e comandos disponíveis
devices|Listar dispositivos conectados
status|Status do roteador (CPU, RAM, uptime)
alerts|Configurar alertas (off/known/unknown/all)
kick|Desconectar dispositivo (MAC ou IP)
block|Bloquear dispositivo permanentemente (MAC)
unblock|Remover bloqueio (MAC)
name|Salvar nome para um dispositivo (MAC nome)
limit|Definir limite de velocidade (MAC down up em Mbps)
unlimit|Remover limite de velocidade (MAC)
update|Verificar atualizações (use confirm para aplicar)
rollback|Restaurar versão anterior (use confirm para aplicar)
help|Mostrar esta mensagem'

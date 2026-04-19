#!/bin/bash

ACTIVATION_FLAG="/etc/.activated"
BACKEND="http://102.129.137.139:8282/check.php"

main() {
  echo "🔥 Bienvenido al sistema"
  # 👉 aquí ponés TODO tu sistema real
}

check_activation() {
  # === SI YA ESTÁ ACTIVADO ===
  if [[ -f "$ACTIVATION_FLAG" ]]; then
    echo "✅ Sistema ya activado"
    return
  fi

  # === PEDIR TOKEN ===
  clear
  echo "🔐 Activación requerida"
  read -p "Ingresa tu token: " TOKEN

  if [[ -z "$TOKEN" ]]; then
    echo "❌ Token vacío"
    exit 1
  fi

  RESP=$(curl -s --max-time 5 "$BACKEND?token=$TOKEN")

  if [[ "$RESP" == "OK" ]]; then
    touch "$ACTIVATION_FLAG"
    chmod 600 "$ACTIVATION_FLAG"

    echo "✅ Activado"
    sleep 1
  else
    echo "❌ Token inválido"
    exit 1
  fi
}

# 🔥 FLUJO CORRECTO
check_activation
main


# === AQUÍ EMPIEZA TU SCRIPT NORMAL ===

# ==================================================================
# MATA SOLO MENÚS DUPLICADOS SIN JODER EL LIMITADOR NI FUNCIONES
# ==================================================================
if [[ -z "$1" && -t 0 ]]; then   # Solo cuando se ejecuta como menú interactivo
    MI_PID=$$
    # Busca otros procesos del mismo script ejecutándose como menú
    OTROS_MENUS=$(pgrep -f '^bash.*scrip\.sh$' | grep -v "^${MI_PID}$")

    if [[ -n "$OTROS_MENUS" ]]; then
        echo -e "\033[1;33mYa había otro menú abierto, lo cierro para evitar duplicados...\033[0m"
        kill -9 $OTROS_MENUS 2>/dev/null
        sleep 0.3
    fi
fi

# ================================
# VARIABLES Y RUTAS
# ================================
export REGISTROS="/diana/reg.txt"
export HISTORIAL="/alexia/log.txt"

# Archivo donde se guardará la tabla generada
export LOGFILE="/Abigail/conexiones.log"

# PIDs separados
export PID_MON="/Abigail/mon.pid"                # monitorear_conexiones
export PID_LIMITADOR="/Abigail/limitador.pid"    # limitador
export PID_BLOQUEOS="/Abigail/mon_bloqueos.pid"  # monitorear_bloqueos

export STATUS="/tmp/limitador_status"
export ENABLED="/tmp/limitador_enabled"

# Crear directorios si no existen
mkdir -p "$(dirname "$REGISTROS")"
mkdir -p "$(dirname "$HISTORIAL")"
mkdir -p "/Abigail"


SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_INCLUDE_DIR="/etc/ssh/sshd_config.d"
TEMP_FILE="/tmp/sshd_config.tmp"

# ================================
# FUNCIONES
# ================================

# Modifica o agrega un parámetro en un archivo
# $1 = archivo
# $2 = parámetro (ClientAliveInterval, ClientAliveCountMax)
# $3 = valor
set_sshd_param() {
    local file="$1"
    local param="$2"
    local value="$3"

    # Si existe (comentada o descomentada), reemplaza
    if grep -q -E "^\s*#?\s*$param" "$file"; then
        sed -i -E "s|^\s*#?\s*${param}.*|${param} ${value}|" "$file"
    else
        # Si no existe, agregar al final
        echo "${param} ${value}" >> "$file"
    fi
}

# ================================
# CONFIGURACIÓN PRINCIPAL
# ================================
# Modificar parámetros en sshd_config principal
set_sshd_param "$SSHD_CONFIG" "ClientAliveInterval" 30
set_sshd_param "$SSHD_CONFIG" "ClientAliveCountMax" 3

# Modificar parámetros en archivos incluidos si existen
if [ -d "$SSHD_INCLUDE_DIR" ]; then
    for f in "$SSHD_INCLUDE_DIR"/*.conf; do
        [ -f "$f" ] || continue
        set_sshd_param "$f" "ClientAliveInterval" 30
        set_sshd_param "$f" "ClientAliveCountMax" 3
    done
fi

# ================================
# REINICIAR SSH
# ================================
systemctl restart sshd && echo "SSH configurado correctamente."
    
                                        
ssh_bot() {
    # Asegurar que jq esté instalado
    if ! command -v jq &>/dev/null; then
        echo -e "${AMARILLO_SUAVE}📥 Instalando jq...${NC}"
        curl -L -o /usr/bin/jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
        chmod +x /usr/bin/jq
    fi

    clear
    echo -e "${VIOLETA}======🤖 SSH BOT ======${NC}"
    echo -e "${AMARILLO_SUAVE}1. 🟢 Activar Bot${NC}"
    echo -e "${AMARILLO_SUAVE}2. 🔴 Eliminar Token${NC}"
    echo -e "${AMARILLO_SUAVE}0. 🚪 Volver${NC}"
    read -p "➡️ Selecciona una opción: " BOT_OPCION

    case $BOT_OPCION in
        1)
            read -p "👉 Ingresa tu Token ID: " TOKEN_ID
            read -p "👉 Ingresa tu ID de usuario de Telegram: " USER_ID
            read -p "👉 Ingresa tu nombre: " USER_NAME
            echo "$TOKEN_ID" > /root/sshbot_token
            echo "$USER_ID" > /root/sshbot_userid
            echo "$USER_NAME" > /root/sshbot_username

            nohup bash -c "
                export LC_ALL=es_SV.utf8
                export REGISTROS='$REGISTROS'
                export HISTORIAL='$HISTORIAL'
                export PIDFILE='$PIDFILE'

                mkdir -p \"\$(dirname \"\$REGISTROS\")\"
                mkdir -p \"\$(dirname \"\$HISTORIAL\")\"
                mkdir -p \"\$(dirname \"\$PIDFILE\")\"

                URL='https://api.telegram.org/bot$TOKEN_ID'
                OFFSET=0
                EXPECTING_USER_DATA=0
                USER_DATA_STEP=0
                EXPECTING_DELETE_USER=0
                EXPECTING_RENEW_USER=0
                RENEW_STEP=0
                EXPECTING_BACKUP=0
                EXPECTING_USER_DETAILS=0
                declare -A USER_MAP
                USERNAME=''
                PASSWORD=''
                DAYS=''
                MOBILES=''

                calcular_dias_restantes() {
                    local fecha_expiracion=\"\$1\"
                    local dia=\$(echo \"\$fecha_expiracion\" | cut -d'/' -f1)
                    local mes=\$(echo \"\$fecha_expiracion\" | cut -d'/' -f2)
                    mes=\$(echo \"\$mes\" | tr '[:upper:]' '[:lower:]')
                    local anio=\$(echo \"\$fecha_expiracion\" | cut -d'/' -f3)

                    case \$mes in
                        \"enero\") mes_num=\"01\" ;;
                        \"febrero\") mes_num=\"02\" ;;
                        \"marzo\") mes_num=\"03\" ;;
                        \"abril\") mes_num=\"04\" ;;
                        \"mayo\") mes_num=\"05\" ;;
                        \"junio\") mes_num=\"06\" ;;
                        \"julio\") mes_num=\"07\" ;;
                        \"agosto\") mes_num=\"08\" ;;
                        \"septiembre\") mes_num=\"09\" ;;
                        \"octubre\") mes_num=\"10\" ;;
                        \"noviembre\") mes_num=\"11\" ;;
                        \"diciembre\") mes_num=\"12\" ;;
                        *) echo 0; return ;;
                    esac

                    local fecha_formateada=\"\$anio-\$mes_num-\$dia\"
                    local fecha_actual=\$(date \"+%Y-%m-%d\")

                    local fecha_exp_epoch=\$(date -d \"\$fecha_formateada\" \"+%s\" 2>/dev/null)
                    local fecha_act_epoch=\$(date -d \"\$fecha_actual\" \"+%s\")

                    if [[ -z \"\$fecha_exp_epoch\" ]]; then
                        echo 0
                        return
                    fi

                    local diff_segundos=\$((fecha_exp_epoch - fecha_act_epoch))
                    local dias_restantes=\$((diff_segundos / 86400))

                    if [ \$dias_restantes -lt 0 ]; then
                        dias_restantes=0
                    fi

                    echo \$dias_restantes
                }

                while true; do
                    UPDATES=\$(curl -s \"\$URL/getUpdates?offset=\$OFFSET&timeout=10\")
                    for row in \$(echo \"\$UPDATES\" | jq -c '.result[]'); do
                        OFFSET=\$(echo \$row | jq '.update_id')
                        OFFSET=\$((OFFSET+1))
                        MSG_TEXT=\$(echo \$row | jq -r '.message.text')
                        CHAT_ID=\$(echo \$row | jq -r '.message.chat.id')
                        USERNAME_TELEGRAM=\$(echo \$row | jq -r '.message.from.username')
                        DOCUMENT_ID=\$(echo \$row | jq -r '.message.document.file_id // empty')

                        if [[ \"\$CHAT_ID\" == \"$USER_ID\" ]]; then
                            if [[ \$EXPECTING_BACKUP -eq 1 ]]; then
                                if [[ -n \"\$DOCUMENT_ID\" ]]; then
                                    FILE_INFO=\$(curl -s \"\$URL/getFile?file_id=\$DOCUMENT_ID\")
                                    FILE_PATH=\$(echo \$FILE_INFO | jq -r '.result.file_path')
                                    if [[ -n \"\$FILE_PATH\" ]]; then
                                        DOWNLOAD_URL=\"https://api.telegram.org/file/bot$TOKEN_ID/\$FILE_PATH\"
                                        curl -s -o /tmp/backup_restore.txt \"\$DOWNLOAD_URL\"
                                        succeeded=0
                                        while IFS=' ' read -r user_data fecha_expiracion dias moviles fecha_crea hora_crea; do
                                            usuario=\${user_data%%:*}
                                            password=\${user_data#*:}
                                            if [[ -z \"\$usuario\" || -z \"\$password\" ]]; then
                                                continue
                                            fi
                                            dia=\$(echo \"\$fecha_expiracion\" | cut -d'/' -f1)
                                            mes=\$(echo \"\$fecha_expiracion\" | cut -d'/' -f2)
                                            mes=\$(echo \"\$mes\" | tr '[:upper:]' '[:lower:]')
                                            anio=\$(echo \"\$fecha_expiracion\" | cut -d'/' -f3)
                                            case \$mes in
                                                enero) mes_num=01 ;;
                                                febrero) mes_num=02 ;;
                                                marzo) mes_num=03 ;;
                                                abril) mes_num=04 ;;
                                                mayo) mes_num=05 ;;
                                                junio) mes_num=06 ;;
                                                julio) mes_num=07 ;;
                                                agosto) mes_num=08 ;;
                                                septiembre) mes_num=09 ;;
                                                octubre) mes_num=10 ;;
                                                noviembre) mes_num=11 ;;
                                                diciembre) mes_num=12 ;;
                                                *) continue ;;
                                            esac
                                            fecha_formateada=\"\$anio-\$mes_num-\$dia\"
                                            fecha_expiracion_sistema=\$(date -d \"\$fecha_formateada +1 day\" \"+%Y-%m-%d\" 2>/dev/null)
                                            if [[ -z \"\$fecha_expiracion_sistema\" ]]; then
                                                continue
                                            fi
                                            if id \"\$usuario\" >/dev/null 2>&1; then
                                                if ! echo \"\$usuario:\$password\" | chpasswd 2>/dev/null; then
                                                    continue
                                                fi
                                                if ! chage -E \"\$fecha_expiracion_sistema\" \"\$usuario\" 2>/dev/null; then
                                                    continue
                                                fi
                                                sed -i \"/^\$usuario:/d\" \"\$REGISTROS\"
                                            else
                                                if ! useradd -M -s /sbin/nologin \"\$usuario\" 2>/dev/null; then
                                                    continue
                                                fi
                                                if ! echo \"\$usuario:\$password\" | chpasswd 2>/dev/null; then
                                                    userdel \"\$usuario\" 2>/dev/null
                                                    continue
                                                fi
                                                if ! chage -E \"\$fecha_expiracion_sistema\" \"\$usuario\" 2>/dev/null; then
                                                    userdel \"\$usuario\" 2>/dev/null
                                                    continue
                                                fi
                                            fi
                                            echo \"\$user_data \$fecha_expiracion \$dias \$moviles \$fecha_crea \$hora_crea\" >> \"\$REGISTROS\"
                                            ((succeeded++))
                                        done < /tmp/backup_restore.txt
                                        rm -f /tmp/backup_restore.txt
                                        curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"✅ *Restauración completada exitosamente! Restaurados \$succeeded usuarios.* 📥 Escribe *hola* para volver al menú.\" -d parse_mode=Markdown >/dev/null
                                        EXPECTING_BACKUP=0
                                    else
                                        curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"❌ *Error al obtener el archivo.* Intenta de nuevo o escribe 'cancel' para cancelar.\" -d parse_mode=Markdown >/dev/null
                                    fi
                                elif [[ \"\$MSG_TEXT\" == \"cancel\" ]]; then
                                    EXPECTING_BACKUP=0
                                    curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"❌ *Restauración cancelada.* Escribe *hola* para volver al menú.\" -d parse_mode=Markdown >/dev/null
                                else
                                    curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"📥 *Esperando el archivo de backup.* Envía el archivo TXT o escribe 'cancel' para cancelar.\" -d parse_mode=Markdown >/dev/null
                                fi
                                continue
                            fi
                            if [[ \$EXPECTING_USER_DATA -eq 1 ]]; then
                                case \$USER_DATA_STEP in
                                    1)
                                        USERNAME=\"\$MSG_TEXT\"
                                        curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"🔑 Ingresa la contraseña:\" -d parse_mode=Markdown >/dev/null
                                        USER_DATA_STEP=2
                                        ;;
                                    2)
                                        PASSWORD=\"\$MSG_TEXT\"
                                        curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"📅 Ingresa los días de validez:\" -d parse_mode=Markdown >/dev/null
                                        USER_DATA_STEP=3
                                        ;;
                                    3)
                                        DAYS=\"\$MSG_TEXT\"
                                        curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"📱 Ingresa el límite de móviles:\" -d parse_mode=Markdown >/dev/null
                                        USER_DATA_STEP=4
                                        ;;
                                    4)
                                        MOBILES=\"\$MSG_TEXT\"
                                        if [[ -z \"\$USERNAME\" || -z \"\$PASSWORD\" || -z \"\$DAYS\" || -z \"\$MOBILES\" ]]; then
                                            curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"❌ Todos los campos son obligatorios. Intenta de nuevo con la opción 1.\" -d parse_mode=Markdown >/dev/null
                                        elif ! [[ \"\$DAYS\" =~ ^[0-9]+$ ]] || ! [[ \"\$MOBILES\" =~ ^[0-9]+$ ]]; then
                                            curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"❌ Días y móviles deben ser números. Intenta de nuevo con la opción 1.\" -d parse_mode=Markdown >/dev/null
                                        else
                                            if id \"\$USERNAME\" >/dev/null 2>&1; then
                                                curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"❌ El usuario *\\\`$USERNAME\\\`* ya existe en el sistema. Intenta con otro nombre.\" -d parse_mode=Markdown >/dev/null
                                            else
                                                if ! useradd -M -s /sbin/nologin \"\$USERNAME\" 2>/dev/null; then
                                                    curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"❌ Error al crear el usuario en el sistema.\" -d parse_mode=Markdown >/dev/null
                                                else
                                                    if ! echo \"\$USERNAME:\$PASSWORD\" | chpasswd 2>/dev/null; then
                                                        userdel \"\$USERNAME\" 2>/dev/null
                                                        curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"❌ Error al establecer la contraseña.\" -d parse_mode=Markdown >/dev/null
                                                    else
                                                        fecha_expiracion_sistema=\$(date -d \"+\$((DAYS + 1)) days\" \"+%Y-%m-%d\")
                                                        if ! chage -E \"\$fecha_expiracion_sistema\" \"\$USERNAME\" 2>/dev/null; then
                                                            userdel \"\$USERNAME\" 2>/dev/null
                                                            curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"❌ Error al establecer la fecha de expiración.\" -d parse_mode=Markdown >/dev/null
                                                        else
                                                            fecha_creacion=\$(date \"+%Y-%m-%d %H:%M:%S\")
                                                            fecha_expiracion=\$(date -d \"+\$DAYS days\" \"+%d/%B/%Y\")
                                                            echo \"\$USERNAME:\$PASSWORD \$fecha_expiracion \$DAYS \$MOBILES \$fecha_creacion\" >> \"\$REGISTROS\"
                                                            echo \"Usuario creado: \$USERNAME, Expira: \$fecha_expiracion, Móviles: \$MOBILES, Creado: \$fecha_creacion\" >> \"\$HISTORIAL\"
                                                            if [[ \"\$DAYS\" -eq 1 ]]; then
                                                                DIAS_TEXTO=\"Día\"
                                                            else
                                                                DIAS_TEXTO=\"Días\"
                                                            fi
                                                            RESUMEN=\"✅ *Usuario creado correctamente:*

👤 *Usuario*: \\\`\${USERNAME}\\\`
🔑 *Clave*: \\\`\${PASSWORD}\\\`
\\\`📅 Expira: \${fecha_expiracion}\\\`
🧔 *Usuario*: \\\`\${USERNAME}\\\`
⏳  *\${DIAS_TEXTO}*: \\\`\${DAYS}\\\`
📱 *Límite móviles*: \\\`\${MOBILES}\\\`
📅 *Creado*: \\\`\${fecha_creacion}\\\`
📊 *Datos*: \\\`\${USERNAME}:\${PASSWORD}\\\`

\\\`\\\`\\\`
🌐✨ Reglas SSH WebSocket ✨🌐

👋 Hola, \${USERNAME}
Por favor cumple con estas reglas para mantener tu acceso activo:

 🚫 No compartas tu cuenta
 📱 Máx. \${MOBILES} móviles conectados 🚨 → Si excedes el límite tu usuario será bloqueado automáticamente.
 📅 Respeta tu fecha de expiración
 📥 Prohibido torrents o descargas abusivas
 🔒 No cambies tu clave ni uses accesos de otros
 ⚠️ Nada de usos ilegales (spam/ataques)
 🧑‍💻 SOPORTE: ENVÍA TU MENSAJE UNA SOLA VEZ Y ESPERA RESPUESTA. 🚫 NO HAGAS SPAM.

⚡👉 El incumplimiento resultará en suspensión inmediata.
\\\`\\\`\\\`\"
                                                            curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"\$RESUMEN\" -d parse_mode=Markdown >/dev/null
                                                        fi
                                                    fi
                                                fi
                                            fi
                                        fi
                                        EXPECTING_USER_DATA=0
                                        USER_DATA_STEP=0
                                        ;;
                                esac
                            elif [[ \$EXPECTING_DELETE_USER -eq 1 ]]; then
                                USUARIO_A_ELIMINAR=\"\$MSG_TEXT\"
                                if ! grep -q \"^\$USUARIO_A_ELIMINAR:\" \"\$REGISTROS\"; then
                                    curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"❌ El usuario *\\\`\${USUARIO_A_ELIMINAR}\\\`* no está registrado. Escribe *hola* para volver al menú.\" -d parse_mode=Markdown >/dev/null
                                else
                                    pkill -KILL -u \"\$USUARIO_A_ELIMINAR\" 2>/dev/null
                                    sleep 1
                                    fecha_eliminacion=\$(date \"+%Y-%m-%d %H:%M:%S\")
                                    if userdel -r -f \"\$USUARIO_A_ELIMINAR\" >/dev/null 2>&1; then
                                        if ! id \"\$USUARIO_A_ELIMINAR\" &>/dev/null; then
                                            sed -i \"/^\$USUARIO_A_ELIMINAR:/d\" \"\$REGISTROS\"
                                            echo \"Usuario eliminado: \$USUARIO_A_ELIMINAR, Fecha: \$fecha_eliminacion\" >> \"\$HISTORIAL\"
                                            curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"✅ *Usuario* \\\`\${USUARIO_A_ELIMINAR}\\\` *eliminado exitosamente!* 😈
Escribe *hola* para volver al menú.\" -d parse_mode=Markdown >/dev/null
                                        else
                                            rm -rf \"/home/\$USUARIO_A_ELIMINAR\" 2>/dev/null
                                            rm -f \"/var/mail/\$USUARIO_A_ELIMINAR\" 2>/dev/null
                                            rm -f \"/var/spool/mail/\$USUARIO_A_ELIMINAR\" 2>/dev/null
                                            sed -i \"/^\$USUARIO_A_ELIMINAR:/d\" /etc/passwd
                                            sed -i \"/^\$USUARIO_A_ELIMINAR:/d\" /etc/shadow
                                            sed -i \"/^\$USUARIO_A_ELIMINAR:/d\" /etc/group
                                            sed -i \"/^\$USUARIO_A_ELIMINAR:/d\" /etc/gshadow
                                            if ! id \"\$USUARIO_A_ELIMINAR\" &>/dev/null; then
                                                sed -i \"/^\$USUARIO_A_ELIMINAR:/d\" \"\$REGISTROS\"
                                                echo \"Usuario eliminado forzosamente: \$USUARIO_A_ELIMINAR, Fecha: \$fecha_eliminacion\" >> \"\$HISTORIAL\"
                                                curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"✅ *Usuario* \\\`\${USUARIO_A_ELIMINAR}\\\` *eliminado forzosamente!* 😈
Escribe *hola* para volver al menú.\" -d parse_mode=Markdown >/dev/null
                                            else
                                                echo \"Error al eliminar usuario persistente: \$USUARIO_A_ELIMINAR, Fecha: \$fecha_eliminacion\" >> \"\$HISTORIAL\"
                                                curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"❌ *Error persistente al eliminar el usuario* \\\`\${USUARIO_A_ELIMINAR}\\\`.
Escribe *hola* para volver al menú.\" -d parse_mode=Markdown >/dev/null
                                            fi
                                        fi
                                    else
                                        echo \"Error al eliminar usuario: \$USUARIO_A_ELIMINAR, Fecha: \$fecha_eliminacion\" >> \"\$HISTORIAL\"
                                        curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"❌ *Error al eliminar el usuario* \\\`\${USUARIO_A_ELIMINAR}\\\`.
Escribe *hola* para volver al menú.\" -d parse_mode=Markdown >/dev/null
                                    fi
                                fi
                                EXPECTING_DELETE_USER=0
                            elif [[ \$EXPECTING_RENEW_USER -eq 1 ]]; then
                                case \$RENEW_STEP in
                                    1)
                                        USUARIO=\"\$MSG_TEXT\"
                                        if ! grep -q \"^\$USUARIO:\" \"\$REGISTROS\"; then
                                            curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"❌ *El usuario* \\\`\${USUARIO}\\\` *no existe.* 😕
Escribe *hola* para volver al menú.\" -d parse_mode=Markdown >/dev/null
                                            EXPECTING_RENEW_USER=0
                                            RENEW_STEP=0
                                        else
                                            user_line=\$(grep \"^\$USUARIO:\" \"\$REGISTROS\")
                                            usuario=\${user_line%%:*}
                                            clave=\${user_line#*:}
                                            clave=\${clave%% *}
                                            resto_line=\${user_line#* }
                                            fecha_expiracion=\$(echo \"\$resto_line\" | awk '{print \$1}')
                                            dias_actuales=\$(echo \"\$resto_line\" | awk '{print \$2}')
                                            moviles=\$(echo \"\$resto_line\" | awk '{print \$3}')
                                            fecha_creacion=\$(echo \"\$resto_line\" | awk '{print \$4, \$5}')
                                            curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"📅 *¿Cuántos días deseas agregar?* (puedes usar negativos para disminuir) \" -d parse_mode=Markdown >/dev/null
                                            RENEW_STEP=2
                                        fi
                                        ;;
                                    2)
                                        DIAS_RENOVAR=\"\$MSG_TEXT\"
                                        if ! [[ \"\$DIAS_RENOVAR\" =~ ^-?[0-9]+$ ]]; then
                                            curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"❌ *Días inválidos.* Debe ser un número entero (positivo o negativo). 😕
Escribe *hola* para volver al menú.\" -d parse_mode=Markdown >/dev/null
                                            EXPECTING_RENEW_USER=0
                                            RENEW_STEP=0
                                        else
                                            curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"📱 *Cantidad de móviles a agregar* (actual: \$moviles, 0 si no): \" -d parse_mode=Markdown >/dev/null
                                            RENEW_STEP=3
                                        fi
                                        ;;
                                    3)
                                        MOVILES_CAMBIOS=\"\$MSG_TEXT\"
                                        if ! [[ \"\$MOVILES_CAMBIOS\" =~ ^-?[0-9]+$ ]]; then
                                            MOVILES_CAMBIOS=0
                                        fi
                                        nuevos_moviles=\$((moviles + MOVILES_CAMBIOS))
                                        if (( nuevos_moviles < 0 )); then
                                            curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"❌ *El límite de móviles no puede ser menor que 0.* 😕
Escribe *hola* para volver al menú.\" -d parse_mode=Markdown >/dev/null
                                            EXPECTING_RENEW_USER=0
                                            RENEW_STEP=0
                                        else
                                            fecha_expiracion_std=\$(echo \"\$fecha_expiracion\" | sed 's|enero|01|;s|febrero|02|;s|marzo|03|;s|abril|04|;s|mayo|05|;s|junio|06|;s|julio|07|;s|agosto|08|;s|septiembre|09|;s|octubre|10|;s|noviembre|11|;s|diciembre|12|')
                                            fecha_expiracion_std=\$(echo \"\$fecha_expiracion_std\" | awk -F'/' '{printf \"%04d-%02d-%02d\", \$3, \$2, \$1}')
                                            nueva_fecha_std=\$(date -d \"\$fecha_expiracion_std + \$DIAS_RENOVAR days\" \"+%Y-%m-%d\" 2>/dev/null)
                                            if [[ -z \"\$nueva_fecha_std\" ]]; then
                                                curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"❌ *Error al calcular la nueva fecha de expiración.* 😕
Escribe *hola* para volver al menú.\" -d parse_mode=Markdown >/dev/null
                                                echo \"Error al calcular nueva fecha para \$USUARIO, Fecha: \$(date \"+%Y-%m-%d %H:%M:%S\")\" >> \"\$HISTORIAL\"
                                                EXPECTING_RENEW_USER=0
                                                RENEW_STEP=0
                                            else
                                                fecha_expiracion_sistema=\$(date -d \"\$nueva_fecha_std + 1 day\" \"+%Y-%m-%d\" 2>/dev/null)
                                                if ! chage -E \"\$fecha_expiracion_sistema\" \"\$USUARIO\" 2>/tmp/chage_error; then
                                                    error_msg=\$(cat /tmp/chage_error)
                                                    curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"❌ *Error al actualizar la fecha de expiración en el sistema:* \$error_msg 😕
Escribe *hola* para volver al menú.\" -d parse_mode=Markdown >/dev/null
                                                    echo \"Error al actualizar fecha de expiración para \$USUARIO: \$error_msg, Fecha: \$(date \"+%Y-%m-%d %H:%M:%S\")\" >> \"\$HISTORIAL\"
                                                    rm -f /tmp/chage_error
                                                    EXPECTING_RENEW_USER=0
                                                    RENEW_STEP=0
                                                else
                                                    nueva_fecha=\$(echo \"\$nueva_fecha_std\" | awk -F'-' '{
                                                        meses[\"01\"]=\"enero\"; meses[\"02\"]=\"febrero\"; meses[\"03\"]=\"marzo\"; meses[\"04\"]=\"abril\";
                                                        meses[\"05\"]=\"mayo\"; meses[\"06\"]=\"junio\"; meses[\"07\"]=\"julio\"; meses[\"08\"]=\"agosto\";
                                                        meses[\"09\"]=\"septiembre\"; meses[\"10\"]=\"octubre\"; meses[\"11\"]=\"noviembre\"; meses[\"12\"]=\"diciembre\";
                                                        printf \"%02d/%s/%04d\", \$3, meses[\$2], \$1
                                                    }')
                                                    dias_restantes=\$(calcular_dias_restantes \"\$nueva_fecha\")
                                                    if ! grep -q \"^\$USUARIO:\" \"\$REGISTROS\"; then
                                                        curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"❌ *Error: el usuario \$USUARIO no se encuentra en los registros.* 😕
Escribe *hola* para volver al menú.\" -d parse_mode=Markdown >/dev/null
                                                        echo \"Error: usuario \$USUARIO no encontrado en \$REGISTROS, Fecha: \$(date \"+%Y-%m-%d %H:%M:%S\")\" >> \"\$HISTORIAL\"
                                                        EXPECTING_RENEW_USER=0
                                                        RENEW_STEP=0
                                                    else
                                                        temp_file=\"/tmp/registros_\$USUARIO.tmp\"
                                                        sed \"/^\$USUARIO:/d\" \"\$REGISTROS\" > \"\$temp_file\"
                                                        echo \"\$USUARIO:\$clave \$nueva_fecha \$dias_actuales \$nuevos_moviles \$fecha_creacion\" >> \"\$temp_file\"
                                                        if ! mv \"\$temp_file\" \"\$REGISTROS\" 2>/tmp/sed_error; then
                                                            error_msg=\$(cat /tmp/sed_error)
                                                            curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"❌ *Error al actualizar el archivo de registros:* \$error_msg 😕
Escribe *hola* para volver al menú.\" -d parse_mode=Markdown >/dev/null
                                                            echo \"Error al actualizar \$REGISTROS para \$USUARIO: \$error_msg, Fecha: \$(date \"+%Y-%m-%d %H:%M:%S\")\" >> \"\$HISTORIAL\"
                                                            rm -f /tmp/sed_error
                                                            EXPECTING_RENEW_USER=0
                                                            RENEW_STEP=0
                                                        else
                                                            echo \"Usuario renovado: \$USUARIO, Nueva fecha: \$nueva_fecha, Móviles: \$nuevos_moviles, Fecha: \$(date \"+%Y-%m-%d %H:%M:%S\")\" >> \"\$HISTORIAL\"
                                                            RESUMEN=\"🎉 *¡Usuario renovado con éxito!* 🚀

👤 *Usuario*: \\\`\${USUARIO}\\\`
🔒 *Clave*: \\\`\${clave}\\\`
➕ *Días agregados*: \\\`\${DIAS_RENOVAR}\\\`
📱 *Móviles agregados*: \\\`\${MOVILES_CAMBIOS}\\\`
🗓️ *Fecha anterior de expiración*: \\\`\${fecha_expiracion}\\\`
✨ *Nueva fecha de expiración*: \\\`\${nueva_fecha}\\\`
📱 *Límite de móviles actualizado*: \\\`\${nuevos_moviles}\\\`
🕒 *Fecha de creación*: \\\`\${fecha_creacion}\\\`
⏳ *Días restantes*: \\\`\${dias_restantes}\\\`

Escribe *hola* para volver al menú.\"
                                                            curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"\$RESUMEN\" -d parse_mode=Markdown >/dev/null
                                                            EXPECTING_RENEW_USER=0
                                                            RENEW_STEP=0
                                                        fi
                                                    fi
                                                fi
                                            fi
                                        fi
                                        ;;
                                esac
                            elif [[ \$EXPECTING_USER_DETAILS -eq 1 ]]; then
                                input=\"\$MSG_TEXT\"
                                if [[ \$input =~ ^[0-9]+$ && -n \"\${USER_MAP[\$input]}\" ]]; then
                                    usuario=\"\${USER_MAP[\$input]}\"
                                else
                                    usuario=\"\$input\"
                                    if ! grep -q \"^\$usuario:\" \"\$REGISTROS\"; then
                                        curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"❌ *Usuario no encontrado.* Escribe *hola* para volver al menú.\" -d parse_mode=Markdown >/dev/null
                                        EXPECTING_USER_DETAILS=0
                                        continue
                                    fi
                                fi

                                linea=\$(grep \"^\$usuario:\" \"\$REGISTROS\")
                                IFS=' ' read -r user_data fecha_expiracion dias moviles fecha_creacion1 fecha_creacion2 <<< \"\$linea\"
                                clave=\${user_data#*:}
                                dias_restantes=\$(calcular_dias_restantes \"\$fecha_expiracion\")
                                fecha_actual=\$(date \"+%Y-%m-%d %H:%M\")

                                conexiones=\$(( \$(ps -u \"\$usuario\" -o comm= | grep -cE \"^(sshd|dropbear)\$\") ))
                                tmp_status=\"/tmp/status_\${usuario}.tmp\"
                                bloqueo_file=\"/tmp/bloqueo_\${usuario}.lock\"

                                conex_info=\"\"
                                tiempo_conectado=\"\"
                                ultima_conexion=\"\"
                                historia_conexion=\"\"

                                if [[ -f \"\$bloqueo_file\" ]]; then
                                    bloqueo_hasta=\$(cat \"\$bloqueo_file\")
                                    if [[ \$(date +%s) -lt \$bloqueo_hasta ]]; then
                                        ultima_conexion=\"🚫 Bloqueado hasta \$(date -d @\$bloqueo_hasta '+%I:%M%p')\"
                                    fi
                                fi

                                ultimo_registro=\$(grep \"^\$usuario|\" \"\$HISTORIAL\" | grep -E '|[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}|[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}' | tail -1)
                                if [[ -n \"\$ultimo_registro\" ]]; then
                                    IFS='|' read -r _ hora_conexion hora_desconexion _ <<< \"\$ultimo_registro\"

                                    ult_month=\$(LC_ALL=es_SV.UTF-8 date -d \"\$hora_desconexion\" +\"%B\" 2>/dev/null | tr '[:upper:]' '[:lower:]')
                                    ult_fmt=\$(LC_ALL=es_SV.UTF-8 date -d \"\$hora_desconexion\" +\"%d de \$ult_month %H:%M\" 2>/dev/null)

                                    ultima_conexion=\"📅 Última: \$ult_fmt\"

                                    sec_con=\$(date -d \"\$hora_conexion\" +%s 2>/dev/null)
                                    sec_des=\$(date -d \"\$hora_desconexion\" +%s 2>/dev/null)
                                    if [[ -n \"\$sec_con\" && -n \"\$sec_des\" && \$sec_des -ge \$sec_con ]]; then
                                        dur_seg=\$((sec_des - sec_con))
                                        h=\$((dur_seg / 3600))
                                        m=\$(((dur_seg % 3600) / 60))
                                        s=\$((dur_seg % 60))
                                        duracion=\$(printf \"%02d:%02d:%02d\" \$h \$m \$s)
                                    else
                                        duracion=\"N/A\"
                                    fi

                                    con_month=\$(LC_ALL=es_SV.UTF-8 date -d \"\$hora_conexion\" +\"%B\" 2>/dev/null | tr '[:upper:]' '[:lower:]')
                                    conexion_fmt=\$(LC_ALL=es_SV.UTF-8 date -d \"\$hora_conexion\" +\"%d/\$con_month %H:%M\" 2>/dev/null)

                                    des_month=\$(LC_ALL=es_SV.UTF-8 date -d \"\$hora_desconexion\" +\"%B\" 2>/dev/null | tr '[:upper:]' '[:lower:]')
                                    desconexion_fmt=\$(LC_ALL=es_SV.UTF-8 date -d \"\$hora_desconexion\" +\"%d/\$des_month %H:%M\" 2>/dev/null)

                                    historia_conexion=\"
-------------------------
🌷 Conectada    \$conexion_fmt
🌙 Desconectada       \$desconexion_fmt
⏰ Duración   \$duracion
-------------------------\"
                                else
                                    ultima_conexion=\"😴 Nunca conectado\"
                                fi

                                if [[ \$conexiones -gt 0 ]]; then
                                    conex_info=\"📲 CONEXIONES \$conexiones 🟢\"
                                    if [[ -f \"\$tmp_status\" ]]; then
                                        contenido=\$(cat \"\$tmp_status\")
                                        if [[ \"\$contenido\" =~ ^[0-9]+$ ]]; then
                                            start_s=\$((10#\$contenido))
                                        else
                                            start_s=\$(date +%s)
                                            echo \$start_s > \"\$tmp_status\"
                                        fi
                                        now_s=\$(date +%s)
                                        elapsed=\$(( now_s - start_s ))
                                        h=\$(( elapsed / 3600 ))
                                        m=\$(( (elapsed % 3600) / 60 ))
                                        s=\$(( elapsed % 60 ))
                                        tiempo_conectado=\$(printf \"⏰ TIEMPO CONECTADO    %02d:%02d:%02d\" \"\$h\" \"\$m\" \"\$s\")
                                    else
                                        tiempo_conectado=\"⏰  TIEMPO CONECTADO    N/A\"
                                    fi
                                else
                                    conex_info=\"📲 CONEXIONES 0 🔴\"
                                fi

                                INFO=\"💖 *INFORMACIÓN DE \${usuario^^}* 💖

🕒 *FECHA*: \\\`\${fecha_actual}\\\`
👩 *Usuario* \\\`\${usuario}\\\`
🔒 *Clave* \\\`\${clave}\\\`
📅 *Expira* \\\`\${fecha_expiracion}\\\`
⏳ *Días* \\\`\${dias_restantes}\\\`
📲 *Móviles* \\\`\${moviles}\\\`
\$conex_info
📱 *MÓVILES* \\\`\${moviles}\\\`\"
                                if [[ \"\$ultima_conexion\" != \"😴 Nunca conectado\" ]]; then
                                    INFO=\"\$INFO
\$ultima_conexion\"
                                fi
                                if [[ -n \"\$tiempo_conectado\" ]]; then
                                    INFO=\"\$INFO
\$tiempo_conectado\"
                                fi
                                if [[ -n \"\$historia_conexion\" ]]; then
                                    INFO=\"\$INFO
\$historia_conexion\"
                                elif [[ \"\$ultima_conexion\" == \"😴 Nunca conectado\" ]]; then
                                    INFO=\"\$INFO
\$ultima_conexion\"
                                fi

                                INFO=\"\$INFO

Escribe *hola* para volver al menú.\"

                                curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"\$INFO\" -d parse_mode=Markdown >/dev/null
                                EXPECTING_USER_DETAILS=0
                                USER_MAP=()
                            else
                                case \"\$MSG_TEXT\" in
                                    'Hola'|'hola'|'/start')
                                        MENU=\"¡Hola! 😏 *$USER_NAME* 👋 Te invito a seleccionar una de estas opciones:

🔧 *Presiona 1* para crear usuario
📋 *Presiona 2* para ver los usuarios registrados
🗑️ *Presiona 3* para eliminar usuario
🔄 *Presiona 4* para renovar usuario
✅ *Presiona 5* para mostrar usuarios conectados
💾 *Presiona 6* para crear backup
📥 *Presiona 7* para restaurar backup
👁️‍🗨️ *Presiona 8* para información detallada de usuario
🏠 *Presiona 0* para volver al menú principal\"
                                        curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"\$MENU\" -d parse_mode=Markdown >/dev/null
                                        ;;
                                    '1')
                                        curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"🔧 *Crear Usuario SSH* 🆕

👤 Ingresa el nombre del usuario:\" -d parse_mode=Markdown >/dev/null
                                        EXPECTING_USER_DATA=1
                                        USER_DATA_STEP=1
                                        ;;
                                    '2')
                                        if [[ ! -f \"\$REGISTROS\" || ! -s \"\$REGISTROS\" ]]; then
                                            curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"📋 *Lista de Usuarios* ❌

🔍 *No hay usuarios SSH registrados*
💡 Usa la opción 1 para crear uno\" -d parse_mode=Markdown >/dev/null
                                        else
                                            LISTA=\"🌸 *REGISTROS DE USUARIOS* 🌸

*Usuario     clave.      Expi.    Dias.  Moviles*
\"
                                            count=1
                                            while IFS=' ' read -r user_data fecha_expiracion dias moviles _; do
                                                usuario=\${user_data%%:*}
                                                clave=\${user_data#*:}
                                                dias_restantes=\$(calcular_dias_restantes \"\$fecha_expiracion\")
                                                dia=\$(echo \"\$fecha_expiracion\" | cut -d'/' -f1)
                                                mes=\$(echo \"\$fecha_expiracion\" | cut -d'/' -f2)
                                                case \$mes in
                                                    enero) mes=\"ene\" ;;
                                                    febrero) mes=\"feb\" ;;
                                                    marzo) mes=\"mar\" ;;
                                                    abril) mes=\"abr\" ;;
                                                    mayo) mes=\"may\" ;;
                                                    junio) mes=\"jun\" ;;
                                                    julio) mes=\"jul\" ;;
                                                    agosto) mes=\"ago\" ;;
                                                    septiembre) mes=\"sep\" ;;
                                                    octubre) mes=\"oct\" ;;
                                                    noviembre) mes=\"nov\" ;;
                                                    diciembre) mes=\"dic\" ;;
                                                esac
                                                fecha_corta=\"\$dia/\$mes\"

                                                LISTA=\"\${LISTA}*\${count}*. \\\`\${usuario}:\${clave}\\\` | \\\`Exp \${fecha_corta}\\\` | \${dias_restantes} d | \${moviles}

\"
                                                ((count++))
                                            done < \"\$REGISTROS\"

                                            TOTAL=\$((count - 1))
                                            LISTA=\"\${LISTA}*Total registrados:* \$TOTAL usuarios\"
                                            curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"\$LISTA\" -d parse_mode=Markdown >/dev/null
                                        fi
                                        ;;
                                    '3')
                                        if [[ ! -f \"\$REGISTROS\" || ! -s \"\$REGISTROS\" ]]; then
                                            curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"❌ *No hay usuarios registrados.*
Escribe *hola* para volver al menú.\" -d parse_mode=Markdown >/dev/null
                                        else
                                            LISTA=\"¡Hola! 😏 *$USER_NAME* Aquí te muestro todos los usuarios que tienes registrados, solo pon un usuario y lo vamos a eliminar al instante 😈

\"
                                            while IFS=' ' read -r user_data _; do
                                                usuario=\${user_data%%:*}
                                                LISTA=\"\${LISTA}\\\`\${usuario}\\\`
\"
                                            done < \"\$REGISTROS\"
                                            curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"\$LISTA\" -d parse_mode=Markdown >/dev/null
                                            curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"🗑️ Ingresa el nombre del usuario a eliminar:\" -d parse_mode=Markdown >/dev/null
                                            EXPECTING_DELETE_USER=1
                                        fi
                                        ;;
                                    '4')
                                        if [[ ! -f \"\$REGISTROS\" || ! -s \"\$REGISTROS\" ]]; then
                                            curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"❌ *No hay usuarios registrados.*
Escribe *hola* para volver al menú.\" -d parse_mode=Markdown >/dev/null
                                        else
                                            LISTA=\"🌸 *USUARIOS REGISTRADOS* 🌸

Selecciona un usuario para renovar:

\"
                                            count=1
                                            while IFS=' ' read -r user_data _; do
                                                usuario=\${user_data%%:*}
                                                LISTA=\"\${LISTA}\${count}. \\\`\${usuario}\\\`
\"
                                                ((count++))
                                            done < \"\$REGISTROS\"
                                            curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"\$LISTA\" -d parse_mode=Markdown >/dev/null
                                            curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"👤 *Ingresa el nombre del usuario a renovar:*\" -d parse_mode=Markdown >/dev/null
                                            EXPECTING_RENEW_USER=1
                                            RENEW_STEP=1
                                        fi
                                        ;;
                                    '5')
                                        if [[ ! -f \"\$REGISTROS\" || ! -s \"\$REGISTROS\" ]]; then
                                            curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"❌ *No hay usuarios registrados.*
Escribe *hola* para volver al menú.\" -d parse_mode=Markdown >/dev/null
                                        else
                                            FECHA_ACTUAL=\$(date +\"%Y-%m-%d %H:%M\")
                                            LISTA=\"===== 🥳 *USUARIOS ONLINE* 😎 =====

*USUARIO  CONEXIONES  MÓVILES  CONECTADO*
-----------------------------------------------------------------

\"
                                            LISTA_TXT=\"===== 🥳 USUARIOS ONLINE 😎 =====\n\nUSUARIO  CONEXIONES  MÓVILES  CONECTADO\n-----------------------------------------------------------------\n\"
                                            total_online=0
                                            total_usuarios=0
                                            inactivos=0

                                            while IFS=' ' read -r userpass fecha_exp dias moviles fecha_crea hora_crea; do
                                                usuario=\${userpass%%:*}
                                                if ! id \"\$usuario\" &>/dev/null; then
                                                    continue
                                                fi
                                                (( total_usuarios++ ))
                                                conexiones=\$(( \$(ps -u \"\$usuario\" -o comm= | grep -cE \"^(sshd|dropbear)\$\") ))
                                                tmp_status=\"/tmp/status_\${usuario}.tmp\"
                                                bloqueo_file=\"/tmp/bloqueo_\${usuario}.lock\"
                                                detalle=\"😴 Nunca conectado\"

                                                if [[ -f \"\$bloqueo_file\" ]]; then
                                                    bloqueo_hasta=\$(cat \"\$bloqueo_file\")
                                                    if [[ \$(date +%s) -lt \$bloqueo_hasta ]]; then
                                                        detalle=\"🚫 Bloqueado (hasta \$(date -d @\$bloqueo_hasta '+%I:%M%p'))\"
                                                    else
                                                        rm -f \"\$bloqueo_file\"
                                                    fi
                                                fi

                                                if [[ \$conexiones -gt 0 ]]; then
                                                    (( total_online += conexiones ))
                                                    if [[ -f \"\$tmp_status\" ]]; then
                                                        contenido=\$(cat \"\$tmp_status\")
                                                        if [[ \"\$contenido\" =~ ^[0-9]+$ ]]; then
                                                            start_s=\$((10#\$contenido))
                                                        else
                                                            start_s=\$(date +%s)
                                                            echo \$start_s > \"\$tmp_status\"
                                                        fi
                                                        now_s=\$(date +%s)
                                                        elapsed=\$(( now_s - start_s ))
                                                        h=\$(( elapsed / 3600 ))
                                                        m=\$(( (elapsed % 3600) / 60 ))
                                                        s=\$(( elapsed % 60 ))
                                                        detalle=\$(printf \"⏰ %02d:%02d:%02d\" \"\$h\" \"\$m\" \"\$s\")
                                                    else
                                                        start_s=\$(date +%s)
                                                        echo \$start_s > \"\$tmp_status\"
                                                        detalle=\"⏰ 00:00:00\"
                                                    fi
                                                else
                                                    if [[ ! \$detalle =~ \"🚫 Bloqueado\" ]]; then
                                                        rm -f \"\$tmp_status\"
                                                        ult=\$(grep \"^\$usuario|\" \"\$HISTORIAL\" | tail -1 | awk -F'|' '{print \$3}')
                                                        if [[ -n \"\$ult\" ]]; then
                                                            ult_fmt=\$(date -d \"\$ult\" +\"%d/%b/%Y %H:%M\" 2>/dev/null)
                                                            if [[ -n \"\$ult_fmt\" ]]; then
                                                                detalle=\"📅 Última: \$ult_fmt\"
                                                            else
                                                                detalle=\"😴 Nunca conectado\"
                                                            fi
                                                        else
                                                            detalle=\"😴 Nunca conectado\"
                                                        fi
                                                        (( inactivos++ ))
                                                    fi
                                                fi
                                                if [[ \$conexiones -gt 0 ]]; then
                                                    conexiones_status=\"\$conexiones 🟢\"
                                                else
                                                    conexiones_status=\"\$conexiones 🔴\"
                                                fi

                                                LISTA=\"\${LISTA}🕒 *FECHA*: \\\`\${FECHA_ACTUAL}\\\`
*🧑‍💻Usuario*: \\\`\${usuario}\\\`
*🌐Conexiones*: \$conexiones_status
*📲Móviles*: \$moviles
*🟣Estado del cliente*: \$detalle

\"
                                                LISTA_TXT=\"\${LISTA_TXT}🕒 FECHA: \$FECHA_ACTUAL\n🧑‍💻Usuario: \$usuario\n🌐Conexiones: \$conexiones_status\n📲Móviles: \$moviles\n🟣Estado del cliente: \$detalle\n\n\"
                                            done < \"\$REGISTROS\"

                                            LISTA=\"\${LISTA}-----------------------------------------------------------------
*Total de Online:* \$total_online  *Total usuarios:* \$total_usuarios  *Inactivos:* \$inactivos
=================================================\"
                                            LISTA_TXT=\"\${LISTA_TXT}-----------------------------------------------------------------\nTotal de Online: \$total_online  Total usuarios: \$total_usuarios  Inactivos: \$inactivos\n=================================================\"

                                            temp_users=\"/tmp/usuarios_online_\$(date +%Y%m%d_%H%M%S).txt\"
                                            echo -e \"\$LISTA_TXT\" > \"\$temp_users\"
                                            curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"\$LISTA\" -d parse_mode=Markdown >/dev/null
                                            curl -s -X POST \"\$URL/sendDocument\" -F chat_id=\$CHAT_ID -F document=@\"\$temp_users\" -F parse_mode=Markdown >/dev/null
                                            rm -f \"\$temp_users\"
                                        fi
                                        ;;
                                    '6')
                                        if [[ ! -f \"\$REGISTROS\" || ! -s \"\$REGISTROS\" ]]; then
                                            curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"❌ *No hay usuarios registrados para crear backup.*
Escribe *hola* para volver al menú.\" -d parse_mode=Markdown >/dev/null
                                        else
                                            temp_backup=\"/tmp/backup_\$(date +%Y%m%d_%H%M%S).txt\"
                                            cp \"\$REGISTROS\" \"\$temp_backup\"
                                            curl -s -X POST \"\$URL/sendDocument\" -F chat_id=\$CHAT_ID -F document=@\"\$temp_backup\" -F parse_mode=Markdown >/dev/null
                                            rm -f \"\$temp_backup\"
                                        fi
                                        ;;
                                    '7')
                                        curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"📥 *Envía el archivo de backup (TXT) para restaurar los usuarios.* Escribe 'cancel' para cancelar.\" -d parse_mode=Markdown >/dev/null
                                        EXPECTING_BACKUP=1
                                        ;;
                                    '8')
                                        if [[ ! -f \"\$REGISTROS\" || ! -s \"\$REGISTROS\" ]]; then
                                            curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"😿 *No hay registros disponibles.* Escribe *hola* para volver al menú.\" -d parse_mode=Markdown >/dev/null
                                        else
                                            LISTA=\"===== 🌸 *REGISTROS* =====
\"
                                            count=1
                                            USER_MAP=()
                                            while IFS=' ' read -r user_data fecha_expiracion dias moviles fecha_creacion1 fecha_creacion2; do
                                                usuario=\${user_data%%:*}
                                                USER_MAP[\$count]=\"\$usuario\"
                                                LISTA=\"\${LISTA}\${count} \\\`\${usuario}\\\`
\"
                                                ((count++))
                                            done < \"\$REGISTROS\"
                                            curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"\$LISTA\" -d parse_mode=Markdown >/dev/null
                                            curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"🌟 *Ingresa el número o nombre del usuario:*\" -d parse_mode=Markdown >/dev/null
                                            EXPECTING_USER_DETAILS=1
                                        fi
                                        ;;
                                    '0')
                                        curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"🏠 *Menú Principal* 🔙

✅ *Regresando al menú...*
👋 ¡Hasta pronto!\" -d parse_mode=Markdown >/dev/null
                                        ;;

                                    
                                    *)
                                        curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"❓ *Opción no válida* ⚠️

🤔 No entiendo esa opción...
💡 Escribe *hola* para ver el menú
🔢 O usa: 1, 2, 3, 4, 5, 6, 7, 8, 0\" -d parse_mode=Markdown >/dev/null
                                        ;;
                                esac
                            fi
                        fi
                    done
                done
            " >/dev/null 2>&1 &
            echo $! > "$PIDFILE"
            echo -e "${VERDE}✅ Bot activado y corriendo en segundo plano (PID: $(cat $PIDFILE)).${NC}"
            echo -e "${AMARILLO_SUAVE}💡 El bot responderá a 'hola' con el menú interactivo.${NC}"
            ;;
        2)
            if [[ -f "$PIDFILE" ]]; then
                kill -9 $(cat "$PIDFILE") 2>/dev/null
                rm -f "$PIDFILE"
            fi
            rm -f /root/sshbot_token /root/sshbot_userid /root/sshbot_username
            pkill -f "api.telegram.org"
            echo -e "${ROJO}❌ Token eliminado y bot detenido.${NC}"
            ;;
        0)
            return
            ;;
        *)
            echo -e "${ROJO}❌ ¡Opción inválida!${NC}"
            ;;
    esac
}              

    
    function barra_sistema() {  
    # ================= Colores =================  
    BLANCO='\033[97m'  
    AZUL='\033[94m'  
    MAGENTA='\033[95m'  
    ROJO='\033[91m'  
    AMARILLO='\033[93m'  
    VERDE='\033[92m'  
    NC='\033[0m'  
    CIAN='\033[38;5;51m'  # Para inactivos

    # ================= Config persistente =================
    STATE_FILE="/etc/mi_script/contador_online.conf"

    # ================= Usuarios =================  
    TOTAL_CONEXIONES=0  
    TOTAL_USUARIOS=0  
    USUARIOS_EXPIRAN=()  
    inactivos=0  

    if [[ -f "$REGISTROS" ]]; then  
        while IFS=' ' read -r user_data fecha_expiracion dias moviles fecha_creacion; do  
            usuario=${user_data%%:*}  
            if id "$usuario" &>/dev/null; then  
                ((TOTAL_USUARIOS++))  
                DIAS_RESTANTES=$(calcular_dias_restantes "$fecha_expiracion")  
                if [[ $DIAS_RESTANTES -eq 0 ]]; then  
                    USUARIOS_EXPIRAN+=("${BLANCO}${usuario}${NC} ${AMARILLO}0 Días${NC}")  
                fi  
                conexiones=$(( $(ps -u "$usuario" -o comm= | grep -cE "^(sshd|dropbear)$") ))  
                bloqueo_file="/tmp/bloqueo_${usuario}.lock"  
                if [[ $conexiones -eq 0 && ! -f "$bloqueo_file" ]]; then  
                    ((inactivos++))  
                elif [[ -f "$bloqueo_file" ]]; then  
                    bloqueo_hasta=$(cat "$bloqueo_file")  
                    if [[ $(date +%s) -ge $bloqueo_hasta ]]; then  
                        rm -f "$bloqueo_file"  
                        ((inactivos++))  
                    fi  
                fi  
            fi  
        done < "$REGISTROS"  
    fi  

    # ================= Contador Online =================  
    TOTAL_CONEXIONES=0
    if [[ -f "$STATE_FILE" ]] && [[ "$(cat "$STATE_FILE")" == "ON" ]]; then
        if [[ -f "$REGISTROS" ]]; then  
            while IFS=' ' read -r user_data fecha_expiracion dias moviles fecha_creacion; do  
                usuario=${user_data%%:*}  
                if id "$usuario" &>/dev/null; then  
                    CONEXIONES_SSH=$(ps -u "$usuario" -o comm= | grep -c "^sshd$")  
                    CONEXIONES_DROPBEAR=$(ps -u "$usuario" -o comm= | grep -c "^dropbear$")  
                    CONEXIONES=$((CONEXIONES_SSH + CONEXIONES_DROPBEAR))  
                    TOTAL_CONEXIONES=$((TOTAL_CONEXIONES + CONEXIONES))  
                fi  
            done < "$REGISTROS"  
        fi  
        ONLINE_STATUS="${VERDE}🟢 ONLINE: ${AMARILLO}${TOTAL_CONEXIONES}${NC}"  
    else  
        ONLINE_STATUS="${ROJO}🔴 ONLINE OFF${NC}"  
        TOTAL_CONEXIONES=0  
    fi

    # ================= Memoria =================  
    MEM_TOTAL=$(free -m | awk '/^Mem:/ {print $2}')  
    MEM_USO=$(free -m | awk '/^Mem:/ {print $3}')  
    MEM_DISPONIBLE=$(free -m | awk '/^Mem:/ {print $7}')  
    MEM_PORC=$((100 * MEM_USO / MEM_TOTAL))

    human() {  
        local value=$1  
        if [ "$value" -ge 1024 ]; then  
            awk "BEGIN {printf \"%.1fG\", $value/1024}"  
        else  
            echo "${value}M"  
        fi  
    }  

    MEM_TOTAL_H=$(human "$MEM_TOTAL")  
    MEM_DISPONIBLE_H=$(human "$MEM_DISPONIBLE")

    # ================= Disco =================  
    DISCO_INFO=$(df -h / | awk '/\// {print $2, $3, $4, $5}' | tr -d '%')  
    read -r DISCO_TOTAL_H DISCO_USO_H DISCO_DISPONIBLE_H DISCO_PORC <<< "$DISCO_INFO"  
    if [ "${DISCO_PORC%.*}" -ge 80 ]; then  
        DISCO_PORC_COLOR="${ROJO}${DISCO_PORC}%${NC}"  
    elif [ "${DISCO_PORC%.*}" -ge 50 ]; then  
        DISCO_PORC_COLOR="${AMARILLO}${DISCO_PORC}%${NC}"  
    else  
        DISCO_PORC_COLOR="${VERDE}${DISCO_PORC}%${NC}"  
    fi  

    # ================= CPU tipo kernel instantáneo =================
    CPU_STAT_FILE="/tmp/.cpu_stat_prev"
    read cpu a b c d e f g h i j < /proc/stat
    idle=$d
    total=$((a+b+c+d+e+f+g+h+i+j))
    if [[ -f "$CPU_STAT_FILE" ]]; then
        read prev_total prev_idle < "$CPU_STAT_FILE"
        diff_idle=$((idle - prev_idle))
        diff_total=$((total - prev_total))
        if [[ $diff_total -gt 0 ]]; then
            CPU_PORC=$(( (100 * (diff_total - diff_idle)) / diff_total ))
        else
            CPU_PORC=0
        fi
    else
        CPU_PORC=0
    fi
    echo "$total $idle" > "$CPU_STAT_FILE"

    CPU_MHZ=$(awk -F': ' '/^cpu MHz/ {sum+=$2; n++} END {if(n>0) printf "%.3f", sum/n; else print "Desconocido"}' /proc/cpuinfo)
    CPU_CORES=$(nproc)   # Detecta automáticamente los núcleos
    # ================= IP y fecha =================  
    if command -v curl &>/dev/null; then  
        IP_PUBLICA=$(curl -s ifconfig.me)  
    elif command -v wget &>/dev/null; then  
        IP_PUBLICA=$(wget -qO- ifconfig.me)  
    else  
        IP_PUBLICA="No disponible"  
    fi  
    FECHA_ACTUAL=$(date +"%Y-%m-%d %I:%M")  

    # ================= Sistema =================  
    if [[ -f /etc/os-release ]]; then  
        SO_NAME=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2- | tr -d '"')  
    else  
        SO_NAME=$(uname -o)  
    fi  

    ENABLED="/tmp/limitador_enabled"  
    PIDFILE="/Abigail/mon.pid"  
    if [[ -f "$ENABLED" ]] && [[ -f "$PIDFILE" ]] && ps -p "$(cat "$PIDFILE" 2>/dev/null)" >/dev/null 2>&1; then  
        LIMITADOR_ESTADO="${VERDE}ACTIVO 🟢${NC}"  
    else  
        LIMITADOR_ESTADO="${ROJO}DESACTIVADO 🔴${NC}"  
    fi  

    # ================= Uptime =================    
 uptime_seconds=$(cut -d. -f1 /proc/uptime)

if (( uptime_seconds < 3600 )); then
    minutos=$(( uptime_seconds / 60 ))
    [[ $minutos -lt 1 ]] && minutos=0

    if (( minutos == 1 )); then
        texto="1 minuto"
    else
        texto="${minutos} minutos"
    fi

elif (( uptime_seconds < 86400 )); then
    horas=$(( uptime_seconds / 3600 ))
    minutos_restantes=$(( (uptime_seconds % 3600) / 60 ))

    hora_texto=$([[ $horas == 1 ]] && echo "1 hora" || echo "${horas} horas")

    if (( minutos_restantes == 0 )); then
        texto="${hora_texto}"
    elif (( minutos_restantes == 1 )); then
        texto="${hora_texto} 1 minuto"
    else
        texto="${hora_texto} ${minutos_restantes} minutos"
    fi

elif (( uptime_seconds < 2592000 )); then
    dias=$(( uptime_seconds / 86400 ))
    horas_restantes=$(( (uptime_seconds % 86400) / 3600 ))

    dia_texto=$([[ $dias == 1 ]] && echo "1 día" || echo "${dias} días")

    if (( horas_restantes == 0 )); then
        texto="${dia_texto}"
    elif (( horas_restantes == 1 )); then
        texto="${dia_texto} 1 hora"
    else
        texto="${dia_texto} ${horas_restantes} horas"
    fi

else
    meses=$(( uptime_seconds / 2592000 ))
    dias=$(( (uptime_seconds % 2592000) / 86400 ))

    mes_texto=$([[ $meses == 1 ]] && echo "1 mes" || echo "${meses} meses")

    if (( dias == 0 )); then
        texto="${mes_texto}"
    elif (( dias == 1 )); then
        texto="${mes_texto} 1 día"
    else
        texto="${mes_texto} ${dias} días"
    fi
fi

UPTIME_COLOR="${MAGENTA} 🕓 UPTIME: ${AMARILLO}${texto}${NC}"


    # ================= Load average =================
LOAD_RAW=$(uptime | awk -F'load average:' '{print $2}' | xargs)
read -r LOAD_1 LOAD_5 LOAD_15 <<< $(echo $LOAD_RAW | tr ',' ' ')

# Colores según carga vs núcleos
load_icon() {
    local carga=$1
    local cores=$2
    local ratio=$(echo "$carga / $cores" | bc -l)

    # Si solo tiene 1 núcleo, reglas especiales
    if [[ "$cores" -eq 1 ]]; then
        if (( $(echo "$carga < 1.2" | bc -l) )); then
            echo "🟢"
        elif (( $(echo "$carga < 2.0" | bc -l) )); then
            echo "🟡"
        elif (( $(echo "$carga < 3.0" | bc -l) )); then
            echo "🔴"
        else
            echo "💀"
        fi
    else
        # Multi-core (ratio normalizado)
        if (( $(echo "$ratio < 0.50" | bc -l) )); then
            echo "🟢"
        elif (( $(echo "$ratio < 1.00" | bc -l) )); then
            echo "🟡"
        elif (( $(echo "$ratio < 1.50" | bc -l) )); then
            echo "🔴"
        else
            echo "💀"
        fi
    fi
}

ICON_LOAD=$(load_icon $LOAD_1 $CPU_CORES)
LOAD_AVG="${ICON_LOAD} ${LOAD_1}, ${LOAD_5}, ${LOAD_15}"
    # ================= Transferencia =================  
TRANSFER_FILE="/tmp/vps_transfer_total"  
LAST_FILE="/tmp/vps_transfer_last"  

RX_TOTAL=$(awk '/eth0|ens|enp|wlan|wifi/{rx+=$2} END{print rx}' /proc/net/dev)  
TX_TOTAL=$(awk '/eth0|ens|enp|wlan|wifi/{tx+=$10} END{print tx}' /proc/net/dev)  

TOTAL_BYTES=$((RX_TOTAL + TX_TOTAL))

if [[ ! -f "$LAST_FILE" ]]; then
    TRANSFER_ACUM=0
    echo "$TOTAL_BYTES" > "$LAST_FILE"
else
    LAST_TOTAL=$(cat "$LAST_FILE")
    DIFF=$((TOTAL_BYTES - LAST_TOTAL))
    [[ -f "$TRANSFER_FILE" ]] && TRANSFER_ACUM=$(cat "$TRANSFER_FILE") || TRANSFER_ACUM=0
    TRANSFER_ACUM=$((TRANSFER_ACUM + DIFF))
    echo "$TOTAL_BYTES" > "$LAST_FILE"
    echo "$TRANSFER_ACUM" > "$TRANSFER_FILE"
fi

human_transfer() {
    local bytes=$1
    local value
    local unit

    if (( bytes >= 1099511627776 )); then       # >= 1 TB
        value=$(awk "BEGIN {printf \"%.1f\", $bytes / 1099511627776}")
        unit="TB"
    elif (( bytes >= 1073741824 )); then        # >= 1 GB
        value=$(awk "BEGIN {printf \"%.1f\", $bytes / 1073741824}")
        unit="GB"
    else                                        # < 1 GB
        value=$(( bytes / 1048576 ))
        unit="MB"
    fi

    [[ "$value" == *".0" ]] && value="${value%.0}"

    echo "${value} ${unit}"
}

TRANSFER_DISPLAY=$(human_transfer "$TRANSFER_ACUM")

    # ================= Imprimir todo =================  
    echo -e "${AZUL}═══════════════════════════════════════════════════${NC}"
    echo -e "${BLANCO} 💾 TOTAL:${AMARILLO} ${MEM_TOTAL_H}${NC}     ${BLANCO}∘ 💧 DISPONIBLE:${AMARILLO} ${MEM_DISPONIBLE_H}${NC} ${BLANCO}∘ 💿 HDD:${AMARILLO} ${DISCO_TOTAL_H}${NC} ${DISCO_PORC_COLOR}"
    echo -e "${BLANCO} 📊 U/RAM: ${MEM_PORC}%   🖥️ U/CPU: ${CPU_PORC}%       🔧 CPU MHz: ${CPU_MHZ}${NC}"
    echo -e "${AZUL}═══════════════════════════════════════════════════${NC}"
    echo -e "${BLANCO} 🌍 IP:${AMARILLO} ${IP_PUBLICA}${NC}          ${BLANCO} 🕒 FECHA:${AMARILLO} ${FECHA_ACTUAL}${NC}"
    echo -e "${BLANCO} 🖼️ SO:${AMARILLO}${SO_NAME}${NC}        ${BLANCO}📡 TRANSFERENCIA TOTAL:${AMARILLO} ${TRANSFER_DISPLAY}${NC}"
    echo -e "${UPTIME_COLOR}${BLANCO}.${NC}"
    echo -e "${MAGENTA} 📈 Load average:${NC} ${LOAD_AVG}"
    echo -e "${BLANCO} ${ONLINE_STATUS}    👥️ TOTAL:${AMARILLO}${TOTAL_USUARIOS}${NC}    ${CIAN}🔴 Inactivos:${AMARILLO} ${inactivos}${NC}"
    echo -e "${AZUL}═══════════════════════════════════════════════════${NC}"
    echo -e "${BLANCO} LIMITADOR:${NC} ${LIMITADOR_ESTADO}"
    if [[ ${#USUARIOS_EXPIRAN[@]} -gt 0 ]]; then
        echo -e "${ROJO}⚠️ USUARIOS QUE EXPIRAN HOY:${NC}"
        echo -e "${USUARIOS_EXPIRAN[*]}"
    fi
}

        

    function contador_online() {
    STATE_FILE="/etc/mi_script/contador_online.conf"
    mkdir -p /etc/mi_script

    if [[ -f "$STATE_FILE" ]] && [[ "$(cat "$STATE_FILE")" == "ON" ]]; then
        nohup bash -c "echo 'OFF' > '$STATE_FILE'" >/dev/null 2>&1 &
        echo -e "${VERDE}Contador de usuarios en línea desactivado 🔴${NC}"
    else
        nohup bash -c "echo 'ON' > '$STATE_FILE'" >/dev/null 2>&1 &
        echo -e "${VERDE}Contador de usuarios en línea activado 🟢${NC}"
    fi

    read -p "$(echo -e ${BLANCO}Presiona Enter para continuar...${NC})"
}



function informacion_usuarios() {
    clear

    # Definir colores  
    ROSADO='\033[38;5;211m'  
    LILA='\033[38;5;183m'  
    TURQUESA='\033[38;5;45m'  
    NC='\033[0m'  

    echo -e "${ROSADO}🌸✨  INFORMACIÓN DE CONEXIONES 💖✨ 🌸${NC}"  

    # Mapa de meses para traducción (abreviaturas en español minúsculas a completo)
    declare -A month_map=(  
        ["ene"]="enero" ["feb"]="febrero" ["mar"]="marzo" ["abr"]="abril"  
        ["may"]="mayo" ["jun"]="junio" ["jul"]="julio" ["ago"]="agosto"  
        ["sep"]="septiembre" ["oct"]="octubre" ["nov"]="noviembre" ["dic"]="diciembre"  
    )  

    # Verificar si al menos uno de los archivos existe  
    if [[ ! -f "$REGISTROS" && ! -f "$HISTORIAL" ]]; then  
        echo -e "${LILA}😿 ¡Oh no! No hay registros ni historial de conexiones aún, pequeña! 💔${NC}"  
        read -p "$(echo -e ${TURQUESA}Presiona Enter para seguir, corazón... 💌${NC})"  
        return 1  
    fi  

    # Inicializar el archivo de log (sobrescribir cada vez para info actual)  
    echo "🌸✨  INFORMACIÓN DE CONEXIONES 💖✨ 🌸" > "$LOGFILE"  
    printf "%-15s %-22s %-22s %-12s\n" "Usuaria" "Conectada" "Desconectada" "Duración" >> "$LOGFILE"  
    echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" >> "$LOGFILE"  

    # Encabezado de la tabla en pantalla  
    printf "${LILA}%-15s %-22s %-22s %-12s${NC}\n" "👩‍💼 Usuaria" "🌷 Conectada" "🌙 Desconectada" "⏰  Duración"  
    echo -e "${ROSADO}~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~${NC}"  

    # Obtener lista única de usuarios desde REGISTROS y HISTORIAL  
    mapfile -t USUARIOS_REG < <(sort -u "$REGISTROS" 2>/dev/null)  
    mapfile -t USUARIOS_HIS < <(awk -F'|' '{print $1}' "$HISTORIAL" | sort -u 2>/dev/null)  
    mapfile -t USUARIOS < <(printf "%s\n" "${USUARIOS_REG[@]}" "${USUARIOS_HIS[@]}" | sort -u)  

    if [[ ${#USUARIOS[@]} -eq 0 ]]; then  
        echo -e "${LILA}😿 No hay usuarias registradas o con historial, dulce! 💔${NC}"  
        echo "No hay usuarias registradas o con historial." >> "$LOGFILE"  
    else  
        for USUARIO in "${USUARIOS[@]}"; do  
            if id "$USUARIO" &>/dev/null; then  
                # Inicializar valores por defecto  
                CONEXION_FMT="N/A"  
                DESCONEXION_FMT="N/A"  
                DURACION="N/A"  

                # Obtener el último registro válido del usuario desde HISTORIAL (con ambos tiempos presentes)  
                ULTIMO_REGISTRO=$(grep "^$USUARIO|" "$HISTORIAL" | grep -E '\|[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\|[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}' | tail -1)  
                if [[ -n "$ULTIMO_REGISTRO" ]]; then  
                    IFS='|' read -r _ HORA_CONEXION HORA_DESCONEXION _ <<< "$ULTIMO_REGISTRO"  

                    if [[ "$HORA_CONEXION" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]][0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then  
                        # Formatear conexión  
                        CONEXION_FMT=$(date -d "$HORA_CONEXION" +"%d/%b %I:%M %p" 2>/dev/null)  
                        # Traducir meses a español  
                        for eng in "${!month_map[@]}"; do  
                            esp=${month_map[$eng]}  
                            CONEXION_FMT=${CONEXION_FMT/$eng/$esp}  
                        done  

                        SEC_CON=$(date -d "$HORA_CONEXION" +%s 2>/dev/null)  

                        if [[ "$HORA_DESCONEXION" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]][0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then  
                            # Formatear desconexión  
                            DESCONEXION_FMT=$(date -d "$HORA_DESCONEXION" +"%d/%b %I:%M %p" 2>/dev/null)  
                            # Traducir meses a español  
                            for eng in "${!month_map[@]}"; do  
                                esp=${month_map[$eng]}  
                                DESCONEXION_FMT=${DESCONEXION_FMT/$eng/$esp}  
                            done  

                            SEC_DES=$(date -d "$HORA_DESCONEXION" +%s 2>/dev/null)  
                        else  
                            # Asumir aún conectada si no hay desconexión válida  
                            DESCONEXION_FMT="Aún conectada"  
                            SEC_DES=$(date +%s)  
                        fi  

                        if [[ -n "$SEC_CON" && -n "$SEC_DES" && $SEC_DES -ge $SEC_CON ]]; then  
                            DURACION_SEG=$((SEC_DES - SEC_CON))  
                            HORAS=$((DURACION_SEG / 3600))  
                            MINUTOS=$(((DURACION_SEG % 3600) / 60))  
                            SEGUNDOS=$((DURACION_SEG % 60))  
                            DURACION=$(printf "%02d:%02d:%02d" $HORAS $MINUTOS $SEGUNDOS)  
                        fi  
                    fi  
                fi  

                # Si no se pudo obtener info válida de HISTORIAL, fallback a 'last'  
                if [[ "$CONEXION_FMT" == "N/A" ]]; then  
                    LAST_INFO=$(last -R -1 "$USUARIO" 2>/dev/null | head -1)  
                    if [[ -n "$LAST_INFO" && "$LAST_INFO" != *'wtmp begins'* ]]; then  
                        # Parsear salida de 'last'  
                        WEEKDAY=$(awk '{print $3}' <<< "$LAST_INFO")  
                        MONTH=$(awk '{print $4}' <<< "$LAST_INFO")  
                        DAY=$(awk '{print $5}' <<< "$LAST_INFO")  
                        LOGINTIME=$(awk '{print $6}' <<< "$LAST_INFO")  
                        NEXT=$(awk '{print $7}' <<< "$LAST_INFO")  

                        CURRENT_YEAR=$(date +%Y)  
                        LOGIN_STR="$MONTH $DAY $LOGINTIME $CURRENT_YEAR"  
                        SEC_CON=$(date -d "$LOGIN_STR" +%s 2>/dev/null)  

                        if [[ -n "$SEC_CON" ]]; then  
                            CONEXION_FMT=$(date -d "$LOGIN_STR" +"%d/%b %I:%M %p" 2>/dev/null)  
                            # Traducir meses a español  
                            for eng in "${!month_map[@]}"; do  
                                esp=${month_map[$eng]}  
                                CONEXION_FMT=${CONEXION_FMT/$eng/$esp}  
                            done  

                            if [[ "$NEXT" == "still" ]]; then  
                                DESCONEXION_FMT="Aún conectada"  
                                SEC_DES=$(date +%s)  
                            elif [[ "$NEXT" == "-" ]]; then  
                                LOGOUTTIME=$(awk '{print $8}' <<< "$LAST_INFO")  
                                if [[ "$LOGOUTTIME" =~ ^[0-2][0-9]:[0-5][0-9]$ ]]; then  
                                    # Usar duración para calcular SEC_DES (más preciso para multi-día)  
                                    DUR_STR=$(awk '{gsub(/[()]/,"",$9); print $9}' <<< "$LAST_INFO")  
                                    if [[ "$DUR_STR" =~ \+ ]]; then  
                                        DAYS=${DUR_STR%%+*}  
                                        HM=${DUR_STR##*+}  
                                        H=${HM%%:*}  
                                        M=${HM##*:}  
                                        DURACION_SEG=$((DAYS * 86400 + H * 3600 + M * 60))  
                                    else  
                                        H=${DUR_STR%%:*}  
                                        M=${DUR_STR##*:}  
                                        DURACION_SEG=$((H * 3600 + M * 60))  
                                    fi  
                                    SEC_DES=$((SEC_CON + DURACION_SEG))  
                                    DESCONEXION_FMT=$(date -d "@$SEC_DES" +"%d/%b %I:%M %p" 2>/dev/null)  
                                    # Traducir meses a español  
                                    for eng in "${!month_map[@]}"; do  
                                        esp=${month_map[$eng]}  
                                        DESCONEXION_FMT=${DESCONEXION_FMT/$eng/$esp}  
                                    done  
                                else  
                                    # Casos como 'down' o 'crash'  
                                    DESCONEXION_FMT="Desconectada (${LOGOUTTIME})"  
                                    DUR_STR=$(awk '{gsub(/[()]/,"",$9); print $9}' <<< "$LAST_INFO")  
                                    if [[ -n "$DUR_STR" ]]; then  
                                        if [[ "$DUR_STR" =~ \+ ]]; then  
                                            DAYS=${DUR_STR%%+*}  
                                            HM=${DUR_STR##*+}  
                                            H=${HM%%:*}  
                                            M=${HM##*:}  
                                            DURACION_SEG=$((DAYS * 86400 + H * 3600 + M * 60))  
                                        else  
                                            H=${DUR_STR%%:*}  
                                            M=${DUR_STR##*:}  
                                            DURACION_SEG=$((H * 3600 + M * 60))  
                                        fi  
                                        SEC_DES=$((SEC_CON + DURACION_SEG))  
                                    fi  
                                fi  
                            else  
                                DESCONEXION_FMT="N/A"  
                            fi  

                            if [[ -n "$SEC_DES" && $SEC_DES -ge $SEC_CON ]]; then  
                                DURACION_SEG=$((SEC_DES - SEC_CON))  
                                HORAS=$((DURACION_SEG / 3600))  
                                MINUTOS=$(((DURACION_SEG % 3600) / 60))  
                                SEGUNDOS=$((DURACION_SEG % 60))  
                                DURACION=$(printf "%02d:%02d:%02d" $HORAS $MINUTOS $SEGUNDOS)  
                            fi  
                        fi  
                    fi  
                fi  

                # Mostrar fila en pantalla  
                printf "${TURQUESA}%-15s %-22s %-22s %-12s${NC}\n" "$USUARIO" "$CONEXION_FMT" "$DESCONEXION_FMT" "$DURACION"  

                # Registrar en el log (sin colores)  
                printf "%-15s %-22s %-22s %-12s\n" "$USUARIO" "$CONEXION_FMT" "$DESCONEXION_FMT" "$DURACION" >> "$LOGFILE"  
            fi  
        done  
    fi  

    echo -e "${ROSADO}~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~${NC}"  
    echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" >> "$LOGFILE"  

    echo -e "${LILA}Puedes consultar el log con: cat $LOGFILE 🌟${NC}"  
    read -p "$(echo -e ${LILA}Presiona Enter para continuar, dulce... 🌟${NC})"
}
                        
                        
    
calcular_expiracion() {
    local dias=$1
    # FORZAR IDIOMA ESPAÑOL PARA QUE EL MES SALGA EN ESPAÑOL
    local fecha_expiracion=$(LC_ALL=es_SV.UTF-8 date -d "+$dias days" "+%d/%B/%Y")
    echo $fecha_expiracion
}

calcular_dias_restantes() {
    local fecha_expiracion="$1"

    local dia=$(echo "$fecha_expiracion" | cut -d'/' -f1)
    local mes=$(echo "$fecha_expiracion" | cut -d'/' -f2)
    local anio=$(echo "$fecha_expiracion" | cut -d'/' -f3)

    # Normalizar mes a minúsculas (FIX - ESTO ES LO NUEVO)
    mes=$(echo "$mes" | tr '[:upper:]' '[:lower:]')

    # Convertir mes español a número
    case $mes in
        "enero") mes_num="01" ;;
        "febrero") mes_num="02" ;;
        "marzo") mes_num="03" ;;
        "abril") mes_num="04" ;;
        "mayo") mes_num="05" ;;
        "junio") mes_num="06" ;;
        "julio") mes_num="07" ;;
        "agosto") mes_num="08" ;;
        "septiembre") mes_num="09" ;;
        "octubre") mes_num="10" ;;
        "noviembre") mes_num="11" ;;
        "diciembre") mes_num="12" ;;
        *) echo 0; return ;;
    esac

    local fecha_formateada="$anio-$mes_num-$dia"
    local fecha_actual=$(date "+%Y-%m-%d")

    local fecha_exp_epoch=$(date -d "$fecha_formateada" "+%s" 2>/dev/null)
    local fecha_act_epoch=$(date -d "$fecha_actual" "+%s")

    if [[ -z "$fecha_exp_epoch" ]]; then
        echo 0
        return
    fi

    local diff_segundos=$((fecha_exp_epoch - fecha_act_epoch))
    local dias_restantes=$((diff_segundos / 86400))

    if [ $dias_restantes -lt 0 ]; then
        dias_restantes=0
    fi

    echo $dias_restantes
}

# Función para crear usuario
function crear_usuario() {
    clear
    echo -e "${VIOLETA}===== 🤪 CREAR USUARIO SSH =====${NC}"
    read -p "$(echo -e ${AZUL}👤 Nombre del usuario: ${NC})" usuario
    read -p "$(echo -e ${AZUL}🔑 Contraseña: ${NC})" clave
    read -p "$(echo -e ${AZUL}📅 Días de validez: ${NC})" dias
    read -p "$(echo -e ${AZUL}📱 ¿Cuántos móviles? ${NC})" moviles

    # Validar entradas
    if [[ -z "$usuario" || -z "$clave" || -z "$dias" || -z "$moviles" ]]; then
        echo -e "${ROJO}❌ Todos los campos son obligatorios.${NC}"
        read -p "$(echo -e ${CIAN}Presiona Enter para continuar...${NC})"
        return
    fi

    if ! [[ "$dias" =~ ^[0-9]+$ ]] || ! [[ "$moviles" =~ ^[0-9]+$ ]]; then
        echo -e "${ROJO}❌ Días y móviles deben ser números.${NC}"
        read -p "$(echo -e ${CIAN}Presiona Enter para continuar...${NC})"
        return
    fi

    # Verificar si el usuario ya existe en el sistema
    if id "$usuario" >/dev/null 2>&1; then
        echo -e "${ROJO}❌ El usuario $usuario ya existe en el sistema.${NC}"
        read -p "$(echo -e ${CIAN}Presiona Enter para continuar...${NC})"
        return
    fi

    # Crear usuario en el sistema Linux
    if ! useradd -M -s /sbin/nologin "$usuario" 2>/dev/null; then
        echo -e "${ROJO}❌ Error al crear el usuario en el sistema.${NC}"
        read -p "$(echo -e ${CIAN}Presiona Enter para continuar...${NC})"
        return
    fi

    # Establecer la contraseña
    if ! echo "$usuario:$clave" | chpasswd 2>/dev/null; then
        echo -e "${ROJO}❌ Error al establecer la contraseña.${NC}"
        userdel "$usuario" 2>/dev/null
        read -p "$(echo -e ${CIAN}Presiona Enter para continuar...${NC})"
        return
    fi

    # Configurar fecha de expiración en el sistema (a las 00:00 del día siguiente al último día)
    fecha_expiracion_sistema=$(date -d "+$((dias + 1)) days" "+%Y-%m-%d")
    if ! chage -E "$fecha_expiracion_sistema" "$usuario" 2>/dev/null; then
        echo -e "${ROJO}❌ Error al establecer la fecha de expiración.${NC}"
        userdel "$usuario" 2>/dev/null
        read -p "$(echo -e ${CIAN}Presiona Enter para continuar...${NC})"
        return
    fi

    # Obtener fecha actual y de expiración para registros
    fecha_creacion=$(date "+%Y-%m-%d %H:%M:%S")
    fecha_expiracion=$(calcular_expiracion $dias)

    # Guardar en archivo de registros
    echo "$usuario:$clave $fecha_expiracion $dias $moviles $fecha_creacion" >> $REGISTROS

    # Guardar en historial
    echo "Usuario creado: $usuario, Expira: $fecha_expiracion, Móviles: $moviles, Creado: $fecha_creacion" >> $HISTORIAL
    # Singular o plural
    if [[ "$dias" -eq 1 ]]; then
        texto_dia="⌛ Día: 1"
        texto_resumen="1 día"
    else
        texto_dia="⌛ Días: $dias"
        texto_resumen="$dias días"
    fi

    # Mostrar confirmación
    echo -e "${VERDE}✅ Usuario creado correctamente:${NC}"
    echo -e "${AZUL}👤 Usuario: ${AMARILLO}$usuario${NC}"
    echo -e "${AZUL}🔑 Clave: ${AMARILLO}$clave${NC}"
    echo -e "${AZUL}📅 Expira: ${AMARILLO}$fecha_expiracion${NC}"
    echo -e "${AZUL}🧔 Usuario: ${AMARILLO}$usuario${NC}"
    echo -e "${AZUL}${texto_dia}${NC}"
    echo -e "${AZUL}📱 Límite móviles: ${AMARILLO}$moviles${NC}"
    echo -e "${AZUL}📅 Creado: ${AMARILLO}$fecha_creacion${NC}"
    echo -e "${VIOLETA}===== 📝 RESUMEN DE REGISTRO =====${NC}"
    echo -e "${AMARILLO}👤 Usuario    📅 Expira        ⏳ Días      📱 Móviles    📅 Creado${NC}"
    echo -e "${CIAN}---------------------------------------------------------------${NC}"
    printf "${VERDE}%-12s %-18s %-12s %-12s %s${NC}\n" "$usuario:$clave" "$fecha_expiracion" "$texto_resumen" "$moviles" "$fecha_creacion"
    echo -e "${CIAN}===============================================================${NC}"
    read -p "$(echo -e ${CIAN}Presiona Enter para continuar...${NC})"

}  

function ver_registros() {
    clear
    echo -e "${VIOLETA}===== 🌸 REGISTROS =====${NC}"
    echo -e "${AMARILLO}Nº 👩 Usuario 🔒 Clave   📅 Expira    ⏳  Días   📲 Móviles${NC}"
    if [[ ! -f $REGISTROS || ! -s $REGISTROS ]]; then
        echo -e "${ROJO}No hay registros disponibles.${NC}"
    else
        count=1
        while IFS=' ' read -r user_data fecha_expiracion dias moviles fecha_creacion1 fecha_creacion2; do
            usuario=${user_data%%:*}
            clave=${user_data#*:}
            # FIX: Se quitó el segundo parámetro "$dias"
            dias_restantes=$(calcular_dias_restantes "$fecha_expiracion")
            fecha_creacion="$fecha_creacion1 $fecha_creacion2"
            # Usar la fecha de expiración directamente, ya está en formato dd/mes/YYYY
            printf "${VERDE}%-2s ${VERDE}%-11s ${AZUL}%-10s ${VIOLETA}%-16s ${VERDE}%-8s ${AMARILLO}%-8s${NC}
" \
                "$count" "$usuario" "$clave" "$fecha_expiracion" "$dias_restantes" "$moviles"
            ((count++))
        done < $REGISTROS
    fi
    read -p "$(echo -e ${CIAN}Presiona Enter para continuar...${NC})"
}


function mini_registro() {
    clear
    echo -e "${VIOLETA}==== 📋 MINI REGISTRO ====${NC}"
    echo -e "${AMARILLO}👤 Nombre  🔑 Contraseña   ⏳ Días   📱 Móviles${NC}"
    if [[ ! -f $REGISTROS || ! -s $REGISTROS ]]; then
        echo -e "${ROJO}No hay registros disponibles.${NC}"
    else
        count=0
        while IFS=' ' read -r user_data fecha_expiracion dias moviles fecha_creacion1 fecha_creacion2; do
            usuario=${user_data%%:*}
            clave=${user_data#*:}
            # FIX: Se quitó el segundo parámetro "$dias"
            dias_restantes=$(calcular_dias_restantes "$fecha_expiracion")
            printf "${VERDE}%-12s ${AZUL}%-16s ${AMARILLO}%-10s ${AMARILLO}%-10s${NC}
" \
                "$usuario" "$clave" "$dias_restantes" "$moviles"
            ((count++))
        done < $REGISTROS
        echo -e "${CIAN}===========================================${NC}"
        echo -e "${AMARILLO}TOTAL: ${VERDE}$count usuarios${NC}"
    fi
    echo -e "${CIAN}Presiona Enter para continuar... ✨${NC}"
    read
}


# Función para crear múltiples usuarios
crear_multiples_usuarios() {
    # ===================== COLORES FEMENINOS VIBRANTES =====================
    ROSA_FUERTE="\033[38;5;207m"    # Magenta/rosa principal
    ROSA_CLARO="\033[38;5;219m"     # Rosa suave
    MORADO="\033[38;5;213m"        # Morado/fucsia
    CYAN_CLARO="\033[38;5;156m"     # Verde agua / cian suave
    LILA="\033[38;5;183m"          # Lila pastel (no lo usé mucho, pero por si acaso)
    BLANCO="\033[38;5;231m"        # Blanco puro para nombres/claves
    AMARILLO="\033[93m"            # Amarillo para warnings
    ROJO="\033[91m"                # Rojo para errores
    RESET="\033[0m"                # Resetear color

    clear
    echo -e "${ROSA_FUERTE}===== 🆕 CREAR / ACTUALIZAR MÚLTIPLES USUARIOS SSH =====${RESET}"
    echo -e "${ROSA_CLARO}📝 Formato: nombre contraseña días móviles${RESET}"
    echo -e "${MORADO}📋 Ejemplo: lucy 123 5 4${RESET}"
    echo -e "${ROSA_FUERTE}✅ Ingresa los usuarios (una línea por usuario)${RESET}"
    echo -e "${ROSA_FUERTE}   Presiona Enter en una línea vacía para terminar.${RESET}\n"

    declare -a usuarios_input
    declare -a usuarios_crear
    declare -a usuarios_actualizar
    declare -a errores

    # ============================
    # LECTURA DE INPUT
    # ============================
    while true; do
        read -r linea || break
        [[ -z "$linea" ]] && break
        usuarios_input+=("$linea")
    done

    if [ ${#usuarios_input[@]} -eq 0 ]; then
        echo -e "${ROJO}❌ No se ingresaron usuarios.${RESET}"
        read -p "Presiona Enter para continuar..."
        return
    fi

    # ============================
    # VALIDAR DUPLICADOS EN INPUT
    # ============================
    if printf '%s\n' "${usuarios_input[@]}" | awk '{print $1}' | sort | uniq -d | grep -q .; then
        echo -e "${ROJO}❌ Error: Hay nombres de usuario repetidos en la misma lista.${RESET}"
        echo -e "${ROJO}   Corrígelo y vuelve a intentarlo.${RESET}"
        read -p "Presiona Enter para continuar..."
        return
    fi

    # ============================
    # PROCESAR ENTRADAS
    # ============================
    for linea in "${usuarios_input[@]}"; do
        read -r usuario clave dias moviles <<< "$linea"

        if [[ -z "$usuario" || -z "$clave" || -z "$dias" || -z "$moviles" ]]; then
            errores+=("Línea inválida: '$linea' → faltan campos")
            continue
        fi

        if ! [[ "$dias" =~ ^[0-9]+$ ]] || ! [[ "$moviles" =~ ^[0-9]+$ ]]; then
            errores+=("Línea inválida: '$linea' → días o móviles no son números")
            continue
        fi

        if id "$usuario" >/dev/null 2>&1; then
            usuarios_actualizar+=("$usuario:$clave:$dias:$moviles")
        else
            usuarios_crear+=("$usuario:$clave:$dias:$moviles")
        fi
    done

    # ============================
    # MOSTRAR ERRORES
    # ============================
    if [ ${#errores[@]} -gt 0 ]; then
        echo -e "${AMARILLO}⚠️ Errores encontrados:${RESET}"
        for e in "${errores[@]}"; do echo -e "   ${ROJO}- $e${RESET}"; done
        echo ""
        read -p "${AMARILLO}¿Continuar solo con los usuarios válidos? (s/n): ${RESET}" r
        [[ "$r" != "s" && "$r" != "S" ]] && return
        echo ""
    fi

    # ============================
    # RESUMEN GENERAL
    # ============================
    total=$(( ${#usuarios_crear[@]} + ${#usuarios_actualizar[@]} ))
    echo -e "${ROSA_FUERTE}===== 📋 RESUMEN DE OPERACIÓN =====${RESET}"
    echo -e "${ROSA_CLARO}Total usuarios a procesar: $total${RESET}"
    [ ${#usuarios_crear[@]}     -gt 0 ] && echo -e "${CYAN_CLARO}🆕 A crear:     ${#usuarios_crear[@]}${RESET}"
    [ ${#usuarios_actualizar[@]} -gt 0 ] && echo -e "${MORADO}🔄 A actualizar: ${#usuarios_actualizar[@]}${RESET}"
    echo ""

    # ============================
    # MOSTRAR TABLA DE USUARIOS A CREAR
    # ============================
    if [ ${#usuarios_crear[@]} -gt 0 ]; then
        echo -e "${CYAN_CLARO}===== 📋 USUARIOS A CREAR =====${RESET}"
        echo -e "${ROSA_CLARO}👤 Usuario    🔑 Clave      ⏳ Días       📱 Móviles${RESET}"
        echo -e "${ROSA_FUERTE}---------------------------------------------------------------${RESET}"
        for data in "${usuarios_crear[@]}"; do
            IFS=':' read -r usuario clave dias moviles <<< "$data"
            printf "${BLANCO}%-12s${RESET} ${MORADO}%-12s${RESET} ${CYAN_CLARO}%-12s${RESET} ${ROSA_FUERTE}%-12s${RESET}\n" "$usuario" "$clave" "$dias" "$moviles"
        done
        echo -e "${ROSA_FUERTE}===============================================================${RESET}"
        echo ""
    fi

    # ============================
    # MOSTRAR TABLA DE USUARIOS A ACTUALIZAR
    # ============================
    if [ ${#usuarios_actualizar[@]} -gt 0 ]; then
        echo -e "${MORADO}===== 🔄 USUARIOS A ACTUALIZAR =====${RESET}"
        echo -e "${ROSA_CLARO}👤 Usuario    🔑 Clave      ⏳ Días       📱 Móviles${RESET}"
        echo -e "${ROSA_FUERTE}---------------------------------------------------------------${RESET}"
        for data in "${usuarios_actualizar[@]}"; do
            IFS=':' read -r usuario clave dias moviles <<< "$data"
            printf "${BLANCO}%-12s${RESET} ${MORADO}%-12s${RESET} ${CYAN_CLARO}%-12s${RESET} ${ROSA_FUERTE}%-12s${RESET}\n" "$usuario" "$clave" "$dias" "$moviles"
        done
        echo -e "${ROSA_FUERTE}===============================================================${RESET}"
        echo ""
    fi

    # ============================
    # CONFIRMACIÓN FINAL
    # ============================
    echo -ne "${ROSA_FUERTE}✅ ¿Confirmar operación? (s/n): ${RESET}"
    read confirmacion
    [[ "$confirmacion" != "s" && "$confirmacion" != "S" ]] && { echo -e "${ROJO}Operación cancelada.${RESET}"; read; return; }

    count_creados=0
    count_actualizados=0

    # ============================
    # CREAR USUARIOS NUEVOS
    # ============================
    for data in "${usuarios_crear[@]}"; do
        IFS=':' read -r usuario clave dias moviles <<< "$data"

        if ! useradd -M -s /sbin/nologin "$usuario" 2>/dev/null; then
            echo -e "${ROJO}❌ Falló creación de $usuario (useradd)${RESET}"
            continue
        fi

        if ! echo "$usuario:$clave" | chpasswd 2>/dev/null; then
            echo -e "${ROJO}❌ Falló contraseña de $usuario → eliminando usuario${RESET}"
            userdel "$usuario" 2>/dev/null
            continue
        fi

        fecha_exp=$(date -d "+$((dias + 1)) days" "+%Y-%m-%d")
        chage -E "$fecha_exp" "$usuario" 2>/dev/null

        fecha_creacion=$(date "+%Y-%m-%d %H:%M:%S")
        fecha_expiracion=$(calcular_expiracion "$dias")

        echo "$usuario:$clave $fecha_expiracion $dias $moviles $fecha_creacion" >> "$REGISTROS"
        echo "Usuario creado: $usuario ($fecha_creacion)" >> "$HISTORIAL"

        echo -e "${CYAN_CLARO}✅ Creado: $usuario${RESET}"
        ((count_creados++))
    done

    # ============================
    # ACTUALIZAR USUARIOS EXISTENTES
    # ============================
    for data in "${usuarios_actualizar[@]}"; do
        IFS=':' read -r usuario clave dias moviles <<< "$data"

        echo "$usuario:$clave" | chpasswd 2>/dev/null || { echo -e "${ROJO}❌ Falló actualización contraseña de $usuario${RESET}"; continue; }

        fecha_exp=$(date -d "+$((dias + 1)) days" "+%Y-%m-%d")
        chage -E "$fecha_exp" "$usuario" 2>/dev/null

        fecha_act=$(date "+%Y-%m-%d %H:%M:%S")
        fecha_expiracion=$(calcular_expiracion "$dias")

        sed -i "/^$usuario:/d" "$REGISTROS" 2>/dev/null
        echo "$usuario:$clave $fecha_expiracion $dias $moviles $fecha_act" >> "$REGISTROS"

        echo "Usuario actualizado: $usuario ($fecha_act)" >> "$HISTORIAL"
        echo -e "${MORADO}🔄 Actualizado: $usuario${RESET}"
        ((count_actualizados++))
    done

    # ============================
    # RESUMEN FINAL
    # ============================
    echo ""
    echo -e "${ROSA_FUERTE}===== 📊 RESUMEN FINAL =====${RESET}"
    echo -e "${CYAN_CLARO}🆕 Usuarios creados:     $count_creados${RESET}"
    echo -e "${MORADO}🔄 Usuarios actualizados: $count_actualizados${RESET}"
    echo -e "${ROSA_FUERTE}============================${RESET}"
    read -p "Presiona Enter para continuar..."
}

# Función para eliminar múltiples usuarios


    eliminar_multiples_usuarios() {
    clear
    echo "===== 💣 ELIMINAR USUARIO: NIVEL DIABLO - SATÁN ROOT 🔥 ====="
    echo "Nº      👤 Usuario"
    echo "--------------------------"
    if [[ ! -f $REGISTROS || ! -s $REGISTROS ]]; then
        echo "No hay registros disponibles."
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Cargar usuarios en un array para fácil acceso por número
    declare -a usuarios
    count=1
    while IFS=' ' read -r user_data _; do
        usuario=${user_data%%:*}
        usuarios[$count]="$usuario"
        printf "%-7s %-20s\n" "$count" "$usuario"
        ((count++))
    done < $REGISTROS

    read -p "🗑️ Ingrese los números o nombres de usuarios a eliminar (separados por espacios) (0 para cancelar): " input

    if [[ "$input" == "0" ]]; then
        echo "❌ Eliminación cancelada."
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Procesar input: puede ser números o nombres
    declare -a usuarios_a_eliminar
    for item in $input; do
        if [[ "$item" =~ ^[0-9]+$ ]]; then
            # Es un número
            if [[ $item -ge 1 && $item -lt $count ]]; then
                usuarios_a_eliminar+=("${usuarios[$item]}")
            else
                echo "❌ Número inválido: $item"
            fi
        else
            # Es un nombre, verificar si existe
            if grep -q "^$item:" $REGISTROS; then
                usuarios_a_eliminar+=("$item")
            else
                echo "❌ Usuario no encontrado: $item"
            fi
        fi
    done

    # Eliminar duplicados si los hay
    usuarios_a_eliminar=($(echo "${usuarios_a_eliminar[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

    if [ ${#usuarios_a_eliminar[@]} -eq 0 ]; then
        echo "❌ No se seleccionaron usuarios válidos."
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Confirmar eliminación
    echo "===== 📋 USUARIOS A ELIMINAR ====="
    for usuario in "${usuarios_a_eliminar[@]}"; do
        echo "👤 $usuario"
    done
    read -p "✅ ¿Confirmar eliminación? (s/n): " confirmacion
    if [[ "$confirmacion" != "s" && "$confirmacion" != "S" ]]; then
        echo "❌ Eliminación cancelada."
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Eliminar usuarios
    count=0
    failed_count=0
    fecha_eliminacion=$(date "+%Y-%m-%d %H:%M:%S")
    for usuario in "${usuarios_a_eliminar[@]}"; do
        # Terminar todas las sesiones y procesos de manera forzada
        pkill -KILL -u "$usuario" 2>/dev/null
        sleep 1  # Dar tiempo para que los procesos terminen

        # Intentar eliminar el usuario con remoción de home y mail spool
        if userdel -r -f "$usuario" >/dev/null 2>&1; then
            # Verificar si el usuario realmente se eliminó
            if ! id "$usuario" &>/dev/null; then
                # Eliminar del registro
                sed -i "/^$usuario:/d" $REGISTROS

                # Registrar en historial
                echo "Usuario eliminado: $usuario, Fecha: $fecha_eliminacion" >> $HISTORIAL

                ((count++))
            else
                # Si aún existe, intentar limpieza manual
                rm -rf "/home/$usuario" 2>/dev/null
                rm -f "/var/mail/$usuario" 2>/dev/null
                rm -f "/var/spool/mail/$usuario" 2>/dev/null
                # Forzar eliminación de entradas en /etc/passwd y /etc/shadow si es necesario (peligroso, pero robusto)
                sed -i "/^$usuario:/d" /etc/passwd
                sed -i "/^$usuario:/d" /etc/shadow
                sed -i "/^$usuario:/d" /etc/group
                sed -i "/^$usuario:/d" /etc/gshadow

                # Verificar nuevamente
                if ! id "$usuario" &>/dev/null; then
                    # Eliminar del registro
                    sed -i "/^$usuario:/d" $REGISTROS

                    # Registrar en historial
                    echo "Usuario eliminado forzosamente: $usuario, Fecha: $fecha_eliminacion" >> $HISTORIAL

                    ((count++))
                else
                    echo "❌ Fallo persistente al eliminar el usuario $usuario."
                    echo "Error al eliminar usuario persistente: $usuario, Fecha: $fecha_eliminacion" >> $HISTORIAL
                    ((failed_count++))
                fi
            fi
        else
            echo "❌ Error inicial al eliminar el usuario $usuario."
            echo "Error al eliminar usuario: $usuario, Fecha: $fecha_eliminacion" >> $HISTORIAL
            ((failed_count++))
        fi
    done

    # Mostrar resumen
    echo "===== 📊 RESUMEN DE ELIMINACIÓN ====="
    echo "✅ Usuarios eliminados exitosamente: $count"
    if [[ $failed_count -gt 0 ]]; then
        echo "❌ Usuarios con fallos: $failed_count"
    fi
    echo "Presiona Enter para continuar... ✨"
    read
}



# ================================
#  FUNCIÓN: MONITOREAR CONEXIONES
# ================================
monitorear_conexiones() {
    LOG="/var/log/monitoreo_conexiones.log"
    HISTORIAL="/alexia/log.txt"
    INTERVALO=1
    DROPBEAR_PORTS="80 443"

    mkdir -p "$(dirname "$HISTORIAL")"
    [[ ! -f "$HISTORIAL" ]] && touch "$HISTORIAL"
    mkdir -p "$(dirname "$LOG")"
    [[ ! -f "$LOG" ]] && touch "$LOG"

    while true; do
        usuarios_ps=$(ps -o user= -C sshd -C dropbear | sort -u)

        for usuario in $usuarios_ps; do
            [[ -z "$usuario" ]] && continue
            tmp_status="/tmp/status_${usuario}.tmp"

            # ZOMBIES
            zombies=$(ps -u "$usuario" -o state,pid | grep '^Z' | awk '{print $2}')
            if [[ -n "$zombies" ]]; then
                for pid in $zombies; do
                    kill -9 "$pid" 2>/dev/null
                    echo "$(date '+%Y-%m-%d %H:%M:%S'): Proceso zombie (PID: $pid) de $usuario terminado." >> "$LOG"
                done
            fi

            # CONEXIONES ACTIVAS
            conexiones=$(( $(ps -u "$usuario" -o comm= | grep -c "^sshd$") + $(ps -u "$usuario" -o comm= | grep -c "^dropbear$") ))

            if [[ $conexiones -gt 0 ]]; then
                if [[ ! -f "$tmp_status" ]]; then
                    date +%s > "$tmp_status"
                    echo "$(date '+%Y-%m-%d %H:%M:%S'): $usuario conectado." >> "$LOG"
                else
                    contenido=$(cat "$tmp_status")
                    [[ ! "$contenido" =~ ^[0-9]+$ ]] && date +%s > "$tmp_status"
                fi
            fi
        done

        # SSH anti-conexiones fantasma
        ss -eto '( sport = :22 )' 2>/dev/null | \
        awk '/(ESTAB|TIME_WAIT|CLOSE_WAIT)/ && /timer:/ {
            if (match($0, /users:(("sshd",pid=([0-9]+)/, arr)) {
                if (match($0, /timer:[^,]+,([0-9]+)/, tarr) && tarr[1] > 180)
                    print arr[1];
            }
        }' | while read -r pid; do
            [[ -n "$pid" ]] && kill -9 "$pid" 2>/dev/null
            echo "$(date '+%Y-%m-%d %H:%M:%S'): Conexión SSH idle (PID: $pid) eliminada tras 3min." >> "$LOG"
        done

        # Dropbear anti-conexiones fantasma
        for port in $DROPBEAR_PORTS; do
            ss -eto '( sport = :'"$port"' )' 2>/dev/null | \
            awk '/(ESTAB|TIME_WAIT|CLOSE_WAIT)/ && /timer:/ {
                if (match($0, /users:(("dropbear",pid=([0-9]+)/, arr)) {
                    if (match($0, /timer:[^,]+,([0-9]+)/, tarr) && tarr[1] > 180)
                        print arr[1];
                }
            }' | while read -r pid; do
                [[ -n "$pid" ]] && kill -9 "$pid" 2>/dev/null
                echo "$(date '+%Y-%m-%d %H:%M:%S'): Conexión Dropbear idle (PID: $pid, puerto: $port) eliminada tras 3min." >> "$LOG"
            done
        done

        # Revisar desconexiones
        for f in /tmp/status_*.tmp; do
            [[ ! -f "$f" ]] && continue
            usuario=$(basename "$f" .tmp | cut -d_ -f2)
            conexiones=$(( $(ps -u "$usuario" -o comm= | grep -c "^sshd$") + $(ps -u "$usuario" -o comm= | grep -c "^dropbear$") ))

            if [[ $conexiones -eq 0 ]]; then
                hora_ini=$(date -d @"$(cat "$f")" "+%Y-%m-%d %H:%M:%S")
                hora_fin=$(date "+%Y-%m-%d %H:%M:%S")
                rm -f "$f"
                echo "$usuario|$hora_ini|$hora_fin" >> "$HISTORIAL"
                echo "$(date '+%Y-%m-%d %H:%M:%S'): $usuario desconectado. Inicio: $hora_ini Fin: $hora_fin" >> "$LOG"
            fi
        done

        sleep "$INTERVALO"
    done
}

# ================================
#  MODO MONITOREO DIRECTO
# ================================
if [[ "$1" == "mon" ]]; then
    monitorear_conexiones
    exit 0
fi

# ================================
# ARRANQUE AUTOMÁTICO DEL MONITOR DE CONEXIONES
# ================================
if [[ ! -f "$PID_MON" ]] || ! ps -p "$(cat "$PID_MON" 2>/dev/null)" >/dev/null 2>&1; then
    rm -f "$PID_MON"
    nohup bash "$0" mon >/dev/null 2>&1 &
    echo $! > "$PID_MON"
fi


# Colores bonitos
AZUL_SUAVE='\033[38;5;45m'
VERDE='\033[38;5;42m'
ROJO='\033[38;5;196m'

BLANCO='\033[38;5;15m'
GRIS='\033[38;5;245m'
NC='\033[0m'

# ================================
# FUNCIÓN: ACTIVAR/DESACTIVAR LIMITADOR
# ================================
activar_desactivar_limitador() {
    clear
    echo -e "${AZUL_SUAVE}===== ⚙️  ACTIVAR/DESACTIVAR LIMITADOR DE CONEXIONES =====${NC}"
    
    if [[ -f "$ENABLED" ]] && [[ -f "$PID_LIMITADOR" ]] && ps -p "$(cat "$PID_LIMITADOR" 2>/dev/null)" >/dev/null 2>&1; then
        ESTADO="${VERDE}🟢 Activado${NC}"
        INTERVALO_ACTUAL=$(cat "$STATUS" 2>/dev/null || echo "1")
    else
        rm -f "$PID_LIMITADOR" "$STATUS" "$ENABLED"
        ESTADO="${ROJO}🔴 Desactivado${NC}"
        INTERVALO_ACTUAL="N/A"
    fi

    echo -e "${BLANCO}Estado actual:${NC} $ESTADO"
    echo -e "${BLANCO}Intervalo actual:${NC} ${AMARILLO}${INTERVALO_ACTUAL}${NC} ${GRIS}segundo(s)${NC}"
    echo -e "${AZUL_SUAVE}----------------------------------------------------------${NC}"

    echo -ne "${VERDE}¿Desea activar/desactivar el limitador? (s/n): ${NC}"
    read respuesta

    if [[ "$respuesta" =~ ^[sS]$ ]]; then
        if [[ -f "$ENABLED" ]]; then
            # DESACTIVAR
            if [[ -f "$PID_LIMITADOR" ]]; then
                kill "$(cat "$PID_LIMITADOR")" 2>/dev/null
                rm -f "$PID_LIMITADOR"
            fi
            rm -f "$STATUS" "$ENABLED"
            echo -e "${VERDE}✅ Limitador desactivado exitosamente.${NC}"
            echo "$(date '+%Y-%m-%d %H:%M:%S'): Limitador desactivado." >> "$HISTORIAL"
        else
            # ACTIVAR
            echo -ne "${VERDE}Ingrese el intervalo de verificación en segundos (1-60): ${NC}"
            read intervalo
            if [[ "$intervalo" =~ ^[0-9]+$ ]] && [[ "$intervalo" -ge 1 && "$intervalo" -le 60 ]]; then
                echo "$intervalo" > "$STATUS"
                touch "$ENABLED"
                nohup bash "$0" limitador >/dev/null 2>&1 &
                echo $! > "$PID_LIMITADOR"
                echo -e "${VERDE}✅ Limitador activado con intervalo de $intervalo segundo(s).${NC}"
                echo "$(date '+%Y-%m-%d %H:%M:%S'): Limitador activado con intervalo de $intervalo segundos." >> "$HISTORIAL"
            else
                echo -e "${ROJO}❌ Intervalo inválido. Debe ser un número entre 1 y 60.${NC}"
            fi
        fi
    else
        echo -e "${AMARILLO}⚠️ Operación cancelada.${NC}"
    fi

    echo -ne "${AZUL_SUAVE}Presiona Enter para continuar...${NC}"
    read
}

# ================================
# MODO LIMITADOR
# ================================
if [[ "$1" == "limitador" ]]; then
    while [[ -f "$ENABLED" ]]; do
        INTERVALO=$(cat "$STATUS" 2>/dev/null || echo "1")
        if [[ -f "$REGISTROS" ]]; then
            while IFS=' ' read -r user_data _ _ moviles _; do
                usuario=${user_data%%:*}
                if id "$usuario" &>/dev/null; then
                    pids=($(ps -u "$usuario" --sort=start_time -o pid,comm | grep -E '^[ ]*[0-9]+ (sshd|dropbear)$' | awk '{print $1}'))
                    conexiones=${#pids[@]}
                    if [[ $conexiones -gt $moviles ]]; then
                        for ((i=moviles; i<conexiones; i++)); do
                            pid=${pids[$i]}
                            kill -9 "$pid" 2>/dev/null
                            echo "$(date '+%Y-%m-%d %H:%M:%S'): Conexión extra de $usuario (PID: $pid) terminada. Límite: $moviles, Conexiones: $conexiones" >> "$HISTORIAL"
                        done
                    fi
                fi
            done < "$REGISTROS"
        fi
        sleep "$INTERVALO"
    done
    exit 0
fi

# ================================
# ARRANQUE AUTOMÁTICO DEL LIMITADOR (solo si está habilitado)
# ================================
if [[ -f "$ENABLED" ]]; then
    if [[ ! -f "$PID_LIMITADOR" ]] || ! ps -p "$(cat "$PID_LIMITADOR" 2>/dev/null)" >/dev/null 2>&1; then
        nohup bash "$0" limitador >/dev/null 2>&1 &
        echo $! > "$PID_LIMITADOR"
    fi
fi


function verificar_online() {
    clear

    # Definir colores exactos
    AZUL_SUAVE='\033[38;5;45m'
    SOFT_PINK='\033[38;5;211m'
    PASTEL_BLUE='\033[38;5;153m'
    LILAC='\033[38;5;183m'
    SOFT_CORAL='\033[38;5;217m'
    HOT_PINK='\033[38;5;198m'
    PASTEL_PURPLE='\033[38;5;189m'
    MINT_GREEN='\033[38;5;159m'
    VERDE='\033[38;5;42m'
    VIOLETA='\033[38;5;183m'
    
    CIAN='\033[38;5;51m'
    NC='\033[0m'

    echo -e "${AZUL_SUAVE}===== 🟢   USUARIOS ONLINE =====${NC}"
    printf "${AMARILLO}%-14s ${AMARILLO}%-14s ${AMARILLO}%-10s ${AMARILLO}%-25s${NC}\n" \
        "👤 USUARIO" "📲 CONEXIONES" "📱 MÓVILES" "⏰ TIEMPO CONECTADO"
    echo -e "${LILAC}-----------------------------------------------------------------${NC}"

    total_online=0
    total_usuarios=0
    inactivos=0

    if [[ ! -f "$REGISTROS" ]]; then
        echo -e "${HOT_PINK}❌ No hay registros.${NC}"
        read -p "$(echo -e ${PASTEL_PURPLE}Presiona Enter para continuar... ✨${NC})"
        return
    fi

    while read -r userpass fecha_exp dias moviles fecha_crea hora_crea; do
        usuario=${userpass%%:*}

        if ! id "$usuario" &>/dev/null; then
            continue
        fi

        (( total_usuarios++ ))
        conexiones=$(( $(ps -u "$usuario" -o comm= | grep -cE "^(sshd|dropbear)$") ))

        estado="📴 0"
        detalle="⭕ Nunca conectado"
        mov_txt="📲 $moviles"
        tmp_status="/tmp/status_${usuario}.tmp"
        bloqueo_file="/tmp/bloqueo_${usuario}.lock"

        COLOR_ESTADO="${ROJO}"
        COLOR_DETALLE="${VIOLETA}"

        # 🔒 Verificar si está bloqueado primero
        if [[ -f "$bloqueo_file" ]]; then
            bloqueo_hasta=$(cat "$bloqueo_file")
            if [[ $(date +%s) -lt $bloqueo_hasta ]]; then
                detalle="🚫 bloqueado (hasta $(date -d @$bloqueo_hasta '+%I:%M%p'))"
                COLOR_DETALLE="${ROJO}"
            else
                rm -f "$bloqueo_file"
            fi
        fi

        # 🟢 Si el usuario está conectado normalmente
        if [[ $conexiones -gt 0 ]]; then
            estado="🟢 $conexiones"
            COLOR_ESTADO="${MINT_GREEN}"
            (( total_online += conexiones ))

            if [[ -f "$tmp_status" ]]; then
                contenido=$(cat "$tmp_status")
                if [[ "$contenido" =~ ^[0-9]+$ ]]; then
                    start_s=$((10#$contenido))
                else
                    start_s=$(date +%s)
                    echo $start_s > "$tmp_status"
                fi

                now_s=$(date +%s)
                elapsed=$(( now_s - start_s ))
                h=$(( elapsed / 3600 ))
                m=$(( (elapsed % 3600) / 60 ))
                s=$(( elapsed % 60 ))
                detalle=$(printf "⏰ %02d:%02d:%02d" "$h" "$m" "$s")
                COLOR_DETALLE="${VERDE}"
            fi
        else
            # ❌ Solo mostramos última conexión si NO está bloqueado
            if [[ ! $detalle =~ "🚫 bloqueado" ]]; then
                rm -f "$tmp_status"
                ult=$(grep "^$usuario|" "$HISTORIAL" | tail -1 | awk -F'|' '{print $3}')
                if [[ -n "$ult" ]]; then
                    ult_fmt=$(date -d "$ult" +"%d de %B %H:%M")
                    detalle="📅 Última: $ult_fmt"
                    COLOR_DETALLE="${ROJO}"
                else
                    detalle="😴 Nunca conectado"
                    COLOR_DETALLE="${VIOLETA}"
                fi
            fi
            (( inactivos++ ))
        fi

        # Imprimir cada fila bien coloreada
        printf "${VERDE}%-14s ${COLOR_ESTADO}%-14s ${VERDE}%-10s ${COLOR_DETALLE}%-25s${NC}\n" \
            "$usuario" "$estado" "$mov_txt" "$detalle"
    done < "$REGISTROS"

    echo -e "${LILAC}-----------------------------------------------------------------${NC}"
    echo -e "${CIAN}Total de Online: ${AMARILLO}${total_online}${NC}  ${CIAN}Total usuarios: ${AMARILLO}${total_usuarios}${NC}  ${CIAN}Inactivos: ${AMARILLO}${inactivos}${NC}"
    echo -e "${HOT_PINK}================================================${NC}"
    read -p "$(echo -e ${VIOLETA}Presiona Enter para continuar... ✨${NC})"
}



bloquear_desbloquear_usuario() {
    clear
    # 🎨 Colores más vivos y definidos
    AZUL_SUAVE='\033[38;5;45m'
    
    
    ROJO='\033[38;5;196m'
    
    CYAN='\033[38;5;51m'
    NC='\033[0m'

    printf "\n${AZUL_SUAVE}==== 🔒 BLOQUEAR/DESBLOQUEAR USUARIO ====${NC}\n"
    printf "${LILAC}===== 📋 USUARIOS REGISTRADOS =====${NC}\n"
    printf "${AMARILLO}%-3s %-12s %-10s %-16s %-22s${NC}\n" "Nº" "👤 Usuario" "🔑 Clave" "📅 Expira" "✅ Estado"
    printf "${CYAN}----------------------------------------------------------------------------${NC}\n"

    usuarios=()
    index=1
    while read -r userpass fecha_exp dias moviles fecha_crea hora_crea; do
        usuario=${userpass%%:*}
        clave=${userpass#*:}
        estado="desbloqueado"
        COLOR_ESTADO="${VERDE}"
        bloqueo_file="/tmp/bloqueo_${usuario}.lock"

        if [[ -f "$bloqueo_file" ]]; then
            bloqueo_hasta=$(cat "$bloqueo_file")
            if [[ $(date +%s) -lt $bloqueo_hasta ]]; then
                estado="bloqueado (hasta $(date -d @$bloqueo_hasta '+%I:%M%p'))"
                COLOR_ESTADO="${ROJO}"
            else
                rm -f "$bloqueo_file"
                usermod -U "$usuario" 2>/dev/null
                estado="desbloqueado"
                COLOR_ESTADO="${VERDE}"
            fi
        fi

        # 🎨 Fila de datos con colores más sutiles
        printf "%-3s ${VERDE}%-12s ${CYAN}%-10s ${AMARILLO}%-16s ${COLOR_ESTADO}%-22s${NC}\n" \
            "$index" "$usuario" "$clave" "$fecha_exp" "$estado"

        usuarios[$index]="$usuario"
        ((index++))
    done < "$REGISTROS"

    printf "${CYAN}============================================================================${NC}\n"
    read -p "👤 Digite el número o el nombre del usuario: " input

    if [[ "$input" =~ ^[0-9]+$ ]] && [[ -n "${usuarios[$input]}" ]]; then
        usuario="${usuarios[$input]}"
    else
        usuario="$input"
    fi

    if ! grep -q "^${usuario}:" "$REGISTROS"; then
        printf "${ROJO}❌ Usuario '$usuario' no encontrado.${NC}\n"
        read -p "Presiona Enter para continuar..."
        return
    fi

    bloqueo_file="/tmp/bloqueo_${usuario}.lock"
    if [[ -f "$bloqueo_file" ]] && [[ $(date +%s) -lt $(cat "$bloqueo_file") ]]; then
        printf "𒯢 El usuario '$usuario' está ${ROJO}BLOQUEADO${NC} hasta $(date -d @$(cat "$bloqueo_file") '+%I:%M%p').\n"
        read -p "✅ Desea desbloquear al usuario '$usuario'? (s/n) " respuesta
        if [[ "$respuesta" =~ ^[sS]$ ]]; then
            rm -f "$bloqueo_file"
            usermod -U "$usuario" 2>/dev/null
            loginctl terminate-user "$usuario" 2>/dev/null
            pkill -9 -u "$usuario" 2>/dev/null
            killall -u "$usuario" -9 2>/dev/null
            printf "${VERDE}🔓 Usuario '$usuario' desbloqueado exitosamente.${NC}\n"
        else
            printf "${AMARILLO}⚠️ Operación cancelada.${NC}\n"
        fi
        read -p "Presiona Enter para continuar..."
        return
    else
        printf "𒯢 El usuario '$usuario' está ${VERDE}DESBLOQUEADO${NC}.\n"
        read -p "✅ Desea bloquear al usuario '$usuario'? (s/n) " respuesta
        if [[ "$respuesta" =~ ^[sS]$ ]]; then
            read -p "⏳ Ponga en minutos el tiempo que el usuario estaría bloqueado y confirmar con Enter: " minutos
            if [[ "$minutos" =~ ^[0-9]+$ ]] && [[ $minutos -gt 0 ]]; then
                bloqueo_hasta=$(( $(date +%s) + minutos * 60 ))
                echo "$bloqueo_hasta" > "$bloqueo_file"
                usermod -L "$usuario" 2>/dev/null
                loginctl terminate-user "$usuario" 2>/dev/null
                pkill -9 -u "$usuario" 2>/dev/null
                killall -u "$usuario" -9 2>/dev/null
                printf "${VERDE}🔒 Usuario '$usuario' bloqueado exitosamente y sesiones SSH terminadas. ✅${NC}\n"
                printf "⏰ Desbloqueado automáticamente hasta las $(date -d @$bloqueo_hasta '+%I:%M%p')\n"
            else
                printf "${ROJO}❌ Tiempo inválido. Debe ser un número mayor a 0.${NC}\n"
            fi
        else
            printf "${AMARILLO}⚠️ Operación cancelada.${NC}\n"
        fi
        read -p "Presiona Enter para continuar..."
    fi
}


# ================================
# monitorear_bloqueos
# ================================
monitorear_bloqueos() {
    LOG="/var/log/monitoreo_bloqueos.log"
    INTERVALO=10

    mkdir -p "$(dirname "$LOG")"
    [[ ! -f "$LOG" ]] && touch "$LOG"

    while true; do
        for bloqueo_file in /tmp/bloqueo_*.lock; do
            [[ ! -f "$bloqueo_file" ]] && continue
            usuario=$(basename "$bloqueo_file" .lock | cut -d_ -f2)
            bloqueo_hasta=$(cat "$bloqueo_file")
            if [[ $(date +%s) -ge $bloqueo_hasta ]]; then
                rm -f "$bloqueo_file"
                usermod -U "$usuario" 2>/dev/null
                loginctl terminate-user "$usuario" 2>/dev/null
                pkill -9 -u "$usuario" 2>/dev/null
                killall -u "$usuario" -9 2>/dev/null
                echo "$(date '+%Y-%m-%d %H:%M:%S'): $usuario desbloqueado automáticamente." >> "$LOG"
            fi
        done
        sleep "$INTERVALO"
    done
}

# ================================
#  ARRANQUE AUTOMÁTICO DEL MONITOR DE BLOQUEOS
# ================================
if [[ ! -f "$PID_BLOQUEOS" ]] || ! ps -p "$(cat "$PID_BLOQUEOS" 2>/dev/null)" >/dev/null 2>&1; then
    rm -f "$PID_BLOQUEOS"
    nohup bash "$0" mon_bloqueos >/dev/null 2>&1 &
    echo $! > "$PID_BLOQUEOS"
fi

# ================================
#  MODO MONITOREO DE BLOQUEOS
# ================================
if [[ "$1" == "mon_bloqueos" ]]; then
    monitorear_bloqueos
    exit 0
fi

function configurar_banner_ssh() {
    clear
    echo -e "${VIOLETA}===== 🎀 CONFIGURAR BANNER SSH =====${NC}"
    echo -e "${AMARILLO}1) AGREGAR${NC}"
    echo -e "${AMARILLO}2) ELIMINAR${NC}"
    echo
    PROMPT=$(echo -e "${ROSA}➡️ Selecciona una opción: ${NC}")
    read -p "$PROMPT" SUBOP

    BANNER_FILE="/etc/ssh_banner"
    SSHD_CONFIG="/etc/ssh/sshd_config"

    case $SUBOP in
        1)
            clear
            echo -e "${VIOLETA}===== 🎀 AGREGAR BANNER SSH =====${NC}"
            echo -e "${AMARILLO}📝 Pega o escribe tu banner en formato HTML (puedes incluir colores, emojis, etc.).${NC}"
            echo -e "${AMARILLO}📌 Presiona Enter dos veces (línea vacía) para terminar.${NC}"
            echo -e "${AMARILLO}📌 Ejemplo: <h2><font color=\"Red\">⛅ ESTÁS USANDO UNA VPS PREMIUM 🌈</font></h2>${NC}"
            echo -e "${AMARILLO}📌 Nota: Los saltos de línea dentro de una entrada serán corregidos automáticamente.${NC}"
            echo -e "${AMARILLO}📌 Asegúrate de que tu cliente SSH (ej. PuTTY) esté configurado para UTF-8 y soporte HTML.${NC}"
            echo

            # Arreglos para almacenar las líneas del banner y el texto limpio
            declare -a BANNER_LINES
            declare -a PLAIN_TEXT_LINES
            LINE_COUNT=0
            TEMP_LINE=""
            PREVIOUS_EMPTY=false

            # Leer el banner línea por línea
            while true; do
                PROMPT=$(echo -e "${ROSA}➡️ Línea $((LINE_COUNT + 1)): ${NC}")
                read -r INPUT_LINE

                # Verificar si es una línea vacía (Enter)
                if [[ -z "$INPUT_LINE" ]]; then
                    if [[ "$PREVIOUS_EMPTY" == true ]]; then
                        # Dos Enters consecutivos, terminar entrada
                        if [[ -n "$TEMP_LINE" ]]; then
                            # Guardar la última línea acumulada
                            CLEAN_LINE=$(echo "$TEMP_LINE" | tr -d '\n' | tr -s ' ')
                            BANNER_LINES[$LINE_COUNT]="$CLEAN_LINE"
                            PLAIN_TEXT=$(echo "$CLEAN_LINE" | sed -e 's/<[^>]*>//g' -e 's/&nbsp;/ /g')
                            PLAIN_TEXT_LINES[$LINE_COUNT]="$PLAIN_TEXT"
                            ((LINE_COUNT++))
                        fi
                        break
                    fi
                    PREVIOUS_EMPTY=true
                    continue
                fi

                PREVIOUS_EMPTY=false
                TEMP_LINE="$TEMP_LINE$INPUT_LINE"

                # Verificar si la línea contiene una etiqueta de cierre </h2> o </font>
                if [[ "$INPUT_LINE" =~ \</(h2|font)\> ]]; then
                    CLEAN_LINE=$(echo "$TEMP_LINE" | tr -d '\n' | tr -s ' ')
                    if [[ -z "$CLEAN_LINE" ]]; then
                        echo -e "${ROJO}❌ La línea no puede estar vacía. Intenta de nuevo.${NC}"
                        TEMP_LINE=""
                        continue
                    fi
                    BANNER_LINES[$LINE_COUNT]="$CLEAN_LINE"
                    PLAIN_TEXT=$(echo "$CLEAN_LINE" | sed -e 's/<[^>]*>//g' -e 's/&nbsp;/ /g')
                    PLAIN_TEXT_LINES[$LINE_COUNT]="$PLAIN_TEXT"
                    ((LINE_COUNT++))
                    TEMP_LINE=""
                fi
            done

            if [[ $LINE_COUNT -eq 0 ]]; then
                echo -e "${ROJO}❌ No se ingresaron líneas válidas para el banner.${NC}"
                read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
                return
            fi

            # Mostrar vista previa y pedir confirmación
            clear
            echo -e "${VIOLETA}===== 🎀 VISTA PREVIA DEL BANNER =====${NC}"
            echo -e "${CIAN}📜 Así se verá el banner (sin etiquetas HTML, colores y emojis dependen del cliente SSH):${NC}"
            for ((i=0; i<LINE_COUNT; i++)); do
                echo -e "${PLAIN_TEXT_LINES[$i]}"
            done
            echo
            echo -e "${AMARILLO}⚠️ Nota: Asegúrate de que tu cliente SSH (ej. PuTTY) use UTF-8 para ver emojis y soporte HTML para colores.${NC}"
            PROMPT=$(echo -e "${ROSA}➡️ ¿Confirmar y guardar el banner? (s/n): ${NC}")
            read -p "$PROMPT" CONFIRM
            if [[ "$CONFIRM" != "s" && "$CONFIRM" != "S" ]]; then
                echo -e "${AMARILLO}⚠️ Configuración de banner cancelada.${NC}"
                read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
                return
            fi

            # Crear el archivo del banner con codificación UTF-8
            : > "$BANNER_FILE"  # Limpiar el archivo
            printf '\xEF\xBB\xBF' > "$BANNER_FILE"  # Agregar BOM para UTF-8
            for ((i=0; i<LINE_COUNT; i++)); do
                echo "${BANNER_LINES[$i]}" >> "$BANNER_FILE" 2>/dev/null || {
                    echo -e "${ROJO}❌ Error al crear el archivo $BANNER_FILE. Verifica permisos.${NC}"
                    read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
                    return
                }
            done

            # Configurar el banner en sshd_config
            if grep -q "^Banner" "$SSHD_CONFIG"; then
                sed -i "s|^Banner.*|Banner $BANNER_FILE|" "$SSHD_CONFIG" 2>/dev/null || {
                    echo -e "${ROJO}❌ Error al modificar $SSHD_CONFIG. Verifica permisos.${NC}"
                    read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
                    return
                }
            else
                echo "Banner $BANNER_FILE" >> "$SSHD_CONFIG" 2>/dev/null || {
                    echo -e "${ROJO}❌ Error al modificar $SSHD_CONFIG. Verifica permisos.${NC}"
                    read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
                    return
                }
            fi

            # Configurar el servidor SSH para aceptar UTF-8
            if ! grep -q "^AcceptEnv LANG LC_*" "$SSHD_CONFIG"; then
                echo "AcceptEnv LANG LC_*" >> "$SSHD_CONFIG" 2>/dev/null || {
                    echo -e "${ROJO}❌ Error al modificar $SSHD_CONFIG para UTF-8. Verifica permisos.${NC}"
                    read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
                    return
                }
            fi

            # Reiniciar el servicio SSH
            systemctl restart sshd >/dev/null 2>&1 || {
                echo -e "${ROJO}❌ Error al reiniciar el servicio SSH. Verifica manualmente.${NC}"
                read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
                return
            }

            echo -e "${VERDE}✅ Banner SSH configurado exitosamente en $BANNER_FILE.${NC}"
            echo -e "${CIAN}📜 Contenido final del banner:${NC}"
            for ((i=0; i<LINE_COUNT; i++)); do
                echo -e "${PLAIN_TEXT_LINES[$i]}"
            done
            echo -e "${AMARILLO}⚠️ Nota: Configura tu cliente SSH (ej. PuTTY) con UTF-8 para ver emojis y verifica soporte HTML para colores.${NC}"
            read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
            ;;
        2)
            if grep -q "^Banner" "$SSHD_CONFIG"; then
                sed -i 's|^Banner.*|#Banner none|' "$SSHD_CONFIG" 2>/dev/null || {
                    echo -e "${ROJO}❌ Error al modificar $SSHD_CONFIG. Verifica permisos.${NC}"
                    read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
                    return
                }
                rm -f "$BANNER_FILE" 2>/dev/null
                systemctl restart sshd >/dev/null 2>&1 || {
                    echo -e "${ROJO}❌ Error al reiniciar el servicio SSH. Verifica manualmente.${NC}"
                    read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
                    return
                }
                echo -e "${VERDE}✅ Banner SSH desactivado exitosamente.${NC}"
            else
                echo -e "${AMARILLO}⚠️ El banner ya está desactivado.${NC}"
            fi
            read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
            ;;
        *)
            echo -e "${ROJO}❌ ¡Opción inválida!${NC}"
            read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
            ;;
    esac
}

slowdns_panel(){

BASE="/usr/local/slowdns"
KEYDIR="$BASE/keys"
BIN="$BASE/dns-server"
AUTOSTART="/bin/autoboot"
CONF="$BASE/domain"

rosa='\033[1;95m'
rosita='\033[1;38;5;213m'
magenta='\033[1;35m'
verde='\033[1;32m'
rojo='\033[1;31m'
amarillo='\033[1;33m'
azul='\033[1;34m'
cyan='\033[1;36m'
blanco='\033[1;97m'
reset='\033[0m'

fix_key(){

mkdir -p $KEYDIR

cat <<EOF > $KEYDIR/server.key
76e12e653cd58bf9a3f9cde0204d029e5dd1970596cafd2293f08e2626348e01
EOF

cat <<EOF > $KEYDIR/server.pub
4aa683a10a8c4e7d44ab11e8494640ce1a8077d0f9a9f007b20437121f3e8a2d
EOF

}

enable_network(){

echo -e "${rosita}✨ Configurando la red con amor... 💕${reset}"

echo 1 > /proc/sys/net/ipv4/ip_forward

sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

sysctl -p >/dev/null 2>&1

IFACE=$(ip route | grep default | awk '{print $5}')

iptables -t nat -C POSTROUTING -o $IFACE -j MASQUERADE 2>/dev/null || \
iptables -t nat -A POSTROUTING -o $IFACE -j MASQUERADE

iptables -t nat -C PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300 2>/dev/null || \
iptables -t nat -A PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300

}

install_slowdns(){

clear
echo -e "${rosa}🌸💗 INSTALANDO SLOWDNS CON MUCHO AMOR 💗🌸${reset}"

apt update -y
apt install git wget curl screen iptables-persistent -y

echo -e "${amarillo}Instalando GO...${reset}"

cd /usr/local
rm -rf go
wget -q https://go.dev/dl/go1.16.6.linux-amd64.tar.gz
tar -xzf go1.16.6.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin

echo -e "${amarillo}Descargando DNSTT...${reset}"

cd /usr/local
rm -rf dnstt
git clone https://www.bamsoftware.com/git/dnstt.git >/dev/null 2>&1
cd dnstt
git checkout v1.20210812.0 >/dev/null 2>&1

echo -e "${amarillo}Compilando dns-server...${reset}"

go build -o dns-server ./dnstt-server

mkdir -p $BASE
mv dns-server $BIN
chmod +x $BIN

read -p "Ingrese dominio NS: " DOMAIN
echo $DOMAIN > $CONF

echo -e "${verde}Aplicando KEY fija...${reset}"

fix_key
enable_network

cat > $AUTOSTART <<EOF
#!/bin/bash
screen -wipe >/dev/null 2>&1
screen -dmS slowdns $BIN -udp :5300 -privkey-file $KEYDIR/server.key $DOMAIN 127.0.0.1:22
EOF

chmod +x $AUTOSTART

(crontab -l 2>/dev/null; echo "@reboot $AUTOSTART") | crontab -

netfilter-persistent save >/dev/null 2>&1

/bin/autoboot

echo ""
echo -e "${verde}SlowDNS instalado correctamente ✨${reset}"
echo ""
echo -e "${cyan}NS:${reset} $DOMAIN"
echo ""
echo -e "${cyan}PUBLIC KEY:${reset}"
cat $KEYDIR/server.pub
echo ""

read -p "ENTER"

}

start_slowdns(){

/bin/autoboot
echo -e "${verde}🌟 SlowDNS encendido con todo el poder 💖${reset}"
sleep 2

}

stop_slowdns(){

screen -S slowdns -X quit 2>/dev/null
echo -e "${rojo}🛑 SlowDNS pausado con cuidado bb 💔${reset}"
sleep 2

}

status_slowdns(){

clear

PORT=$(ss -lunp | grep 5300)

echo -e "${rosa}💿 ESTADO DE TU SLOWDNS QUEEN 💿${reset}"

if [[ $PORT ]]; then
echo -e "${verde}ON & shining ✨${reset}"
else
echo -e "${rojo}OFF mi amor 😔${reset}"
fi

echo ""
screen -ls

read -p "Presiona ENTER para continuar..."

}

show_info(){

clear

echo -e "${magenta}🌷 INFO COMPLETA DE TU SLOWDNS GIRL 🌷${reset}"

echo ""
echo -e "${amarillo}NS:${reset}"
cat $CONF 2>/dev/null

echo ""
echo -e "${verde}PUBLIC KEY:${reset}"
cat $KEYDIR/server.pub 2>/dev/null

echo ""
echo -e "${rojo}PRIVATE KEY:${reset}"
cat $KEYDIR/server.key 2>/dev/null

echo ""
read -p "ENTER"

}

remove_slowdns(){

screen -S slowdns -X quit 2>/dev/null
rm -rf $BASE
rm -f $AUTOSTART

echo -e "${rojo}💔 SlowDNS se fue volando... adiós reina 😢${reset}"
sleep 2

}

while true
do

clear

PORT=$(ss -lunp | grep 5300)

if [[ $PORT ]]; then
STATUS="${verde}ACTIVO MI REINA 💃${reset}"
else
STATUS="${rojo}DETENIDO mi amor 😘${reset}"
fi

echo -e "${rosa}✨🌸═══════════════════════════════════════🌸✨${reset}"
echo -e "${rosa}          💗 PANEL SLOWDNS PRINCESS 💗${reset}"
echo -e "${rosa}✨🌸═══════════════════════════════════════🌸✨${reset}"
echo ""
echo -e "${blanco}Estado actual: ${STATUS}${reset}"
echo ""
echo -e "${amarillo}1 🐌 Instalar SlowDNS${reset}"
echo -e "${amarillo}2 ✨ Iniciar${reset}"
echo -e "${amarillo}3 🛑 Detener${reset}"
echo -e "${amarillo}4 💿 Ver estado${reset}"
echo -e "${amarillo}5 🔑 Ver NS + Keys${reset}"
echo -e "${amarillo}6 🗑️ Desinstalar${reset}"
echo -e "${amarillo}0 👑 Volver al menú principal${reset}"
echo ""

echo -ne "${rosita}Selecciona tu opción reina → ${reset}"
read opc

case $opc in

1) install_slowdns ;;
2) start_slowdns ;;
3) stop_slowdns ;;
4) status_slowdns ;;
5) show_info ;;
6) remove_slowdns ;;
0)
return
;;
*)
echo -e "${rojo}Uy esa opción no existe bb 😅${reset}"
sleep 1
;;

esac

done

}

function renovar_usuario() {
    clear
    echo -e "${VIOLETA}===== 🔄 RENOVAR USUARIO 🌸 =====${NC}"

    echo -e "${AMARILLO}Usuarios registrados:${NC}"
    if [[ ! -f "$REGISTROS" || ! -s "$REGISTROS" ]]; then
        read -p "$(echo -e "${ROJO}❌ No hay registros disponibles. 😕\n${CIAN}⏎ Presiona Enter para continuar...${NC}")"
        return
    fi

    count=1
    while IFS=' ' read -r user_data fecha_expiracion dias moviles fecha_creacion1 fecha_creacion2; do
        usuario=${user_data%%:*}
        echo -e "${VERDE}$count. $usuario${NC}"
        ((count++))
    done < "$REGISTROS"

    read -p "$(echo -e "${CIAN}👤 Ingresa el nombre del usuario a renovar: ${NC}")" usuario

    if ! grep -q "^$usuario:" "$REGISTROS"; then
        read -p "$(echo -e "${ROJO}❌ ¡El usuario $usuario no existe! 😕\n${CIAN}⏎ Presiona Enter para continuar...${NC}")"
        return
    fi

    user_line=$(grep "^$usuario:" "$REGISTROS")
    usuario=${user_line%%:*}
    clave=${user_line#*:}
    clave=${clave%% *}
    resto_line=${user_line#* }
    fecha_expiracion=$(echo "$resto_line" | awk '{print $1}')
    dias_actuales=$(echo "$resto_line" | awk '{print $2}')
    moviles=$(echo "$resto_line" | awk '{print $3}')
    fecha_creacion=$(echo "$resto_line" | awk '{print $4, $5}')

    read -p "$(echo -e "${CIAN}📅 ¿Cuántos días deseas agregar? (puedes usar negativos para disminuir) ${NC}")" dias_renovar
    if ! [[ "$dias_renovar" =~ ^-?[0-9]+$ ]]; then
        read -p "$(echo -e "${ROJO}❌ ¡Días inválidos! Debe ser un número entero (positivo o negativo). 😕\n${CIAN}⏎ Presiona Enter para continuar...${NC}")"
        return
    fi

    read -p "$(echo -e "${CIAN}📱 Cantidad de móviles a agregar (actual: $moviles, 0 si no): ${NC}")" moviles_cambios
    if ! [[ "$moviles_cambios" =~ ^-?[0-9]+$ ]]; then
        moviles_cambios=0
    fi

    nuevos_moviles=$((moviles + moviles_cambios))
    if (( nuevos_moviles < 0 )); then
        echo -e "${ROJO}❌ El límite de móviles no puede ser menor que 0.${NC}"
        nuevos_moviles=$moviles
        read -p "$(echo -e "${CIAN}⏎ Presiona Enter para continuar...${NC}")"
        return
    fi

    fecha_expiracion_std=$(echo "$fecha_expiracion" | sed 's|enero|01|;s|febrero|02|;s|marzo|03|;s|abril|04|;s|mayo|05|;s|junio|06|;s|julio|07|;s|agosto|08|;s|septiembre|09|;s|octubre|10|;s|noviembre|11|;s|diciembre|12|')
    fecha_expiracion_std=$(echo "$fecha_expiracion_std" | awk -F'/' '{printf "%04d-%02d-%02d", $3, $2, $1}')

    nueva_fecha_std=$(date -d "$fecha_expiracion_std + $dias_renovar days" "+%Y-%m-%d" 2>/dev/null)

    fecha_expiracion_sistema=$(date -d "$nueva_fecha_std + 1 day" "+%Y-%m-%d")
    if ! chage -E "$fecha_expiracion_sistema" "$usuario" 2>/dev/null; then
        echo -e "${ROJO}❌ Error al actualizar la fecha de expiración en el sistema.${NC}"
        read -p "$(echo -e "${CIAN}⏎ Presiona Enter para continuar...${NC}")"
        return
    fi

    nueva_fecha=$(echo "$nueva_fecha_std" | awk -F'-' '{
        meses["01"]="enero"; meses["02"]="febrero"; meses["03"]="marzo"; meses["04"]="abril";
        meses["05"]="mayo"; meses["06"]="junio"; meses["07"]="julio"; meses["08"]="agosto";
        meses["09"]="septiembre"; meses["10"]="octubre"; meses["11"]="noviembre"; meses["12"]="diciembre";
        printf "%02d/%s/%04d\n", $3, meses[$2], $1
    }')

    dias_restantes=$(( ( ( $(date -d "$nueva_fecha_std" +%s) - $(date +%s) ) / 86400 ) + 1 ))

    sed -i "s|^$usuario:.*|$usuario:$clave $nueva_fecha $dias_actuales $nuevos_moviles $fecha_creacion|" "$REGISTROS"

    echo -e "\n${VERDE}🎉 ¡Usuario $usuario renovado con éxito! 🚀${NC}"
    echo -e "${AMARILLO}👤 Usuario:${NC} $usuario"
    echo -e "${AMARILLO}🔒 Clave:${NC} $clave"
    echo -e "${AMARILLO}➕ Días agregados:${NC} $dias_renovar"
    echo -e "${AMARILLO}📱 Móviles agregados:${NC} $moviles_cambios"
    echo -e "${AMARILLO}🗓️ Fecha anterior de expiración:${NC} $fecha_expiracion"
    echo -e "${AMARILLO}✨ Nueva fecha de expiración:${NC} $nueva_fecha"
    echo -e "${AMARILLO}📱 Límite de móviles actualizado:${NC} $nuevos_moviles"
    echo -e "${AMARILLO}🕒 Fecha de creación:${NC} $fecha_creacion"
    echo -e "${AMARILLO}⏳ Días restantes:${NC} $dias_restantes\n"

    read -p "$(echo -e "${CIAN}⏎ Presiona Enter para continuar...${NC}")"
}

# Colores y emojis
VIOLETA='\033[38;5;141m'
VERDE='\033[38;5;42m'
AMARILLO='\033[38;5;220m'
AZUL='\033[38;5;39m'
ROJO='\033[1;31m'
CIAN='\033[38;5;51m'
FUCHSIA='\033[38;2;255;0;255m'
AMARILLO_SUAVE='\033[38;2;255;204;0m'
ROSA='\033[38;2;255;105;180m'
ROSA_CLARO='\033[1;95m'
NC='\033[0m'


    # =======================
#  MENU PRINCIPAL VPN/SSH
# =======================

# ==== AUTO-INSTALAR EN .bash_profile ====
if ! grep -q "/root/scrip.sh" /root/.bash_profile; then
    echo "bash /root/scrip.sh" >> /root/.bash_profile
fi

# ==== FUNCIONES SWAP ====

activar_desactivar_swap() {
    while true; do
        clear
        echo
        echo -e "${VIOLETA}======💾 PANEL SWAP ======${NC}"
        echo -e "${AMARILLO_SUAVE}1. Activar Swap${NC}"
        echo -e "${AMARILLO_SUAVE}2. Eliminar Swap${NC}"
        echo -e "${AMARILLO_SUAVE}0. Volver al menú principal${NC}"
        echo
        read -p "$(echo -e "${ROSA}➡️  Selecciona una opción: ${NC}")" SUBOPCION

        case $SUBOPCION in
            1) instalar_swap ;;
            2) eliminar_swap ;;
            0) return ;;
            *)
                echo -e "${ROJO}❌ ¡Opción inválida!${NC}"
                read -p "$(echo -e "${ROSA_CLARO}Presiona Enter para continuar...${NC}")"
                ;;
        esac
    done
}

instalar_swap() {
    clear
    echo
    echo -e "${VIOLETA}======💾 ACTIVAR SWAP ======${NC}"
    echo

    [ "$EUID" -ne 0 ] && {
        echo -e "${ROJO}❌ Esta operación requiere permisos de root.${NC}"
        read -p "$(echo -e "${ROSA_CLARO}Presiona Enter para continuar...${NC}")"
        return
    }

    if swapon --show | grep -q "/swapfile"; then
        echo -e "${ROJO}❌ Ya existe un swapfile activo. Elimínalo primero antes de crear uno nuevo.${NC}"
        read -p "$(echo -e "${ROSA_CLARO}Presiona Enter para continuar...${NC}")"
        return
    fi

    read -p "$(echo -e "${AMARILLO_SUAVE}Tamaño de Swap en GB (ej: 1, 2, 3): ${ROSA}➡️  ${NC}")" SIZE_GB

    if ! [[ "$SIZE_GB" =~ ^[1-9][0-9]*$ ]]; then
        echo -e "${ROJO}❌ Valor inválido. Ingresa un número entero positivo.${NC}"
        read -p "$(echo -e "${ROSA_CLARO}Presiona Enter para continuar...${NC}")"
        return
    fi

    ESPACIO_LIBRE_MB=$(df / --output=avail -BM | tail -1 | tr -d 'M')
    SIZE_MB=$((SIZE_GB * 1024))
    MARGEN_MB=200

    if [ "$((SIZE_MB + MARGEN_MB))" -ge "$ESPACIO_LIBRE_MB" ]; then
        ESPACIO_GB=$(( ESPACIO_LIBRE_MB / 1024 ))
        echo -e "${ROJO}❌ Espacio insuficiente. Disponible: ~${ESPACIO_GB}GB — Solicitado: ${SIZE_GB}GB (se reservan 200MB de margen)${NC}"
        read -p "$(echo -e "${ROSA_CLARO}Presiona Enter para continuar...${NC}")"
        return
    fi

    [ -f /swapfile ] && rm -f /swapfile

    echo
    echo -e "${AMARILLO_SUAVE}Creando swapfile de ${SIZE_GB}GB...${NC}"

    fallocate -l "${SIZE_GB}G" /swapfile || {
        echo -e "${ROJO}❌ Error al crear el swapfile con fallocate.${NC}"
        rm -f /swapfile
        read -p "$(echo -e "${ROSA_CLARO}Presiona Enter para continuar...${NC}")"
        return
    }

    chmod 600 /swapfile

    mkswap /swapfile || {
        echo -e "${ROJO}❌ Error al formatear el swapfile (mkswap).${NC}"
        rm -f /swapfile
        read -p "$(echo -e "${ROSA_CLARO}Presiona Enter para continuar...${NC}")"
        return
    }

    swapon /swapfile || {
        echo -e "${ROJO}❌ Error al activar el swapfile (swapon).${NC}"
        rm -f /swapfile
        read -p "$(echo -e "${ROSA_CLARO}Presiona Enter para continuar...${NC}")"
        return
    }

    if ! grep -q "^/swapfile" /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi

    sysctl vm.swappiness=10
    grep -q "^vm.swappiness" /etc/sysctl.conf || echo "vm.swappiness=10" >> /etc/sysctl.conf

    echo
    echo -e "${VERDE}✅ Swap de ${SIZE_GB}GB activado — swappiness=10 aplicado y persistente.${NC}"
    echo
    swapon --show
    free -h
    echo

    read -p "$(echo -e "${ROSA_CLARO}Presiona Enter para continuar...${NC}")"
}

eliminar_swap() {
    clear
    echo
    echo -e "${VIOLETA}======💾 ELIMINAR SWAP ======${NC}"
    echo

    [ "$EUID" -ne 0 ] && {
        echo -e "${ROJO}❌ Esta operación requiere permisos de root.${NC}"
        read -p "$(echo -e "${ROSA_CLARO}Presiona Enter para continuar...${NC}")"
        return
    }

    if ! [ -f /swapfile ]; then
        echo -e "${ROJO}❌ No se encontró ningún swapfile activo.${NC}"
        read -p "$(echo -e "${ROSA_CLARO}Presiona Enter para continuar...${NC}")"
        return
    fi

    echo -e "${AMARILLO_SUAVE}Se eliminará el swapfile y se removerá de /etc/fstab.${NC}"
    echo -e "${ROJO}Presiona Enter para confirmar, o Ctrl+C para cancelar.${NC}"
    read

    swapoff /swapfile || echo -e "${AMARILLO_SUAVE}⚠️  No se pudo desactivar el swap (puede que ya esté inactivo).${NC}"
    rm -f /swapfile
    sed -i '/^\/swapfile/d' /etc/fstab

    echo
    echo -e "${VERDE}✅ Swap eliminado correctamente.${NC}"
    echo
    free -h
    echo

    read -p "$(echo -e "${ROSA_CLARO}Presiona Enter para continuar...${NC}")"
}


function usuarios_ssh() {
    clear
    # Colores bonitos y suaves
    ROSADO='\u001B[38;5;211m'
    LILA='\u001B[38;5;183m'
    TURQUESA='\u001B[38;5;45m'
    VERDE_SUAVE='\u001B[38;5;159m'
    ROJO_SUAVE='\u001B[38;5;210m'
    AZUL_SUAVE='\u001B[38;5;153m'
    NC='\u001B[0m'

    # Mostrar lista de registros
    echo -e "${ROSADO}===== 🌸 REGISTROS =====${NC}"
    if [[ ! -f $REGISTROS || ! -s $REGISTROS ]]; then
        echo -e "${ROJO_SUAVE}😿 No hay registros disponibles.${NC}"
        read -p "$(echo -e ${LILA}Presiona Enter para continuar... ✨${NC})"
        return
    fi

    # Leer usuarios y mostrar numerados (solo nombres de usuario)
    count=1
    declare -A user_map
    while IFS=' ' read -r user_data fecha_expiracion dias moviles fecha_creacion1 fecha_creacion2; do
        usuario=${user_data%%:*}
        user_map[$count]="$usuario"
        echo -e "${TURQUESA}${count} ${AMARILLO_SUAVE}${usuario}${NC}"
        ((count++))
    done < $REGISTROS

    # Solicitar input
    read -p "$(echo -e ${LILA}🌟 Ingresa el número o nombre del usuario: ${NC})" input

    # Validar input: si número, obtener usuario; si nombre, verificar existencia
    if [[ $input =~ ^[0-9]+$ && -n "${user_map[$input]}" ]]; then
        usuario="${user_map[$input]}"
    else
        usuario="$input"
        # Verificar si existe
        grep -q "^$usuario:" $REGISTROS
        if [[ $? -ne 0 ]]; then
            echo -e "${ROJO_SUAVE}❌ Usuario no encontrado.${NC}"
            read -p "$(echo -e ${LILA}Presiona Enter para continuar... ✨${NC})"
            return
        fi
    fi

    # Obtener datos del usuario desde REGISTROS
    linea=$(grep "^$usuario:" $REGISTROS)
    IFS=' ' read -r user_data fecha_expiracion dias moviles fecha_creacion1 fecha_creacion2 <<< "$linea"
    clave=${user_data#*:}
    dias_restantes=$(calcular_dias_restantes "$fecha_expiracion")
    fecha_actual=$(date "+%Y-%m-%d %H:%M")

    # Obtener info de conexiones (similar a verificar_online e informacion_usuarios)
    conexiones=$(( $(ps -u "$usuario" -o comm= | grep -cE "^(sshd|dropbear)$") ))
    tmp_status="/tmp/status_${usuario}.tmp"
    bloqueo_file="/tmp/bloqueo_${usuario}.lock"

    # Inicializar variables
    conex_info=""
    tiempo_conectado=""
    ultima_conexion=""
    historia_conexion=""

    # Verificar bloqueo
    if [[ -f "$bloqueo_file" ]]; then
        bloqueo_hasta=$(cat "$bloqueo_file")
        if [[ $(date +%s) -lt $bloqueo_hasta ]]; then
            ultima_conexion="🚫 Bloqueado hasta $(date -d @$bloqueo_hasta '+%I:%M%p')"
        fi
    fi

    # Siempre obtener el último registro completado de HISTORIAL
    ultimo_registro=$(grep "^$usuario|" "$HISTORIAL" | grep -E '|[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}|[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}' | tail -1)
    if [[ -n "$ultimo_registro" ]]; then
        IFS='|' read -r _ hora_conexion hora_desconexion _ <<< "$ultimo_registro"

        # Formatear última desconexión con "de mes" (FORZAR ESPAÑOL MINÚSCULA)
        ult_month=$(LC_ALL=es_SV.UTF-8 date -d "$hora_desconexion" +"%B" 2>/dev/null | tr '[:upper:]' '[:lower:]')
        ult_fmt=$(LC_ALL=es_SV.UTF-8 date -d "$hora_desconexion" +"%d de MONTH %H:%M" 2>/dev/null)
        ult_fmt=${ult_fmt/MONTH/$ult_month}
        ultima_conexion="📅 Última: ${ROJO_SUAVE}${ult_fmt}${NC}"

        # Calcular duración
        sec_con=$(date -d "$hora_conexion" +%s 2>/dev/null)
        sec_des=$(date -d "$hora_desconexion" +%s 2>/dev/null)
        if [[ -n "$sec_con" && -n "$sec_des" && $sec_des -ge $sec_con ]]; then
            dur_seg=$((sec_des - sec_con))
            h=$((dur_seg / 3600))
            m=$(((dur_seg % 3600) / 60))
            s=$((dur_seg % 60))
            duracion=$(printf "%02d:%02d:%02d" $h $m $s)
        else
            duracion="N/A"
        fi

        # Formatear conexión y desconexión con /mes (FORZAR ESPAÑOL MINÚSCULA)
        con_month=$(LC_ALL=es_SV.UTF-8 date -d "$hora_conexion" +"%B" 2>/dev/null | tr '[:upper:]' '[:lower:]')
        conexion_fmt=$(LC_ALL=es_SV.UTF-8 date -d "$hora_conexion" +"%d/MONTH %H:%M" 2>/dev/null)
        conexion_fmt=${conexion_fmt/MONTH/$con_month}

        des_month=$(LC_ALL=es_SV.UTF-8 date -d "$hora_desconexion" +"%B" 2>/dev/null | tr '[:upper:]' '[:lower:]')
        desconexion_fmt=$(LC_ALL=es_SV.UTF-8 date -d "$hora_desconexion" +"%d/MONTH %H:%M" 2>/dev/null)
        desconexion_fmt=${desconexion_fmt/MONTH/$des_month}

        historia_conexion="
${LILA}-------------------------${NC}
${VERDE_SUAVE}🌷 Conectada    ${conexion_fmt}${NC}
${ROJO_SUAVE}🌙 Desconectada       ${desconexion_fmt}${NC}
${AZUL_SUAVE}⏰ Duración   ${duracion}${NC}
${LILA}-------------------------${NC}"
    else
        ultima_conexion="😴 Nunca conectado"
    fi

    # 🟢 Si el usuario está conectado actualmente
    if [[ $conexiones -gt 0 ]]; then
        conex_info="📲 CONEXIONES ${VERDE_SUAVE}${conexiones}${NC}"
        if [[ -f "$tmp_status" ]]; then
            contenido=$(cat "$tmp_status")
            if [[ "$contenido" =~ ^[0-9]+$ ]]; then
                start_s=$((10#$contenido))
            else
                start_s=$(date +%s)
                echo $start_s > "$tmp_status"
            fi
            now_s=$(date +%s)
            elapsed=$(( now_s - start_s ))
            h=$(( elapsed / 3600 ))
            m=$(( (elapsed % 3600) / 60 ))
            s=$(( elapsed % 60 ))
            tiempo_conectado=$(printf "⏰ TIEMPO CONECTADO    ⏰ %02d:%02d:%02d" "$h" "$m" "$s")
        else
            tiempo_conectado="⏰  TIEMPO CONECTADO    ⏰  N/A"
        fi
    else
        conex_info="📲 CONEXIONES ${ROJO_SUAVE}0${NC}"
    fi

    # Mostrar información detallada
    clear
    echo -e "${ROSADO}===== 💖 INFORMACIÓN DE ${usuario^^} 💖 =====${NC}"
    echo -e "${AZUL_SUAVE}🕒 FECHA:   ${fecha_actual}${NC}"
    echo -e "${VERDE_SUAVE}👩 Usuario ${usuario}${NC}"
    echo -e "${VERDE_SUAVE}🔒 Clave   ${clave}${NC}"
    echo -e "${VERDE_SUAVE}📅 Expira  ${fecha_expiracion}${NC}"
    echo -e "${VERDE_SUAVE}⏳ Días    ${dias_restantes}${NC}"
    echo -e "${VERDE_SUAVE}📲 Móviles ${moviles}${NC}"
    echo -e "${conex_info}"
    echo -e "${VERDE_SUAVE}📱 MÓVILES ${moviles}${NC}"
    if [[ "$ultima_conexion" != "😴 Nunca conectado" ]]; then
        echo -e "${ultima_conexion}"
    fi
    if [[ -n "$tiempo_conectado" ]]; then
        echo -e "${AZUL_SUAVE}${tiempo_conectado}${NC}"
    fi
    if [[ -n "$historia_conexion" ]]; then
        echo -e "${historia_conexion}"
    elif [[ "$ultima_conexion" == "😴 Nunca conectado" ]]; then
        echo -e "${ultima_conexion}"
    fi
    read -p "$(echo -e ${LILA}Presiona Enter para regresar al menú principal... ✨${NC})"
}



#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════
#   MCCARTHEY — XRAY + 3X-UI MANAGER
#   auto_patch xhttp v2 + watchdog v4.1 (solo cron) + SSL + panel completo
#   SSL dual-mode: dominio (90 días) ó IP (shortlived, 6 días)
#
#   WATCHDOG: Este script NO escribe /root/xray_watchdog.sh.
#   El watchdog v4.1 es instalado y mantenido exclusivamente por vpn_full.sh.
#   setup_watchdog_cron() solo registra el cron si el archivo ya existe.
#   remove_panel() no elimina el watchdog si VPN Full está activo.
#
#   PARCHES APLICADOS:
#   1. apply_cert_to_panel corta ejecución si falla la DB (return 1)
#   2. check_port_80_free valida puerto 80 libre antes de acme
#   3. run_acme_with_retry encapsula acme con 1 reintento tras 30s
#   4. rotate_ssl_log llamado al inicio de apply_cert_to_panel y force_renew_ssl
#   5. timeout 10s en todos los openssl s_client para evitar cuelgues
# ═══════════════════════════════════════════════════════════════════════

HOT_PINK="\033[1;95m"
CYAN="\033[1;96m"
GREEN="\033[1;92m"
RED="\033[1;91m"
YELLOW="\033[1;93m"
RESET="\033[0m"

DOMAIN_FILE="/etc/MCCARTHEY/ssl_domain"
TYPE_FILE="/etc/MCCARTHEY/ssl_type"
SSL_DIR="/etc/x-ui/ssl"
SSL_LOG="/var/log/mccarthey_ssl.log"

# ── Logger SSL dedicado ─────────────────────────────────────────────────
log_ssl() {
    local LEVEL="$1"; shift
    local TAG="$1";   shift
    local MSG="$*"
    printf '[%s] [%-5s] [%-7s] %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" \
        "$LEVEL" \
        "$TAG" \
        "$MSG" >> "$SSL_LOG"
}

# ── Rotación liviana del log SSL ─────────────────────────────────────────
rotate_ssl_log() {
    local MAX_BYTES=$(( 5 * 1024 * 1024 ))
    if [ -f "$SSL_LOG" ]; then
        local SIZE
        SIZE=$(stat -c%s "$SSL_LOG" 2>/dev/null || echo 0)
        if [ "$SIZE" -ge "$MAX_BYTES" ]; then
            mv "$SSL_LOG" "${SSL_LOG}.1"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO ] [CONFIG ] Log rotado — tamaño anterior: ${SIZE} bytes" >> "$SSL_LOG"
        fi
    fi
}

# ═══════════════════════════════════════════════════════════════════════
#   AUTO PATCH XHTTP v2 — cron cada 6 horas
# ═══════════════════════════════════════════════════════════════════════
setup_auto_patch_cron() {

    # 👉 Crear log desde instalación (clave)
    touch /var/log/auto_patch_xhttp.log
    chmod 644 /var/log/auto_patch_xhttp.log

    cat > /root/auto_patch_xhttp.sh << 'EOF'
#!/bin/bash

# 👉 Asegurar log (backup por si lo borran)
LOG="/var/log/auto_patch_xhttp.log"
[ ! -f "$LOG" ] && touch "$LOG"
chmod 644 "$LOG"

DB="/etc/x-ui/x-ui.db"
LOCK="/tmp/auto_patch_xhttp.lock"

RAM_SAFE=70
CPU_SAFE=75

TARGET_POSTS=10
TARGET_BYTES="500000"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"
}

exec 200>"$LOCK"
flock -n 200 || exit 0

[ ! -f "$DB" ] && log "ERROR: DB no encontrada en $DB" && exit 1
! command -v sqlite3 &>/dev/null && log "ERROR: sqlite3 no instalado" && exit 1

log "INFO: Escaneando inbounds xhttp..."

CHANGES=$(sqlite3 "$DB" "
UPDATE inbounds
SET stream_settings = json_set(
    stream_settings,
    '$.xhttpSettings.scMaxBufferedPosts', $TARGET_POSTS,
    '$.xhttpSettings.scMaxEachPostBytes', '$TARGET_BYTES'
)
WHERE json_extract(stream_settings, '$.network') = 'xhttp'
  AND (
       CAST(COALESCE(
           json_extract(stream_settings, '$.xhttpSettings.scMaxBufferedPosts'),
           -1
       ) AS INTEGER) != $TARGET_POSTS
    OR CAST(COALESCE(
           json_extract(stream_settings, '$.xhttpSettings.scMaxEachPostBytes'),
           ''
       ) AS TEXT) != '$TARGET_BYTES'
  );

SELECT changes();
" 2>/dev/null)

if ! [[ "$CHANGES" =~ ^[0-9]+$ ]]; then
    log "ERROR: Resultado inesperado de changes(): '$CHANGES'"
    exit 1
fi

if [ "$CHANGES" -eq 0 ]; then
    log "INFO: Sin cambios necesarios → Xray no se toca"
    exit 0
fi

log "PATCH: $CHANGES inbound(s) corregido(s) → evaluando carga para decidir reinicio"

RAM_PCT=$(free | awk '/^Mem:/ {printf "%.0f", ($2-$7)/$2 * 100}')
LOAD_1=$(awk '{print $1}' /proc/loadavg)
NCPU=$(nproc)
CPU_PCT=$(awk "BEGIN {printf \"%.0f\", ($LOAD_1/$NCPU)*100}")

if ! [[ "$RAM_PCT" =~ ^[0-9]+$ ]] || ! [[ "$CPU_PCT" =~ ^[0-9]+$ ]]; then
    log "ERROR: Métricas inválidas — RAM='$RAM_PCT' CPU='$CPU_PCT' — abortando"
    exit 1
fi

log "INFO: RAM real=${RAM_PCT}% | CPU load=${CPU_PCT}% (load1=${LOAD_1}, nproc=${NCPU})"

BLOCK_REASON=""
[ "$RAM_PCT" -ge "$RAM_SAFE" ] && BLOCK_REASON="RAM alta (${RAM_PCT}% ≥ ${RAM_SAFE}%)"
if [ "$CPU_PCT" -ge "$CPU_SAFE" ]; then
    [ -n "$BLOCK_REASON" ] \
        && BLOCK_REASON="${BLOCK_REASON} + CPU saturada (${CPU_PCT}% ≥ ${CPU_SAFE}%)" \
        || BLOCK_REASON="CPU saturada (${CPU_PCT}% ≥ ${CPU_SAFE}%)"
fi

if [ -n "$BLOCK_REASON" ]; then
    log "INFO: Reinicio pospuesto — $BLOCK_REASON → se aplicará en el próximo ciclo"
    exit 0
fi

log "ACTION: RAM ${RAM_PCT}% y CPU ${CPU_PCT}% dentro de rangos → reiniciando Xray"
x-ui restart-xray >> "$LOG" 2>&1
EXIT_CODE=$?

[ "$EXIT_CODE" -eq 0 ] \
    && log "OK: Xray reiniciado correctamente" \
    || log "ERROR: Falló reinicio de Xray (código $EXIT_CODE)"

exit 0
EOF

    chmod +x /root/auto_patch_xhttp.sh

    (crontab -l 2>/dev/null | grep -v auto_patch_xhttp.sh; echo "0 */6 * * * /root/auto_patch_xhttp.sh") | crontab -

    echo -e "${GREEN}Auto-patch xhttp v2 activo ✅ (log listo desde instalación)${RESET}"
}

# ═══════════════════════════════════════════════════════════════════════
#   SETUP WATCHDOG CRON
#   IMPORTANTE: Este script NO escribe el watchdog.
#   Solo registra el cron apuntando al archivo existente (v4.1 de vpn_full.sh).
#   Si el archivo no existe, avisa que hay que instalar VPN Full primero.
# ═══════════════════════════════════════════════════════════════════════
setup_watchdog_cron() {
    local WATCHDOG="/root/xray_watchdog.sh"

    if [ ! -f "$WATCHDOG" ]; then
        echo -e "${RED}⚠️  Watchdog no encontrado en $WATCHDOG${RESET}"
        echo -e "${YELLOW}   Instalá primero el VPN Full para obtener el watchdog v4.1.${RESET}"
        echo -e "${YELLOW}   El panel funcionará sin watchdog hasta que se instale VPN Full.${RESET}"
        return 1
    fi

    # Solo registra el cron — nunca sobreescribe el archivo
    local CRON_TMP
    CRON_TMP=$(mktemp)
    crontab -l 2>/dev/null > "$CRON_TMP" || true
    if ! grep -qF "xray_watchdog.sh" "$CRON_TMP"; then
        echo "*/5 * * * * $WATCHDOG" >> "$CRON_TMP"
        crontab "$CRON_TMP"
        echo -e "${GREEN}Watchdog v4.1 — cron registrado ✅${RESET}"
    else
        echo -e "${CYAN}Watchdog — cron ya existe, sin cambios ✅${RESET}"
    fi
    rm -f "$CRON_TMP"
}

# ═══════════════════════════════════════════════════════════════════════
#   HELPERS INTERNOS
# ═══════════════════════════════════════════════════════════════════════

panel_installed() { command -v x-ui &>/dev/null; }

panel_status() {
    if systemctl is-active --quiet x-ui; then STATUS="Activo 🟢"; else STATUS="Inactivo 🔴"; fi
}

get_port() {
    PORT=$(x-ui settings 2>/dev/null | awk '/port:/ {print $2}')
    [ -z "$PORT" ] && PORT="No detectado"
}

get_domain() {
    [ -f "$DOMAIN_FILE" ] && DOMAIN=$(cat "$DOMAIN_FILE") || DOMAIN=""
}

get_ssl_type() {
    [ -f "$TYPE_FILE" ] && SSL_TYPE=$(cat "$TYPE_FILE") || SSL_TYPE="domain"
}

start_proxy() {
    local EXISTING
    EXISTING=$(pgrep -f /etc/MCCARTHEY/PDirect.py)
    if [ -z "$EXISTING" ]; then
        nohup python3 /etc/MCCARTHEY/PDirect.py 80 > /root/nohup.out 2>&1 &
        sleep 2
        echo -e "${GREEN}Proxy MCCARTHEY iniciado ✅${RESET}"
    else
        echo -e "${CYAN}Proxy MCCARTHEY ya está activo (PID $EXISTING), no se duplica.${RESET}"
    fi
}

stop_proxy() {
    local PROXY_PID
    PROXY_PID=$(pgrep -f /etc/MCCARTHEY/PDirect.py)
    if [ -n "$PROXY_PID" ]; then
        echo -e "${YELLOW}Deteniendo proxy MCCARTHEY (PID $PROXY_PID)...${RESET}"
        kill "$PROXY_PID"
        sleep 3
    fi
}

cleanup_old_certs() {
    local CURRENT_VALUE="$1"
    local DIRNAME
    for dir in /root/.acme.sh/*; do
        [ -d "$dir" ] || continue
        DIRNAME=$(basename "$dir")
        [[ "$DIRNAME" == ca ]]       && continue
        [[ "$DIRNAME" == account* ]] && continue
        if [[ "$DIRNAME" != "${CURRENT_VALUE}_ecc" && "$DIRNAME" != "$CURRENT_VALUE" ]]; then
            echo -e "${YELLOW}Eliminando certificado obsoleto: $DIRNAME${RESET}"
            rm -rf "$dir"
        fi
    done
}

cert_is_valid() {
    local CERT="$1"
    [ -f "$CERT" ] || return 1
    openssl x509 -checkend 0 -noout -in "$CERT" 2>/dev/null
}

# PARCHE 5: timeout 10s para evitar cuelgues en openssl s_client
get_live_cert_days() {
    local HOST="$1"
    local PORT="$2"
    local EXP
    EXP=$(timeout 10 openssl s_client \
            -connect "${HOST}:${PORT}" \
            -servername "${HOST}" \
            </dev/null 2>/dev/null \
          | openssl x509 -enddate -noout 2>/dev/null \
          | cut -d= -f2)
    if [ -z "$EXP" ]; then echo -1; return; fi
    echo $(( ( $(date -d "$EXP" +%s) - $(date +%s) ) / 86400 ))
}

# ═══════════════════════════════════════════════════════════════════════
#   PARCHE 2: Valida que el puerto 80 esté libre antes de acme
# ═══════════════════════════════════════════════════════════════════════
check_port_80_free() {
    local OCCUPIED
    OCCUPIED=$(ss -tlnp 'sport = :80' 2>/dev/null | tail -n+2)
    if [ -n "$OCCUPIED" ]; then
        local PROC
        PROC=$(echo "$OCCUPIED" | grep -oP 'users:\(\(".*?"\)' | head -1)
        log_ssl WARN  PROXY  "Puerto 80 ocupado antes de acme — proceso: ${PROC:-desconocido}"
        echo -e "${RED}[SSL] ❌  Puerto 80 en uso por otro proceso: ${PROC:-desconocido}${RESET}"
        echo -e "${YELLOW}    Liberalo antes de renovar SSL.${RESET}"
        return 1
    fi
    return 0
}

# ═══════════════════════════════════════════════════════════════════════
#   PARCHE 3: Emite/renueva via acme con 1 reintento automático
# ═══════════════════════════════════════════════════════════════════════
run_acme_with_retry() {
    local HOST="$1"
    local TYPE="$2"
    local ACME_CERT="/root/.acme.sh/${HOST}_ecc/fullchain.cer"
    local EXIT_CODE ATTEMPT

    for ATTEMPT in 1 2; do
        if [ "$ATTEMPT" -eq 2 ]; then
            log_ssl WARN ACME "Intento 1 fallido — esperando 30s antes de reintentar — host: $HOST ($TYPE)"
            echo -e "${YELLOW}[SSL] Reintentando en 30 segundos...${RESET}"
            sleep 30
        fi

        if [ "$TYPE" = "domain" ]; then
            if [ ! -f "$ACME_CERT" ]; then
                log_ssl INFO ACME "Intento $ATTEMPT — issue -d $HOST --standalone --httpport 80"
                timeout 120 /root/.acme.sh/acme.sh --issue \
                    -d "$HOST" --standalone --httpport 80 >> "$SSL_LOG" 2>&1
            else
                log_ssl INFO ACME "Intento $ATTEMPT — renew -d $HOST --force"
                timeout 120 /root/.acme.sh/acme.sh --renew \
                    -d "$HOST" --force >> "$SSL_LOG" 2>&1
            fi
        else
            log_ssl INFO ACME "Intento $ATTEMPT — issue IP $HOST --shortlived --force"
            timeout 120 /root/.acme.sh/acme.sh --issue \
                -d "$HOST" --standalone --httpport 80 \
                --server letsencrypt --certificate-profile shortlived \
                --force >> "$SSL_LOG" 2>&1
        fi

        EXIT_CODE=$?
        [ "$EXIT_CODE" -eq 124 ] && log_ssl WARN ACME "Intento $ATTEMPT — TIMEOUT (120s) — host: $HOST ($TYPE)"

        sleep 3
        if openssl x509 -checkend 0 -noout -in "$ACME_CERT" 2>/dev/null; then
            log_ssl OK ACME "Intento $ATTEMPT exitoso — cert válido en $ACME_CERT — host: $HOST ($TYPE)"
            return 0
        fi
        log_ssl WARN ACME "Intento $ATTEMPT fallido — exit: $EXIT_CODE — cert inválido — host: $HOST ($TYPE)"
    done

    log_ssl ERROR ACME "Todos los intentos fallaron — host: $HOST ($TYPE)"
    return 1
}

# ═══════════════════════════════════════════════════════════════════════
#   PARCHE 1 + 4 + 5: apply_cert_to_panel
# ═══════════════════════════════════════════════════════════════════════
apply_cert_to_panel() {
    local HOST="$1"
    local ACME_CERT="/root/.acme.sh/${HOST}_ecc/fullchain.cer"
    local ACME_KEY="/root/.acme.sh/${HOST}_ecc/${HOST}.key"
    local DEST_CERT="$SSL_DIR/fullchain.cer"
    local DEST_KEY="$SSL_DIR/${HOST}.key"
    local DB="/etc/x-ui/x-ui.db"

    rotate_ssl_log   # PARCHE 4

    log_ssl INFO  APPLY  "Iniciando apply_cert_to_panel — host: $HOST"

    if ! openssl x509 -checkend 0 -noout -in "$ACME_CERT" 2>/dev/null; then
        echo -e "${RED}[SSL] El certificado de acme no es válido o no existe: $ACME_CERT${RESET}"
        log_ssl ERROR APPLY  "Cert acme inválido o inexistente: $ACME_CERT — abortando sin aplicar"
        return 1
    fi

    echo -e "${CYAN}[SSL] Copiando certificados a $SSL_DIR...${RESET}"
    log_ssl INFO  APPLY  "Copiando cert: $ACME_CERT → $DEST_CERT"
    mkdir -p "$SSL_DIR"
    cp "$ACME_CERT" "$DEST_CERT"
    cp "$ACME_KEY"  "$DEST_KEY"
    chmod 644 "$DEST_CERT"
    chmod 600 "$DEST_KEY"

    echo -e "${CYAN}[SSL] Actualizando rutas en la DB...${RESET}"
    log_ssl INFO  APPLY  "Actualizando DB — cert: $DEST_CERT | key: $DEST_KEY"
    local DB_OUT DB_EXIT
    DB_OUT=$(sqlite3 "$DB" "
        DELETE FROM settings WHERE key IN ('webCertFile', 'webKeyFile');
        INSERT INTO settings (key, value) VALUES ('webCertFile', '$DEST_CERT');
        INSERT INTO settings (key, value) VALUES ('webKeyFile',  '$DEST_KEY');
    " 2>&1)
    DB_EXIT=$?

    # PARCHE 1: si falla la DB, NO seguir
    if [ "$DB_EXIT" -ne 0 ]; then
        log_ssl ERROR APPLY  "Fallo al actualizar DB (exit $DB_EXIT): $DB_OUT — ABORTANDO, no se reinicia panel"
        echo -e "${RED}[SSL] ❌  Fallo en DB (exit $DB_EXIT). No se reinicia el panel para evitar estado inconsistente.${RESET}"
        return 1
    fi
    log_ssl OK    APPLY  "DB actualizada correctamente (exit 0)"

    echo -e "${YELLOW}[SSL] Reiniciando panel para aplicar certificado...${RESET}"
    log_ssl INFO  APPLY  "Reiniciando x-ui para activar cert"
    systemctl restart x-ui
    sleep 3

    get_port
    local LIVE_EXP LIVE_DAYS

    # PARCHE 5: timeout 10s
    LIVE_EXP=$(timeout 10 openssl s_client \
                -connect "${HOST}:${PORT}" \
                -servername "${HOST}" \
                </dev/null 2>/dev/null \
               | openssl x509 -enddate -noout 2>/dev/null \
               | cut -d= -f2)

    if [ -n "$LIVE_EXP" ]; then
        LIVE_DAYS=$(( ( $(date -d "$LIVE_EXP" +%s) - $(date +%s) ) / 86400 ))
        echo -e "${GREEN}[SSL] ✅  Cert aplicado — vence en $LIVE_DAYS días ($LIVE_EXP)${RESET}"
        log_ssl OK    APPLY  "Cert vivo verificado en $HOST:$PORT — vence en $LIVE_DAYS días ($LIVE_EXP)"
    else
        echo -e "${RED}[SSL] ❌  No se pudo verificar el cert vivo en puerto $PORT.${RESET}"
        log_ssl WARN  APPLY  "Cert copiado pero no verificable en $HOST:$PORT (panel puede demorar en responder)"
    fi
}

# ═══════════════════════════════════════════════════════════════════════
#   PATCH XHTTP — opción manual desde el menú
# ═══════════════════════════════════════════════════════════════════════
patch_xhttp_settings() {
    clear
    local DB="/etc/x-ui/x-ui.db"

    echo -e "${HOT_PINK}"
    echo "════════════════════════════════════ 💋"
    echo "     PATCH xhttpSettings 🔧👑"
    echo "════════════════════════════════════ 💋"
    echo -e "${RESET}"

    if [ ! -f "$DB" ]; then
        echo -e "${RED}❌  No se encontró la base de datos en: $DB${RESET}"
        echo -e "${YELLOW}Asegurate de que el panel esté instalado.${RESET}"
        read -rp "ENTER para continuar"
        return 1
    fi

    local TOTAL
    TOTAL=$(sqlite3 "$DB" \
        "SELECT COUNT(*) FROM inbounds
         WHERE json_extract(stream_settings, '$.network') = 'xhttp';" \
        2>/dev/null)

    if [ -z "$TOTAL" ] || [ "$TOTAL" -eq 0 ]; then
        echo -e "${YELLOW}⚠️  No se encontraron inbounds con network = xhttp en la DB.${RESET}"
        echo -e "${CYAN}Creá el inbound desde el panel y volvé a ejecutar esta opción.${RESET}"
        read -rp "ENTER para continuar"
        return 0
    fi

    echo -e "${CYAN}Inbounds xhttp encontrados: ${GREEN}$TOTAL${RESET}"
    echo
    echo -e "${YELLOW}Aplicando cambios:${RESET}"
    echo -e "  ${CYAN}scMaxBufferedPosts${RESET}  →  ${GREEN}10${RESET}"
    echo -e "  ${CYAN}scMaxEachPostBytes${RESET}  →  ${GREEN}500000${RESET}"
    echo

    sqlite3 "$DB" "
        UPDATE inbounds
        SET stream_settings = json_set(
            stream_settings,
            '$.xhttpSettings.scMaxBufferedPosts', 10,
            '$.xhttpSettings.scMaxEachPostBytes', '500000'
        )
        WHERE json_extract(stream_settings, '$.network') = 'xhttp';
    "

    local EXIT_CODE=$?

    if [ "$EXIT_CODE" -ne 0 ]; then
        echo -e "${RED}❌  Error al modificar la DB (código $EXIT_CODE).${RESET}"
        read -rp "ENTER para continuar"
        return 1
    fi

    echo -e "${GREEN}✅  DB actualizada correctamente.${RESET}"
    echo
    echo -e "${CYAN}Verificando valores aplicados...${RESET}"
    echo

    sqlite3 "$DB" \
        "SELECT
            id,
            remark,
            json_extract(stream_settings, '$.network')                          AS network,
            json_extract(stream_settings, '$.xhttpSettings.scMaxBufferedPosts') AS scMaxBufferedPosts,
            json_extract(stream_settings, '$.xhttpSettings.scMaxEachPostBytes') AS scMaxEachPostBytes
         FROM inbounds
         WHERE json_extract(stream_settings, '$.network') = 'xhttp';" \
        2>/dev/null \
    | while IFS='|' read -r id remark network posts bytes; do
        echo -e "  ID ${CYAN}$id${RESET} │ ${HOT_PINK}$remark${RESET}"
        echo -e "    network            : ${GREEN}$network${RESET}"
        echo -e "    scMaxBufferedPosts : ${GREEN}$posts${RESET}"
        echo -e "    scMaxEachPostBytes : ${GREEN}$bytes${RESET}"
        echo
    done

    echo -e "${YELLOW}Reiniciando Xray para aplicar cambios...${RESET}"
    x-ui restart-xray
    sleep 2

    echo
    echo -e "${GREEN}✅  Xray reiniciado. Cambios activos.${RESET}"
    read -rp "ENTER para continuar"
}

# ═══════════════════════════════════════════════════════════════════════
#   SETUP SSL RENEWAL — cron diario a las 4am
# ═══════════════════════════════════════════════════════════════════════
setup_ssl_renewal() {

    cat > /root/renew_ssl.sh << 'SCRIPT'
#!/bin/bash

DOMAIN_FILE="/etc/MCCARTHEY/ssl_domain"
TYPE_FILE="/etc/MCCARTHEY/ssl_type"
SSL_DIR="/etc/x-ui/ssl"
SSL_LOG="/var/log/mccarthey_ssl.log"
ACME_TIMEOUT=120

log_ssl() {
    local LEVEL="$1"; shift
    local TAG="$1";   shift
    local MSG="$*"
    printf '[%s] [%-5s] [%-7s] %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" \
        "$LEVEL" \
        "$TAG" \
        "$MSG" >> "$SSL_LOG"
}

rotate_ssl_log() {
    local MAX_BYTES=$(( 5 * 1024 * 1024 ))
    if [ -f "$SSL_LOG" ]; then
        local SIZE
        SIZE=$(stat -c%s "$SSL_LOG" 2>/dev/null || echo 0)
        if [ "$SIZE" -ge "$MAX_BYTES" ]; then
            mv "$SSL_LOG" "${SSL_LOG}.1"
            log_ssl INFO CONFIG "Log rotado — tamaño anterior: ${SIZE} bytes"
        fi
    fi
}

rotate_ssl_log

log_ssl INFO  RENEW  "==== Iniciando renew_ssl.sh (cron) ===="

if [ ! -f "$DOMAIN_FILE" ]; then
    log_ssl ERROR CONFIG "Archivo $DOMAIN_FILE no encontrado — abortando"
    exit 1
fi
HOST=$(cat "$DOMAIN_FILE")
if [ -z "$HOST" ]; then
    log_ssl ERROR CONFIG "$DOMAIN_FILE existe pero está vacío — abortando"
    exit 1
fi

SSL_TYPE="domain"
[ -f "$TYPE_FILE" ] && SSL_TYPE=$(cat "$TYPE_FILE")

if [[ "$SSL_TYPE" != "domain" && "$SSL_TYPE" != "ip" ]]; then
    log_ssl ERROR CONFIG "ssl_type desconocido ('$SSL_TYPE') en $TYPE_FILE — abortando"
    exit 1
fi

log_ssl INFO  CONFIG "Configuración leída — host: $HOST | tipo: $SSL_TYPE"

ACME_CERT="/root/.acme.sh/${HOST}_ecc/fullchain.cer"
ACME_KEY="/root/.acme.sh/${HOST}_ecc/${HOST}.key"
DEST_CERT="$SSL_DIR/fullchain.cer"
DEST_KEY="$SSL_DIR/${HOST}.key"

get_live_cert_days() {
    local H="$1" P="$2" EXP
    EXP=$(timeout 10 openssl s_client -connect "${H}:${P}" -servername "${H}" \
            </dev/null 2>/dev/null \
          | openssl x509 -enddate -noout 2>/dev/null | cut -d= -f2)
    [ -z "$EXP" ] && echo -1 && return
    echo $(( ( $(date -d "$EXP" +%s) - $(date +%s) ) / 86400 ))
}

apply_cert() {
    local DB="/etc/x-ui/x-ui.db"
    log_ssl INFO  APPLY  "Copiando cert a $SSL_DIR — host: $HOST"
    mkdir -p "$SSL_DIR"
    cp "$ACME_CERT" "$DEST_CERT"
    cp "$ACME_KEY"  "$DEST_KEY"
    chmod 644 "$DEST_CERT"
    chmod 600 "$DEST_KEY"

    log_ssl INFO  APPLY  "Actualizando rutas en DB — cert: $DEST_CERT | key: $DEST_KEY"
    local DB_OUT DB_EXIT
    DB_OUT=$(sqlite3 "$DB" "
        DELETE FROM settings WHERE key IN ('webCertFile', 'webKeyFile');
        INSERT INTO settings (key, value) VALUES ('webCertFile', '$DEST_CERT');
        INSERT INTO settings (key, value) VALUES ('webKeyFile',  '$DEST_KEY');
    " 2>&1)
    DB_EXIT=$?

    if [ "$DB_EXIT" -ne 0 ]; then
        log_ssl ERROR APPLY  "Fallo al actualizar DB (exit $DB_EXIT): $DB_OUT — ABORTANDO, no se reinicia panel"
        return 1
    fi
    log_ssl OK    APPLY  "DB actualizada correctamente"

    log_ssl INFO  APPLY  "Reiniciando x-ui"
    systemctl restart x-ui
    sleep 3

    PANEL_PORT=$(x-ui settings 2>/dev/null | awk '/port:/ {print $2}')
    [ -z "$PANEL_PORT" ] && PANEL_PORT="443"

    LIVE_EXP=$(timeout 10 openssl s_client -connect "${HOST}:${PANEL_PORT}" -servername "${HOST}" \
                </dev/null 2>/dev/null \
               | openssl x509 -enddate -noout 2>/dev/null | cut -d= -f2)
    if [ -n "$LIVE_EXP" ]; then
        LIVE_DAYS=$(( ( $(date -d "$LIVE_EXP" +%s) - $(date +%s) ) / 86400 ))
        log_ssl OK    APPLY  "Cert vivo verificado en $HOST:$PANEL_PORT — vence en $LIVE_DAYS días ($LIVE_EXP)"
    else
        log_ssl WARN  APPLY  "Cert copiado pero no verificable en $HOST:$PANEL_PORT (panel puede demorar)"
    fi
}

stop_proxy_local() {
    local PID
    PID=$(pgrep -f /etc/MCCARTHEY/PDirect.py)
    if [ -n "$PID" ]; then
        log_ssl INFO  PROXY  "Deteniendo proxy (PID $PID) para liberar puerto 80"
        kill "$PID"
        sleep 5
    else
        log_ssl INFO  PROXY  "Proxy no estaba activo — puerto 80 libre"
    fi
}

start_proxy_local() {
    if [ -z "$(pgrep -f /etc/MCCARTHEY/PDirect.py)" ]; then
        log_ssl INFO  PROXY  "Reactivando proxy MCCARTHEY"
        nohup python3 /etc/MCCARTHEY/PDirect.py 80 > /root/nohup.out 2>&1 &
        sleep 2
    else
        log_ssl INFO  PROXY  "Proxy ya activo — no se duplica"
    fi
}

check_port_80_free_local() {
    local OCCUPIED
    OCCUPIED=$(ss -tlnp 'sport = :80' 2>/dev/null | tail -n+2)
    if [ -n "$OCCUPIED" ]; then
        local PROC
        PROC=$(echo "$OCCUPIED" | grep -oP 'users:\(\(".*?"\)' | head -1)
        log_ssl WARN PROXY "Puerto 80 ocupado (proceso: ${PROC:-desconocido}) — abortando emisión acme"
        return 1
    fi
    return 0
}

run_acme_with_retry_local() {
    local TYPE="$1"
    local EXIT_CODE ATTEMPT

    for ATTEMPT in 1 2; do
        if [ "$ATTEMPT" -eq 2 ]; then
            log_ssl WARN ACME "Intento 1 fallido — esperando 30s antes de reintentar — host: $HOST ($TYPE)"
            sleep 30
        fi

        if [ "$TYPE" = "domain" ]; then
            if [ ! -f "$ACME_CERT" ]; then
                log_ssl INFO ACME "Intento $ATTEMPT — issue -d $HOST --standalone (timeout ${ACME_TIMEOUT}s)"
                timeout "$ACME_TIMEOUT" /root/.acme.sh/acme.sh --issue -d "$HOST" --standalone --httpport 80 >> "$SSL_LOG" 2>&1
            else
                log_ssl INFO ACME "Intento $ATTEMPT — renew -d $HOST (timeout ${ACME_TIMEOUT}s)"
                timeout "$ACME_TIMEOUT" /root/.acme.sh/acme.sh --renew -d "$HOST" >> "$SSL_LOG" 2>&1
            fi
        else
            log_ssl INFO ACME "Intento $ATTEMPT — issue IP $HOST --shortlived --force (timeout ${ACME_TIMEOUT}s)"
            timeout "$ACME_TIMEOUT" /root/.acme.sh/acme.sh --issue \
                -d "$HOST" --standalone --httpport 80 \
                --server letsencrypt --certificate-profile shortlived \
                --force >> "$SSL_LOG" 2>&1
        fi

        EXIT_CODE=$?
        [ "$EXIT_CODE" -eq 124 ] && log_ssl WARN ACME "Intento $ATTEMPT — TIMEOUT (${ACME_TIMEOUT}s) — host: $HOST ($TYPE)"

        sleep 3
        if openssl x509 -checkend 0 -noout -in "$ACME_CERT" 2>/dev/null; then
            log_ssl OK ACME "Intento $ATTEMPT exitoso — cert válido — host: $HOST ($TYPE)"
            return 0
        fi
        log_ssl WARN ACME "Intento $ATTEMPT fallido — exit: $EXIT_CODE — host: $HOST ($TYPE)"
    done

    log_ssl ERROR ACME "Todos los intentos fallaron — host: $HOST ($TYPE)"
    return 1
}

for dir in /root/.acme.sh/*; do
    [ -d "$dir" ] || continue
    DIRNAME=$(basename "$dir")
    [[ "$DIRNAME" == ca ]]       && continue
    [[ "$DIRNAME" == account* ]] && continue
    if [[ "$DIRNAME" != "${HOST}_ecc" && "$DIRNAME" != "$HOST" ]]; then
        log_ssl INFO  CONFIG "Eliminando cert obsoleto: $DIRNAME"
        rm -rf "$dir"
    fi
done

if [ "$SSL_TYPE" = "domain" ]; then

    PANEL_PORT=$(x-ui settings 2>/dev/null | awk '/port:/ {print $2}')
    [ -z "$PANEL_PORT" ] && PANEL_PORT="443"

    NECESITA_EMITIR=false
    NECESITA_APLICAR=false

    if [ ! -f "$DEST_CERT" ]; then
        log_ssl INFO  RENEW  "Cert no encontrado en $SSL_DIR — se emitirá uno nuevo"
        NECESITA_EMITIR=true
        NECESITA_APLICAR=true
    else
        EXPIRACION=$(openssl x509 -enddate -noout -in "$DEST_CERT" | cut -d= -f2)
        DIAS=$(( ( $(date -d "$EXPIRACION" +%s) - $(date +%s) ) / 86400 ))
        log_ssl INFO  RENEW  "Cert en $SSL_DIR vence en $DIAS días ($EXPIRACION)"
        if [ "$DIAS" -le 7 ]; then
            log_ssl INFO  RENEW  "Faltan $DIAS días (umbral ≤7) — renovación necesaria"
            NECESITA_EMITIR=true
            NECESITA_APLICAR=true
        else
            log_ssl INFO  RENEW  "Cert dentro de plazo — no se renueva"
        fi
    fi

    LIVE_DAYS=$(get_live_cert_days "$HOST" "$PANEL_PORT")
    if [ "$LIVE_DAYS" -lt 0 ]; then
        log_ssl WARN  RENEW  "No se pudo conectar al panel en $HOST:$PANEL_PORT para verificar cert vivo"
    elif [ "$LIVE_DAYS" -lt 10 ]; then
        log_ssl WARN  RENEW  "Cert vivo vence en $LIVE_DAYS días (panel desfasado) — forzando reaplicación"
        NECESITA_APLICAR=true
    else
        log_ssl INFO  RENEW  "Cert vivo OK en $HOST:$PANEL_PORT — $LIVE_DAYS días restantes"
    fi

    if [ "$NECESITA_EMITIR" = true ]; then
        stop_proxy_local
        if ! check_port_80_free_local; then
            log_ssl ERROR RENEW "Puerto 80 ocupado — no se puede emitir cert para $HOST (dominio)"
            start_proxy_local
            exit 1
        fi
        if ! run_acme_with_retry_local "domain"; then
            log_ssl ERROR RENEW "Emisión fallida tras reintentos — host: $HOST (dominio) — NO se aplica cert"
            start_proxy_local
            exit 1
        fi
    fi

    if [ "$NECESITA_APLICAR" = true ]; then
        apply_cert
    fi

    if [ "$NECESITA_EMITIR" = true ]; then
        start_proxy_local
    fi

    if [ "$NECESITA_EMITIR" = false ] && [ "$NECESITA_APLICAR" = false ]; then
        log_ssl OK    RENEW  "Todo en orden para $HOST (dominio) — sin acciones necesarias"
    else
        log_ssl OK    RENEW  "Proceso completado para $HOST (dominio)"
    fi

elif [ "$SSL_TYPE" = "ip" ]; then

    log_ssl INFO  RENEW  "Tipo IP — renovación forzada siempre (cert shortlived ~6 días)"
    stop_proxy_local

    if ! check_port_80_free_local; then
        log_ssl ERROR RENEW "Puerto 80 ocupado — no se puede emitir cert para $HOST (IP)"
        start_proxy_local
        exit 1
    fi

    if ! run_acme_with_retry_local "ip"; then
        log_ssl ERROR RENEW "Emisión fallida tras reintentos — host: $HOST (IP) — NO se aplica cert"
        start_proxy_local
        exit 1
    fi

    apply_cert
    start_proxy_local
    log_ssl OK    RENEW  "Proceso completado para $HOST (IP)"

else
    log_ssl ERROR CONFIG "ssl_type desconocido ('$SSL_TYPE') — abortando"
    exit 1
fi
SCRIPT

    chmod +x /root/renew_ssl.sh
    (crontab -l 2>/dev/null | grep -v renew_ssl.sh; echo "0 4 * * * /root/renew_ssl.sh") | crontab -
    echo -e "${GREEN}Script de renovación SSL configurado ✅${RESET}"
}

# ═══════════════════════════════════════════════════════════════════════
#   FORCE RENEW SSL — opción manual desde el menú
# ═══════════════════════════════════════════════════════════════════════
force_renew_ssl() {
    clear
    echo -e "${YELLOW}Iniciando renovación SSL manual... 🔐${RESET}"
    echo

    rotate_ssl_log

    get_domain
    get_ssl_type

    if [ -z "$DOMAIN" ]; then
        echo -e "${YELLOW}No hay host guardado. Ingresá el valor:${RESET}"
        read -rp "Dominio ó IP → " DOMAIN
        if [ -z "$DOMAIN" ]; then
            echo -e "${RED}No se ingresó un valor. Abortando.${RESET}"
            read -rp "ENTER para continuar"
            return
        fi
        mkdir -p /etc/MCCARTHEY
        echo "$DOMAIN" > "$DOMAIN_FILE"

        echo -e "${CYAN}¿Qué tipo es?${RESET}"
        echo "  1) Dominio"
        echo "  2) IP"
        read -rp "→ " TIPO_RESP
        [ "$TIPO_RESP" = "2" ] && SSL_TYPE="ip" || SSL_TYPE="domain"
        echo "$SSL_TYPE" > "$TYPE_FILE"
    fi

    if [[ "$SSL_TYPE" != "domain" && "$SSL_TYPE" != "ip" ]]; then
        echo -e "${RED}❌  ssl_type inválido ('$SSL_TYPE') en $TYPE_FILE. Corregilo manualmente.${RESET}"
        log_ssl ERROR FORCE "ssl_type inválido ('$SSL_TYPE') — abortando force_renew_ssl"
        read -rp "ENTER para continuar"
        return
    fi

    local HOST="$DOMAIN"

    echo -e "${CYAN}Host: $HOST | Tipo: $SSL_TYPE${RESET}"
    echo

    stop_proxy

    if ! check_port_80_free; then
        start_proxy
        read -rp "ENTER para continuar"
        return
    fi

    if ! run_acme_with_retry "$HOST" "$SSL_TYPE"; then
        echo -e "${RED}❌  Error: acme no emitió un cert válido tras 2 intentos. No se aplicaron cambios.${RESET}"
        log_ssl ERROR FORCE  "Emisión fallida tras reintentos — host: $HOST ($SSL_TYPE) — NO se aplica cert"
        start_proxy
        read -rp "ENTER para continuar"
        return
    fi

    log_ssl OK FORCE "Cert válido confirmado — host: $HOST ($SSL_TYPE) — procediendo a aplicar"

    apply_cert_to_panel "$HOST"
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌  Fallo al aplicar cert al panel. Revisá el log: $SSL_LOG${RESET}"
        start_proxy
        read -rp "ENTER para continuar"
        return
    fi

    get_port

    local DEST_CERT="$SSL_DIR/fullchain.cer"
    local LIVE_DAYS
    LIVE_DAYS=$(get_live_cert_days "$HOST" "$PORT")

    if [ "$LIVE_DAYS" -lt 0 ]; then
        echo -e "${YELLOW}⚠️  No se pudo conectar al panel (puerto $PORT). Verificando archivo local...${RESET}"
        if cert_is_valid "$DEST_CERT"; then
            local EXP DIAS
            EXP=$(openssl x509 -enddate -noout -in "$DEST_CERT" | cut -d= -f2)
            DIAS=$(( ( $(date -d "$EXP" +%s) - $(date +%s) ) / 86400 ))
            echo -e "${CYAN}Cert en $SSL_DIR: válido, vence en $DIAS días ($EXP)${RESET}"
        fi
    elif [ "$LIVE_DAYS" -lt 10 ] && [ "$SSL_TYPE" = "domain" ]; then
        echo -e "${RED}⚠️  Panel sirviendo cert con $LIVE_DAYS días. Reaplicando...${RESET}"
        apply_cert_to_panel "$HOST"
    else
        echo -e "${GREEN}✅  Cert vivo verificado: $LIVE_DAYS días restantes.${RESET}"
    fi

    cleanup_old_certs "$HOST"
    start_proxy

    echo
    echo -e "${GREEN}✅  SSL renovado correctamente para: $HOST${RESET}"
    read -rp "ENTER para continuar"
}

# ═══════════════════════════════════════════════════════════════════════
#   INSTALL PANEL
# ═══════════════════════════════════════════════════════════════════════
install_panel() {
    clear

    echo -e "${HOT_PINK}"
    echo "════════════════════════════════════ 💋"
    echo "     INSTALAR PANEL 3X-UI"
    echo "════════════════════════════════════ 💋"
    echo -e "${RESET}"

    echo -e "${CYAN}¿Cómo vas a configurar el SSL?${RESET}"
    echo
    echo "  1) Dominio  (cert 90 días — renovación automática normal)"
    echo "  2) IP       (cert 6 días  — renovación forzada diaria)"
    echo
    read -rp "→ " SSL_MODE

    case "$SSL_MODE" in
        1) SSL_TYPE="domain" ;;
        2) SSL_TYPE="ip"     ;;
        *)
            echo -e "${RED}Opción inválida. Abortando instalación.${RESET}"
            read -rp "ENTER para continuar"
            return
            ;;
    esac

    echo
    if [ "$SSL_TYPE" = "domain" ]; then
        read -rp "Ingresá el dominio (ej: panel.tudominio.com) → " HOST
        if [ -z "$HOST" ]; then
            echo -e "${RED}No se ingresó un dominio. Abortando instalación.${RESET}"
            read -rp "ENTER para continuar"
            return
        fi
    else
        read -rp "Ingresá la IP del servidor → " HOST
        if [ -z "$HOST" ]; then
            echo -e "${RED}No se ingresó una IP. Abortando instalación.${RESET}"
            read -rp "ENTER para continuar"
            return
        fi
    fi

    mkdir -p /etc/MCCARTHEY
    echo "$HOST"     > "$DOMAIN_FILE"
    echo "$SSL_TYPE" > "$TYPE_FILE"
    echo -e "${GREEN}Configuración guardada: $HOST ($SSL_TYPE)${RESET}"
    echo

    echo -e "${YELLOW}Instalando dependencias y panel... ⏳${RESET}"
    stop_proxy

    apt update -y >/dev/null 2>&1
    apt install -y curl sqlite3 sudo wget apache2-utils >/dev/null 2>&1

    printf "\nY\n" | bash <(curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh) >/dev/null 2>&1
    echo -e "${GREEN}Panel instalado correctamente ✅${RESET}"

    setup_ssl_renewal
    setup_auto_patch_cron
    setup_watchdog_cron   # Solo registra cron, no escribe el archivo

    local ACME_OK=false
    if ! check_port_80_free; then
        echo -e "${YELLOW}⚠️  Puerto 80 ocupado. El panel funcionará sin SSL por ahora.${RESET}"
        log_ssl WARN INSTALL "Puerto 80 ocupado — se omite emisión SSL para $HOST ($SSL_TYPE)"
    else
        if run_acme_with_retry "$HOST" "$SSL_TYPE"; then
            log_ssl OK INSTALL "Emisión SSL exitosa — host: $HOST ($SSL_TYPE)"
            ACME_OK=true
        else
            echo -e "${RED}⚠️  No se pudo emitir el SSL tras 2 intentos. El panel funcionará sin SSL.${RESET}"
            log_ssl ERROR INSTALL "Emisión SSL fallida tras reintentos — host: $HOST ($SSL_TYPE)"
        fi
    fi

    if [ "$ACME_OK" = true ]; then
        apply_cert_to_panel "$HOST"
    fi

    cleanup_old_certs "$HOST"
    start_proxy
    sleep 2

    if panel_installed; then
        local USER PASS HASH PATHP
        USER=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 10)
        PASS=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 14)

        echo -e "${YELLOW}Configurando credenciales del panel...${RESET}"
        HASH=$(htpasswd -bnBC 10 "" "$PASS" | tr -d ':\n')

        if [ -f /etc/x-ui/x-ui.db ]; then
            sqlite3 /etc/x-ui/x-ui.db \
                "UPDATE users SET username='$USER', password='$HASH' WHERE id=1;"
        fi

        x-ui restart >/dev/null 2>&1
        sleep 3

        get_port
        PATHP=$(x-ui settings 2>/dev/null | awk '/webBasePath/ {print $2}')

        local DEST_CERT="$SSL_DIR/fullchain.cer"

        clear
        echo -e "${GREEN}"
        echo "════════════════════════════════════"
        echo "       PANEL LISTO 💖"
        echo "════════════════════════════════════"
        echo -e "${RESET}"
        echo "Usuario  : $USER"
        echo "Password : $PASS"
        echo "Puerto   : $PORT"
        echo "Ruta     : $PATHP"
        echo "Host     : $HOST"
        echo "Tipo SSL : $SSL_TYPE"
        echo

        if cert_is_valid "$DEST_CERT"; then
            echo "URL DEL PANEL"
            echo "https://$HOST:$PORT$PATHP"
            if [ "$SSL_TYPE" = "ip" ]; then
                echo
                echo -e "${YELLOW}⚠️  Cert shortlived (~6 días). Cron diario (4am) renueva automáticamente.${RESET}"
            fi
        else
            echo "URL DEL PANEL (sin SSL)"
            echo "http://$HOST:$PORT$PATHP"
        fi

        echo
        echo -e "${CYAN}💡 Auto-patch xhttp v2 activo (cada 6 horas).${RESET}"
        echo -e "${CYAN}   Log: tail -f /var/log/auto_patch_xhttp.log${RESET}"
        echo

        # Watchdog: mensaje según si existe o no
        if [ -f /root/xray_watchdog.sh ]; then
            echo -e "${CYAN}💡 Watchdog v4.1 activo (cada 5 min — proceso culpable identificado por delta CPU).${RESET}"
            echo -e "${CYAN}   RAM: ≥80% inmediato | ≥70% × 2 ciclos (~10 min)${RESET}"
            echo -e "${CYAN}   CPU: ≥75% inmediato | ≥70% × 2 ciclos (~10 min)${RESET}"
            echo -e "${CYAN}   Log: tail -f /var/log/xray_watchdog.log${RESET}"
        else
            echo -e "${YELLOW}⚠️  Watchdog no encontrado. Instalá VPN Full para activarlo.${RESET}"
            echo -e "${YELLOW}   El panel funciona normalmente — solo sin monitoreo de procesos.${RESET}"
        fi

        echo
        if [ "$SSL_TYPE" = "domain" ]; then
            echo -e "${CYAN}💡 Renovación SSL: diaria 4am — renueva si quedan ≤7 días (cert 90d)${RESET}"
        else
            echo -e "${CYAN}💡 Renovación SSL: diaria 4am — siempre forzada (cert shortlived ~6d)${RESET}"
        fi
        echo -e "${CYAN}   Log SSL: tail -f /var/log/mccarthey_ssl.log${RESET}"
    else
        echo -e "${RED}La instalación falló.${RESET}"
    fi

    read -rp "ENTER para continuar"
}

# ═══════════════════════════════════════════════════════════════════════
#   SHOW PANEL
# ═══════════════════════════════════════════════════════════════════════
show_panel() {
    clear

    if ! panel_installed; then
        echo "El panel no está instalado."
        read -rp "ENTER"
        return
    fi

    get_port
    get_domain
    get_ssl_type

    local PATHP IP
    PATHP=$(x-ui settings 2>/dev/null | awk '/webBasePath/ {print $2}')
    IP=$(curl -s https://api.ipify.org)

    echo "════════════════════════════════════"
    echo "       DATOS DEL PANEL"
    echo "════════════════════════════════════"
    echo

    systemctl status x-ui | grep Active
    echo

    echo "Puerto   : $PORT"
    echo "Ruta     : $PATHP"
    echo "IP real  : $IP"
    echo "Host SSL : ${DOMAIN:-No configurado}"
    echo "Tipo SSL : ${SSL_TYPE}"
    echo

    local DEST_CERT="$SSL_DIR/fullchain.cer"

    if cert_is_valid "$DEST_CERT"; then
        local EXPIRACION DIAS
        EXPIRACION=$(openssl x509 -enddate -noout -in "$DEST_CERT" | cut -d= -f2)
        DIAS=$(( ( $(date -d "$EXPIRACION" +%s) - $(date +%s) ) / 86400 ))
        echo "SSL      : ✅  Válido — vence en $DIAS días ($EXPIRACION)"
        echo
        if [ -n "$DOMAIN" ]; then
            echo "URL: https://$DOMAIN:$PORT$PATHP"
        else
            echo "URL: https://$IP:$PORT$PATHP"
        fi
    else
        echo "SSL      : ❌  Certificado no encontrado o inválido en $SSL_DIR"
        echo
        if [ -n "$DOMAIN" ]; then
            echo "URL (sin SSL): http://$DOMAIN:$PORT$PATHP"
        else
            echo "URL (sin SSL): http://$IP:$PORT$PATHP"
        fi
    fi

    local PROXY_PID
    PROXY_PID=$(pgrep -f /etc/MCCARTHEY/PDirect.py)
    echo
    if [ -n "$PROXY_PID" ]; then
        echo "Proxy    : ✅  Activo (PID $PROXY_PID)"
    else
        echo "Proxy    : ❌  Inactivo"
    fi

    echo
    if [ -f /root/auto_patch_xhttp.sh ]; then
        echo "AutoPatch xhttp : ✅  Activo  → log: /var/log/auto_patch_xhttp.log"
    else
        echo "AutoPatch xhttp : ❌  No instalado"
    fi

    echo
    if [ -f /root/xray_watchdog.sh ]; then
        local RAM_NOW LOAD_NOW NCPU_NOW CPU_NOW RAM_CTR CPU_CTR
        RAM_NOW=$(free  | awk '/^Mem:/ {printf "%.0f", ($2-$7)/$2 * 100}')
        LOAD_NOW=$(awk '{print $1}' /proc/loadavg)
        NCPU_NOW=$(nproc)
        CPU_NOW=$(awk "BEGIN {printf \"%.0f\", ($LOAD_NOW/$NCPU_NOW)*100}")
        RAM_CTR=$(cat /tmp/watchdog_counter_ram 2>/dev/null || echo 0)
        CPU_CTR=$(cat /tmp/watchdog_counter_cpu 2>/dev/null || echo 0)

        echo "Watchdog v4.1   : ✅  Activo  → log: /var/log/xray_watchdog.log"
        echo "RAM real        : ${RAM_NOW}%  (warn≥70% × 2 | crit≥80% inmediato | ctr: ${RAM_CTR}/2)"
        echo "CPU load        : ${CPU_NOW}%  (warn≥70% × 2 | crit≥75% inmediato | ctr: ${CPU_CTR}/2)"
        echo "load1 / nproc   : ${LOAD_NOW} / ${NCPU_NOW}"
    else
        echo "Watchdog        : ❌  No instalado (requiere VPN Full)"
    fi

    read -rp "ENTER para continuar"
}

# ═══════════════════════════════════════════════════════════════════════
#   REMOVE PANEL
#   No elimina el watchdog si VPN Full está activo en el mismo servidor.
# ═══════════════════════════════════════════════════════════════════════
remove_panel() {
    clear
    echo -e "${RED}Eliminando panel...${RESET}"

    x-ui stop      >/dev/null 2>&1
    x-ui uninstall >/dev/null 2>&1

    crontab -l 2>/dev/null \
        | grep -v auto_patch_xhttp.sh \
        | grep -v xray_watchdog.sh \
        | grep -v renew_ssl.sh \
        | crontab -

    rm -f /root/auto_patch_xhttp.sh
    rm -f /root/renew_ssl.sh
    rm -f /tmp/auto_patch_xhttp.lock

    # Watchdog: solo eliminar si VPN Full no está activo en este servidor
    if systemctl is-active --quiet stunnel4 || pgrep -f PDirect.py > /dev/null 2>&1; then
        echo -e "${YELLOW}Watchdog v4.1 conservado — VPN Full está activo en este servidor.${RESET}"
        echo -e "${YELLOW}Para eliminar el watchdog, desinstalá VPN Full primero.${RESET}"
    else
        rm -f /root/xray_watchdog.sh
        rm -f /tmp/watchdog_counter_ram
        rm -f /tmp/watchdog_counter_cpu
        rm -f /tmp/xray_watchdog_last
        rm -f /tmp/xray_watchdog.lock
        echo -e "${YELLOW}Watchdog eliminado — VPN Full no estaba activo.${RESET}"
    fi

    echo -e "${GREEN}Panel y scripts eliminados correctamente ✅${RESET}"
    read -rp "ENTER para continuar"
}


# ═══════════════════════════════════════════════════════════════════════
#   MENÚ PRINCIPAL
# ═══════════════════════════════════════════════════════════════════════
xhttp_panel() {
    while true; do
        panel_status
        get_port
        clear
        echo -e "${HOT_PINK}"
        echo "════════════════════════════════════ 💋"
        echo "     XRAY + 3X-UI MANAGER 🌸👑"
        echo "════════════════════════════════════ 💋"
        echo -e "${RESET}"
        echo
        if [ "$STATUS" = "Activo 🟢" ]; then
            echo -e "${CYAN}ESTADO :${RESET}  ${GREEN}ACTIVO 🟢${RESET}"
        else
            echo -e "${CYAN}ESTADO :${RESET}  ${RED}INACTIVO 🔴${RESET}"
        fi
        echo
        echo -e "${CYAN}1) Instalar / Actualizar panel ✨${RESET}"
        echo -e "${CYAN}2) Ver datos del panel 👀💕${RESET}"
        echo -e "${CYAN}3) Renovar SSL manualmente 🔐${RESET}"
        echo -e "${CYAN}4) Eliminar panel 😈🗑️${RESET}"
        echo -e "${CYAN}5) Parchear xhttpSettings 🔧${RESET}"
        echo -e "${CYAN}0) Salir 💔${RESET}"
        echo
        read -rp "👑 Seleccione una opción reina → " op
        case "$op" in
            1) install_panel        ;;
            2) show_panel           ;;
            3) force_renew_ssl      ;;
            4) remove_panel         ;;
            5) patch_xhttp_settings ;;
            0) break                ;;
        esac
    done
}



# ==== MENU ====  
if [[ -t 0 ]]; then  
while true; do  
    clear  
    barra_sistema
    echo
             echo -e "${VIOLETA}🌸✨═══ 🐾 PANELCITO VPN | SSH UWU ═══✨🌸${NC}"
    
    echo -e "${ROJO}➜ ${VERDE}1.${NC} ${AMARILLO_SUAVE}🆕 Crear usuario${NC}"
    echo -e "${ROJO}➜ ${VERDE}2.${NC} ${AMARILLO_SUAVE}📋 Ver registros${NC}"
    echo -e "${ROJO}➜ ${VERDE}3.${NC} ${AMARILLO_SUAVE}🗑️ Eliminar usuario${NC}"
    echo -e "${ROJO}➜ ${VERDE}4.${NC} ${AMARILLO_SUAVE}📊 Información${NC}"
    echo -e "${ROJO}➜ ${VERDE}5.${NC} ${AMARILLO_SUAVE}🟢 Verificar usuarios online${NC}"
    echo -e "${ROJO}➜ ${VERDE}6.${NC} ${AMARILLO_SUAVE}🔒 Bloquear/Desbloquear usuario${NC}"
    echo -e "${ROJO}➜ ${VERDE}7.${NC} ${AMARILLO_SUAVE}🆕 Crear múltiples usuarios${NC}"
    echo -e "${ROJO}➜ ${VERDE}8.${NC} ${AMARILLO_SUAVE}📋 Mini registro${NC}"
    echo -e "${ROJO}➜ ${VERDE}9.${NC} ${AMARILLO_SUAVE}⚙️ Activar/Desactivar limitador${NC}"
    echo -e "${ROJO}➜ ${VERDE}10.${NC} ${AMARILLO_SUAVE}🎨 Configurar banner SSH${NC}"
    echo -e "${ROJO}➜ ${VERDE}11.${NC} ${AMARILLO_SUAVE}🔄 Activar/Desactivar contador online${NC}"
    echo -e "${ROJO}➜ ${VERDE}12.${NC} ${AMARILLO_SUAVE}🛬 SSH BOT${NC}"
    echo -e "${ROJO}➜ ${VERDE}13.${NC} ${AMARILLO_SUAVE}🔄 Renovar usuario${NC}"
    echo -e "${ROJO}➜ ${VERDE}14.${NC} ${AMARILLO_SUAVE}💾 Activar/Desactivar Swap${NC}"
    echo -e "${ROJO}➜ ${VERDE}15.${NC} ${AMARILLO_SUAVE}👁️‍🗨️ Información detallada de usuario${NC}"
    echo -e "${ROJO}➜ ${VERDE}16.${NC} ${ROJO}🐌 SLOWDNS CARACOL${NC}"
    echo -e "${ROJO}➜ ${VERDE}17.${NC} ${VIOLETA}😌 XHTTP${NC}"  
    echo -e "${ROJO}➜ ${VERDE}0.${NC} ${AMARILLO_SUAVE} 🚪 Salir${NC}"
    
    echo -e "${VIOLETA}═══════════════════════════════════════════════════${NC}"
    
   
  
    # == MENU 🚫  
    while true; do  
        read -p "$(echo -e "${VERDE}➡️ Selecciona una opción: ${NC}")" OPCION  
  
        # ENTER vacío → no imprime nada  
        if [[ -z "$OPCION" ]]; then  
            tput cuu1  
            tput dl1  
            continue  
        fi  
  
        # Solo permitir 0–16  
        if [[ ! "$OPCION" =~ ^([0-9]|1[0-7])$ ]]; then  
            tput cuu1  
            tput dl1  
            continue  
        fi  
  
        break  
    done  
  
    case "$OPCION" in  
        1) crear_usuario ;;  
        2) ver_registros ;;  
        3) eliminar_multiples_usuarios ;;  
        4) informacion_usuarios ;;  
        5) verificar_online ;;  
        6) bloquear_desbloquear_usuario ;;  
        7) crear_multiples_usuarios ;;  
        8) mini_registro ;;  
        9) activar_desactivar_limitador ;;  
        10) configurar_banner_ssh ;;  
        11) contador_online ;;  
        12) ssh_bot ;;  
        13) renovar_usuario ;;  
        14) activar_desactivar_swap ;;  
        15) usuarios_ssh ;;  
        16) slowdns_panel ;;
        17) xhttp_panel ;;
        0)  
            echo -e "${AMARILLO_SUAVE}🚪 Saliendo al shell...${NC}"  
            exec /bin/bash  
            ;;  
    esac  
done  
fi  
  
  

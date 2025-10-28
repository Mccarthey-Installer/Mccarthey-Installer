#!/bin/bash

# ================================
# VARIABLES Y RUTAS
# ================================
export REGISTROS="/diana/reg.txt"
export HISTORIAL="/alexia/log.txt"
export PIDFILE="/Abigail/mon.pid"

# Crear directorios si no existen
mkdir -p "$(dirname "$REGISTROS")"
mkdir -p "$(dirname "$HISTORIAL")"
mkdir -p "$(dirname "$PIDFILE")"




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

    # Definir rutas de archivos
    export REGISTROS="/diana/reg.txt"
    export HISTORIAL="/alexia/log.txt"
    export PIDFILE="/Abigail/mon.pid"

    # Crear directorios si no existen
    mkdir -p "$(dirname "$REGISTROS")"
    mkdir -p "$(dirname "$HISTORIAL")"
    mkdir -p "$(dirname "$PIDFILE")"

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
                                                            RESUMEN=\"✅ *Usuario creado correctamente:*

👤 *Usuario*: \\\`\${USERNAME}\\\`
🔑 *Clave*: \\\`\${PASSWORD}\\\`
\\\`📅 Expira: \${fecha_expiracion}\\\`
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
*⏳Tiempo conectado/última vez/nunca conectado*: \$detalle

\"
                                                LISTA_TXT=\"\${LISTA_TXT}🕒 FECHA: \$FECHA_ACTUAL\n🧑‍💻Usuario: \$usuario\n🌐Conexiones: \$conexiones_status\n📲Móviles: \$moviles\n⏳Tiempo conectado/última vez/nunca conectado: \$detalle\n\n\"
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
                                    '0')
                                        curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"🏠 *Menú Principal* 🔙

✅ *Regresando al menú...*
👋 ¡Hasta pronto!\" -d parse_mode=Markdown >/dev/null
                                        ;;
                                    *)
                                        curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"❓ *Opción no válida* ⚠️

🤔 No entiendo esa opción...
💡 Escribe *hola* para ver el menú
🔢 O usa: 1, 2, 3, 4, 5, 6, 7, 0\" -d parse_mode=Markdown >/dev/null
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
    CIAN='\033[38;5;51m'  # Added CIAN to match verificar_online for consistency

    # ================= Config persistente =================
    STATE_FILE="/etc/mi_script/contador_online.conf"

    # ================= Usuarios =================  
    TOTAL_CONEXIONES=0  
    TOTAL_USUARIOS=0  
    USUARIOS_EXPIRAN=()  
    inactivos=0  # Initialize inactivos counter

    if [[ -f "$REGISTROS" ]]; then  
        while IFS=' ' read -r user_data fecha_expiracion dias moviles fecha_creacion; do  
            usuario=${user_data%%:*}  
            if id "$usuario" &>/dev/null; then  
                ((TOTAL_USUARIOS++))  
                DIAS_RESTANTES=$(calcular_dias_restantes "$fecha_expiracion")  
                if [[ $DIAS_RESTANTES -eq 0 ]]; then  
                    USUARIOS_EXPIRAN+=("${BLANCO}${usuario}${NC} ${AMARILLO}0 Días${NC}")  
                fi  
                # Calculate inactivos based on verificar_online logic
                conexiones=$(( $(ps -u "$usuario" -o comm= | grep -cE "^(sshd|dropbear)$") ))  
                bloqueo_file="/tmp/bloqueo_${usuario}.lock"  
                if [[ $conexiones -eq 0 && ! -f "$bloqueo_file" ]]; then  
                    ((inactivos++))  
                elif [[ -f "$bloqueo_file" ]]; then  
                    bloqueo_hasta=$(cat "$bloqueo_file")  
                    if [[ $(date +%s) -ge $bloqueo_hasta ]]; then  
                        rm -f "$bloqueo_file"  
                        ((inactivos++))  # Consider unblocked but disconnected users as inactive
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
    MEM_PORC=$(awk "BEGIN {printf \"%.2f\", ($MEM_USO/$MEM_TOTAL)*100}")  

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

    # ================= CPU =================  
    CPU_PORC=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')  
    CPU_PORC=$(awk "BEGIN {printf \"%.0f\", $CPU_PORC}")  
    CPU_MHZ=$(awk -F': ' '/^cpu MHz/ {print $2; exit}' /proc/cpuinfo)  
    [[ -z "$CPU_MHZ" ]] && CPU_MHZ="Desconocido"  

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
UPTIME=$(uptime -p | sed 's/up //')  # Obtiene el uptime en formato legible, ej: "6 hours, 13 minutes"
UPTIME_COLOR="${MAGENTA}🕓 UPTIME: ${AMARILLO}${UPTIME}${NC}"  # Formato con color y emoji para destacar


    # ================= Transferencia acumulada =================  
    TRANSFER_FILE="/tmp/vps_transfer_total"  
    LAST_FILE="/tmp/vps_transfer_last"  

    RX_TOTAL=$(awk '/eth0|ens|enp|wlan|wifi/{rx+=$2} END{print rx}' /proc/net/dev)  
    TX_TOTAL=$(awk '/eth0|ens|enp|wlan|wifi/{tx+=$10} END{print tx}' /proc/net/dev)  
    TOTAL_BYTES=$((RX_TOTAL + TX_TOTAL))

    if [[ ! -f "$LAST_FILE" ]]; then
        TRANSFER_ACUM=0
        DIFF=0
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
        if [ "$bytes" -ge 1073741824 ]; then  
            awk "BEGIN {printf \"%.2f GB\", $bytes/1073741824}"  
        else  
            awk "BEGIN {printf \"%.2f MB\", $bytes/1048576}"  
        fi  
    }  

    TRANSFER_DISPLAY=$(human_transfer $TRANSFER_ACUM)

    # ================= Imprimir todo =================  
    echo -e "${AZUL}═══════════════════════════════════════════════════${NC}"
    echo -e "${BLANCO} 💾 TOTAL:${AMARILLO} ${MEM_TOTAL_H}${NC}     ${BLANCO}∘ 💧 DISPONIBLE:${AMARILLO} ${MEM_DISPONIBLE_H}${NC} ${BLANCO}∘ 💿 HDD:${AMARILLO} ${DISCO_TOTAL_H}${NC} ${DISCO_PORC_COLOR}"
    echo -e "${BLANCO} 📊 U/RAM:${AMARILLO} ${MEM_PORC}%${NC}   ${BLANCO}∘ 🖥️ U/CPU:${AMARILLO}${CPU_PORC}%${NC}       ${BLANCO}∘ 🔧 CPU MHz:${AMARILLO} ${CPU_MHZ}${NC}"
    echo -e "${AZUL}═══════════════════════════════════════════════════${NC}"
    echo -e "${BLANCO} 🌍 IP:${AMARILLO} ${IP_PUBLICA}${NC}          ${BLANCO} 🕒 FECHA:${AMARILLO} ${FECHA_ACTUAL}${NC}"
    echo -e "${BLANCO} 🖼️ SO:${AMARILLO}${SO_NAME}${NC}        ${BLANCO}📡 TRANSFERENCIA TOTAL:${AMARILLO} ${TRANSFER_DISPLAY}${NC}"
    echo -e "${BLANCO} ${UPTIME_COLOR}${NC}"
    echo -e "${BLANCO} ${ONLINE_STATUS}    👥️ TOTAL:${AMARILLO}${TOTAL_USUARIOS}${NC}    ${CIAN}🔴 Inactivos:${AMARILLO} ${inactivos}${NC}"  # Updated line to match requested format
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

export REGISTROS="/diana/reg.txt"
export HISTORIAL="/alexia/log.txt"
export PIDFILE="/Abigail/mon.pid"
export LOGFILE="/alexia/conexiones_log.txt"

# Crear directorios si no existen
mkdir -p "$(dirname "$REGISTROS")"
mkdir -p "$(dirname "$HISTORIAL")"
mkdir -p "$(dirname "$PIDFILE")"
mkdir -p "$(dirname "$LOGFILE")"

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
                        
                        
    
# Función para calcular la fecha de expiración
calcular_expiracion() {
    local dias=$1
    local fecha_expiracion=$(date -d "+$dias days" "+%d/%B/%Y")
    echo $fecha_expiracion
}
calcular_dias_restantes() {
    local fecha_expiracion="$1"

    local dia=$(echo "$fecha_expiracion" | cut -d'/' -f1)
    local mes=$(echo "$fecha_expiracion" | cut -d'/' -f2)
    local anio=$(echo "$fecha_expiracion" | cut -d'/' -f3)

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

    # Mostrar confirmación
    echo -e "${VERDE}✅ Usuario creado correctamente:${NC}"
    echo -e "${AZUL}👤 Usuario: ${AMARILLO}$usuario${NC}"
    echo -e "${AZUL}🔑 Clave: ${AMARILLO}$clave${NC}"
    echo -e "${AZUL}📅 Expira: ${AMARILLO}$fecha_expiracion${NC}"
    echo -e "${AZUL}📱 Límite móviles: ${AMARILLO}$moviles${NC}"
    echo -e "${AZUL}📅 Creado: ${AMARILLO}$fecha_creacion${NC}"
    echo -e "${VIOLETA}===== 📝 RESUMEN DE REGISTRO =====${NC}"
    echo -e "${AMARILLO}👤 Usuario    📅 Expira        ⏳ Días      📱 Móviles    📅 Creado${NC}"
    echo -e "${CIAN}---------------------------------------------------------------${NC}"
    printf "${VERDE}%-12s %-18s %-12s %-12s %s${NC}\n" "$usuario:$clave" "$fecha_expiracion" "$dias días" "$moviles" "$fecha_creacion"
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
            dias_restantes=$(calcular_dias_restantes "$fecha_expiracion" "$dias")
            fecha_creacion="$fecha_creacion1 $fecha_creacion2"
            # Usar la fecha de expiración directamente, ya está en formato dd/mes/YYYY
            printf "${VERDE}%-2s ${VERDE}%-11s ${AZUL}%-10s ${VIOLETA}%-16s ${VERDE}%-8s ${AMARILLO}%-8s${NC}\n" \
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
            dias_restantes=$(calcular_dias_restantes "$fecha_expiracion" "$dias")
            printf "${VERDE}%-12s ${AZUL}%-16s ${AMARILLO}%-10s ${AMARILLO}%-10s${NC}\n" \
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
    clear
    echo "===== 🆕 CREAR MÚLTIPLES USUARIOS SSH ====="
    echo "📝 Formato: nombre contraseña días móviles (separados por espacios, una línea por usuario)"
    echo "📋 Ejemplo: lucy 123 5 4"
    echo "✅ Presiona Enter dos veces para confirmar."

    # Array para almacenar las entradas de usuarios
    declare -a usuarios_input
    while true; do
        read -r linea
        # Si la línea está vacía y la anterior también, salir del bucle
        if [[ -z "$linea" ]]; then
            read -r linea_siguiente
            if [[ -z "$linea_siguiente" ]]; then
                break
            else
                usuarios_input+=("$linea" "$linea_siguiente")
                continue
            fi
        fi
        usuarios_input+=("$linea")
    done

    # Verificar si se ingresaron usuarios
    if [ ${#usuarios_input[@]} -eq 0 ]; then
        echo "❌ No se ingresaron usuarios."
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Procesar y validar entradas
    declare -a usuarios_validos
    declare -a errores
    for linea in "${usuarios_input[@]}"; do
        # Separar los campos
        read -r usuario clave dias moviles <<< "$linea"

        # Validar que todos los campos estén presentes
        if [[ -z "$usuario" || -z "$clave" || -z "$dias" || -z "$moviles" ]]; then
            errores+=("Línea '$linea': Todos los campos son obligatorios.")
            continue
        fi

        # Validar que días y móviles sean números
        if ! [[ "$dias" =~ ^[0-9]+$ ]] || ! [[ "$moviles" =~ ^[0-9]+$ ]]; then
            errores+=("Línea '$linea': Días y móviles deben ser números.")
            continue
        fi

        # Verificar si el usuario ya existe en el sistema
        if id "$usuario" >/dev/null 2>&1; then
            errores+=("Línea '$linea': El usuario $usuario ya existe en el sistema.")
            continue
        fi

        # Almacenar usuario válido
        usuarios_validos+=("$usuario:$clave:$dias:$moviles")
    done

    # Mostrar errores si los hay
    if [ ${#errores[@]} -gt 0 ]; then
        echo "❌ Errores encontrados:"
        for error in "${errores[@]}"; do
            echo "$error"
        done
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Mostrar resumen de usuarios a crear
    echo "===== 📋 USUARIOS A CREAR ====="
    echo "👤 Usuario    🔑 Clave      ⏳ Días       📱 Móviles"
    echo "---------------------------------------------------------------"
    for usuario_data in "${usuarios_validos[@]}"; do
        IFS=':' read -r usuario clave dias moviles <<< "$usuario_data"
        printf "%-12s %-12s %-12s %-12s\n" "$usuario" "$clave" "$dias" "$moviles"
    done
    echo "==============================================================="

    # Confirmar creación
    read -p "✅ ¿Confirmar creación de estos usuarios? (s/n): " confirmacion
    if [[ "$confirmacion" != "s" && "$confirmacion" != "S" ]]; then
        echo "❌ Creación cancelada."
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Crear usuarios y registrar
    count=0
    for usuario_data in "${usuarios_validos[@]}"; do
        IFS=':' read -r usuario clave dias moviles <<< "$usuario_data"

        # Crear usuario en el sistema Linux
        if ! useradd -M -s /sbin/nologin "$usuario" 2>/dev/null; then
            echo "❌ Error al crear el usuario $usuario en el sistema."
            continue
        fi

        # Establecer la contraseña
        if ! echo "$usuario:$clave" | chpasswd 2>/dev/null; then
            echo "❌ Error al establecer la contraseña para $usuario."
            userdel "$usuario" 2>/dev/null
            continue
        fi

        # Configurar fecha de expiración en el sistema
        fecha_expiracion_sistema=$(date -d "+$((dias + 1)) days" "+%Y-%m-%d")
        if ! chage -E "$fecha_expiracion_sistema" "$usuario" 2>/dev/null; then
            echo "❌ Error al establecer la fecha de expiración para $usuario."
            userdel "$usuario" 2>/dev/null
            continue
        fi

        # Obtener fecha actual y de expiración para registros
        fecha_creacion=$(date "+%Y-%m-%d %H:%M:%S")
        fecha_expiracion=$(calcular_expiracion $dias)

        # Guardar en archivo de registros
        echo "$usuario:$clave $fecha_expiracion $dias $moviles $fecha_creacion" >> $REGISTROS

        # Guardar en historial
        echo "Usuario creado: $usuario, Expira: $fecha_expiracion, Móviles: $moviles, Creado: $fecha_creacion" >> $HISTORIAL

        ((count++))
    done

    # Mostrar resumen de creación
    echo "===== 📊 RESUMEN DE CREACIÓN ====="
    echo "✅ Usuarios creados exitosamente: $count"
    echo "Presiona Enter para continuar... ✨"
    read
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
    HISTORIAL="/alexia/log.txt"  # Usar tu ruta definida
    INTERVALO=1

    # Asegurarse de que el directorio de HISTORIAL exista    
    mkdir -p "$(dirname "$HISTORIAL")"    
    # Crear el archivo HISTORIAL si no existe    
    [[ ! -f "$HISTORIAL" ]] && touch "$HISTORIAL"    
    # Asegurarse de que el directorio de LOG exista    
    mkdir -p "$(dirname "$LOG")"    
    # Crear el archivo LOG si no existe    
    [[ ! -f "$LOG" ]] && touch "$LOG"    

    # Configurar puertos de Dropbear (ajusta según tu configuración)
    DROPBEAR_PORTS="80 443"  # Agrega más puertos si Dropbear usa otros

    while true; do    
        usuarios_ps=$(ps -o user= -C sshd -C dropbear | sort -u)    

        for usuario in $usuarios_ps; do    
            [[ -z "$usuario" ]] && continue    
            tmp_status="/tmp/status_${usuario}.tmp"    

            # 🔍 Detectar y eliminar procesos zombies    
            zombies=$(ps -u "$usuario" -o state,pid | grep '^Z' | awk '{print $2}')    
            if [[ -n "$zombies" ]]; then    
                for pid in $zombies; do    
                    kill -9 "$pid" 2>/dev/null    
                    echo "$(date '+%Y-%m-%d %H:%M:%S'): Proceso zombie (PID: $pid) de $usuario terminado." >> "$LOG"    
                done    
            fi    

            # 📡 Contar conexiones activas del usuario    
            conexiones=$(( $(ps -u "$usuario" -o comm= | grep -c "^sshd$") + $(ps -u "$usuario" -o comm= | grep -c "^dropbear$") ))    

            # 🟢 Registrar conexión si no existía previamente    
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

        # 🔥 BLOQUE ANTI CONEXIONES FANTASMA SSH Y DROPBEAR 🔥    
        # Mata conexiones inactivas por más de 3 minutos (180 seg)    
        # Incluye estados ESTAB, TIME_WAIT, CLOSE_WAIT    

        # --- SSH (puerto 22)    
        ss -eto '( sport = :22 )' 2>/dev/null | \
        awk '/(ESTAB|TIME_WAIT|CLOSE_WAIT)/ && /timer:/ {    
            if (match($0, /users:\(\("sshd",pid=([0-9]+)/, arr)) {    
                if (match($0, /timer:[^,]+,([0-9]+)/, tarr) && tarr[1] > 180)    
                    print arr[1];    
            }    
        }' | while read -r pid; do    
            [[ -n "$pid" ]] && kill -9 "$pid" 2>/dev/null    
            echo "$(date '+%Y-%m-%d %H:%M:%S'): Conexión SSH idle (PID: $pid) eliminada tras 3min." >> "$LOG"    
        done    

        # --- Dropbear (puertos configurados)    
        for port in $DROPBEAR_PORTS; do
            ss -eto '( sport = :'"$port"' )' 2>/dev/null | \
            awk '/(ESTAB|TIME_WAIT|CLOSE_WAIT)/ && /timer:/ {    
                if (match($0, /users:\(\("dropbear",pid=([0-9]+)/, arr)) {    
                    if (match($0, /timer:[^,]+,([0-9]+)/, tarr) && tarr[1] > 180)    
                        print arr[1];    
                }    
            }' | while read -r pid; do    
                [[ -n "$pid" ]] && kill -9 "$pid" 2>/dev/null    
                echo "$(date '+%Y-%m-%d %H:%M:%S'): Conexión Dropbear idle (PID: $pid, puerto: $port) eliminada tras 3min." >> "$LOG"    
            done    
        done    

        # ⚙️ Revisar desconexiones y registrar historial    
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
#  ARRANQUE AUTOMÁTICO DEL MONITOR
# ================================
if [[ ! -f "$PIDFILE" ]] || ! ps -p "$(cat "$PIDFILE" 2>/dev/null)" >/dev/null 2>&1; then
    rm -f "$PIDFILE"
    nohup bash "$0" mon >/dev/null 2>&1 &
    echo $! > "$PIDFILE"
fi


# ================================
# VARIABLES Y RUTAS
# ================================
export REGISTROS="/diana/reg.txt"
export HISTORIAL="/alexia/log.txt"
export PIDFILE="/Abigail/mon.pid"
export STATUS="/tmp/limitador_status"
export ENABLED="/tmp/limitador_enabled"   # Control estricto de activación

# Crear directorios si no existen
mkdir -p "$(dirname "$REGISTROS")"
mkdir -p "$(dirname "$HISTORIAL")"
mkdir -p "$(dirname "$PIDFILE")"

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
    
    # Verificar estado actual: chequea si proceso y archivo ENABLED existen
    if [[ -f "$ENABLED" ]] && [[ -f "$PIDFILE" ]] && ps -p "$(cat "$PIDFILE" 2>/dev/null)" >/dev/null 2>&1; then
        ESTADO="${VERDE}🟢 Activado${NC}"
        INTERVALO_ACTUAL=$(cat "$STATUS" 2>/dev/null || echo "1")
    else
        # Limpieza procesos huérfanos si existen
        if [[ -f "$PIDFILE" ]]; then
            pkill -f "$0 limitador" 2>/dev/null
            rm -f "$PIDFILE"
        fi
        ESTADO="${ROJO}🔴 Desactivado${NC}"
        INTERVALO_ACTUAL="N/A"
    fi

    # Presentar estado con colores combinados
    echo -e "${BLANCO}Estado actual:${NC} $ESTADO"
    echo -e "${BLANCO}Intervalo actual:${NC} ${AMARILLO}${INTERVALO_ACTUAL}${NC} ${GRIS}segundo(s)${NC}"
    echo -e "${AZUL_SUAVE}----------------------------------------------------------${NC}"

    echo -ne "${VERDE}¿Desea activar/desactivar el limitador? (s/n): ${NC}"
    read respuesta

    if [[ "$respuesta" =~ ^[sS]$ ]]; then
        if [[ "$ESTADO" == *"Activado"* ]]; then
            # Desactivar limitador - BORRANDO TODOS LOS ARCHIVOS DE CONTROL
            pkill -f "$0 limitador" 2>/dev/null
            rm -f "$PIDFILE" "$STATUS" "$ENABLED"
            echo -e "${VERDE}✅ Limitador desactivado exitosamente.${NC}"
            echo "$(date '+%Y-%m-%d %H:%M:%S'): Limitador desactivado." >> "$HISTORIAL"
        else
            # Activar limitador
            echo -ne "${VERDE}Ingrese el intervalo de verificación en segundos (1-60): ${NC}"
            read intervalo
            if [[ "$intervalo" =~ ^[0-9]+$ ]] && [[ "$intervalo" -ge 1 && "$intervalo" -le 60 ]]; then
                echo "$intervalo" > "$STATUS"
                touch "$ENABLED"  # CREA EL ARCHIVO DE CONTROL PARA INDICAR QUE ESTÁ ACTIVO
                nohup bash "$0" limitador >/dev/null 2>&1 &
                echo $! > "$PIDFILE"
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
    INTERVALO=$(cat "$STATUS" 2>/dev/null || echo "1")

    while true; do
        if [[ -f "$REGISTROS" ]]; then
            while IFS=' ' read -r user_data _ _ moviles _; do
                usuario=${user_data%%:*}
                if id "$usuario" &>/dev/null; then
                    # Obtener PIDs ordenados: más antiguos primero
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
fi

# ================================
# ARRANQUE AUTOMÁTICO DEL LIMITADOR (solo si está habilitado)
# ================================
if [[ -f "$ENABLED" ]]; then
    if [[ ! -f "$PIDFILE" ]] || ! ps -p "$(cat "$PIDFILE" 2>/dev/null)" >/dev/null 2>&1; then
        nohup bash "$0" limitador >/dev/null 2>&1 &
        echo $! > "$PIDFILE"
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


monitorear_bloqueos() {
    LOG="/var/log/monitoreo_bloqueos.log"
    INTERVALO=10 # Verificar cada 10 segundos

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
if [[ ! -f "$PIDFILE.bloqueos" ]] || ! ps -p "$(cat "$PIDFILE.bloqueos" 2>/dev/null)" >/dev/null 2>&1; then
    rm -f "$PIDFILE.bloqueos"
    nohup bash "$0" mon_bloqueos >/dev/null 2>&1 &
    echo $! > "$PIDFILE.bloqueos"
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
    clear
    echo
    echo -e "${VIOLETA}======💾 PANEL SWAP ======${NC}"
    echo -e "${AMARILLO_SUAVE}1. Activar Swap${NC}"
    echo -e "${AMARILLO_SUAVE}2. Eliminar Swap${NC}"
    echo -e "${AMARILLO_SUAVE}0. Volver al menú principal${NC}"
    echo
    PROMPT=$(echo -e "${ROSA}➡️ Selecciona una opción: ${NC}")
    read -p "$PROMPT" SUBOPCION

    case $SUBOPCION in
        1) instalar_swap ;;
        2) eliminar_swap ;;
        0) return ;;
        *) 
            echo -e "${ROJO}❌ ¡Opción inválida!${NC}"
            read -p "$(echo -e ${ROSA_CLARO}Presiona Enter para continuar...${NC})"
            activar_desactivar_swap
            ;;
    esac
}

instalar_swap() {
    clear
    echo
    echo -e "${VIOLETA}======💾 ACTIVAR SWAP ======${NC}"
    echo -e "${AMARILLO_SUAVE}Instalando dependencias para Stress...${NC}"
    apt update -y &>/dev/null
    apt install stress -y &>/dev/null

    echo -e "${AMARILLO_SUAVE}Tamaño de Swap en GB (ej: 1, 2, 3): ${NC}"
    read -p "$(echo -e ${ROSA}➡️ ) " SIZE_GB
    SIZE_MB=$((SIZE_GB * 1024))

    echo -e "${AMARILLO_SUAVE}Creando archivo de swap de ${SIZE_GB}GB...${NC}"
    dd if=/dev/zero of=/swapfile bs=1M count=$SIZE_MB status=progress &>/dev/null
    chmod 600 /swapfile
    mkswap /swapfile &>/dev/null
    swapon /swapfile &>/dev/null
    echo '/swapfile none swap sw 0 0' >> /etc/fstab

    echo -e "${AMARILLO_SUAVE}Número de procesos para Stress (ej: 1, 2, 3, 4): ${NC}"
    read -p "$(echo -e ${ROSA}➡️ ) " NUM_PROCS

    echo -e "${AMARILLO_SUAVE}Intervalo en horas para ejecutar Stress (ej: 6): ${NC}"
    read -p "$(echo -e ${ROSA}➡️ ) " INTERVAL_HOURS

    # Forzar vm-bytes siempre a 1400M
    VM_BYTES=1400

    echo -e "${AMARILLO_SUAVE}Presiona Enter para confirmar instalación y configuración...${NC}"
    read

    cat > /root/run_stress.sh << EOF
#!/bin/bash
stress --vm $NUM_PROCS --vm-bytes ${VM_BYTES}M --timeout 30s
EOF
    chmod +x /root/run_stress.sh

    (crontab -l 2>/dev/null; echo "0 */$INTERVAL_HOURS * * * /root/run_stress.sh") | crontab -
    echo -e "${VERDE}✅ Swap activado y Stress programado cada ${INTERVAL_HOURS} horas (vm-bytes fijo en 1400M).${NC}"

    # 🚀 Ejecutar stress inmediatamente para liberar RAM ya mismo
    echo -e "${AMARILLO_SUAVE}Ejecutando Stress inicial...${NC}"
    stress --vm $NUM_PROCS --vm-bytes ${VM_BYTES}M --timeout 30s

    read -p "$(echo -e ${ROSA_CLARO}Presiona Enter para continuar...${NC})"
    activar_desactivar_swap
}

eliminar_swap() {
    clear
    echo
    echo -e "${VIOLETA}======💾 ELIMINAR SWAP ======${NC}"
    echo -e "${AMARILLO_SUAVE}Confirmar eliminación de Swap (Enter para continuar, Ctrl+C para cancelar)${NC}"
    read

    swapoff /swapfile &>/dev/null
    rm -f /swapfile
    sed -i '/\/swapfile/d' /etc/fstab &>/dev/null

    # Remover cron job de stress
    crontab -l | grep -v "run_stress.sh" | crontab - &>/dev/null
    rm -f /root/run_stress.sh

    apt remove stress -y &>/dev/null

    echo -e "${VERDE}✅ Swap eliminado y configuraciones removidas.${NC}"

    read -p "$(echo -e ${ROSA_CLARO}Presiona Enter para continuar...${NC})"
    activar_desactivar_swap
}

# ========================================
# MENÚ V2RAY (SUBMENÚ) - Integrado como opción 15
# ========================================

menu_v2ray() {
    # === VARIABLES DEL V2RAY (no interfieren con tu menú principal) ===
    local CONFIG_DIR="/usr/local/etc/xray"
    local CONFIG_FILE="$CONFIG_DIR/config.json"
    local SERVICE_FILE="/etc/systemd/system/xray.service"
    local LOG_DIR="/var/log/xray"
    local USERS_FILE="$CONFIG_DIR/users.db"
    local BACKUP_DIR="$CONFIG_DIR/backups"
    local IP=$(curl -s ifconfig.me || echo "IP_NO_DETECTADA")
    local PORT=8080
    local XRAY_BIN="/usr/local/bin/xray"

    # COLORES LOCALES (no sobrescriben los tuyos)
    local RED='\033[1;91m'
    local GREEN='\033[1;92m'
    local YELLOW='\033[1;93m'
    local BLUE='\033[1;94m'
    local PURPLE='\033[1;95m'
    local CYAN='\033[1;96m'
    local WHITE='\033[1;97m'
    local GRAY='\033[0;90m'
    local NC='\033[0m'

    # EMOJIS
    local FIRE="🔥"
    local ROCKET="🚀"
    local SPARK="✨"
    local STAR="⭐"
    local CHECK="✅"
    local CROSS="❌"
    local TRASH="🗑️"
    local USER="👤"
    local KEY="🔑"
    local CAL="📅"
    local DOWN="⬇️"
    local UP="⬆️"

    mkdir -p "$CONFIG_DIR" "$LOG_DIR" "$BACKUP_DIR"
    [ ! -f "$USERS_FILE" ] && touch "$USERS_FILE"

    # === FUNCIONES LOCALES ===
    midnight_tomorrow() {
        date -d "tomorrow 00:00" +%s 2>/dev/null || date -d "next day 00:00" +%s
    }

    days_left_natural() {
        local expires=$1
        local now_midnight=$(date -d "today 00:00" +%s)
        local expire_midnight=$(date -d "$(date -d "@$expires" +%Y-%m-%d) 00:00" +%s 2>/dev/null)
        local days=$(( (expire_midnight - now_midnight) / 86400 ))
        (( days < 0 )) && days=0
        echo $days
    }

    install_xray() {
        clear
        echo -e "${ROCKET} ${PURPLE}Instalando Xray Core...${NC} $SPARK"
        cd /tmp
        wget -q https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip
        unzip -o Xray-linux-64.zip >/dev/null 2>&1
        sudo mv xray "$XRAY_BIN" 2>/dev/null
        sudo chmod +x "$XRAY_BIN"
        echo -e "${CHECK} ${GREEN}Xray instalado correctamente.${NC}"
        sleep 1.5
    }

    create_service() {
        cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
Type=simple
ExecStart=$XRAY_BIN run -c $CONFIG_FILE
Restart=on-failure
RestartSec=3
User=root
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable xray &>/dev/null
    }

    generate_config() {
        local path="$1"
        local host="$2"
        {
            echo "{"
            echo '  "log": {'
            echo '    "loglevel": "warning",'
            echo "    \"access\": \"$LOG_DIR/access.log\","
            echo "    \"error\": \"$LOG_DIR/error.log\""
            echo '  },'
            echo '  "inbounds": ['
            echo '    {'
            echo "      \"port\": $PORT,"
            echo '      "listen": "0.0.0.0",'
            echo '      "protocol": "vmess",'
            echo '      "settings": {'
            echo '        "clients": ['
            
            first=true
            while IFS=: read -r name uuid created expires delete_at; do
                [[ $name == "#"* ]] && continue
                [ $(( $(date +%s) )) -ge $delete_at ] && continue
                if [ "$first" = false ]; then echo "        },"; fi
                echo "          {"
                echo "            \"id\": \"$uuid\","
                echo "            \"level\": 8,"
                echo "            \"alterId\": 0"
                first=false
            done < <(grep -v "^#" "$USERS_FILE")
            
            [ "$first" = false ] && echo "        }"
            echo '        ]'
            echo '      },'
            echo '      "streamSettings": {'
            echo '        "network": "ws",'
            echo '        "wsSettings": {'
            echo "          \"path\": \"$path\""
            [ -n "$host" ] && echo "          ,\"headers\": { \"Host\": \"$host\" }"
            echo '        }'
            echo '      }'
            echo '    }'
            echo '  ],'
            echo '  "outbounds": [{ "protocol": "freedom" }]'
            echo '}'
        } > "$CONFIG_FILE"
    }

    add_user() {
    clear
    echo -e "${USER} ${CYAN}AGREGAR NUEVO USUARIO${NC} $SPARK"
    echo -e "${GRAY}────────────────────────────────────${NC}"
    read -p "Nombre del usuario: " name
    read -p "Días de validez (1, 7, 30...): " days
    [[ ! "$days" =~ ^[0-9]+$ ]] && { echo -e "${CROSS} ${RED}Solo números.${NC}"; sleep 1.5; return; }

    uuid=$($XRAY_BIN uuid)
    created=$(date +%s)
    expires=$(( created + days * 86400 ))
    delete_at=$(( $(date -d "$(date -d "@$expires" +%Y-%m-%d) + 1 day" +%s) ))

    echo "$name:$uuid:$created:$expires:$delete_at" >> "$USERS_FILE"

    current_path=$(grep '"path"' $CONFIG_FILE 2>/dev/null | awk -F'"' '{print $4}' || echo "/pams")
    current_host=$(grep '"Host"' $CONFIG_FILE 2>/dev/null | awk -F'"' '{print $4}' || echo "")

    json_data=$(cat <<EOF
{
  "add": "$IP",
  "port": "$PORT",
  "id": "$uuid",
  "aid": "0",
  "security": "auto",
  "net": "ws",
  "type": "none",
  "host": "$current_host",
  "path": "$current_path",
  "tls": ""
}
EOF
)
    vmess_link="vmess://$(echo "$json_data" | base64 -w0)"

    clear
    echo -e "${CHECK} ${GREEN}USUARIO CREADO CON ÉXITO${NC} $FIRE"
    echo -e "${GRAY}════════════════════════════════════${NC}"
    echo -e "${USER} Nombre:   ${YELLOW}$name${NC}"
    echo -e "${KEY} UUID:     ${CYAN}$uuid${NC}"
    echo -e "${CAL} Vence:    ${PURPLE}$(date -d "@$expires" +"%d/%m/%Y")${NC}"
    echo -e "${TRASH} Borrado:  ${RED}$(date -d "@$delete_at" +"%d/%m/%Y")${NC}"
    echo -e "${GRAY}════════════════════════════════════${NC}"
    echo -e "${ROCKET} ${BLUE}LINK VMESS (HTTP CUSTOM):${NC}"
    echo -e "${WHITE}$vmess_link${NC}"
    echo -e "${GRAY}────────────────────────────────────${NC}"
    read -p "Presiona Enter para continuar..."
}

    remove_user_menu() {
        clear
        echo -e "${TRASH} ${RED}ELIMINAR USUARIO${NC}"
        echo -e "${GRAY}────────────────────────────────────${NC}"

        mapfile -t users < "$USERS_FILE"
        if [ ${#users[@]} -eq 0 ]; then
            echo -e "${CROSS} ${YELLOW}No hay usuarios registrados.${NC}"
            read -p "Enter..." && return
        fi

        i=1
        for line in "${users[@]}"; do
            name=$(echo "$line" | cut -d: -f1)
            echo -e "$i) ${YELLOW}$name${NC}"
            ((i++))
        done

        echo -e "${GRAY}────────────────────────────────────${NC}"
        read -p "Elige número o escribe nombre: " input

        if [[ "$input" =~ ^[0-9]+$ ]]; then
            index=$((input-1))
            user_line="${users[$index]}"
            [ -z "$user_line" ] && { echo -e "${CROSS} ${RED}Opción inválida.${NC}"; sleep 1.5; return; }
            username=$(echo "$user_line" | cut -d: -f1)
        else
            username="$input"
        fi

        if ! grep -q "^$username:" "$USERS_FILE"; then
            echo -e "${CROSS} ${RED}Usuario no encontrado.${NC}"
            sleep 1.5
            return
        fi

        sed -i "/^$username:/d" "$USERS_FILE"
        generate_config "$(grep '"path"' "$CONFIG_FILE" | awk -F'"' '{print $4}' | head -1)" "$(grep '"Host"' "$CONFIG_FILE" | awk -F'"' '{print $4}')"
        systemctl restart xray 2>/dev/null

        echo -e "${CHECK} ${GREEN}Usuario '$username' eliminado.${NC}"
        sleep 1.5
    }

    list_users() {
        clear
        echo -e "${STAR} ${BLUE}USUARIOS ACTIVOS${NC} $SPARK"
        echo -e "${PURPLE}════════════════════════════════════${NC}"
        active=0
        while IFS=: read -r name uuid created expires delete_at; do
            [[ $name == "#"* ]] && continue
            [ $(date +%s) -ge $delete_at ] && continue
            days_left=$(days_left_natural $expires)
            active=1
            echo -e "${USER} ${WHITE}Nombre:${NC} ${YELLOW}$name${NC}"
            echo -e "${KEY} ${WHITE}UUID:${NC}   ${CYAN}$uuid${NC}"
            echo -e "${CAL} ${WHITE}Días:${NC}   ${GREEN}$days_left${NC} | Vence: ${PURPLE}$(date -d "@$expires" +"%d/%m/%Y")${NC}"
            echo -e "${TRASH} ${WHITE}Borrado:${NC}${RED}$(date -d "@$delete_at" +"%d/%m/%Y")${NC}"
            echo -e "${PURPLE}────────────────────────────────────${NC}"
        done < "$USERS_FILE"
        [ $active -eq 0 ] && echo -e "${CROSS} ${RED}No hay usuarios activos.${NC}"
        read -p "Presiona Enter para volver..."
    }

    export_all_vmess() {
        clear
        echo -e "${ROCKET} ${BLUE}EXPORTAR TODOS (vmess://)${NC}"
        echo -e "${PURPLE}════════════════════════════════${NC}"
        current_path=$(grep '"path"' "$CONFIG_FILE" 2>/dev/null | awk -F'"' '{print $4}' | head -1 || echo "/pams")
        current_host=$(grep '"Host"' "$CONFIG_FILE" 2>/dev/null | awk -F'"' '{print $4}' || echo "")
        while IFS=: read -r name uuid created expires delete_at; do
            [[ $name == "#"* ]] && continue
            [ $(date +%s) -ge $delete_at ] && continue
            json_data=$(cat <<EOF
{
  "add": "$IP",
  "port": "$PORT",
  "id": "$uuid",
  "aid": "0",
  "security": "auto",
  "net": "ws",
  "type": "none",
  "host": "$current_host",
  "path": "$current_path",
  "tls": ""
}
EOF
)
            vmess_link="vmess://$(echo "$json_data" | base64 -w0)"
            echo -e "${YELLOW}→ $name${NC}"
            echo -e "${CYAN}$vmess_link${NC}"
            echo -e "${PURPLE}────────────────────────────────${NC}"
        done < "$USERS_FILE"
        read -p "Enter..."
    }
# === BACKUP Y RESTAURAR ===
    backup_v2ray() {
        clear
        echo -e "${SPARK} ${YELLOW}HACIENDO BACKUP COMPLETO...${NC} $SPARK"
        local timestamp=$(date +"%Y%m%d_%H%M%S")
        local backup_file="$BACKUP_DIR/v2ray_backup_$timestamp.tar.gz"

        mkdir -p "$BACKUP_DIR"

        tar -czf "$backup_file" \
            "$CONFIG_FILE" \
            "$USERS_FILE" \
            2>/dev/null

        if [ $? -eq 0 ] && [ -f "$backup_file" ]; then
            echo -e "${CHECK} ${GREEN}Backup creado:${NC}"
            echo -e "${WHITE}   $backup_file${NC}"
            echo -e "${CYAN}   Tamaño: $(du -h "$backup_file" | cut -f1)${NC}"
            echo -e "${GRAY}────────────────────────────────────${NC}"
            echo -e "${ROCKET} Copia este archivo a un lugar seguro."
            read -p "Presiona Enter para continuar..."
        else
            echo -e "${CROSS} ${RED}Error al crear el backup.${NC}"
            sleep 2
        fi
    }
restore_v2ray() {
        clear
        echo -e "${ROCKET} ${BLUE}RESTAURAR BACKUP${NC} $SPARK"
        echo -e "${GRAY}────────────────────────────────────${NC}"

        if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR"/*.tar.gz 2>/dev/null)" ]; then
            echo -e "${CROSS} ${YELLOW}No hay backups en $BACKUP_DIR${NC}"
            read -p "Enter..." && return
        fi

        echo -e "${WHITE}Backups disponibles:${NC}"
        mapfile -t backups < <(ls -1 "$BACKUP_DIR"/*.tar.gz 2>/dev/null | sort -r)
        for i in "${!backups[@]}"; do
            file="${backups[$i]}"
            size=$(du -h "$file" | cut -f1)
            date=$(basename "$file" | sed 's/v2ray_telegram_//' | sed 's/\.tar\.gz//' | sed 's/_/ /g' | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\) \([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3 \4:\5:\6/')
            echo -e " $((i+1))) ${YELLOW}$(basename "$file")${NC} [${CYAN}$size${NC}] [${PURPLE}$date${NC}]"
        done

        echo -e "${GRAY}────────────────────────────────────${NC}"
        read -p "Elige número de backup: " choice
        [[ ! "$choice" =~ ^[0-9]+$ ]] && { echo -e "${CROSS} Inválido."; sleep 1.5; return; }
        index=$((choice-1))
        backup_file="${backups[$index]}"
        [ -z "$backup_file" ] && { echo -e "${CROSS} No existe."; sleep 1.5; return; }

        # DETENER XRAY
        systemctl stop xray 2>/dev/null

        # CREAR DIRECTORIOS
        mkdir -p "$CONFIG_DIR" "$LOG_DIR"

        # EXTRAER DIRECTO AL LUGAR CORRECTO
        if ! tar -xzf "$backup_file" -C "$CONFIG_DIR" --strip-components=1 2>/dev/null; then
            echo -e "${CROSS} ${RED}Error al extraer el backup.${NC}"
            systemctl start xray 2>/dev/null
            sleep 2
            return
        fi

        # VERIFICAR QUE users.db FUE EXTRAÍDO
        if [ ! -f "$USERS_FILE" ]; then
            echo -e "${CROSS} ${RED}Error: users.db no se extrajo correctamente.${NC}"
            systemctl start xray 2>/dev/null
            sleep 2
            return
        fi

        # OBTENER PATH Y HOST DEL config.json RESTAURADO
        restored_path=$(grep '"path"' "$CONFIG_FILE" 2>/dev/null | awk -F'"' '{print $4}' | head -1)
        restored_host=$(grep '"Host"' "$CONFIG_FILE" 2>/dev/null | awk -F'"' '{print $4}' | head -1)

        # SI NO HAY, USAR POR DEFECTO
        [ -z "$restored_path" ] && restored_path="/pams"
        [ -z "$restored_host" ] && restored_host=""

        # REGENERAR config.json CON TODOS LOS USUARIOS
        generate_config "$restored_path" "$restored_host"

        # REINICIAR XRAY
        systemctl restart xray 2>/dev/null

        # CONTAR USUARIOS
        user_count=$(wc -l < "$USERS_FILE" 2>/dev/null || echo 0)

        echo -e "${CHECK} ${GREEN}Backup restaurado correctamente:${NC}"
        echo -e "${WHITE}   $(basename "$backup_file")${NC}"
        echo -e "${CYAN}   Usuarios restaurados: $user_count${NC}"
        echo -e "${PURPLE}   Path: $restored_path | Host: $restored_host${NC}"
        sleep 3
    }

    restore_from_telegram() {
        clear
        echo -e "${ROCKET} ${BLUE}RESTAURAR DESDE TELEGRAM${NC} $SPARK"
        echo -e "${GRAY}────────────────────────────────────${NC}"

        # Verificar bot
        if [[ ! -f /root/sshbot_token || ! -f /root/sshbot_userid ]]; then
            echo -e "${CROSS} ${RED}Bot no configurado. Usa opción 12 del menú principal.${NC}"
            sleep 2
            return
        fi

        TOKEN=$(cat /root/sshbot_token)
        URL="https://api.telegram.org/bot$TOKEN"

        read -p "Pega el File ID del backup (ej: BQACAg...): " file_id
        [[ -z "$file_id" ]] && { echo -e "${CROSS} ID vacío."; sleep 1.5; return; }

        echo -e "${YELLOW}Descargando backup de Telegram...${NC}"
        FILE_INFO=$(curl -s "$URL/getFile?file_id=$file_id")
        if ! echo "$FILE_INFO" | grep -q '"ok":true'; then
            error=$(echo "$FILE_INFO" | jq -r '.description')
            echo -e "${CROSS} ${RED}Error: $error${NC}"
            sleep 2
            return
        fi

        FILE_PATH=$(echo "$FILE_INFO" | jq -r '.result.file_path')
        DOWNLOAD_URL="https://api.telegram.org/file/bot$TOKEN/$FILE_PATH"

        curl -s "$DOWNLOAD_URL" -o /tmp/v2ray_telegram_restore.tar.gz

        if [[ ! -f /tmp/v2ray_telegram_restore.tar.gz ]]; then
            echo -e "${CROSS} ${RED}Error al descargar el archivo.${NC}"
            sleep 2
            return
        fi

        # Instalar Xray si no existe
        if [[ ! -f "$XRAY_BIN" ]]; then
            echo -e "${YELLOW}Xray no instalado. Instalando...${NC}"
            install_xray
        fi

        # Crear directorios
        mkdir -p "$CONFIG_DIR" "$LOG_DIR"

        # Extraer
        if ! tar -xzf /tmp/v2ray_telegram_restore.tar.gz -C "$CONFIG_DIR" --strip-components=1 2>/dev/null; then
            echo -e "${CROSS} ${RED}Error al extraer el backup.${NC}"
            rm -f /tmp/v2ray_telegram_restore.tar.gz
            sleep 2
            return
        fi

        rm -f /tmp/v2ray_telegram_restore.tar.gz

        # Verificar users.db
        if [[ ! -f "$USERS_FILE" ]]; then
            echo -e "${CROSS} ${RED}users.db no encontrado en el backup.${NC}"
            sleep 2
            return
        fi

        # Regenerar config
        path=$(grep '"path"' "$CONFIG_FILE" 2>/dev/null | awk -F'"' '{print $4}' | head -1 || echo "/pams")
        host=$(grep '"Host"' "$CONFIG_FILE" 2>/dev/null | awk -F'"' '{print $4}' || echo "")
        generate_config "$path" "$host"

        # Service
        create_service
        systemctl daemon-reload
        systemctl restart xray 2>/dev/null

        user_count=$(wc -l < "$USERS_FILE" 2>/dev/null || echo 0)

        echo -e "${CHECK} ${GREEN}Backup restaurado desde Telegram!${NC}"
        echo -e "${WHITE}   Usuarios: $user_count${NC}"
        echo -e "${CYAN}   Path: $path | Host: $host${NC}"
        sleep 3
    }
    
    send_backup_telegram() {
        clear
        echo -e "${SPARK} ${YELLOW}ENVIANDO BACKUP POR TELEGRAM...${NC} $SPARK"

        # Instalar jq si no existe
        if ! command -v jq &>/dev/null; then
            echo -e "${YELLOW}Instalando jq...${NC}"
            curl -L -o /usr/bin/jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
            chmod +x /usr/bin/jq
        fi

        # Verificar bot
        if [[ ! -f /root/sshbot_token || ! -f /root/sshbot_userid ]]; then
            echo -e "${CROSS} ${RED}Bot no configurado. Usa 'SSH BOT' primero.${NC}"
            sleep 2
            return
        fi

        TOKEN=$(cat /root/sshbot_token)
        USER_ID=$(cat /root/sshbot_userid)
        URL="https://api.telegram.org/bot$TOKEN"

        # Crear backup
        local timestamp=$(date +"%Y%m%d_%H%M%S")
        local backup_file="/tmp/v2ray_backup_$timestamp.tar.gz"
        local config_backup="/tmp/config.json"
        local users_backup="/tmp/users.db"

        cp "$CONFIG_FILE" "$config_backup" 2>/dev/null || { echo "Error config"; return; }
        cp "$USERS_FILE" "$users_backup" 2>/dev/null || { echo "Error users"; return; }

        tar -czf "$backup_file" "$config_backup" "$users_backup" 2>/dev/null

        if [[ ! -f "$backup_file" ]]; then
            echo -e "${CROSS} ${RED}Error al crear el backup.${NC}"
            sleep 2
            return
        fi

        # Enviar a Telegram
        response=$(curl -s -F "chat_id=$USER_ID" \
            -F "document=@$backup_file" \
            -F "caption=Backup V2Ray - $timestamp\nIP: $IP\nPuerto: $PORT\nUsuarios: $(wc -l < "$USERS_FILE" 2>/dev/null || echo 0)\nPath: $(grep '"path"' "$CONFIG_FILE" | awk -F'"' '{print $4}' | head -1 || echo "/pams")" \
            "$URL/sendDocument")

        # GUARDAR TAMBIÉN LOCALMENTE (BONUS)
        local local_backup="$BACKUP_DIR/v2ray_telegram_$timestamp.tar.gz"
        cp "$backup_file" "$local_backup"

        rm -f "$backup_file" "$config_backup" "$users_backup"

        if echo "$response" | grep -q '"ok":true'; then
            file_id=$(echo "$response" | jq -r '.result.document.file_id')
            echo -e "${CHECK} ${GREEN}Backup enviado a Telegram!${NC}"
            echo -e "${WHITE}   Archivo ID: $file_id${NC}"
            echo -e "${CYAN}   Guardado local: $local_backup${NC}"
            echo -e "${GRAY}────────────────────────────────────${NC}"
            echo -e "${ROCKET} Ahora puedes restaurar con opción 10 incluso sin internet."
        else
            error=$(echo "$response" | jq -r '.description // "Error desconocido"')
            echo -e "${CROSS} ${RED}Error al enviar: $error${NC}"
        fi

        read -p "Presiona Enter..."
    }

    show_v2ray_menu() {
        while true; do
            clear
            current_path=$(grep '"path"' "$CONFIG_FILE" 2>/dev/null | awk -F'"' '{print $4}' | head -1 || echo "No configurado")
            current_host=$(grep '"Host"' "$CONFIG_FILE" 2>/dev/null | awk -F'"' '{print $4}' || echo "Ninguno")

            echo -e "${FIRE}${FIRE}${FIRE} ${WHITE}MENÚ V2RAY (Xray)${NC} ${FIRE}${FIRE}${FIRE}"
            echo -e "${GRAY}════════════════════════════════════════════════${NC}"
            echo -e " ${UP} IP:     ${GREEN}$IP${NC}"
            echo -e " ${UP} Puerto: ${GREEN}$PORT${NC}"
            echo -e " ${UP} Path:   ${YELLOW}$current_path${NC}"
            echo -e " ${UP} Host:   ${YELLOW}$current_host${NC}"
            echo -e "${PURPLE}════════════════════════════════════════════════${NC}"
            echo -e " ${STAR} 1) ${CYAN}Instalar Xray desde cero${NC}"
            echo -e " ${STAR} 2) ${CYAN}Cambiar Path / Host${NC}"
            echo -e " ${STAR} 3) ${GREEN}Agregar usuario${NC}"
            echo -e " ${STAR} 4) ${RED}Eliminar usuario${NC}"
            echo -e " ${STAR} 5) ${BLUE}Listar usuarios${NC}"
            echo -e " ${STAR} 6) ${PURPLE}Exportar todos (vmess://)${NC}"
            echo -e " ${STAR} 7) ${YELLOW}Reiniciar Xray${NC}"
            echo -e " ${STAR} 8) ${RED}Desinstalar TODO${NC} ${TRASH}"
            echo -e " ${STAR} 9) ${GREEN}Enviar backup por Telegram${NC}"
            echo -e " ${STAR}10) ${BLUE}Restaurar desde backup local${NC}"
            echo -e " ${STAR}11) ${GREEN}Restaurar desde Telegram (File ID)${NC}"
            echo -e " ${STAR} 0) ${GRAY}Volver al menú principal${NC}"
            echo -e "${PURPLE}════════════════════════════════════════════════${NC}"
            read -p " ${ROCKET} Elige una opción: " opt

            case $opt in
                1) install_xray; read -p "Path: " p; read -p "Host: " h; generate_config "$p" "$h"; create_service; systemctl restart xray 2>/dev/null; read -p "Enter...";;
                2) read -p "Nuevo Path: " p; read -p "Nuevo Host: " h; generate_config "$p" "$h"; systemctl restart xray 2>/dev/null; read -p "Enter...";;
                3) add_user; generate_config "$(grep '"path"' "$CONFIG_FILE" | awk -F'"' '{print $4}' | head -1)" "$(grep '"Host"' "$CONFIG_FILE" | awk -F'"' '{print $4}')"; systemctl restart xray 2>/dev/null;;
                4) remove_user_menu;;
                5) list_users;;
                6) export_all_vmess;;
                7) systemctl restart xray 2>/dev/null; echo -e "${CHECK} ${GREEN}Xray reiniciado.${NC}"; sleep 1.5;;
                8) 
                    clear
                    echo -e "${TRASH} ${RED}DESINSTALANDO TODO...${NC} $SPARK"
                    systemctl stop xray 2>/dev/null
                    systemctl disable xray 2>/dev/null
                    rm -f "$SERVICE_FILE" "$XRAY_BIN"
                    rm -rf "$CONFIG_DIR" "$LOG_DIR" "$BACKUP_DIR"
                    echo -e "${CHECK} ${RED}TODO BORRADO.${NC}"
                    sleep 2
                    return
                    ;;
                9) send_backup_telegram ;;
                10) restore_v2ray ;;
                11) restore_from_telegram ;;
                0) return ;;
                *) echo -e "${CROSS} ${RED}Opción inválida.${NC}"; sleep 1.5;;
            esac
        done
    }
  
    # === INICIO DEL SUBMENÚ ===
    [ ! -f "$XRAY_BIN" ] && echo -e "${YELLOW}Ejecuta la opción 1 para instalar Xray.${NC}"
    show_v2ray_menu
}


# ==== MENU PRINCIPAL ====
if [[ -t 0 ]]; then
while true; do
    clear
    barra_sistema
    echo
    echo -e "${VIOLETA}======💵💫🎄 PANEL DE USUARIOS VPN/SSH ======${NC}"
    echo -e "${AMARILLO_SUAVE}1. 🆕 Crear usuario${NC}"
    echo -e "${AMARILLO_SUAVE}2. 📋 Ver registros${NC}"
    echo -e "${AMARILLO_SUAVE}3. 🗑️ Eliminar usuario${NC}"
    echo -e "${AMARILLO_SUAVE}4. 📊 Información${NC}"
    echo -e "${AMARILLO_SUAVE}5. 🟢 Verificar usuarios online${NC}"
    echo -e "${AMARILLO_SUAVE}6. 🔒 Bloquear/Desbloquear usuario${NC}"
    echo -e "${AMARILLO_SUAVE}7. 🆕 Crear múltiples usuarios${NC}"
    echo -e "${AMARILLO_SUAVE}8. 📋 Mini registro${NC}"
    echo -e "${AMARILLO_SUAVE}9. ⚙️ Activar/Desactivar limitador${NC}"
    echo -e "${AMARILLO_SUAVE}10. 🎨 Configurar banner SSH${NC}"
    echo -e "${AMARILLO_SUAVE}11. 🔄 Activar/Desactivar contador online${NC}"
    echo -e "${AMARILLO_SUAVE}12. 🤖 SSH BOT${NC}"
    echo -e "${AMARILLO_SUAVE}13. 🔄 Renovar usuario${NC}"
    echo -e "${AMARILLO_SUAVE}14. 💾 Activar/Desactivar Swap${NC}"
    echo -e "${AMARILLO_SUAVE}15. 🔥 MENÚ V2RAY (Xray)${NC}"
    echo -e "${AMARILLO_SUAVE}0. 🚪 Salir${NC}"

    PROMPT=$(echo -e "${ROSA}➡️ Selecciona una opción: ${NC}")
    read -p "$PROMPT" OPCION

    case $OPCION in
        1)  crear_usuario ;;
        2)  ver_registros ;;
        3)  eliminar_multiples_usuarios ;;
        4)  informacion_usuarios ;;
        5)  verificar_online ;;
        6)  bloquear_desbloquear_usuario ;;
        7)  crear_multiples_usuarios ;;
        8)  mini_registro ;;
        9)  activar_desactivar_limitador ;;
        10) configurar_banner_ssh ;;
        11) contador_online ;;
        12) ssh_bot ;;
        13) renovar_usuario ;;
        14) activar_desactivar_swap ;;
        15)
            clear
            echo -e "${CYAN}🔥 Accediendo al MENÚ V2RAY...${NC}"
            sleep 1
            menu_v2ray   # ✅ Llama al submenú de XRAY
        ;;
        0)
            echo -e "${AMARILLO_SUAVE}🚪 Saliendo al shell...${NC}"
            exec /bin/bash
        ;;
        *)
            echo -e "${ROJO}❌ ¡Opción inválida!${NC}"
            read -p "$(echo -e ${ROSA_CLARO}Presiona Enter para continuar...${NC})"
        ;;
    esac
done
fi

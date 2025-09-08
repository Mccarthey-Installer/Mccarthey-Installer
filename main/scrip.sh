
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
🗑️ *Presiona 2* para eliminar usuario
📋 *Presiona 3* para ver los usuarios registrados
✅ *Presiona 4* para mostrar usuarios conectados
🔄 *Presiona 5* para renovar usuario
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
                                    '3')
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

                                                LISTA=\"\${LISTA}\${count}. \$(printf \"%-11s | %-5s\" \"\\\`\${usuario}\\\`\" \"\\\`\${clave}\\\`\") | \${fecha_corta} | \${dias_restantes} d | \${moviles}

\"
                                                ((count++))
                                            done < \"\$REGISTROS\"

                                            TOTAL=\$((count - 1))
                                            LISTA=\"\${LISTA}*Total registrados:* \$TOTAL usuarios\"
                                            curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"\$LISTA\" -d parse_mode=Markdown >/dev/null
                                        fi
                                        ;;
                                    '4')
                                        if [[ ! -f \"\$REGISTROS\" || ! -s \"\$REGISTROS\" ]]; then
                                            curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"❌ *No hay usuarios registrados.*
Escribe *hola* para volver al menú.\" -d parse_mode=Markdown >/dev/null
                                        else
                                            LISTA=\"===== 🥳 *USUARIOS ONLINE* 😎 =====

*USUARIO  CONEXIONES  MÓVILES  CONECTADO*
-----------------------------------------------------------------

\"
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

                                                LISTA=\"\${LISTA}*🧑‍💻Usuario*: \\\`\${usuario}\\\`
*🌐Conexiones*: \$conexiones
*📲Móviles*: \$moviles
*⏳Tiempo conectado/última vez/nunca conectado*: \$detalle

\"
                                            done < \"\$REGISTROS\"

                                            LISTA=\"\${LISTA}-----------------------------------------------------------------
*Total de Online:* \$total_online  *Total usuarios:* \$total_usuarios  *Inactivos:* \$inactivos
================================================\"
                                            curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"\$LISTA\" -d parse_mode=Markdown >/dev/null
                                        fi
                                        ;;
                                    '5')
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
                                    '6')
                                        if [[ ! -f \"\$REGISTROS\" || ! -s \"\$REGISTROS\" ]]; then
                                            curl -s -X POST \"\$URL/sendMessage\" -d chat_id=\$CHAT_ID -d text=\"❌ *No hay usuarios registrados para crear backup.*
Escribe *hola* para volver al menú.\" -d parse_mode=Markdown >/dev/null
                                        else
                                            temp_backup=\"/tmp/backup_\$(date +%Y%m%d_%H%M%S).txt\"
                                            cp \"\$REGISTROS\" \"\$temp_backup\"
                                            curl -s -X POST \"\$URL/sendDocument\" -F chat_id=\$CHAT_ID -F document=@\"\$temp_backup\" -F caption=\"💾 *Aquí está tu backup de usuarios.*\" -F parse_mode=Markdown >/dev/null
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

    # ================= Config persistente =================
    STATE_FILE="/etc/mi_script/contador_online.conf"

    # ================= Usuarios =================  
    TOTAL_CONEXIONES=0  
    TOTAL_USUARIOS=0  
    USUARIOS_EXPIRAN=()  

    if [[ -f "$REGISTROS" ]]; then  
        while IFS=' ' read -r user_data fecha_expiracion dias moviles fecha_creacion; do  
            usuario=${user_data%%:*}  
            if id "$usuario" &>/dev/null; then  
                ((TOTAL_USUARIOS++))  
                DIAS_RESTANTES=$(calcular_dias_restantes "$fecha_expiracion")  
                if [[ $DIAS_RESTANTES -eq 0 ]]; then  
                    USUARIOS_EXPIRAN+=("${BLANCO}${usuario}${NC} ${AMARILLO}0 Días${NC}")  
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

    # ================= Transferencia acumulada =================  
TRANSFER_FILE="/tmp/vps_transfer_total"  
LAST_FILE="/tmp/vps_transfer_last"  

RX_TOTAL=$(awk '/eth0|ens|enp|wlan|wifi/{rx+=$2} END{print rx}' /proc/net/dev)  
TX_TOTAL=$(awk '/eth0|ens|enp|wlan|wifi/{tx+=$10} END{print tx}' /proc/net/dev)  
TOTAL_BYTES=$((RX_TOTAL + TX_TOTAL))

# Si no existe LAST_FILE, se inicializa sin contar los bytes previos
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
    echo -e "${BLANCO} 💾 TOTAL:${AMARILLO} ${MEM_TOTAL_H}${NC} ${BLANCO}∘ ⚡ DISPONIBLE:${AMARILLO} ${MEM_DISPONIBLE_H}${NC} ${BLANCO}∘ 💿 HDD:${AMARILLO} ${DISCO_TOTAL_H}${NC} ${DISCO_PORC_COLOR}"
    echo -e "${BLANCO} 📊 U/RAM:${AMARILLO} ${MEM_PORC}%${NC} ${BLANCO}∘ 🖥️ U/CPU:${AMARILLO} ${CPU_PORC}%${NC} ${BLANCO}∘ 🔧 CPU MHz:${AMARILLO} ${CPU_MHZ}${NC}"
    echo -e "${AZUL}═══════════════════════════════════════════════════${NC}"
    echo -e "${BLANCO} 🌍 IP:${AMARILLO} ${IP_PUBLICA}${NC} ${BLANCO}∘ 🕒 FECHA:${AMARILLO} ${FECHA_ACTUAL}${NC}"
    echo -e "${MAGENTA}🇭🇳 𝐌𝐜𝐜𝐚𝐫𝐭𝐡𝐞𝐲${NC}    ${BLANCO}📡 TRANSFERENCIA TOTAL:${AMARILLO} ${TRANSFER_DISPLAY}${NC}"
    echo -e "${BLANCO} ${ONLINE_STATUS}${NC} ${BLANCO}👥 TOTAL:${AMARILLO} ${TOTAL_USUARIOS}${NC} ${BLANCO}🖼️ SO:${AMARILLO} ${SO_NAME}${NC}"
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

    # Mapa de meses para traducción
    declare -A month_map=(
        ["Jan"]="enero" ["Feb"]="febrero" ["Mar"]="marzo" ["Apr"]="abril"
        ["May"]="mayo" ["Jun"]="junio" ["Jul"]="julio" ["Aug"]="agosto"
        ["Sep"]="septiembre" ["Oct"]="octubre" ["Nov"]="noviembre" ["Dec"]="diciembre"
    )

    # Verificar si el archivo HISTORIAL existe
    if [[ ! -f "$HISTORIAL" ]]; then
        echo -e "${LILA}😿 ¡Oh no! No hay historial de conexiones aún, pequeña! 💔${NC}"
        read -p "$(echo -e ${TURQUESA}Presiona Enter para seguir, corazón... 💌${NC})"
        return 1
    fi

    # Encabezado de la tabla
    printf "${LILA}%-15s %-22s %-22s %-12s${NC}\n" "👩‍💼 Usuaria" "🌷 Conectada" "🌙 Desconectada" "⏰  Duración"
    echo -e "${ROSADO}~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~${NC}"

    # Obtener lista única de usuarios desde HISTORIAL
    mapfile -t USUARIOS < <(awk -F'|' '{print $1}' "$HISTORIAL" | sort -u)

    for USUARIO in "${USUARIOS[@]}"; do
        if id "$USUARIO" &>/dev/null; then
            # Obtener el último registro del usuario
            ULTIMO_REGISTRO=$(grep "^$USUARIO|" "$HISTORIAL" | tail -1)
            if [[ -n "$ULTIMO_REGISTRO" ]]; then
                IFS='|' read -r _ HORA_CONEXION HORA_DESCONEXION DURACION <<< "$ULTIMO_REGISTRO"

                # Validar formato de fechas
                if [[ "$HORA_CONEXION" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]][0-9]{2}:[0-9]{2}:[0-9]{2}$ && \
                      "$HORA_DESCONEXION" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]][0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then

                    # Formatear fechas
                    CONEXION_FMT=$(date -d "$HORA_CONEXION" +"%d/%b %I:%M %p" 2>/dev/null)
                    DESCONEXION_FMT=$(date -d "$HORA_DESCONEXION" +"%d/%b %I:%M %p" 2>/dev/null)

                    # Traducir meses a español
                    for eng in "${!month_map[@]}"; do
                        esp=${month_map[$eng]}
                        CONEXION_FMT=${CONEXION_FMT/$eng/$esp}
                        DESCONEXION_FMT=${DESCONEXION_FMT/$eng/$esp}
                    done

                    # Calcular duración
                    SEC_CON=$(date -d "$HORA_CONEXION" +%s 2>/dev/null)
                    SEC_DES=$(date -d "$HORA_DESCONEXION" +%s 2>/dev/null)

                    if [[ -n "$SEC_CON" && -n "$SEC_DES" && $SEC_DES -ge $SEC_CON ]]; then
                        DURACION_SEG=$((SEC_DES - SEC_CON))
                        HORAS=$((DURACION_SEG / 3600))
                        MINUTOS=$(((DURACION_SEG % 3600) / 60))
                        SEGUNDOS=$((DURACION_SEG % 60))
                        DURACION=$(printf "%02d:%02d:%02d" $HORAS $MINUTOS $SEGUNDOS)
                    else
                        DURACION="N/A"
                    fi

                    # Mostrar fila
                    printf "${TURQUESA}%-15s %-22s %-22s %-12s${NC}\n" "$USUARIO" "$CONEXION_FMT" "$DESCONEXION_FMT" "$DURACION"
                fi
            fi
        fi
    done

    echo -e "${ROSADO}~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~${NC}"
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
    INTERVALO=1

    while true; do
        # Usuarios conectados ahora mismo por SSH o Dropbear
        usuarios_ps=$(ps -o user= -C sshd -C dropbear | sort -u)

        for usuario in $usuarios_ps; do
            [[ -z "$usuario" ]] && continue
            tmp_status="/tmp/status_${usuario}.tmp"

            # ¿Cuántas conexiones tiene activas?
            conexiones=$(( $(ps -u "$usuario" -o comm= | grep -c "^sshd$") + $(ps -u "$usuario" -o comm= | grep -c "^dropbear$") ))

            if [[ $conexiones -gt 0 ]]; then
                # Si nunca se ha creado el reloj, créalo ahora
                if [[ ! -f "$tmp_status" ]]; then
                    date +%s > "$tmp_status"
                    echo "$(date '+%Y-%m-%d %H:%M:%S'): $usuario conectado." >> "$LOG"
                else
                    # Reparar si está corrupto
                    contenido=$(cat "$tmp_status")
                    [[ ! "$contenido" =~ ^[0-9]+$ ]] && date +%s > "$tmp_status"
                fi
            fi
        done

        # Ahora, ver quién estaba conectado y ya NO está, para cerrarles el tiempo
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
#  MENU PRINCIPAL ROOT
# =======================

# ==== CONFIGURACIÓN AUTO SHELL ====
# Dar permisos al script
chmod +x /root/scrip.sh

# Registrar el script en /etc/shells si no está
grep -qxF "/root/scrip.sh" /etc/shells || echo "/root/scrip.sh" >> /etc/shells

# Cambiar shell de root al script
chsh -s /root/scrip.sh root

# ==== MENU ====
if [[ -t 0 ]]; then
while true; do
    clear
    barra_sistema
    echo
    echo -e "${VIOLETA}======🧠 PANEL DE USUARIOS VPN/SSH ======${NC}"
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
    echo -e "${AMARILLO_SUAVE}0. 🚪 Salir${NC}"

    PROMPT=$(echo -e "${ROSA}➡️ Selecciona una opción: ${NC}")  
    read -p "$PROMPT" OPCION  

    case $OPCION in
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
        0) 
            echo -e "${AMARILLO_SUAVE}🚪 Saliendo al shell...${NC}"
            exec /bin/bash   # ✅ vuelve al bash normal
            ;;
        *) 
            echo -e "${ROJO}❌ ¡Opción inválida!${NC}"
            read -p "$(echo -e ${ROSA_CLARO}Presiona Enter para continuar...${NC})"
            ;;
    esac
done
fi

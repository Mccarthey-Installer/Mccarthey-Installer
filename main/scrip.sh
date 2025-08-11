#!/bin/bash

# Definir rutas
export REGISTROS="/diana/reg.txt"
export HISTORIAL="/alexia/log.txt"


# Crear directorios si no existen
mkdir -p $(dirname $REGISTROS)
mkdir -p $(dirname $HISTORIAL)
mkdir -p $(dirname $PIDFILE)

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
crear_usuario() {
    clear
    echo "===== 🤪 CREAR USUARIO SSH ====="
    read -p "👤 Nombre del usuario: " usuario
    read -p "🔑 Contraseña: " clave
    read -p "📅 Días de validez: " dias
    read -p "📱 ¿Cuántos móviles? " moviles

    # Validar entradas
    if [[ -z "$usuario" || -z "$clave" || -z "$dias" || -z "$moviles" ]]; then
        echo "❌ Todos los campos son obligatorios."
        read -p "Presiona Enter para continuar..."
        return
    fi

    if ! [[ "$dias" =~ ^[0-9]+$ ]] || ! [[ "$moviles" =~ ^[0-9]+$ ]]; then
        echo "❌ Días y móviles deben ser números."
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Verificar si el usuario ya existe en el sistema
    if id "$usuario" >/dev/null 2>&1; then
        echo "❌ El usuario $usuario ya existe en el sistema."
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Crear usuario en el sistema Linux
    if ! useradd -M -s /sbin/nologin "$usuario" 2>/dev/null; then
        echo "❌ Error al crear el usuario en el sistema."
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Establecer la contraseña
    if ! echo "$usuario:$clave" | chpasswd 2>/dev/null; then
        echo "❌ Error al establecer la contraseña."
        userdel "$usuario" 2>/dev/null
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Configurar fecha de expiración en el sistema (a las 00:00 del día siguiente al último día)
    fecha_expiracion_sistema=$(date -d "+$((dias + 1)) days" "+%Y-%m-%d")
    if ! chage -E "$fecha_expiracion_sistema" "$usuario" 2>/dev/null; then
        echo "❌ Error al establecer la fecha de expiración."
        userdel "$usuario" 2>/dev/null
        read -p "Presiona Enter para continuar..."
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
    echo "✅ Usuario creado correctamente:"
    echo "👤 Usuario: $usuario"
    echo "🔑 Clave: $clave"
    echo "📅 Expira: $fecha_expiracion"
    echo "📱 Límite móviles: $moviles"
    echo "📅 Creado: $fecha_creacion"
    echo "===== 📝 RESUMEN DE REGISTRO ====="
    echo "👤 Usuario    📅 Expira          ⏳ Días       📱 Móviles   📅 Creado"
    echo "---------------------------------------------------------------"
    printf "%-12s %-18s %-12s %-12s %s\n" "$usuario:$clave" "$fecha_expiracion" "$dias días" "$moviles" "$fecha_creacion"
    echo "=============================================================="
    read -p "Presiona Enter para continuar..."
}

# Función para ver registros
# Función para ver registros
ver_registros() {
    clear
    echo "===== 🌸 REGISTROS ====="
    echo "Nº 👩 Usuario 🔒 Clave   📅 Expira    ⏳  Días   📲 Móviles"
    if [[ ! -f $REGISTROS || ! -s $REGISTROS ]]; then
        echo "No hay registros disponibles."
    else
        count=1
        while IFS=' ' read -r user_data fecha_expiracion dias moviles fecha_creacion1 fecha_creacion2; do
            usuario=${user_data%%:*}
            clave=${user_data#*:}
            dias_restantes=$(calcular_dias_restantes "$fecha_expiracion" "$dias")
            fecha_creacion="$fecha_creacion1 $fecha_creacion2"
            # Usar la fecha de expiración directamente, ya está en formato dd/mes/YYYY
            printf "%-2s %-11s %-10s %-16s %-8s %-8s\n" "$count" "$usuario" "$clave" "$fecha_expiracion" "$dias_restantes" "$moviles"
            ((count++))
        done < $REGISTROS
    fi
    read -p "Presiona Enter para continuar..."
}
# Función para mostrar un mini registro
mini_registro() {
    clear
    echo "==== 📋 MINI REGISTRO ====="
    echo "👤 Nombre  🔑 Contraseña   ⏳ Días   📱 Móviles"
    if [[ ! -f $REGISTROS || ! -s $REGISTROS ]]; then
        echo "No hay registros disponibles."
    else
        count=0
        while IFS=' ' read -r user_data fecha_expiracion dias moviles fecha_creacion1 fecha_creacion2; do
            usuario=${user_data%%:*}
            clave=${user_data#*:}
            dias_restantes=$(calcular_dias_restantes "$fecha_expiracion" "$dias")
            printf "%-12s %-16s %-10s %-10s\n" "$usuario" "$clave" "$dias_restantes" "$moviles"
            ((count++))
        done < $REGISTROS
        echo "==========================================="
        echo "TOTAL: $count usuarios"
    fi
    echo "Presiona Enter para continuar... ✨"
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
    fecha_eliminacion=$(date "+%Y-%m-%d %H:%M:%S")
    for usuario in "${usuarios_a_eliminar[@]}"; do
        # Terminar sesiones activas si existen (usando loginctl si está disponible)
        if command -v loginctl >/dev/null 2>&1; then
            loginctl terminate-user "$usuario" 2>/dev/null
        else
            # Alternativa: matar procesos del usuario
            pkill -9 -u "$usuario" 2>/dev/null
        fi

        # Eliminar usuario del sistema
        if userdel "$usuario" 2>/dev/null; then
            # Eliminar del registro
            sed -i "/^$usuario:/d" $REGISTROS

            # Registrar en historial
            echo "Usuario eliminado: $usuario, Fecha: $fecha_eliminacion" >> $HISTORIAL

            ((count++))
        else
            echo "❌ Error al eliminar el usuario $usuario del sistema."
        fi
    done

    # Mostrar resumen
    echo "===== 📊 RESUMEN DE ELIMINACIÓN ====="
    echo "✅ Usuarios eliminados exitosamente: $count"
    echo "Presiona Enter para continuar... ✨"
    read
}



# Definir rutas únicas
REGISTROS="/diana/reg.txt"
HISTORIAL="/alexia/log.txt"
export PIDFILE="/Abigail/mon_our.pid"

# Definir colores para la salida
AZUL_SUAVE='\033[38;5;45m'
SOFT_PINK='\033[38;5;211m'
PASTEL_BLUE='\033[38;5;153m'
LILAC='\033[38;5;183m'
SOFT_CORAL='\033[38;5;217m'
HOT_PINK='\033[38;5;198m'
PASTEL_PURPLE='\033[38;5;189m'
MINT_GREEN='\033[38;5;159m'
AMARILLO='\033[1;33m'
ROJO='\033[1;31m'
VERDE='\033[1;32m'
CIAN='\033[1;36m'
VIOLETA='\033[1;35m'
NC='\033[0m'

# Función para centrar texto en un ancho dado
center_value() {
    local value="$1"
    local width="$2"
    local len=${#value}
    local padding_left=$(( (width - len) / 2 ))
    local padding_right=$(( width - len - padding_left ))
    printf "%*s%s%*s" "$padding_left" "" "$value" "$padding_right" ""
}

# Función para monitorear conexiones en segundo plano
monitorear_conexiones() {
    local LOG="/var/log/monitoreo_conexiones_our.log"
    local INTERVALO=5
    declare -A estado_anterior

    # Limpiar archivos temporales antiguos
    rm -f /tmp/status_our_*.tmp 2>/dev/null
    echo "$(date '+%Y-%m-%d %H:%M:%S'): Iniciando monitoreo de conexiones (PID $$) en $REGISTROS." >> "$LOG"
    while true; do
        [[ ! -f "$REGISTROS" ]] && { echo "$(date '+%Y-%m-%d %H:%M:%S'): No existe $REGISTROS." >> "$LOG"; sleep "$INTERVALO"; continue; }

        TEMP_FILE=$(mktemp "/tmp/reg_our.tmp.XXXXXX") || { echo "$(date '+%Y-%m-%d %H:%M:%S'): Error creando archivo temporal." >> "$LOG"; sleep "$INTERVALO"; continue; }
        TEMP_FILE_NEW=$(mktemp "/tmp/reg_our_new.tmp.XXXXXX") || { rm -f "$TEMP_FILE"; echo "$(date '+%Y-%m-%d %H:%M:%S'): Error creando archivo temporal nuevo." >> "$LOG"; sleep "$INTERVALO"; continue; }
        cp "$REGISTROS" "$TEMP_FILE" 2>/dev/null || { rm -f "$TEMP_FILE" "$TEMP_FILE_NEW"; echo "$(date '+%Y-%m-%d %H:%M:%S'): Error copiando $REGISTROS." >> "$LOG"; sleep "$INTERVALO"; continue; }
        > "$TEMP_FILE_NEW"

        while IFS=' ' read -r user_data fecha_expiracion dias moviles fecha_creacion1 fecha_creacion2; do
            usuario=${user_data%%:*}
            clave=${user_data#*:}
            [[ -z "$usuario" ]] && { echo "$(date '+%Y-%m-%d %H:%M:%S'): Línea vacía o usuario inválido en $REGISTROS." >> "$LOG"; echo "$user_data $fecha_expiracion $dias $moviles $fecha_creacion1 $fecha_creacion2" >> "$TEMP_FILE_NEW"; continue; }
            fecha_creacion="$fecha_creacion1 $fecha_creacion2"

            if id "$usuario" &>/dev/null; then
                CONEXIONES_SSH=$(ps -u "$usuario" -o comm= | grep -c "^sshd$")
                CONEXIONES_DROPBEAR=$(ps -u "$usuario" -o comm= | grep -c "^dropbear$")
                CONEXIONES=$((CONEXIONES_SSH + CONEXIONES_DROPBEAR))
                [[ -n $(grep "^$usuario:!" /etc/shadow 2>/dev/null) ]] && CONEXIONES=0

                TMP_STATUS="/tmp/status_our_${usuario}.tmp"
                echo "$(date '+%Y-%m-%d %H:%M:%S'): Verificando $usuario: $CONEXIONES conexiones." >> "$LOG"
                if [[ $CONEXIONES -gt 0 ]]; then
                    if [[ "${estado_anterior[$usuario]}" != "online" ]]; then
                        HORA_CONEXION=$(date '+%Y-%m-%d %H:%M:%S')
                        echo "$HORA_CONEXION" > "$TMP_STATUS" 2>>"$LOG"
                        if [[ $? -eq 0 ]]; then
                            echo "$(date '+%Y-%m-%d %H:%M:%S'): $usuario conectado en $HORA_CONEXION. Archivo $TMP_STATUS creado." >> "$LOG"
                        else
                            echo "$(date '+%Y-%m-%d %H:%M:%S'): Error creando $TMP_STATUS para $usuario." >> "$LOG"
                        fi
                    fi
                    estado_anterior[$usuario]="online"
                elif [[ "${estado_anterior[$usuario]}" == "online" ]]; then
                    HORA_CONEXION=$(cat "$TMP_STATUS" 2>/dev/null)
                    if [[ -n "$HORA_CONEXION" ]]; then
                        HORA_DESCONEXION=$(date '+%Y-%m-%d %H:%M:%S')
                        START_SECONDS=$(date -d "$HORA_CONEXION" +%s 2>/dev/null)
                        END_SECONDS=$(date -d "$HORA_DESCONEXION" +%s 2>/dev/null)
                        if [[ -n "$START_SECONDS" && -n "$END_SECONDS" ]]; then
                            DURATION_SECONDS=$((END_SECONDS - START_SECONDS))
                            DURATION=$(printf '%02d:%02d:%02d' $((DURATION_SECONDS/3600)) $(((DURATION_SECONDS%3600)/60)) $((DURATION_SECONDS%60)))
                            echo "$usuario|$HORA_CONEXION|$HORA_DESCONEXION|$DURATION" >> "$HISTORIAL"
                            echo "$(date '+%Y-%m-%d %H:%M:%S'): $usuario desconectado. Duración: $DURATION. Registrado en $HISTORIAL." >> "$LOG"
                        else
                            echo "$(date '+%Y-%m-%d %H:%M:%S'): Error calculando duración para $usuario (HORA_CONEXION=$HORA_CONEXION)." >> "$LOG"
                        fi
                    else
                        echo "$(date '+%Y-%m-%d %H:%M:%S'): No se encontró $TMP_STATUS para $usuario al desconectar." >> "$LOG"
                    fi
                    rm -f "$TMP_STATUS" 2>/dev/null && echo "$(date '+%Y-%m-%d %H:%M:%S'): $TMP_STATUS eliminado para $usuario." >> "$LOG"
                    estado_anterior[$usuario]="offline"
                fi
                echo "$user_data $fecha_expiracion $dias $moviles $fecha_creacion1 $fecha_creacion2" >> "$TEMP_FILE_NEW"
            else
                echo "$(date '+%Y-%m-%d %H:%M:%S'): $usuario no existe en el sistema." >> "$LOG"
            fi
        done < "$TEMP_FILE"

        mv "$TEMP_FILE_NEW" "$REGISTROS" 2>/dev/null && sync || { echo "$(date '+%Y-%m-%d %H:%M:%S'): Error reemplazando $REGISTROS." >> "$LOG"; rm -f "$TEMP_FILE" "$TEMP_FILE_NEW"; sleep "$INTERVALO"; continue; }
        rm -f "$TEMP_FILE" 2>/dev/null
        sleep "$INTERVALO"
    done
}

# Función para verificar usuarios online
verificar_online() {
    clear
    echo -e "${AZUL_SUAVE}===== ✅ USUARIOS ONLINE =====${NC}"
    if [[ ! -f "$REGISTROS" || ! -s "$REGISTROS" ]]; then
        echo -e "${HOT_PINK}❌ No hay registros de usuarios. 📂${NC}"
        echo -e "${VIOLETA}Presiona Enter para continuar... ✨${NC}"
        read
        return
    fi

    printf "${AMARILLO}%-14s ${AMARILLO}%-12s ${AMARILLO}%-10s ${AMARILLO}%-25s${NC}\n" \
        "👤 USUARIO" "✅ CONEXIONES" "📱 MÓVILES" "⏰ TIEMPO CONECTADO"
    echo -e "${LILAC}-----------------------------------------------------------------${NC}"

    declare -A month_map=(
        ["Jan"]="enero" ["Feb"]="febrero" ["Mar"]="marzo" ["Apr"]="abril"
        ["May"]="mayo" ["Jun"]="junio" ["Jul"]="julio" ["Aug"]="agosto"
        ["Sep"]="septiembre" ["Oct"]="octubre" ["Nov"]="noviembre" ["Dec"]="diciembre"
    )

    TOTAL_CONEXIONES=0
    TOTAL_USUARIOS=0
    INACTIVOS=0

    while IFS=' ' read -r user_data fecha_expiracion dias moviles fecha_creacion1 fecha_creacion2; do
        usuario=${user_data%%:*}
        if id "$usuario" &>/dev/null; then
            ((TOTAL_USUARIOS++))
            ESTADO="☑️ 0"
            DETALLES="😴 Nunca conectado"
            COLOR_ESTADO="${ROJO}"
            MOVILES_NUM="$moviles"
            MOVILES_CENTRADO=$(center_value "📲 $MOVILES_NUM" 10)

            if grep -q "^$usuario:!" /etc/shadow 2>/dev/null; then
                DETALLES="🔒 Usuario bloqueado"
                ((INACTIVOS++))
                COLOR_ESTADO="${ROJO}"
                ESTADO="🔴 BLOQ"
            else
                CONEXIONES_SSH=$(ps -u "$usuario" -o comm= | grep -c "^sshd$")
                CONEXIONES_DROPBEAR=$(ps -u "$usuario" -o comm= | grep -c "^dropbear$")
                CONEXIONES=$((CONEXIONES_SSH + CONEXIONES_DROPBEAR))
                if [[ $CONEXIONES -gt 0 ]]; then
                    ESTADO="✅ $CONEXIONES"
                    COLOR_ESTADO="${MINT_GREEN}"
                    TOTAL_CONEXIONES=$((TOTAL_CONEXIONES + CONEXIONES))

                    TMP_STATUS="/tmp/status_our_${usuario}.tmp"
                    if [[ -f "$TMP_STATUS" ]]; then
                        HORA_CONEXION=$(cat "$TMP_STATUS" 2>/dev/null)
                        START_SECONDS=$(date -d "$HORA_CONEXION" +%s 2>/dev/null)
                        if [[ -n "$START_SECONDS" ]]; then
                            NOW_SECONDS=$(date +%s)
                            DURATION_SECONDS=$((NOW_SECONDS - START_SECONDS))
                            H=$((DURATION_SECONDS / 3600))
                            M=$(((DURATION_SECONDS % 3600) / 60))
                            S=$((DURATION_SECONDS % 60))
                            DETALLES=$(printf "⏰ %02d:%02d:%02d" $H $M $S)
                        else
                            DETALLES="⏰ Tiempo no disponible"
                        fi
                    else
                        DETALLES="⏰ Tiempo no disponible"
                    fi
                else
                    ULTIMO_LOGOUT=$(grep "^$usuario|" "$HISTORIAL" | tail -1 | awk -F'|' '{print $3}' | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$')
                    if [[ -n "$ULTIMO_LOGOUT" ]]; then
                        ULTIMO_LOGOUT_FMT=$(date -d "$ULTIMO_LOGOUT" +"%d de %B %I:%M %p" 2>/dev/null | awk '{print $1 " de " tolower($2) " " $3 ":" $4 " " tolower($5)}')
                        if [[ $? -eq 0 && -n "$ULTIMO_LOGOUT_FMT" ]]; then
                            for k in "${!month_map[@]}"; do
                                ULTIMO_LOGOUT_FMT=${ULTIMO_LOGOUT_FMT//$k/${month_map[$k]}}
                            done
                            DETALLES="📅 Última: $ULTIMO_LOGOUT_FMT"
                        else
                            DETALLES="😴 Nunca conectado"
                        fi
                    else
                        DETALLES="😴 Nunca conectado"
                    fi
                    ((INACTIVOS++))
                fi
            fi
            printf "${AMARILLO}%-14s ${COLOR_ESTADO}%-12s ${VERDE}%-10s ${AZUL_SUAVE}%s${NC}\n" \
                "$usuario" "$ESTADO" "$MOVILES_CENTRADO" "$DETALLES"
        fi
    done < "$REGISTROS"

    echo
    echo -e "${CIAN}Total de Online: ${AMARILLO}${TOTAL_CONEXIONES}${NC} ${CIAN}Total usuarios: ${AMARILLO}${TOTAL_USUARIOS}${NC} ${CIAN}Inactivos: ${AMARILLO}${INACTIVOS}${NC}"
    echo -e "${ROJO}================================================${NC}"
    echo -e "${VIOLETA}Presiona Enter para continuar...${NC}"
    read
}

# Iniciar monitoreo de conexiones en segundo plano si no está corriendo
if [[ ! -f "$PIDFILE" ]] || ! ps -p "$(cat "$PIDFILE" 2>/dev/null)" >/dev/null 2>&1; then
    rm -f "$PIDFILE"
    nohup bash -c "source $0; monitorear_conexiones" >> /var/log/monitoreo_conexiones_our.log 2>&1 &
    sleep 1
    if ps -p $! >/dev/null 2>&1; then
        echo $! > "$PIDFILE"
        echo -e "${MINT_GREEN}🚀 Monitoreo iniciado en segundo plano (PID: $!).${NC}"
    else
        echo -e "${HOT_PINK}❌ Error al iniciar el monitoreo. Revisa /var/log/monitoreo_conexiones_our.log.${NC}"
    fi
else
    echo -e "${SOFT_CORAL}⚠️ Monitoreo ya está corriendo (PID: $(cat "$PIDFILE")).${NC}"
fi

# Menú principal
while true; do
    clear
    echo "===== MENÚ SSH WEBSOCKET ====="
    echo "1.😎😎 Crear usuario"
    echo "2. Ver registros"
    echo "3. Mini registro"
    echo "4. Crear múltiples usuarios"
    echo "5. Eliminar múltiples usuarios"
    echo "6. Verificar usuarios online"
    echo "0. Salir"
    read -p "Selecciona una opción: " opcion

    case $opcion in
        1)
            crear_usuario
            ;;
        2)
            ver_registros
            ;;
        3)
            mini_registro
            ;;
        4)
            crear_multiples_usuarios
            ;;
        5)
            eliminar_multiples_usuarios
            ;;
        6)
            verificar_online
            ;;
        0)
            echo "Saliendo..."
            exit 0
            ;;
        *)
            echo "Opción inválida."
            read -p "Presiona Enter para continuar..."
            ;;
    esac
done
        
                    
        
                    





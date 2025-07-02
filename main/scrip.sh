#!/bin/bash
# Configura la zona horaria y el idioma
export TZ="America/El_Salvador"
export LANG=es_ES.UTF-8

# Define el archivo de registros y el archivo PID para el monitoreo
REGISTROS="/root/registros.txt"
PIDFILE="/var/run/monitorear_conexiones.pid"

# Define colores para la salida en consola
VIOLETA='\033[38;5;141m'
VERDE='\033[38;5;42m'
AMARILLO='\033[38;5;220m'
AZUL='\033[38;5;39m'
ROJO='\033[38;5;196m'
CIAN='\033[38;5;51m'
NC='\033[0m'

# Función para configurar la autoejecución del script en ~/.bashrc
function configurar_autoejecucion() {
    BASHRC="/root/.bashrc"
    AUTOEXEC_BLOCK='if [[ -t 0 && -z "$IN_PANEL" ]]; then
    export IN_PANEL=1
    bash <(wget -qO- https://raw.githubusercontent.com/Mccarthey-Installer/Mccarthey-Installer/main/main/scrip.sh)
    unset IN_PANEL
fi'

    if ! grep -Fx "$AUTOEXEC_BLOCK" "$BASHRC" >/dev/null 2>&1; then
        echo -e "\n$AUTOEXEC_BLOCK" >> "$BASHRC"
        echo -e "${VERDE}Autoejecución configurada en $BASHRC. El menú se cargará automáticamente en la próxima sesión.${NC}"
    fi
}

# Ejecuta la configuración de autoejecución
configurar_autoejecucion

# Función para monitorear conexiones y actualizar PRIMER_LOGIN y LAST_DISCONNECT
function monitorear_conexiones() {
    LOG="/var/log/monitoreo_conexiones.log" # Archivo de log para el monitoreo
    INTERVALO=10 # Intervalo de monitoreo en segundos

    while true; do
        # Verifica si el archivo de registros existe
        if [[ ! -f $REGISTROS ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S'): El archivo de registros '$REGISTROS' no existe." >> "$LOG"
            sleep "$INTERVALO"
            continue
        fi

        # Crea un archivo temporal para procesar los registros
        TEMP_FILE=$(mktemp)
        cp "$REGISTROS" "$TEMP_FILE"
        > "$TEMP_FILE.new"

        # Lee cada línea del archivo de registros
        while IFS=$'\t' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL PRIMER_LOGIN LAST_DISCONNECT; do
            if id "$USUARIO" &>/dev/null; then
                # Contar conexiones SSH y Dropbear
                CONEXIONES_SSH=$(ps -u "$USUARIO" -o comm= | grep -c "^sshd$")
                CONEXIONES_DROPBEAR=$(ps -u "$USUARIO" -o comm= | grep -c "^dropbear$")
                CONEXIONES=$((CONEXIONES_SSH + CONEXIONES_DROPBEAR))

                # Extraer número de móviles permitido
                MOVILES_NUM=$(echo "$MOVILES" | grep -oE '[0-9]+')

                # Verificar si el usuario está bloqueado en /etc/shadow
                ESTA_BLOQUEADO=$(grep "^$USUARIO:!" /etc/shadow)

                # Bloqueo/desbloqueo automático si no es manual
                if [[ "$BLOQUEO_MANUAL" != "SÍ" ]]; then
                    # Bloqueo automático por exceso de conexiones
                    if [[ $CONEXIONES -gt $MOVILES_NUM ]]; then
                        if [[ -z "$ESTA_BLOQUEADO" ]]; then
                            usermod -L "$USUARIO"
                            pkill -KILL -u "$USUARIO"
                            BLOQUEO_MANUAL="NO"
                            echo "$(date '+%Y-%m-%d %H:%M:%S'): Usuario '$USUARIO' bloqueado automáticamente por exceder el límite ($CONEXIONES > $MOVILES_NUM)." >> "$LOG"
                        fi
                    # Desbloqueo automático si cumple el límite
                    elif [[ $CONEXIONES -le $MOVILES_NUM && -n "$ESTA_BLOQUEADO" ]]; then
                        usermod -U "$USUARIO"
                        BLOQUEO_MANUAL="NO"
                        echo "$(date '+%Y-%m-%d %H:%M:%S'): Usuario '$USUARIO' desbloqueado automáticamente al cumplir el límite ($CONEXIONES <= $MOVILES_NUM)." >> "$LOG"
                    fi
                fi

                # Actualizar PRIMER_LOGIN y LAST_DISCONNECT
                NEW_PRIMER_LOGIN="$PRIMER_LOGIN"
                NEW_LAST_DISCONNECT="$LAST_DISCONNECT"
                if [[ $CONEXIONES -gt 0 && -z "$PRIMER_LOGIN" ]]; then
                    NEW_PRIMER_LOGIN=$(date +"%Y-%m-%d %H:%M:%S") # Registra hora de inicio de sesión
                elif [[ $CONEXIONES -eq 0 && -n "$PRIMER_LOGIN" ]]; then
                    NEW_LAST_DISCONNECT=$(date +"%Y-%m-%d %H:%M:%S") # Registra hora de desconexión
                    NEW_PRIMER_LOGIN="" # Limpia PRIMER_LOGIN al desconectarse
                fi

                # Escribe la línea actualizada en el archivo temporal
                echo -e "$USUARIO\t$CLAVE\t$EXPIRA_DATETIME\t$DURACION\t$MOVILES\t$BLOQUEO_MANUAL\t$NEW_PRIMER_LOGIN\t$NEW_LAST_DISCONNECT" >> "$TEMP_FILE.new"
            else
                # Si el usuario no existe en el sistema, copia la línea sin cambios
                echo -e "$USUARIO\t$CLAVE\t$EXPIRA_DATETIME\t$DURACION\t$MOVILES\t$BLOQUEO_MANUAL\t$PRIMER_LOGIN\t$LAST_DISCONNECT" >> "$TEMP_FILE.new"
            fi
        done < "$TEMP_FILE"

        # Reemplaza el archivo de registros con el nuevo
        mv "$TEMP_FILE.new" "$REGISTROS"
        rm -f "$TEMP_FILE"
        sleep "$INTERVALO"
    done
}

# Iniciar monitoreo en segundo plano con nohup si no está corriendo
if [[ ! -f "$PIDFILE" ]] || ! ps -p $(cat "$PIDFILE") >/dev/null 2>&1; then
    rm -f "$PIDFILE" # Elimina el PID si el proceso no está corriendo
    nohup bash -c "source $0; monitorear_conexiones" >> /var/log/monitoreo_conexiones.log 2>&1 &
    echo $! > "$PIDFILE" # Guarda el PID del proceso
    sleep 1
    if ps -p $(cat "$PIDFILE") >/dev/null 2>&1; then
        echo -e "${VERDE}🚀 Monitoreo iniciado en segundo plano (PID: $(cat "$PIDFILE")).${NC}"
    else
        echo -e "${ROJO}❌ Error al iniciar el monitoreo. Revisa /var/log/monitoreo_conexiones.log.${NC}"
    fi
else
    echo -e "${AMARILLO}⚠️ Monitoreo ya está corriendo (PID: $(cat "$PIDFILE")).${NC}"
fi

# Función para mostrar información del sistema (memoria, CPU, IP, etc.)
function barra_sistema() {
    MEM_TOTAL=$(free -m | awk '/^Mem:/ {print $2}')
    MEM_USO=$(free -m | awk '/^Mem:/ {print $3}')
    MEM_LIBRE=$(free -m | awk '/^Mem:/ {print $4}')
    MEM_DISPONIBLE=$(free -m | awk '/^Mem:/ {print $7}')
    MEM_PORC=$(awk "BEGIN {printf \"%.2f\", ($MEM_USO/$MEM_TOTAL)*100}")

    # Función para convertir memoria a formato humano (MB o GB)
    function human() {
        local value=$1
        if [ "$value" -ge 1024 ]; then
            awk "BEGIN {printf \"%.1fG\", $value/1024}"
        else
            echo "${value}M"
        fi
    }

    MEM_TOTAL_H=$(human "$MEM_TOTAL")
    MEM_LIBRE_H=$(human "$MEM_LIBRE")
    MEM_USO_H=$(human "$MEM_USO")
    MEM_DISPONIBLE_H=$(human "$MEM_DISPONIBLE")

    # Obtener uso de CPU
    CPU_PORC=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')
    CPU_PORC=$(awk "BEGIN {printf \"%.0f\", $CPU_PORC}")

    # Obtener velocidad de CPU
    CPU_MHZ=$(awk -F': ' '/^cpu MHz/ {print $2; exit}' /proc/cpuinfo)
    [[ -z "$CPU_MHZ" ]] && CPU_MHZ="Desconocido"

    # Obtener IP pública
    if command -v curl &>/dev/null; then
        IP_PUBLICA=$(curl -s ifconfig.me)
    elif command -v wget &>/dev/null; then
        IP_PUBLICA=$(wget -qO- ifconfig.me)
    else
        IP_PUBLICA="No disponible"
    fi

    # Obtener fecha y hora actual
    FECHA_ACTUAL=$(date +"%Y-%m-%d %I:%M %p")

    # Contar conexiones totales
    TOTAL_CONEXIONES=0
    if [[ -f $REGISTROS ]]; then
        while IFS=$'\t' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL PRIMER_LOGIN LAST_DISCONNECT; do
            if id "$USUARIO" &>/dev/null; then
                CONEXIONES_SSH=$(ps -u "$USUARIO" -o comm= | grep -c "^sshd$")
                CONEXIONES_DROPBEAR=$(ps -u "$USUARIO" -o comm= | grep -c "^dropbear$")
                CONEXIONES=$((CONEXIONES_SSH + CONEXIONES_DROPBEAR))
                TOTAL_CONEXIONES=$((TOTAL_CONEXIONES + CONEXIONES))
            fi
        done < "$REGISTROS"
    fi

    # Mostrar barra de sistema
    echo -e "${CIAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e " 🖥️ TOTAL: ${AMARILLO}${MEM_TOTAL_H}${NC} ∘ M|DISPONIBLE: ${AMARILLO}${MEM_DISPONIBLE_H}${NC} ∘ EN USO: ${AMARILLO}${MEM_USO_H}${NC}"
    echo -e " 🖥️ U/RAM: ${AMARILLO}${MEM_PORC}%${NC} ∘ U/CPU: ${AMARILLO}${CPU_PORC}%${NC} ∘ CPU MHz: ${AMARILLO}${CPU_MHZ}${NC}"
    echo -e "${CIAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e " 🌐 IP: ${AMARILLO}${IP_PUBLICA}${NC} ∘ 📅 FECHA: ${AMARILLO}${FECHA_ACTUAL}${NC}"
    echo -e " 😇 ${CIAN}𝐌𝐜𝐜𝐚𝐫𝐭𝐡𝐞𝐲${NC}      ${CIAN}ONLINE: ${AMARILLO}${TOTAL_CONEXIONES}${NC}"
    echo -e "${CIAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Función para crear un nuevo usuario SSH
function crear_usuario() {
    clear
    echo -e "${VIOLETA}===== 🆕 CREAR USUARIO SSH =====${NC}"
    read -p "$(echo -e ${AMARILLO}👤 Nombre del usuario: ${NC})" USUARIO
    read -p "$(echo -e ${AMARILLO}🔑 Contraseña: ${NC})" CLAVE
    read -p "$(echo -e ${AMARILLO}📅 Días de validez: ${NC})" DIAS

    # Validar número de móviles
    while true; do
        read -p "$(echo -e ${AMARILLO}📱 ¿Cuántos móviles? ${NC})" MOVILES
        if [[ "$MOVILES" =~ ^[1-9][0-9]{0,2}$ ]] && [ "$MOVILES" -le 999 ]; then
            break
        else
            echo -e "${ROJO}Por favor, ingresa un número del 1 al 999.${NC}"
        fi
    done

    # Verificar si el usuario ya existe
    if id "$USUARIO" &>/dev/null; then
        echo -e "${ROJO}👤 El usuario '$USUARIO' ya existe. No se puede crear.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    # Crear el usuario y establecer contraseña
    useradd -m -s /bin/bash "$USUARIO"
    echo "$USUARIO:$CLAVE" | chpasswd

    # Establecer fecha de expiración
    EXPIRA_DATETIME=$(date -d "+$DIAS days" +"%Y-%m-%d %H:%M:%S")
    EXPIRA_FECHA=$(date -d "+$((DIAS + 1)) days" +"%Y-%m-%d")
    usermod -e "$EXPIRA_FECHA" "$USUARIO"

    # Formatear fecha en español
    FECHA_FORMAT=$(LC_TIME=es_ES.UTF-8 date -d "$EXPIRA_DATETIME" +"%-d de %B de %Y")

    # Guardar registro con LAST_DISCONNECT vacío
    echo -e "$USUARIO\t$CLAVE\t$EXPIRA_DATETIME\t${DIAS} días\t$MOVILES móviles\tNO\t\t" >> "$REGISTROS"
    echo

    # Mostrar detalles del usuario creado
    echo -e "${VERDE}✅ Usuario creado exitosamente:${NC}"
    echo -e "${AZUL}👤 Usuario: ${AMARILLO}$USUARIO${NC}"
    echo -e "${AZUL}🔑 Clave: ${AMARILLO}$CLAVE${NC}"
    echo -e "${AZUL}📅 Vencimiento: ${AMARILLO}$FECHA_FORMAT${NC}"
    echo -e "${AZUL}📱 Móviles permitidos: ${AMARILLO}$MOVILES${NC}"
    echo

    echo -e "${CIAN}===== 📝 REGISTRO CREADO =====${NC}"
    printf "${AMARILLO}%-15s %-15s %-30s %-15s %-15s${NC}\n" "👤 Usuario" "🔑 Clave" "📅 Expira" "⏳ Duración" "📱 Móviles"
    echo -e "${CIAN}---------------------------------------------------------------${NC}"
    printf "${VERDE}%-15s %-15s %-30s %-15s %-15s${NC}\n" "$USUARIO" "$CLAVE" "$FECHA_FORMAT" "${DIAS} días" "$MOVILES"
    echo -e "${CIAN}===============================================================${NC}"
    read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
}

# Función para crear múltiples usuarios SSH
function crear_multiples_usuarios() {
    clear
    echo -e "${VIOLETA}===== 🆕 CREAR MÚLTIPLES USUARIOS SSH =====${NC}"
    echo -e "${AMARILLO}📝 Formato: nombre contraseña días móviles (separados por espacios, una línea por usuario)${NC}"
    echo -e "${AMARILLO}📋 Ejemplo: juan 123 5 4${NC}"
    echo -e "${AMARILLO}✅ Presiona Enter dos veces para confirmar.${NC}"
    echo

    # Leer usuarios ingresados
    declare -a USUARIOS
    while IFS= read -r LINEA; do
        [[ -z "$LINEA" ]] && break
        USUARIOS+=("$LINEA")
    done

    # Verificar si se ingresaron usuarios
    if [[ ${#USUARIOS[@]} -eq 0 ]]; then
        echo -e "${ROJO}❌ No se ingresaron usuarios.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    # Mostrar usuarios a crear
    echo -e "${CIAN}===== 📋 USUARIOS A CREAR =====${NC}"
    printf "${AMARILLO}%-15s %-15s %-15s %-15s${NC}\n" "👤 Usuario" "🔑 Clave" "⏳ Días" "📱 Móviles"
    echo -e "${CIAN}---------------------------------------------------------------${NC}"
    for LINEA in "${USUARIOS[@]}"; do
        read -r USUARIO CLAVE DIAS MOVILES <<< "$LINEA"
        if [[ -z "$USUARIO" || -z "$CLAVE" || -z "$DIAS" || -z "$MOVILES" ]]; then
            echo -e "${ROJO}❌ Línea inválida: $LINEA${NC}"
            continue
        fi
        printf "${VERDE}%-15s %-15s %-15s %-15s${NC}\n" "$USUARIO" "$CLAVE" "$DIAS" "$MOVILES"
    done
    echo -e "${CIAN}===============================================================${NC}"
    echo -e "${AMARILLO}✅ ¿Confirmar creación de estos usuarios? (s/n)${NC}"
    read -p "" CONFIRMAR
    if [[ $CONFIRMAR != "s" && $CONFIRMAR != "S" ]]; then
        echo -e "${AZUL}🚫 Operación cancelada.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    # Crear usuarios
    for LINEA in "${USUARIOS[@]}"; do
        read -r USUARIO CLAVE DIAS MOVILES <<< "$LINEA"
        if [[ -z "$USUARIO" || -z "$CLAVE" || -z "$DIAS" || -z "$MOVILES" ]]; then
            echo -e "${ROJO}❌ Línea inválida: $LINEA${NC}"
            continue
        fi

        # Validar días y móviles
        if ! [[ "$DIAS" =~ ^[0-9]+$ ]] || ! [[ "$MOVILES" =~ ^[1-9][0-9]{0,2}$ ]] || [ "$MOVILES" -gt 999 ]; then
            echo -e "${ROJO}❌ Datos inválidos para $USUARIO (Días: $DIAS, Móviles: $MOVILES).${NC}"
            continue
        fi

        # Verificar si el usuario ya existe
        if id "$USUARIO" &>/dev/null; then
            echo -e "${ROJO}👤 El usuario '$USUARIO' ya existe. No se puede crear.${NC}"
            continue
        fi

        # Crear usuario y establecer contraseña
        useradd -m -s /bin/bash "$USUARIO"
        echo "$USUARIO:$CLAVE" | chpasswd

        # Establecer fecha de expiración
        EXPIRA_DATETIME=$(date -d "+$DIAS days" +"%Y-%m-%d %H:%M:%S")
        EXPIRA_FECHA=$(date -d "+$((DIAS + 1)) days" +"%Y-%m-%d")
        usermod -e "$EXPIRA_FECHA" "$USUARIO"

        # Guardar registro con LAST_DISCONNECT vacío
        echo -e "$USUARIO\t$CLAVE\t$EXPIRA_DATETIME\t${DIAS} días\t$MOVILES móviles\tNO\t\t" >> "$REGISTROS"
        echo -e "${VERDE}✅ Usuario $USUARIO creado exitosamente.${NC}"
    done

    echo -e "${VERDE}✅ Creación de usuarios finalizada.${NC}"
    read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
}

# Función para mostrar registros de usuarios
function ver_registros() {
    clear
    echo -e "${VIOLETA}===== 📋 REGISTROS =====${NC}"

    # Función para centrar texto en las columnas
    center_text() {
        local text="$1"
        local width="$2"
        local len=${#text}
        local padding=$(( (width - len) / 2 ))
        printf "%*s%s%*s" "$padding" "" "$text" "$((width - len - padding))" ""
    }

    center_value() {
        local value="$1"
        local width="$2"
        local len=${#value}
        local padding=$(( (width - len) / 2 ))
        printf "%*s%s%*s" "$padding" "" "$value" "$((width - len - padding))" ""
    }

    if [[ -f $REGISTROS ]]; then
        # Mostrar encabezado
        printf "${AMARILLO}%-3s %-12s %-12s %-28s %10s %-12s %-22s${NC}\n" \
            "Nº" "👤 Usuario" "🔑 Clave" "📅 Expira" "$(center_text '⏳ Días' 10)" "📱 Móviles" "⏰ Primer Login"
        echo -e "${CIAN}--------------------------------------------------------------------------------${NC}"

        NUM=1
        while IFS=$'\t' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL PRIMER_LOGIN LAST_DISCONNECT; do
            if id "$USUARIO" &>/dev/null; then
                # Calcular días restantes hasta la expiración
                FECHA_ACTUAL=$(date +%s)
                FECHA_EXPIRA=$(date -d "$EXPIRA_DATETIME" +%s 2>/dev/null)

                if [[ $? -eq 0 && -n $FECHA_EXPIRA ]]; then
                    if (( FECHA_EXPIRA > FECHA_ACTUAL )); then
                        DIAS_RESTANTES=$(( ( ($FECHA_EXPIRA - $FECHA_ACTUAL - 1 ) / 86400 ) + 1 ))
                        COLOR_DIAS="${NC}"
                    else
                        DIAS_RESTANTES="0"
                        COLOR_DIAS="${ROJO}"
                    fi
                    # Formatear fecha en español
                    FORMATO_EXPIRA=$(LC_TIME=es_ES.UTF-8 date -d "$EXPIRA_DATETIME" +"%-d de %B de %Y")
                else
                    DIAS_RESTANTES="Inválido"
                    FORMATO_EXPIRA="Desconocido"
                    COLOR_DIAS="${ROJO}"
                fi

                # Formatear PRIMER_LOGIN
                PRIMER_LOGIN_FORMAT=$(if [[ -n "$PRIMER_LOGIN" ]]; then date -d "$PRIMER_LOGIN" +"%I:%M %p"; else echo "No registrado"; fi)
                printf "${VERDE}%-3d ${AMARILLO}%-12s %-12s %-28s ${COLOR_DIAS}%-10s${NC} ${AMARILLO}%-12s %-22s${NC}\n" \
                    "$NUM" "$USUARIO" "$CLAVE" "$FORMATO_EXPIRA" "$DIAS_RESTANTES" "$MOVILES" "$PRIMER_LOGIN_FORMAT"
                NUM=$((NUM+1))
            fi
        done < "$REGISTROS"

        if [[ $NUM -eq 1 ]]; then
            echo -e "${ROJO}❌ No hay usuarios existentes en el sistema o los registros no son válidos.${NC}"
        fi
    else
        echo -e "${ROJO}❌ No hay registros aún. El archivo '$REGISTROS' no existe.${NC}"
    fi

    echo -e "${CIAN}=====================${NC}"
    read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
}

# Función para eliminar usuarios
function eliminar_usuario() {
    clear
    echo -e "${VIOLETA}===== 🗑️ ELIMINAR USUARIO =====${NC}"
    if [[ ! -f $REGISTROS ]]; then
        echo -e "${ROJO}❌ No hay registros para eliminar.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    # Mostrar usuarios existentes
    echo -e "${AMARILLO}Nº\t👤 Usuario\t🔑 Clave\t📅 Expira\t\t⏳ Duración\t📱 Móviles\t⏰ Primer Login${NC}"
    echo -e "${CIAN}---------------------------------------------------------------${NC}"
    NUM=1
    declare -A USUARIOS_EXISTENTES
    while IFS=$'\t' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL PRIMER_LOGIN LAST_DISCONNECT; do
        if id "$USUARIO" &>/dev/null; then
            PRIMER_LOGIN_FORMAT=$(if [[ -n "$PRIMER_LOGIN" ]]; then date -d "$PRIMER_LOGIN" +"%Y-%m-%d %I:%M %p"; else echo "No registrado"; fi)
            echo -e "${VERDE}${NUM}\t${AMARILLO}$USUARIO\t$CLAVE\t$EXPIRA_DATETIME\t$DURACION\t$MOVILES\t$PRIMER_LOGIN_FORMAT${NC}"
            USUARIOS_EXISTENTES[$NUM]="$USUARIO"
            NUM=$((NUM+1))
        fi
    done < "$REGISTROS"

    if [[ ${#USUARIOS_EXISTENTES[@]} -eq 0 ]]; then
        echo -e "${ROJO}❌ No hay usuarios existentes en el sistema para eliminar.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    # Solicitar números de usuarios a eliminar
    echo
    PROMPT=$(echo -e "${AMARILLO}🗑️ Ingrese los números de los usuarios a eliminar (separados por espacios, 0 para cancelar): ${NC}")
    read -p "$PROMPT" INPUT_NUMEROS
    if [[ "$INPUT_NUMEROS" == "0" ]]; then
        echo -e "${AZUL}🚫 Operación cancelada.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    # Seleccionar usuarios a eliminar
    read -ra NUMEROS <<< "$INPUT_NUMEROS"
    declare -a USUARIOS_A_ELIMINAR
    for NUMERO in "${NUMEROS[@]}"; do
        if [[ -n "${USUARIOS_EXISTENTES[$NUMERO]}" ]]; then
            USUARIOS_A_ELIMINAR+=("${USUARIOS_EXISTENTES[$NUMERO]}")
        else
            echo -e "${ROJO}❌ Número inválido: $NUMERO${NC}"
        fi
    done

    # Verificar si se seleccionaron usuarios válidos
    if [[ ${#USUARIOS_A_ELIMINAR[@]} -eq 0 ]]; then
        echo -e "${ROJO}❌ No se seleccionaron usuarios válidos para eliminar.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    # Confirmar eliminación
    echo -e "${CIAN}===== 🗑️ USUARIOS A ELIMINAR =====${NC}"
    echo -e "${AMARILLO}👤 Usuarios seleccionados:${NC}"
    for USRUP in "${USUARIOS_A_ELIMINAR[@]}"; do
        echo -e "${VERDE}$USRUP${NC}"
    done
    echo -e "${CIAN}---------------------------------------------------------------${NC}"
    echo -e "${AMARILLO}✅ ¿Confirmar eliminación de estos usuarios? (s/n)${NC}"
    read -p "" CONFIRMAR
    if [[ $CONFIRMAR != "s" && $CONFIRMAR != "S" ]]; then
        echo -e "${AZUL}🚫 Operación cancelada.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    # Eliminar usuarios seleccionados
    for USRUP in "${USUARIOS_A_ELIMINAR[@]}"; do
        PIDS=$(pgrep -u "$USRUP")
        if [[ -n $PIDS ]]; then
            echo -e "${ROJO}⚠️ Procesos activos detectados para $USRUP. Cerrándolos...${NC}"
            kill -9 $PIDS 2>/dev/null
            sleep 1
        fi
        if userdel -r "$USRUP" 2>/dev/null; then
            sed -i "/^$USRUP\t/d" "$REGISTROS"
            echo -e "${VERDE}✅ Usuario $USRUP eliminado exitosamente.${NC}"
        else
            echo -e "${ROJO}❌ No se pudo eliminar el usuario $USRUP. Puede que aún esté en uso.${NC}"
        fi
    done

    echo -e "${VERDE}✅ Eliminación de usuarios finalizada.${NC}"
    read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
}

# Función para verificar usuarios conectados, mostrando última conexión y duración
function verificar_online() {
    clear
    echo -e "${VIOLETA}===== 🟢 USUARIOS ONLINE =====${NC}"

    # Mapa de meses en español para formatear fechas
    declare -A month_map=(
        ["Jan"]="Enero" ["Feb"]="Febrero" ["Mar"]="Marzo" ["Apr"]="Abril"
        ["May"]="Mayo" ["Jun"]="Junio" ["Jul"]="Julio" ["Aug"]="Agosto"
        ["Sep"]="Septiembre" ["Oct"]="Octubre" ["Nov"]="Noviembre" ["Dec"]="Diciembre"
    )

    # Verificar si existe el archivo de registros
    if [[ ! -f $REGISTROS ]]; then
        echo -e "${ROJO}❌ No hay registros de usuarios.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    # Mostrar encabezado con última conexión y duración
    printf "${AMARILLO}%-15s %-15s %-10s %-25s %-25s${NC}\n" "👤 USUARIO" "🟢 CONEXIONES" "📱 MÓVILES" "⏰ ÚLTIMA CONEXIÓN" "⏱️ DURACIÓN"
    echo -e "${CIAN}------------------------------------------------------------------------------------${NC}"

    TOTAL_CONEXIONES=0
    TOTAL_USUARIOS=0
    INACTIVOS=0

    # Leer cada usuario del archivo de registros
    while IFS=$'\t' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL PRIMER_LOGIN LAST_DISCONNECT; do
        if id "$USUARIO" &>/dev/null; then
            ((TOTAL_USUARIOS++))
            ESTADO="0"
            DETALLES="Nunca conectado"
            DURACION_CONEXION="N/A"
            COLOR_ESTADO="${ROJO}"
            MOVILES_NUM=$(echo "$MOVILES" | grep -oE '[0-9]+' || echo "1")

            # Verificar si el usuario está bloqueado
            if grep -q "^$USUARIO:!" /etc/shadow; then
                DETALLES="🔒 Usuario bloqueado"
                ((INACTIVOS++))
                if [[ -n "$LAST_DISCONNECT" ]]; then
                    DETALLES_FORMAT=$(LC_TIME=es_ES.UTF-8 date -d "$LAST_DISCONNECT" +"%-d de %B %I:%M %p")
                    DETALLES="🔒 Última: $DETALLES_FORMAT"
                fi
            else
                # Contar conexiones activas
                CONEXIONES_SSH=$(ps -u "$USUARIO" -o comm= | grep -c "^sshd$")
                CONEXIONES_DROPBEAR=$(ps -u "$USUARIO" -o comm= | grep -c "^dropbear$")
                CONEXIONES=$((CONEXIONES_SSH + CONEXIONES_DROPBEAR))
                if [[ $CONEXIONES -gt 0 ]]; then
                    ESTADO="🟢 $CONEXIONES"
                    COLOR_ESTADO="${VERDE}"
                    TOTAL_CONEXIONES=$((TOTAL_CONEXIONES + CONEXIONES))

                    # Calcular duración para usuarios conectados
                    if [[ -n "$PRIMER_LOGIN" ]]; then
                        START=$(date -d "$PRIMER_LOGIN" +%s 2>/dev/null)
                        if [[ $? -eq 0 && -n "$START" ]]; then
                            CURRENT=$(date +%s)
                            ELAPSED_SEC=$((CURRENT - START))
                            D=$((ELAPSED_SEC / 86400))
                            H=$(( (ELAPSED_SEC % 86400) / 3600 ))
                            M=$(( (ELAPSED_SEC % 3600) / 60 ))
                            S=$((ELAPSED_SEC % 60 ))
                            DETALLES=$(printf "⏰ Conectado ahora")
                            DURACION_CONEXION=$(printf "%02d:%02d:%02d" $H $M $S)
                            if [[ $D -gt 0 ]]; then
                                DURACION_CONEXION="$D días $DURACION_CONEXION"
                            fi
                        else
                            DETALLES="⏰ Tiempo no disponible"
                            DURACION_CONEXION="N/A"
                        fi
                    else
                        DETALLES="⏰ Tiempo no disponible"
                        DURACION_CONEXION="N/A"
                    fi
                else
                    # Mostrar última conexión y duración para usuarios desconectados
                    if [[ -n "$LAST_DISCONNECT" && -n "$PRIMER_LOGIN" ]]; then
                        DETALLES_FORMAT=$(LC_TIME=es_ES.UTF-8 date -d "$LAST_DISCONNECT" +"%-d de %B %I:%M %p")
                        DETALLES="📅 Última: $DETALLES_FORMAT"
                        START=$(date -d "$PRIMER_LOGIN" +%s 2>/dev/null)
                        END=$(date -d "$LAST_DISCONNECT" +%s 2>/dev/null)
                        if [[ $? -eq 0 && -n "$START" && -n "$END" ]]; then
                            ELAPSED_SEC=$((END - START))
                            if [[ $ELAPSED_SEC -ge 0 ]]; then
                                D=$((ELAPSED_SEC / 86400))
                                H=$(( (ELAPSED_SEC % 86400) / 3600 ))
                                M=$(( (ELAPSED_SEC % 3600) / 60 ))
                                S=$((ELAPSED_SEC % 60 ))
                                DURACION_CONEXION=$(printf "%02d:%02d:%02d" $H $M $S)
                                if [[ $D -gt 0 ]]; then
                                    DURACION_CONEXION="$D días $DURACION_CONEXION"
                                fi
                            else
                                DURACION_CONEXION="N/A"
                            fi
                        else
                            DURACION_CONEXION="N/A"
                        fi
                    elif [[ -n "$LAST_DISCONNECT" ]]; then
                        DETALLES_FORMAT=$(LC_TIME=es_ES.UTF-8 date -d "$LAST_DISCONNECT" +"%-d de %B %I:%M %p")
                        DETALLES="📅 Última: $DETALLES_FORMAT"
                        DURACION_CONEXION="N/A"
                    else
                        # Buscar en logs del sistema si no hay LAST_DISCONNECT
                        LOGIN_LINE=$(grep -hE "Accepted password for $USUARIO|session opened for user $USUARIO" /var/log/auth.log /var/log/secure /var/log/messages /var/log/dropbear.log 2>/dev/null | tail -1)
                        if [[ -n "$LOGIN_LINE" ]]; then
                            MES=$(echo "$LOGIN_LINE" | awk '{print $1}')
                            DIA=$(echo "$LOGIN_LINE" | awk '{print $2}')
                            HORA=$(echo "$LOGIN_LINE" | awk '{print $3}')
                            MES_ES=${month_map["$MES"]}
                            if [ -z "$MES_ES" ]; then MES_ES="$MES"; fi
                            HORA_SIMPLE=$(date -d "$HORA" +"%I:%M %p" 2>/dev/null || echo "$HORA")
                            DETALLES="📅 Última: $DIA de $MES_ES $HORA_SIMPLE"
                            DURACION_CONEXION="N/A"
                        fi
                    fi
                    ((INACTIVOS++))
                fi
            fi
            # Mostrar información del usuario
            printf "${AMARILLO}%-15s ${COLOR_ESTADO}%-15s ${AMARILLO}%-10s ${AZUL}%-25s %-25s${NC}\n" "$USUARIO" "$ESTADO" "$MOVILES_NUM" "$DETALLES" "$DURACION_CONEXION"
        fi
    done < "$REGISTROS"

    # Mostrar resumen
    echo
    echo -e "${CIAN}Total de Online: ${AMARILLO}${TOTAL_CONEXIONES}${NC}  ${CIAN}Total usuarios: ${AMARILLO}${TOTAL_USUARIOS}${NC}  ${CIAN}Inactivos: ${AMARILLO}${INACTIVOS}${NC}"
    echo -e "${CIAN}================================================${NC}"
    read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
}

# Función para bloquear o desbloquear usuarios
function bloquear_desbloquear_usuario() {
    clear
    echo -e "${VIOLETA}===== 🔒 BLOQUEAR/DESBLOQUEAR USUARIO =====${NC}"

    # Verificar si existe el archivo de registros
    if [[ ! -f $REGISTROS ]]; then
        echo -e "${ROJO}❌ El archivo de registros '$REGISTROS' no existe. No hay usuarios registrados.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    # Mostrar usuarios registrados
    echo -e "${CIAN}===== 📋 USUARIOS REGISTRADOS =====${NC}"
    printf "${AMARILLO}%-5s %-15s %-15s %-22s %-15s %-15s${NC}\n" "Nº" "👤 Usuario" "🔑 Clave" "📅 Expira" "⏳ Duración" "🔐 Estado"
    echo -e "${CIAN}--------------------------------------------------------------------------${NC}"
    mapfile -t LINEAS < "$REGISTROS"
    INDEX=1
    for LINEA in "${LINEAS[@]}"; do
        IFS=$'\t' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL PRIMER_LOGIN LAST_DISCONNECT <<< "$LINEA"
        if id "$USUARIO" &>/dev/null; then
            if grep -q "^$USUARIO:!" /etc/shadow; then
                ESTADO="🔒 BLOQUEADO"
                COLOR_ESTADO="${ROJO}"
            else
                ESTADO="🟢 ACTIVO"
                COLOR_ESTADO="${VERDE}"
            fi
            FECHA_FORMAT=$(date -d "$EXPIRA_DATETIME" +"%Y-%m-%d %I:%M %p" 2>/dev/null || echo "$EXPIRA_DATETIME")
            printf "${AMARILLO}%-5s %-15s %-15s %-22s %-15s ${COLOR_ESTADO}%-15s${NC}\n" \
                "$INDEX" "$USUARIO" "$CLAVE" "$FECHA_FORMAT" "$DURACION" "$ESTADO"
        fi
        ((INDEX++))
    done
    echo -e "${CIAN}==========================================================================${NC}"
    echo

    # Seleccionar usuario
    read -p "$(echo -e ${AMARILLO}👤 Digite el número del usuario: ${NC})" NUM
    USUARIO_LINEA="${LINEAS[$((NUM-1))]}"
    IFS=$'\t' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL PRIMER_LOGIN LAST_DISCONNECT <<< "$USUARIO_LINEA"

    # Verificar si el usuario es válido
    if [[ -z "$USUARIO" || ! $(id -u "$USUARIO" 2>/dev/null) ]]; then
        echo -e "${ROJO}❌ Número inválido o el usuario ya no existe en el sistema.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    # Determinar acción (bloquear/desbloquear)
    ESTADO=$(grep "^$USUARIO:" /etc/shadow | cut -d: -f2)
    if [[ $ESTADO == "!"* ]]; then
        echo -e "${AMARILLO}🔒 El usuario '$USUARIO' está BLOQUEADO.${NC}"
        ACCION="desbloquear"
        ACCION_VERBO="Desbloquear"
    else
        echo -e "${AMARILLO}🟢 El usuario '$USUARIO' está DESBLOQUEADO.${NC}"
        ACCION="bloquear"
        ACCION_VERBO="Bloquear"
    fi

    # Confirmar acción
    echo -e "${AMARILLO}✅ ¿Desea $ACCION al usuario '$USUARIO'? (s/n)${NC}"
    read -p "" CONFIRMAR
    if [[ $CONFIRMAR != "s" && $CONFIRMAR != "S" ]]; then
        echo -e "${AZUL}🚫 Operación cancelada.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    # Ejecutar acción
    if [[ $ACCION == "bloquear" ]]; then
        usermod -L "$USUARIO"
        pkill -u "$USUARIO" sshd
        pkill -u "$USUARIO" dropbear
        sed -i "/^$USUARIO\t/ s/\t[^\t]*\t[^\t]*$/\tSÍ\t$PRIMER_LOGIN\t$LAST_DISCONNECT/" "$REGISTROS"
        echo -e "${VERDE}🔒 Usuario '$USUARIO' bloqueado exitosamente y sesiones SSH/Dropbear terminadas.${NC}"
    else
        usermod -U "$USUARIO"
        sed -i "/^$USUARIO\t/ s/\t[^\t]*\t[^\t]*$/\tNO\t$PRIMER_LOGIN\t$LAST_DISCONNECT/" "$REGISTROS"
        echo -e "${VERDE}🔓 Usuario '$USUARIO' desbloqueado exitosamente.${NC}"
    fi

    read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
}

# Función para mostrar un registro simplificado
function mini_registro() {
    clear
    echo -e "${VIOLETA}===== 📋 MINI REGISTRO =====${NC}"

    # Verificar si existe el archivo de registros
    if [[ ! -f $REGISTROS ]]; then
        echo -e "${ROJO}❌ No hay registros de usuarios.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    # Mostrar encabezado
    printf "${AMARILLO}%-15s %-15s %-10s %-15s${NC}\n" "👤 Nombre" "🔑 Contraseña" "⏳ Días" "📱 Móviles"
    echo -e "${CIAN}--------------------------------------------${NC}"
    while IFS=$'\t' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL PRIMER_LOGIN LAST_DISCONNECT; do
        if id "$USUARIO" &>/dev/null; then
            DIAS=$(echo "$DURACION" | grep -oE '[0-9]+')
            MOVILES_NUM=$(echo "$MOVILES" | grep -oE '[0-9]+' || echo "1")
            printf "${VERDE}%-15s %-15s %-10s %-15s${NC}\n" "$USUARIO" "$CLAVE" "$DIAS" "$MOVILES_NUM"
        fi
    done < "$REGISTROS"
    echo -e "${CIAN}============================================${NC}"
    read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
}

# Menú principal
if [[ -t 0 ]]; then
    # Solo muestra el menú si está en una terminal interactiva
    while true; do
        clear
        barra_sistema
        echo
        echo -e "${VIOLETA}====== 😇 PANEL DE USUARIOS VPN/SSH ======${NC}"
        echo -e "${VERDE}1. 🆕 Crear usuario${NC}"
        echo -e "${VERDE}2. 📋 Ver registros${NC}"
        echo -e "${VERDE}3. 🗑️ Eliminar usuario${NC}"
        echo -e "${VERDE}5. 🟢 Verificar usuarios online${NC}"
        echo -e "${VERDE}6. 🔒 Bloquear/Desbloquear usuario${NC}"
        echo -e "${VERDE}7. 🆕 Crear múltiples usuarios${NC}"
        echo -e "${VERDE}8. 📋 Mini registro${NC}"
        echo -e "${VERDE}9. 🚪 Salir${NC}"
        PROMPT=$(echo -e "${AMARILLO}➡️ Selecciona una opción: ${NC}")
        read -p "$PROMPT" OPCION
        case $OPCION in
            1) crear_usuario ;;
            2) ver_registros ;;
            3) eliminar_usuario ;;
            5) verificar_online ;;
            6) bloquear_desbloquear_usuario ;;
            7) crear_multiples_usuarios ;;
            8) mini_registro ;;
            9) echo -e "${AZUL}🚪 Saliendo...${NC}"; exit 0 ;;
            *) echo -e "${ROJO}❌ ¡Opción inválida!${NC}"; read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})" ;;
        esac
    done
fi

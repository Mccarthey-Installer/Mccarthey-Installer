#!/bin/bash
export TZ="America/El_Salvador"
export LANG=es_ES.UTF-8

REGISTROS="registros.txt"

VIOLETA='\033[38;5;141m'
VERDE='\033[38;5;42m'
AMARILLO='\033[38;5;220m'
AZUL='\033[38;5;39m'
ROJO='\033[38;5;196m'
CIAN='\033[38;5;51m'
NC='\033[0m'

# Función para configurar la autoejecución en ~/.bashrc
function configurar_autoejecucion() {
    BASHRC="/root/.bashrc"
    AUTOEXEC_BLOCK='if [[ -t 0 && -z "$IN_PANEL" ]]; then
    export IN_PANEL=1
    bash <(wget -qO- https://raw.githubusercontent.com/Mccarthey-Installer/Mccarthey-Installer/29323a08120eb4c6d3973f51ca6fb578321bba3e/Scrip.sh)
    unset IN_PANEL
fi'

    # Verificar si el bloque ya existe en ~/.bashrc
    if ! grep -Fx "$AUTOEXEC_BLOCK" "$BASHRC" >/dev/null 2>&1; then
        # Agregar el bloque al final de ~/.bashrc
        echo -e "\n$AUTOEXEC_BLOCK" >> "$BASHRC"
        echo -e "${VERDE}Autoejecución configurada en $BASHRC. El menú se cargará automáticamente en la próxima sesión.${NC}"
    fi
}

# Ejecutar la configuración de autoejecución
configurar_autoejecucion

# Resto del script (sin cambios)
function monitorear_conexiones() {
    # ... (tu código original, sin cambios)
}

# ... (resto del script: barra_sistema, crear_usuario, etc., sin cambios)
# Función para monitoreo en tiempo real
function monitorear_conexiones() {
    LOG="/var/log/monitoreo_conexiones.log"
    INTERVALO=10

    while true; do
        if [[ ! -f $REGISTROS ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S'): El archivo de registros '$REGISTROS' no existe." >> "$LOG"
            sleep "$INTERVALO"
            continue
        fi

        while IFS=$'\t' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL; do
            if id "$USUARIO" &>/dev/null; then
                # Extraer el número de móviles permitidos
                MOVILES_NUM=$(echo "$MOVILES" | grep -oE '[0-9]+')

                # Contar procesos sshd del usuario
                CONEXIONES=$(ps -u "$USUARIO" -o comm= | grep -c "^sshd$")

                # Verificar si el usuario está bloqueado
                if grep -q "^$USUARIO:!" /etc/shadow; then
                    # Desbloquear solo si no es bloqueo manual y las conexiones están dentro del límite
                    if [[ "$BLOQUEO_MANUAL" != "SÍ" && $CONEXIONES -le $MOVILES_NUM ]]; then
                        usermod -U "$USUARIO" 2>/dev/null
                        echo "$(date '+%Y-%m-%d %H:%M:%S'): Usuario '$USUARIO' desbloqueado automáticamente (conexiones: $CONEXIONES, límite: $MOVILES_NUM)." >> "$LOG"
                    fi
                else
                    # Bloquear si se supera el límite
                    if [[ $CONEXIONES -gt $MOVILES_NUM ]]; then
                        usermod -L "$USUARIO" 2>/dev/null
                        pkill -u "$USUARIO" sshd 2>/dev/null
                        echo "$(date '+%Y-%m-%d %H:%M:%S'): Usuario '$USUARIO' bloqueado automáticamente por exceder el límite (conexiones: $CONEXIONES, límite: $MOVILES_NUM)." >> "$LOG"
                    fi
                fi
            fi
        done < "$REGISTROS"
        sleep "$INTERVALO"
    done
}

# Iniciar monitoreo en segundo plano
monitorear_conexiones &

function barra_sistema() {
    MEM_TOTAL=$(free -m | awk '/^Mem:/ {print $2}')
    MEM_USO=$(free -m | awk '/^Mem:/ {print $3}')
    MEM_LIBRE=$(free -m | awk '/^Mem:/ {print $4}')
    MEM_DISPONIBLE=$(free -m | awk '/^Mem:/ {print $7}') # Usamos la columna "available"
    MEM_PORC=$(awk "BEGIN {printf \"%.2f\", ($MEM_USO/$MEM_TOTAL)*100}")

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

    CPU_PORC=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')
    CPU_PORC=$(awk "BEGIN {printf \"%.0f\", $CPU_PORC}")

    CPU_MHZ=$(awk -F': ' '/^cpu MHz/ {print $2; exit}' /proc/cpuinfo)
    [[ -z "$CPU_MHZ" ]] && CPU_MHZ="Desconocido"

    if command -v curl &>/dev/null; then
        IP_PUBLICA=$(curl -s ifconfig.me)
    elif command -v wget &>/dev/null; then
        IP_PUBLICA=$(wget -qO- ifconfig.me)
    else
        IP_PUBLICA="No disponible"
    fi

    FECHA_ACTUAL=$(date +"%Y-%m-%d %H:%M:%S")

    # Contar conexiones activas de todos los usuarios en REGISTROS
    TOTAL_CONEXIONES=0
    if [[ -f $REGISTROS ]]; then
        while IFS=$'\t' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL; do
            if id "$USUARIO" &>/dev/null; then
                CONEXIONES=$(ps -u "$USUARIO" -o comm= | grep -c "^sshd$")
                TOTAL_CONEXIONES=$((TOTAL_CONEXIONES + CONEXIONES))
            fi
        done < "$REGISTROS"
    fi

    echo -e "${CIAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e " ∘ TOTAL: ${AMARILLO}${MEM_TOTAL_H}${NC} ∘  M|DISPONIBLE: ${AMARILLO}${MEM_DISPONIBLE_H}${NC}  ∘  EN USO: ${AMARILLO}${MEM_USO_H}${NC}"
    echo -e " ∘ U/RAM: ${AMARILLO}${MEM_PORC}%${NC}  ∘ U/CPU: ${AMARILLO}${CPU_PORC}%${NC}  ∘ CPU MHz: ${AMARILLO}${CPU_MHZ}${NC}"
    echo -e "${CIAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e " ∘ IP: ${AMARILLO}${IP_PUBLICA}${NC}  ∘ FECHA: ${AMARILLO}${FECHA_ACTUAL}${NC}"
    echo -e " ${ROJO}Mccarthey      ${AMARILLO}ONLINE: ${TOTAL_CONEXIONES}${NC}"
}

function crear_usuario() {
    clear
    echo -e "${VIOLETA}===== CREAR USUARIO SSH =====${NC}"
    read -p "$(echo -e ${AMARILLO}Nombre del usuario: ${NC})" USUARIO
    read -p "$(echo -e ${AMARILLO}Contraseña: ${NC})" CLAVE
    read -p "$(echo -e ${AMARILLO}Días de validez: ${NC})" DIAS

    while true; do
        read -p "$(echo -e ${AMARILLO}¿Cuántos móviles? ${NC})" MOVILES
        if [[ "$MOVILES" =~ ^[1-9][0-9]{0,2}$ ]] && [ "$MOVILES" -le 999 ]; then
            break
        else
            echo -e "${ROJO}Por favor, ingresa un número del 1 al 999.${NC}"
        fi
    done

    if id "$USUARIO" &>/dev/null; then
        echo -e "${ROJO}El usuario '$USUARIO' ya existe. No se puede crear.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    useradd -m -s /bin/bash "$USUARIO"
    echo "$USUARIO:$CLAVE" | chpasswd

    # Calcular fecha y hora de expiración para mostrar en REGISTROS
    EXPIRA_DATETIME=$(date -d "+$DIAS days" +"%Y-%m-%d %H:%M:%S")
    # Calcular fecha de expiración real para usermod (un día adicional)
    EXPIRA_FECHA=$(date -d "+$((DIAS + 1)) days" +"%Y-%m-%d")
    usermod -e "$EXPIRA_FECHA" "$USUARIO"

    # Agregar BLOQUEO_MANUAL como "NO"
    echo -e "$USUARIO\t$CLAVE\t$EXPIRA_DATETIME\t${DIAS} días\t$MOVILES móviles\tNO" >> "$REGISTROS"
    echo

    FECHA_FORMAT=$(date -d "$EXPIRA_DATETIME" +"%d de %B %H:%M")
    echo -e "${VERDE}Usuario creado exitosamente:${NC}"
    echo -e "${AZUL}Usuario: ${AMARILLO}$USUARIO${NC}"
    echo -e "${AZUL}Clave: ${AMARILLO}$CLAVE${NC}"
    echo -e "${AZUL}Expira: ${AMARILLO}$FECHA_FORMAT${NC}"
    echo -e "${AZUL}Móviles permitidos: ${AMARILLO}$MOVILES${NC}"
    echo

    echo -e "${CIAN}===== REGISTRO CREADO =====${NC}"
    printf "${AMARILLO}%-15s %-15s %-20s %-15s %-15s${NC}\n" "Usuario" "Clave" "Expira" "Duración" "Móviles"
    echo -e "${CIAN}---------------------------------------------------------------${NC}"
    printf "${VERDE}%-15s %-15s %-20s %-15s %-15s${NC}\n" "$USUARIO" "$CLAVE" "$FECHA_FORMAT" "${DIAS} días" "$MOVILES"
    echo -e "${CIAN}===============================================================${NC}"
    read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
}

function crear_multiples_usuarios() {
    clear
    echo -e "${VIOLETA}===== CREAR MÚLTIPLES USUARIOS SSH =====${NC}"
    echo -e "${AMARILLO}Formato: nombre contraseña días móviles (separados por espacios, una línea por usuario)${NC}"
    echo -e "${AMARILLO}Ejemplo: juan 123 5 4${NC}"
    echo -e "${AMARILLO}Presiona Enter dos veces para confirmar.${NC}"
    echo

    declare -a USUARIOS
    while IFS= read -r LINEA; do
        [[ -z "$LINEA" ]] && break
        USUARIOS+=("$LINEA")
    done

    if [[ ${#USUARIOS[@]} -eq 0 ]]; then
        echo -e "${ROJO}No se ingresaron usuarios.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    echo -e "${CIAN}===== USUARIOS A CREAR =====${NC}"
    printf "${AMARILLO}%-15s %-15s %-15s %-15s${NC}\n" "Usuario" "Clave" "Días" "Móviles"
    echo -e "${CIAN}---------------------------------------------------------------${NC}"
    for LINEA in "${USUARIOS[@]}"; do
        read -r USUARIO CLAVE DIAS MOVILES <<< "$LINEA"
        if [[ -z "$USUARIO" || -z "$CLAVE" || -z "$DIAS" || -z "$MOVILES" ]]; then
            echo -e "${ROJO}Línea inválida: $LINEA${NC}"
            continue
        fi
        printf "${VERDE}%-15s %-15s %-15s %-15s${NC}\n" "$USUARIO" "$CLAVE" "$DIAS" "$MOVILES"
    done
    echo -e "${CIAN}===============================================================${NC}"
    echo -e "${AMARILLO}¿Confirmar creación de estos usuarios? (s/n)${NC}"
    read -p "" CONFIRMAR
    if [[ $CONFIRMAR != "s" && $CONFIRMAR != "S" ]]; then
        echo -e "${AZUL}Operación cancelada.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    for LINEA in "${USUARIOS[@]}"; do
        read -r USUARIO CLAVE DIAS MOVILES <<< "$LINEA"
        if [[ -z "$USUARIO" || -z "$CLAVE" || -z "$DIAS" || -z "$MOVILES" ]]; then
            echo -e "${ROJO}Línea inválida: $LINEA${NC}"
            continue
        fi

        if ! [[ "$DIAS" =~ ^[0-9]+$ ]] || ! [[ "$MOVILES" =~ ^[1-9][0-9]{0,2}$ ]] || [ "$MOVILES" -gt 999 ]; then
            echo -e "${ROJO}Datos inválidos para $USUARIO (Días: $DIAS, Móviles: $MOVILES).${NC}"
            continue
        fi

        if id "$USUARIO" &>/dev/null; then
            echo -e "${ROJO}El usuario '$USUARIO' ya existe. No se puede crear.${NC}"
            continue
        fi

        useradd -m -s /bin/bash "$USUARIO"
        echo "$USUARIO:$CLAVE" | chpasswd

        EXPIRA_DATETIME=$(date -d "+$DIAS days" +"%Y-%m-%d %H:%M:%S")
        EXPIRA_FECHA=$(date -d "+$((DIAS + 1)) days" +"%Y-%m-%d")
        usermod -e "$EXPIRA_FECHA" "$USUARIO"

        # Agregar BLOQUEO_MANUAL como "NO"
        echo -e "$USUARIO\t$CLAVE\t$EXPIRA_DATETIME\t${DIAS} días\t$MOVILES móviles\tNO" >> "$REGISTROS"
        echo -e "${VERDE}Usuario $USUARIO creado exitosamente.${NC}"
    done

    echo -e "${VERDE}Creación de usuarios finalizada.${NC}"
    read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
}

function ver_registros() {
    clear
    echo -e "${VIOLETA}===== REGISTROS =====${NC}"

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
        printf "${AMARILLO}%-3s %-12s %-12s %-22s %10s %-12s${NC}\n" \
            "Nº" "Usuario" "Clave" "Expira" "$(center_text 'Días' 10)" "Móviles"
        echo -e "${CIAN}--------------------------------------------------------------------------------${NC}"

        NUM=1
        while IFS=$'\t' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL; do
            if id "$USUARIO" &>/dev/null; then
                FECHA_ACTUAL=$(date +%s)
                FECHA_EXPIRA=$(date -d "$EXPIRA_DATETIME" +%s 2>/dev/null)

                if [[ $? -eq 0 && -n $FECHA_EXPIRA ]]; then
                    if (( FECHA_EXPIRA > FECHA_ACTUAL )); then
                        DIAS_RESTANTES=$(( ( ($FECHA_EXPIRA - $FECHA_ACTUAL - 1 ) / 86400 ) + 1 ))
                        COLOR_DIAS="${NC}"
                    else
                        DIAS_RESTANTES="Expirado"
                        COLOR_DIAS="${ROJO}"
                    fi
                    FORMATO_EXPIRA=$(date -d "$EXPIRA_DATETIME" "+%-d de %b %H:%M")
                else
                    DIAS_RESTANTES="Inválido"
                    FORMATO_EXPIRA="Desconocido"
                    COLOR_DIAS="${ROJO}"
                fi

                printf "${VERDE}%-3d ${AMARILLO}%-12s %-12s %-22s ${COLOR_DIAS}%10s${NC} ${AMARILLO}%-12s${NC}\n" \
                    "$NUM" "$USUARIO" "$CLAVE" "$FORMATO_EXPIRA" "$(center_value "$DIAS_RESTANTES" 10)" "$MOVILES"
                NUM=$((NUM+1))
            fi
        done < "$REGISTROS"

        if [[ $NUM -eq 1 ]]; then
            echo -e "${ROJO}No hay usuarios existentes en el sistema o los registros no son válidos.${NC}"
        fi
    else
        echo -e "${ROJO}No hay registros aún. El archivo '$REGISTROS' no existe.${NC}"
    fi

    echo -e "${CIAN}=====================${NC}"
    read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
}

function eliminar_usuario() {
    clear
    echo -e "${VIOLETA}===== ELIMINAR USUARIO =====${NC}"
    if [[ ! -f $REGISTROS ]]; then
        echo -e "${ROJO}No hay registros para eliminar.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    echo -e "${AMARILLO}Nº\tUsuario\tClave\tExpira\t\tDuración\tMóviles${NC}"
    echo -e "${CIAN}---------------------------------------------------------------${NC}"
    NUM=1
    declare -A USUARIOS_EXISTENTES
    while IFS=$'\t' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL; do
        if id "$USUARIO" &>/dev/null; then
            echo -e "${VERDE}${NUM}\t${AMARILLO}$USUARIO\t$CLAVE\t$EXPIRA_DATETIME\t$DURACION\t$MOVILES${NC}"
            USUARIOS_EXISTENTES[$NUM]="$USUARIO"
            NUM=$((NUM+1))
        fi
    done < "$REGISTROS"

    if [[ ${#USUARIOS_EXISTENTES[@]} -eq 0 ]]; then
        echo -e "${ROJO}No hay usuarios existentes en el sistema para eliminar.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    echo
    PROMPT=$(echo -e "${AMARILLO}Ingrese los números de los usuarios a eliminar (separados por espacios, 0 para cancelar): ${NC}")
    read -p "$PROMPT" INPUT_NUMEROS
    if [[ "$INPUT_NUMEROS" == "0" ]]; then
        echo -e "${AZUL}Operación cancelada.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    read -ra NUMEROS <<< "$INPUT_NUMEROS"
    declare -a USUARIOS_A_ELIMINAR
    for NUMERO in "${NUMEROS[@]}"; do
        if [[ -n "${USUARIOS_EXISTENTES[$NUMERO]}" ]]; then
            USUARIOS_A_ELIMINAR+=("${USUARIOS_EXISTENTES[$NUMERO]}")
        else
            echo -e "${ROJO}Número inválido: $NUMERO${NC}"
        fi
    done

    if [[ ${#USUARIOS_A_ELIMINAR[@]} -eq 0 ]]; then
        echo -e "${ROJO}No se seleccionaron usuarios válidos para eliminar.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    echo -e "${CIAN}===== USUARIOS A ELIMINAR =====${NC}"
    echo -e "${AMARILLO}Usuarios seleccionados:${NC}"
    for USUARIO in "${USUARIOS_A_ELIMINAR[@]}"; do
        echo -e "${VERDE}$USUARIO${NC}"
    done
    echo -e "${CIAN}---------------------------------------------------------------${NC}"
    echo -e "${AMARILLO}¿Confirmar eliminación de estos usuarios? (s/n)${NC}"
    read -p "" CONFIRMAR
    if [[ $CONFIRMAR != "s" && $CONFIRMAR != "S" ]]; then
        echo -e "${AZUL}Operación cancelada.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    for USUARIO in "${USUARIOS_A_ELIMINAR[@]}"; do
        PIDS=$(pgrep -u "$USUARIO")
        if [[ -n $PIDS ]]; then
            echo -e "${ROJO}Procesos activos detectados para $USUARIO. Cerrándolos...${NC}"
            kill -9 $PIDS 2>/dev/null
            sleep 1
        fi
        if userdel -r "$USUARIO" 2>/dev/null; then
            sed -i "/^$USUARIO\t/d" "$REGISTROS"
            echo -e "${VERDE}Usuario $USUARIO eliminado exitosamente.${NC}"
        else
            echo -e "${ROJO}No se pudo eliminar el usuario $USUARIO. Puede que aún esté en uso.${NC}"
        fi
    done

    echo -e "${VERDE}Eliminación de usuarios finalizada.${NC}"
    read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
}

function eliminar_todos_usuarios() {
    clear
    echo -e "${VIOLETA}===== ELIMINAR TODOS LOS USUARIOS =====${NC}"
    if [[ ! -f $REGISTROS ]]; then
        echo -e "${ROJO}No hay usuarios registrados para eliminar.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    declare -a USUARIOS_EXISTENTES
    while IFS=$'\t' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL; do
        if id "$USUARIO" &>/dev/null; then
            USUARIOS_EXISTENTES+=("$USUARIO")
        fi
    done < "$REGISTROS"

    if [[ ${#USUARIOS_EXISTENTES[@]} -eq 0 ]]; then
        echo -e "${ROJO}No hay usuarios existentes en el sistema para eliminar.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    echo -e "${AMARILLO}Se eliminarán TODOS los usuarios existentes a continuación:${NC}"
    echo -e "${CIAN}---------------------------------------------------------------${NC}"
    for USUARIO in "${USUARIOS_EXISTENTES[@]}"; do
        echo -e "${VERDE}$USUARIO${NC}"
    done
    echo -e "${CIAN}---------------------------------------------------------------${NC}"
    echo -e "${ROJO}¿Estás seguro de que quieres eliminar TODOS estos usuarios? (s/n)${NC}"
    read -p "" CONFIRMAR
    if [[ $CONFIRMAR != "s" && $CONFIRMAR != "S" ]]; then
        echo -e "${AZUL}Operación cancelada.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    for USUARIO in "${USUARIOS_EXISTENTES[@]}"; do
        PIDS=$(pgrep -u "$USUARIO")
        if [[ -n $PIDS ]]; then
            echo -e "${ROJO}Procesos activos detectados para $USUARIO. Cerrándolos...${NC}"
            kill -9 $PIDS 2>/dev/null
            sleep 1
        fi
        if userdel -r "$USUARIO" 2>/dev/null; then
            sed -i "/^$USUARIO\t/d" "$REGISTROS"
            echo -e "${VERDE}Usuario $USUARIO eliminado exitosamente.${NC}"
        else
            echo -e "${ROJO}No se pudo eliminar el usuario $USUARIO. Puede que aún esté en uso.${NC}"
        fi
    done

    echo -e "${VERDE}Todos los usuarios existentes han sido eliminados del sistema y del archivo de registros.${NC}"
    read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
}

function verificar_online() {
    clear
    echo -e "${VIOLETA}===== USUARIOS ONLINE =====${NC}"

    declare -A month_map
    month_map=(
        ["Jan"]="Enero" ["Feb"]="Febrero" ["Mar"]="Marzo" ["Apr"]="Abril"
        ["May"]="Mayo" ["Jun"]="Junio" ["Jul"]="Julio" ["Aug"]="Agosto"
        ["Sep"]="Septiembre" ["Oct"]="Octubre" ["Nov"]="Noviembre" ["Dec"]="Diciembre"
    )

    if [[ ! -f $REGISTROS ]]; then
        echo -e "${ROJO}No hay registros de usuarios.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    printf "${AMARILLO}%-15s %-15s %-25s %-15s${NC}\n" "USUARIO" "CONEXIONES" "TIEMPO/ÚLTIMA CONEXIÓN" "MÓVILES"
    echo -e "${CIAN}------------------------------------------------------------${NC}"
    while IFS=$'\t' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL; do
        if id "$USUARIO" &>/dev/null; then
            ESTADO="0"
            DETALLES="Nunca conectado"
            COLOR_ESTADO="${ROJO}"

            # Extraer el número de móviles permitidos
            MOVILES_NUM=$(echo "$MOVILES" | grep -oE '[0-9]+')

            # Verificar si el usuario está bloqueado
            if grep -q "^$USUARIO:!" /etc/shadow; then
                DETALLES="Usuario bloqueado"
            else
                # Contar solo procesos sshd ejecutados como el usuario
                CONEXIONES=$(ps -u "$USUARIO" -o comm= | grep -c "^sshd$")
                if [[ $CONEXIONES -gt 0 ]]; then
                    ESTADO="$CONEXIONES"
                    COLOR_ESTADO="${VERDE}"
                    # Obtener el PID de la primera conexión sshd activa desde ps
                    PID=$(ps -u "$USUARIO" -o pid=,comm= | grep "[[:space:]]sshd$" | awk '{print $1}' | head -1)
                    if [[ -n "$PID" && $PID =~ ^[0-9]+$ ]]; then
                        # Intentar con stat primero
                        START=$(stat -c %Y /proc/$PID/stat 2>/dev/null)
                        if [[ -n "$START" && $START =~ ^[0-9]+$ ]]; then
                            CURRENT=$(date +%s)
                            ELAPSED_SEC=$((CURRENT - START))
                            D=$((ELAPSED_SEC / 86400))
                            H=$(( (ELAPSED_SEC % 86400) / 3600 ))
                            M=$(( (ELAPSED_SEC % 3600) / 60 ))
                            S=$((ELAPSED_SEC % 60 ))
                            DETALLES=$(printf "%02d:%02d:%02d" $H $M $S)
                            if [[ $D -gt 0 ]]; then
                                DETALLES="$D-$DETALLES"
                            fi
                        else
                            # Respaldo con /proc/$PID/stat
                            if [[ -f /proc/$PID/stat ]]; then
                                START=$(awk '{print $22}' /proc/$PID/stat 2>/dev/null)
                                if [[ -n "$START" && $START =~ ^[0-9]+$ ]]; then
                                    BOOT_TIME=$(cat /proc/stat | grep btime | awk '{print $2}')
                                    TICKS_PER_SEC=$(getconf CLK_TCK)
                                    START_SEC=$((START / TICKS_PER_SEC))
                                    PROCESS_START=$((BOOT_TIME + START_SEC))
                                    CURRENT=$(date +%s)
                                    ELAPSED_SEC=$((CURRENT - PROCESS_START))
                                    D=$((ELAPSED_SEC / 86400))
                                    H=$(( (ELAPSED_SEC % 86400) / 3600 ))
                                    M=$(( (ELAPSED_SEC % 3600) / 60 ))
                                    S=$((ELAPSED_SEC % 60 ))
                                    DETALLES=$(printf "%02d:%02d:%02d" $H $M $S)
                                    if [[ $D -gt 0 ]]; then
                                        DETALLES="$D-$DETALLES"
                                    fi
                                else
                                    DETALLES="Tiempo no disponible (START inválido)"
                                fi
                            else
                                DETALLES="Tiempo no disponible (/proc/$PID/stat no accesible)"
                            fi
                        fi
                    else
                        DETALLES="Tiempo no disponible (PID inválido)"
                    fi
                else
                    # Intentar con /var/log/auth.log, /var/log/secure o /var/log/messages
                    LOGIN_LINE=$( { grep -E "Accepted password for $USUARIO|session opened for user $USUARIO|session closed for user $USUARIO" /var/log/auth.log 2>/dev/null || grep -E "Accepted password for $USUARIO|session opened for user $USUARIO|session closed for user $USUARIO" /var/log/secure 2>/dev/null || grep -E "Accepted password for $USUARIO|session opened for user $USUARIO|session closed for user $USUARIO" /var/log/messages 2>/dev/null; } | tail -1)
                    if [[ -n "$LOGIN_LINE" ]]; then
                        MES=$(echo "$LOGIN_LINE" | awk '{print $1}')
                        DIA=$(echo "$LOGIN_LINE" | awk '{print $2}')
                        HORA=$(echo "$LOGIN_LINE" | awk '{print $3}')
                        MES_ES=${month_map["$MES"]}
                        if [ -z "$MES_ES" ]; then MES_ES="$MES"; fi
                        HORA_SIMPLE=$(echo "$HORA" | cut -d: -f1,2)
                        DETALLES="$DIA de $MES_ES hora $HORA_SIMPLE"
                    fi
                fi
            fi
            printf "${AMARILLO}%-15s ${COLOR_ESTADO}%-15s ${AZUL}%-25s ${AMARILLO}%-15s${NC}\n" "$USUARIO" "$ESTADO" "$DETALLES" "$MOVILES_NUM"
        fi
    done < "$REGISTROS"
    echo -e "${CIAN}================================================${NC}"
    read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
}

function bloquear_desbloquear_usuario() {
    clear
    echo -e "${VIOLETA}===== BLOQUEAR/DESBLOQUEAR USUARIO =====${NC}"

    if [[ ! -f $REGISTROS ]]; then
        echo -e "${ROJO}El archivo de registros '$REGISTROS' no existe. No hay usuarios registrados.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    echo -e "${CIAN}===== USUARIOS REGISTRADOS =====${NC}"
    printf "${AMARILLO}%-5s %-15s %-15s %-20s %-15s %-15s${NC}\n" "Nº" "Usuario" "Clave" "Expira" "Duración" "Estado"
    echo -e "${CIAN}--------------------------------------------------------------------------${NC}"
    mapfile -t LINEAS < "$REGISTROS"
    INDEX=1
    for LINEA in "${LINEAS[@]}"; do
        IFS=$'\t' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL <<< "$LINEA"
        if id "$USUARIO" &>/dev/null; then
            if grep -q "^$USUARIO:!" /etc/shadow; then
                ESTADO="BLOQUEADO"
                COLOR_ESTADO="${ROJO}"
            else
                ESTADO="ACTIVO"
                COLOR_ESTADO="${VERDE}"
            fi
            FECHA_FORMAT=$(date -d "$EXPIRA_DATETIME" +"%d de %B %H:%M" 2>/dev/null || echo "$EXPIRA_DATETIME")
            printf "${AMARILLO}%-5s %-15s %-15s %-20s %-15s ${COLOR_ESTADO}%-15s${NC}\n" \
                "$INDEX" "$USUARIO" "$CLAVE" "$FECHA_FORMAT" "$DURACION" "$ESTADO"
        fi
        ((INDEX++))
    done
    echo -e "${CIAN}==========================================================================${NC}"
    echo

    read -p "$(echo -e ${AMARILLO}Digite el número del usuario: ${NC})" NUM
    USUARIO_LINEA="${LINEAS[$((NUM-1))]}"
    IFS=$'\t' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL <<< "$USUARIO_LINEA"

    if [[ -z "$USUARIO" || ! $(id -u "$USUARIO" 2>/dev/null) ]]; then
        echo -e "${ROJO}Número inválido o el usuario ya no existe en el sistema.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    ESTADO=$(grep "^$USUARIO:" /etc/shadow | cut -d: -f2)
    if [[ $ESTADO == "!"* ]]; then
        echo -e "${AMARILLO}El usuario '$USUARIO' está BLOQUEADO.${NC}"
        ACCION="desbloquear"
        ACCION_VERBO="Desbloquear"
    else
        echo -e "${AMARILLO}El usuario '$USUARIO' está DESBLOQUEADO.${NC}"
        ACCION="bloquear"
        ACCION_VERBO="Bloquear"
    fi

    echo -e "${AMARILLO}¿Desea $ACCION al usuario '$USUARIO'? (s/n)${NC}"
    read -p "" CONFIRMAR
    if [[ $CONFIRMAR != "s" && $CONFIRMAR != "S" ]]; then
        echo -e "${AZUL}Operación cancelada.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    if [[ $ACCION == "bloquear" ]]; then
        usermod -L "$USUARIO"
        pkill -u "$USUARIO" sshd
        sed -i "/^$USUARIO\t/ s/\t[^\t]*$/\tSÍ/" "$REGISTROS"
        echo -e "${VERDE}Usuario '$USUARIO' bloqueado exitosamente y sesiones SSH terminadas.${NC}"
    else
        usermod -U "$USUARIO"
        sed -i "/^$USUARIO\t/ s/\t[^\t]*$/\tNO/" "$REGISTROS"
        echo -e "${VERDE}Usuario '$USUARIO' desbloqueado exitosamente.${NC}"
    fi

    read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
}

function mini_registro() {
    clear
    echo -e "${VIOLETA}===== MINI REGISTRO =====${NC}"

    if [[ ! -f $REGISTROS ]]; then
        echo -e "${ROJO}No hay registros de usuarios.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    printf "${AMARILLO}%-15s %-15s %-10s %-10s${NC}\n" "nombre" "contraseña" "días" "móviles"
    echo -e "${CIAN}--------------------------------------------${NC}"
    while IFS=$'\t' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL; do
        if id "$USUARIO" &>/dev/null; then
            # Extraer el número de días de DURACION
            DIAS=$(echo "$DURACION" | grep -oE '[0-9]+')
            # Extraer el número de móviles de MOVILES
            MOVILES_NUM=$(echo "$MOVILES" | grep -oE '[0-9]+')
            printf "${VERDE}%-15s %-15s %-10s %-10s${NC}\n" "$USUARIO" "$CLAVE" "$DIAS" "$MOVILES_NUM"
        fi
    done < "$REGISTROS"
    echo -e "${CIAN}============================================${NC}"
    read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
}

while true; do
    clear
    barra_sistema
    echo
    echo -e "${VIOLETA}====== PANEL DE USUARIOS VPN/SSH ======${NC}"
    echo -e "${VERDE}1. Crear usuario${NC}"
    echo -e "${VERDE}2. Ver registros${NC}"
    echo -e "${VERDE}3. Eliminar usuario${NC}"
    echo -e "${VERDE}4. Eliminar TODOS los usuarios${NC}"
    echo -e "${VERDE}5. Verificar usuarios online${NC}"
    echo -e "${VERDE}6. Bloquear/Desbloquear usuario${NC}"
    echo -e "${VERDE}7. Crear múltiples usuarios${NC}"
    echo -e "${VERDE}8. Mini registro${NC}"
    echo -e "${VERDE}9. Salir${NC}"
    PROMPT=$(echo -e "${AMARILLO}Selecciona una opción: ${NC}")
    read -p "$PROMPT" OPCION
    case $OPCION in
        1) crear_usuario ;;
        2) ver_registros ;;
        3) eliminar_usuario ;;
        4) eliminar_todos_usuarios ;;
        5) verificar_online ;;
        6) bloquear_desbloquear_usuario ;;
        7) crear_multiples_usuarios ;;
        8) mini_registro ;;
        9) echo -e "${AZUL}Saliendo...${NC}"; exit 0 ;;
        *) echo -e "${ROJO}¡Opción inválida!${NC}"; read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})" ;;
    esac
done

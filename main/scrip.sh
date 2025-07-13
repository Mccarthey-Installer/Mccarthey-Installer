#!/bin/bash
export TZ="America/El_Salvador"
export LANG=es_ES.UTF-8
timedatectl set-timezone America/El_Salvador

REGISTROS="/root/registros.txt"
HISTORIAL="/root/historial_conexiones.txt"
HISTORIAL_BLOQUEOS="/root/historial_bloqueos.txt"
PIDFILE="/var/run/monitorear_conexiones.pid"
LIMITADOR_FILE="/root/limitador_estado.txt"

# Inicializar el estado del limitador si el archivo no existe
if [[ ! -f "$LIMITADOR_FILE" ]]; then
    echo "ACTIVADO" > "$LIMITADOR_FILE"
fi
LIMITADOR_ESTADO=$(cat "$LIMITADOR_FILE" 2>/dev/null)

VIOLETA='\033[38;5;141m'
VERDE='\033[38;5;42m'
AMARILLO='\033[38;5;220m'
AZUL='\033[38;5;39m'
ROJO='\033[38;5;196m'
CIAN='\033[38;5;51m'
ROSADO='\033[38;5;218m'
LILA='\033[38;5;135m'
TURQUESA='\033[38;5;45m'
FUCHSIA='\033[38;2;255;0;255m'
AMARILLO_SUAVE='\033[38;2;255;204;0m'
ROSA='\033[38;2;255;105;180m'
ROSA_CLARO='\033[1;95m'
NC='\033[0m'

# Función para configurar la autoejecución en ~/.bashrc
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

configurar_autoejecucion

# Función para monitorear conexiones y actualizar PRIMER_LOGIN y el historial

function monitorear_conexiones() {
    LOG="/var/log/monitoreo_conexiones.log"
    INTERVALO=10

    # Verificar si el comando 'ss' está disponible
    if ! command -v ss >/dev/null 2>&1; then
        echo "$(date '+%Y-%m-%d %H:%M:%S'): Comando 'ss' no disponible, no se pueden verificar conexiones fantasmas." >> "$LOG"
    fi

    while true; do
        LIMITADOR_ESTADO=$(cat "$LIMITADOR_FILE" 2>/dev/null)  # Recargar estado en cada iteración
        if [[ ! -f $REGISTROS ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S'): El archivo de registros '$REGISTROS' no existe." >> "$LOG"
            sleep "$INTERVALO"
            continue
        fi

        TEMP_FILE=$(mktemp)
        cp "$REGISTROS" "$TEMP_FILE"
        > "$TEMP_FILE.new"

        while IFS=$'\t' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL PRIMER_LOGIN; do
            if id "$USUARIO" &>/dev/null; then
                # === LIMPIEZA DE PROCESOS ZOMBIE ===
                ps -u "$USUARIO" -o pid= -o stat= | awk '$2 ~ /^[Zz]/ {print $1}' | while read -r PID; do
                    kill -9 "$PID" 2>/dev/null
                    echo "$(date '+%Y-%m-%d %H:%M:%S'): Proceso zombi (PID: $PID) de usuario $USUARIO eliminado." >> "$LOG"
                done

                # === LIMPIEZA DE PROCESOS COLGADOS (estado D) ===
                ps -u "$USUARIO" -o pid= -o stat= -o comm= | awk '$3 ~ /^(sshd|dropbear)$/ && $2 ~ /^D/ {print $1}' | while read -r PID; do
                    kill -9 "$PID" 2>/dev/null
                    echo "$(date '+%Y-%m-%d %H:%M:%S'): Proceso colgado en estado D (PID: $PID, sshd/dropbear) de usuario $USUARIO eliminado." >> "$LOG"
                done

                # === LIMPIEZA DE CONEXIONES FANTASMAS (estado S, sin conexión de red) ===
                if command -v ss >/dev/null 2>&1; then
                    ps -u "$USUARIO" -o pid= -o stat= -o comm= | awk '$3 ~ /^(sshd|dropbear)$/ && $2 ~ /^S/ {print $1}' | while read -r PID; do
                        if ! ss -tpn 2>/dev/null | grep -q "pid=$PID,"; then
                            kill -9 "$PID" 2>/dev/null
                            echo "$(date '+%Y-%m-%d %H:%M:%S'): Conexión fantasma (PID: $PID, sshd/dropbear, estado S) de usuario $USUARIO eliminada." >> "$LOG"
                        fi
                    done
                fi

                # === LIMPIEZA DE PROCESOS DETENIDOS/PAUSADOS (estado T) ===
                ps -u "$USUARIO" -o pid= -o stat= -o comm= | awk '$3 ~ /^(sshd|dropbear)$/ && $2 ~ /^T/ {print $1}' | while read -r PID; do
                    kill -9 "$PID" 2>/dev/null
                    echo "$(date '+%Y-%m-%d %H:%M:%S'): Proceso detenido (estado T, PID: $PID, sshd/dropbear) de usuario $USUARIO eliminado." >> "$LOG"
                done

                # Limpieza de otros procesos detenidos (no sshd/dropbear)
                ps -u "$USUARIO" -o pid= -o stat= -o comm= | awk '$2 ~ /^T/ && $3 !~ /^(sshd|dropbear)$/ {print $1}' | while read -r PID; do
                    kill -9 "$PID" 2>/dev/null
                    echo "$(date '+%Y-%m-%d %H:%M:%S'): Proceso detenido (estado T, PID: $PID, no sshd/dropbear) de usuario $USUARIO eliminado." >> "$LOG"
                done

                # === LIMPIEZA DE OTROS PROCESOS NO DESEADOS (estados S o R, no sshd/dropbear) ===
                ps -u "$USUARIO" -o pid= -o stat= -o comm= | awk '$2 ~ /^[SR]/ && $3 !~ /^(sshd|dropbear)$/ {print $1}' | while read -r PID; do
                    kill -9 "$PID" 2>/dev/null
                    echo "$(date '+%Y-%m-%d %H:%M:%S'): Proceso no deseado (PID: $PID, estado $2, no sshd/dropbear) de usuario $USUARIO eliminado." >> "$LOG"
                done

                # === CONTAR CONEXIONES ===
                CONEXIONES_SSH=$(ps -u "$USUARIO" -o comm= | grep -c "^sshd$")
                CONEXIONES_DROPBEAR=$(ps -u "$USUARIO" -o comm= | grep -c "^dropbear$")
                CONEXIONES=$((CONEXIONES_SSH + CONEXIONES_DROPBEAR))

                # Extraer número de móviles permitido
                MOVILES_NUM=$(echo "$MOVILES" | grep -oE '[0-9]+' || echo "1")

                # Verificar si el usuario está bloqueado en /etc/shadow
                ESTA_BLOQUEADO=$(grep "^$USUARIO:!" /etc/shadow)

                # === BLOQUEO/DESBLOQUEO AUTOMÁTICO MEJORADO ===
                if [[ "$BLOQUEO_MANUAL" != "SÍ" && "$LIMITADOR_ESTADO" == "ACTIVADO" ]]; then
                    # Bloqueo automático si excede el límite
                    if [[ $CONEXIONES -gt $MOVILES_NUM ]]; then
                        if [[ -z "$ESTA_BLOQUEADO" ]]; then
                            usermod -L "$USUARIO"
                            pkill -KILL -u "$USUARIO"
                            BLOQUEO_MANUAL="NO"
                            FECHA_BLOQUEO=$(date +"%Y-%m-%d %I:%M %p")
                            echo "$USUARIO|$FECHA_BLOQUEO|$MOVILES_NUM|$CONEXIONES|Bloqueado" >> "$HISTORIAL_BLOQUEOS"
                            echo "$(date '+%Y-%m-%d %H:%M:%S'): Usuario '$USUARIO' bloqueado automáticamente por exceder el límite ($CONEXIONES > $MOVILES_NUM)." >> "$LOG"
                        fi
                    fi

                    # Desbloqueo automático si está bloqueado y está dentro del límite
                    if [[ $CONEXIONES -le $MOVILES_NUM && -n "$ESTA_BLOQUEADO" ]]; then
                        usermod -U "$USUARIO"
                        FECHA_DESBLOQUEO=$(date +"%Y-%m-%d %I:%M %p")
                        BLOQUEO_MANUAL="NO"
                        if [[ -f "$HISTORIAL_BLOQUEOS" ]]; then
                            ULTIMA_LINEA=$(grep "^$USUARIO|" "$HISTORIAL_BLOQUEOS" | tail -1)
                            if [[ -n "$ULTIMA_LINEA" && $(echo "$ULTIMA_LINEA" | awk -F'|' '{print $5}') == "Bloqueado" ]]; then
                                sed -i "/^${USUARIO}|.*|Bloqueado$/ s/$/|$FECHA_DESBLOQUEO|Desbloqueado/" "$HISTORIAL_BLOQUEOS"
                            else
                                echo "$USUARIO|$FECHA_BLOQUEO|$MOVILES_NUM|$CONEXIONES|Desbloqueado|$FECHA_DESBLOQUEO" >> "$HISTORIAL_BLOQUEOS"
                            fi
                        fi
                        echo "$(date '+%Y-%m-%d %H:%M:%S'): Usuario '$USUARIO' desbloqueado automáticamente al cumplir el límite ($CONEXIONES <= $MOVILES_NUM)." >> "$LOG"
                    fi

                    # Desbloqueo de emergencia si no hay conexiones activas y sigue bloqueado
                    if [[ $CONEXIONES -eq 0 && -n "$ESTA_BLOQUEADO" ]]; then
                        usermod -U "$USUARIO"
                        FECHA_DESBLOQUEO=$(date +"%Y-%m-%d %I:%M %p")
                        BLOQUEO_MANUAL="NO"
                        if [[ -f "$HISTORIAL_BLOQUEOS" ]]; then
                            ULTIMA_LINEA=$(grep "^$USUARIO|" "$HISTORIAL_BLOQUEOS" | tail -1)
                            if [[ -n "$ULTIMA_LINEA" && $(echo "$ULTIMA_LINEA" | awk -F'|' '{print $5}') == "Bloqueado" ]]; then
                                sed -i "/^${USUARIO}|.*|Bloqueado$/ s/$/|$FECHA_DESBLOQUEO|Desbloqueado/" "$HISTORIAL_BLOQUEOS"
                            else
                                echo "$USUARIO|$FECHA_BLOQUEO|$MOVILES_NUM|$CONEXIONES|Desbloqueado|$FECHA_DESBLOQUEO" >> "$HISTORIAL_BLOQUEOS"
                            fi
                        fi
                        echo "$(date '+%Y-%m-%d %H:%M:%S'): Usuario '$USUARIO' desbloqueado de emergencia (sin conexiones activas)." >> "$LOG"
                    fi
                fi

                # === ACTUALIZAR PRIMER_LOGIN ===
                NEW_PRIMER_LOGIN="$PRIMER_LOGIN"
                if [[ $CONEXIONES -gt 0 && -z "$PRIMER_LOGIN" ]]; then
                    NEW_PRIMER_LOGIN=$(date +"%Y-%m-%d %H:%M:%S")
                elif [[ $CONEXIONES -eq 0 && -n "$PRIMER_LOGIN" ]]; then
                    NEW_PRIMER_LOGIN=""
                fi

                echo -e "$USUARIO\t$CLAVE\t$EXPIRA_DATETIME\t$DURACION\t$MOVILES\t$BLOQUEO_MANUAL\t$NEW_PRIMER_LOGIN" >> "$TEMP_FILE.new"
            else
                # Usuario no existe en sistema, copia línea igual
                echo -e "$USUARIO\t$CLAVE\t$EXPIRA_DATETIME\t$DURACION\t$MOVILES\t$BLOQUEO_MANUAL\t$PRIMER_LOGIN" >> "$TEMP_FILE.new"
            fi
        done < "$TEMP_FILE"

        mv "$TEMP_FILE.new" "$REGISTROS"
        rm -f "$TEMP_FILE"

        # === REGISTRO DE HISTORIAL DE CONEXIONES ===
        while IFS=$'\t' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL PRIMER_LOGIN; do
            TMP_STATUS="/tmp/status_${USUARIO}.tmp"
            CONEXIONES_SSH=$(ps -u "$USUARIO" -o comm= | grep -c "^sshd$")
            CONEXIONES_DROPBEAR=$(ps -u "$USUARIO" -o comm= | grep -c "^dropbear$")
            CONEXIONES=$((CONEXIONES_SSH + CONEXIONES_DROPBEAR))

            if [[ $CONEXIONES -gt 0 ]]; then
                if [[ ! -f $TMP_STATUS ]]; then
                    date +"%Y-%m-%d %H:%M:%S" > "$TMP_STATUS"
                fi
            else
                if [[ -f $TMP_STATUS ]]; then
                    HORA_CONEXION=$(cat "$TMP_STATUS")
                    HORA_DESCONECCION=$(date +"%Y-%m-%d %H:%M:%S")
                    SEC_CON=$(date -d "$HORA_CONEXION" +%s)
                    SEC_DES=$(date -d "$HORA_DESCONECCION" +%s)
                    DURACION_SEC=$((SEC_DES - SEC_CON))
                    HORAS=$((DURACION_SEC / 3600))
                    MINUTOS=$(( (DURACION_SEC % 3600) / 60 ))
                    SEGUNDOS=$((DURACION_SEC % 60))
                    DURACION_FORMAT=$(printf "%02d:%02d:%02d" $HORAS $MINUTOS $SEGUNDOS)
                    echo "$USUARIO|$HORA_CONEXION|$HORA_DESCONECCION|$DURACION_FORMAT" >> "$HISTORIAL"
                    rm -f "$TMP_STATUS"
                fi
            fi
        done < "$REGISTROS"

        sleep "$INTERVALO"
    done
}


# Iniciar monitoreo de conexiones con nohup si no está corriendo
if [[ ! -f "$PIDFILE" ]] || ! ps -p $(cat "$PIDFILE") >/dev/null 2>&1; then
    rm -f "$PIDFILE"
    nohup bash -c "source $0; monitorear_conexiones" >> /var/log/monitoreo_conexiones.log 2>&1 &
    sleep 1
    if ps -p $! >/dev/null 2>&1; then
        echo $! > "$PIDFILE"
        echo -e "${VERDE}🚀 Monitoreo iniciado en segundo plano (PID: $!).${NC}"
    else
        echo -e "${ROJO}❌ Error al iniciar el monitoreo. Revisa /var/log/monitoreo_conexiones.log.${NC}"
    fi
else
    echo -e "${AMARILLO}⚠️ Monitoreo ya está corriendo (PID: $(cat "$PIDFILE")).${NC}"
fi

function barra_sistema() {
    MEM_TOTAL=$(free -m | awk '/^Mem:/ {print $2}')
    MEM_USO=$(free -m | awk '/^Mem:/ {print $3}')
    MEM_LIBRE=$(free -m | awk '/^Mem:/ {print $4}')
    MEM_DISPONIBLE=$(free -m | awk '/^Mem:/ {print $7}')
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

    FECHA_ACTUAL=$(date +"%Y-%m-%d %I:%M %p")

    TOTAL_CONEXIONES=0
    TOTAL_USUARIOS=0
    if [[ -f $REGISTROS ]]; then
        while IFS=$'\t' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL PRIMER_LOGIN; do
            if id "$USUARIO" &>/dev/null; then
                CONEXIONES_SSH=$(ps -u "$USUARIO" -o comm= | grep -c "^sshd$")
                CONEXIONES_DROPBEAR=$(ps -u "$USUARIO" -o comm= | grep -c "^dropbear$")
                CONEXIONES=$((CONEXIONES_SSH + CONEXIONES_DROPBEAR))
                TOTAL_CONEXIONES=$((TOTAL_CONEXIONES + CONEXIONES))
                ((TOTAL_USUARIOS++))
            fi
        done < "$REGISTROS"
    fi

    if [[ -f /etc/os-release ]]; then
        SO_NAME=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2- | tr -d '"')
    else
        SO_NAME=$(uname -o)
    fi

    LIMITADOR_ESTADO=$(cat "$LIMITADOR_FILE" 2>/dev/null)
    if [[ "$LIMITADOR_ESTADO" == "ACTIVADO" ]]; then
        LIMITADOR_DISPLAY="${VERDE}ACTIVADO${NC}"
    else
        LIMITADOR_DISPLAY="${ROJO}DESACTIVADO${NC}"
    fi

    echo -e "${CIAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e " 🖥️ TOTAL: ${AMARILLO}${MEM_TOTAL_H}${NC} ∘ M|DISPONIBLE: ${AMARILLO}${MEM_DISPONIBLE_H}${NC} ∘ EN USO: ${AMARILLO}${MEM_USO_H}${NC}"
    echo -e " 🖥️ U/RAM: ${AMARILLO}${MEM_PORC}%${NC} ∘ U/CPU: ${AMARILLO}${CPU_PORC}%${NC} ∘ CPU MHz: ${AMARILLO}${CPU_MHZ}${NC}"
    echo -e "${CIAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e " 🌐 IP: ${AMARILLO}${IP_PUBLICA}${NC} ∘ 📅 FECHA: ${AMARILLO}${FECHA_ACTUAL}${NC}"
    echo -e "🥂 ${CIAN}𝐌𝐜𝐜𝐚𝐫𝐭𝐡𝐞𝐲${NC}"
    echo -e "ONLINE:${AMARILLO}${TOTAL_CONEXIONES}${NC}   TOTAL:${AMARILLO}${TOTAL_USUARIOS}${NC}   SO:${AMARILLO}${SO_NAME}${NC}"
    echo -e "LIMITADOR: ${LIMITADOR_DISPLAY}"
    echo -e "${CIAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

function informacion_usuarios() {
    clear
    echo -e "${ROSADO}🌸✨ INFORMACIÓN DE CONEXIONES 💖✨🌸${NC}"
    if [[ ! -f $HISTORIAL ]]; then
        echo -e "${LILA}😿 ¡Oh no! No hay historial de conexiones aún, pequeña! 💔${NC}"
        read -p "$(echo -e ${TURQUESA}Presiona Enter para seguir, corazón... 💌${NC})"
        return
    fi

    printf "${LILA}%-15s %-22s %-22s %-12s${NC}\n" "👩‍💼 Usuaria" "🌷 Conectada" "🌙 Desconectada" "⏰ Duración"
    echo -e "${ROSADO}~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~${NC}"

    tac "$HISTORIAL" | awk -F'|' '!v[$1]++' | tac | while IFS='|' read -r USUARIO CONECTO DESCONECTO DURACION; do
        CONECTO_FMT=$(date -d "$CONECTO" +"%d/%B %I:%M %p" 2>/dev/null | \
            sed 's/January/enero/;s/February/febrero/;s/March/marzo/;s/April/abril/;s/May/mayo/;s/June/junio/;s/July/julio/;s/August/agosto/;s/September/septiembre/;s/October/octubre/;s/November/noviembre/;s/December/diciembre/' || echo "$CONECTO")
        DESCONECTO_FMT=$(date -d "$DESCONECTO" +"%d/%B %I:%M %p" 2>/dev/null | \
            sed 's/January/enero/;s/February/febrero/;s/March/marzo/;s/April/abril/;s/May/mayo/;s/June/junio/;s/July/julio/;s/August/agosto/;s/September/septiembre/;s/October/octubre/;s/November/noviembre/;s/December/diciembre/' || echo "$DESCONECTO")
        printf "${TURQUESA}%-15s %-22s %-22s %-12s${NC}\n" "$USUARIO" "$CONECTO_FMT" "$DESCONECTO_FMT" "$DURACION"
    done

    echo -e "${ROSADO}~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~${NC}"
    read -p "$(echo -e ${LILA}Presiona Enter para continuar, dulce... 🌟${NC})"
}

function crear_usuario() {
    clear
    echo -e "${VIOLETA}===== 🆕 CREAR USUARIO SSH =====${NC}"
    read -p "$(echo -e ${AMARILLO}👤 Nombre del usuario: ${NC})" USUARIO
    read -p "$(echo -e ${AMARILLO}🔑 Contraseña: ${NC})" CLAVE
    read -p "$(echo -e ${AMARILLO}📅 Días de validez: ${NC})" DIAS

    while true; do
        read -p "$(echo -e ${AMARILLO}📱 ¿Cuántos móviles? ${NC})" MOVILES
        if [[ "$MOVILES" =~ ^[1-9][0-9]{0,2}$ ]] && [ "$MOVILES" -le 999 ]; then
            break
        else
            echo -e "${ROJO}Por favor, ingresa un número del 1 al 999.${NC}"
        fi
    done

    # Validar que usuario no exista ni en sistema ni en registros
    if id "$USUARIO" &>/dev/null || grep -qP "^$USUARIO\t" "$REGISTROS"; then
        echo -e "${ROJO}👤 El usuario '$USUARIO' ya existe en el sistema o en los registros. No se puede crear.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    useradd -m -s /bin/bash "$USUARIO"
    echo "$USUARIO:$CLAVE" | chpasswd

    EXPIRA_DATETIME=$(date -d "+$DIAS days" +"%Y-%m-%d %H:%M:%S")
    EXPIRA_FECHA=$(date -d "+$((DIAS + 1)) days" +"%Y-%m-%d")
    usermod -e "$EXPIRA_FECHA" "$USUARIO"

    echo -e "$USUARIO\t$CLAVE\t$EXPIRA_DATETIME\t${DIAS} días\t$MOVILES móviles\tNO\t" >> "$REGISTROS"
    echo

    FECHA_FORMAT=$(date -d "$EXPIRA_DATETIME" +"%Y/%B/%d" | awk '{print $1 "/" tolower($2) "/" $3}')
    echo -e "${VERDE}✅ Usuario creado exitosamente:${NC}"
    echo -e "${AZUL}👤 Usuario: ${AMARILLO}$USUARIO${NC}"
    echo -e "${AZUL}🔑 Clave: ${AMARILLO}$CLAVE${NC}"
    echo -e "${AZUL}📅 Expira: ${AMARILLO}$FECHA_FORMAT${NC}"
    echo -e "${AZUL}📱 Móviles permitidos: ${AMARILLO}$MOVILES${NC}"
    echo

    echo -e "${CIAN}===== 📝 REGISTRO CREADO =====${NC}"
    printf "${AMARILLO}%-15s %-15s %-20s %-15s %-15s${NC}\n" "👤 Usuario" "🔑 Clave" "📅 Expira" "⏳ Duración" "📱 Móviles"
    echo -e "${CIAN}---------------------------------------------------------------${NC}"
    printf "${VERDE}%-15s %-15s %-20s %-15s %-15s${NC}\n" "$USUARIO" "$CLAVE" "$FECHA_FORMAT" "${DIAS} días" "$MOVILES"
    echo -e "${CIAN}===============================================================${NC}"
    read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
}

function crear_multiples_usuarios() {
    clear
    echo -e "${VIOLETA}===== 🆕 CREAR MÚLTIPLES USUARIOS SSH =====${NC}"
    echo -e "${AMARILLO}📝 Formato: nombre contraseña días móviles \(separados por espacios, una línea por usuario\)${NC}"
    echo -e "${AMARILLO}📋 Ejemplo: juan 123 5 4${NC}"
    echo -e "${AMARILLO}✅ Presiona Enter dos veces para confirmar.${NC}"
    echo

    declare -a USUARIOS
    while IFS= read -r LINEA; do
        [[ -z "$LINEA" ]] && break
        USUARIOS+=("$LINEA")
    done

    if [[ ${#USUARIOS[@]} -eq 0 ]]; then
        echo -e "${ROJO}❌ No se ingresaron usuarios.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

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

    ERROR_LOG="/tmp/creacion_usuarios_$(date +%Y%m%d_%H%M%S).log"
    touch "$ERROR_LOG" || {
        echo -e "${ROJO}❌ No se pudo crear el archivo de log. Continuando sin registro de errores.${NC}"
        ERROR_LOG=""
    }

    EXITOS=0
    FALLOS=0

    for LINEA in "${USUARIOS[@]}"; do
        read -r USUARIO CLAVE DIAS MOVILES <<< "$LINEA"
        if [[ -z "$USUARIO" || -z "$CLAVE" || -z "$DIAS" || -z "$MOVILES" ]]; then
            echo -e "${ROJO}❌ Datos incompletos: $LINEA${NC}"
            [[ -n "$ERROR_LOG" ]] && echo "$(date): Datos incompletos: $LINEA" >> "$ERROR_LOG"
            ((FALLOS++))
            continue
        fi

        if ! [[ "$DIAS" =~ ^[0-9]+$ ]] || ! [[ "$MOVILES" =~ ^[1-9][0-9]{0,2}$ ]] || [ "$MOVILES" -gt 999 ]; then
            echo -e "${ROJO}❌ Datos inválidos para $USUARIO (Días: $DIAS, Móviles: $MOVILES).${NC}"
            [[ -n "$ERROR_LOG" ]] && echo "$(date): Datos inválidos para $USUARIO (Días: $DIAS, Móviles: $MOVILES)" >> "$ERROR_LOG"
            ((FALLOS++))
            continue
        fi

        # Validar que usuario no exista ni en sistema ni en registros
        if id "$USUARIO" &>/dev/null || grep -qP "^$USUARIO\t" "$REGISTROS"; then
            echo -e "${ROJO}👤 El usuario '$USUARIO' ya existe en el sistema o en los registros. No se puede crear.${NC}"
            [[ -n "$ERROR_LOG" ]] && echo "$(date): Usuario '$USUARIO' ya existe" >> "$ERROR_LOG"
            ((FALLOS++))
            continue
        fi

        useradd -m -s /bin/bash "$USUARIO" 2>>"$ERROR_LOG"
        if [[ $? -ne 0 ]]; then
            echo -e "${ROJO}❌ Error creando usuario $USUARIO. Revisa $ERROR_LOG para más detalles.${NC}"
            ((FALLOS++))
            continue
        fi

        echo "$USUARIO:$CLAVE" | chpasswd 2>>"$ERROR_LOG"
        if [[ $? -ne 0 ]]; then
            echo -e "${ROJO}❌ Error estableciendo la contraseña para $USUARIO. Eliminando usuario...${NC}"
            userdel -r "$USUARIO" 2>/dev/null
            [[ -n "$ERROR_LOG" ]] && echo "$(date): Error estableciendo contraseña para $USUARIO" >> "$ERROR_LOG"
            ((FALLOS++))
            continue
        fi

        EXPIRA_DATETIME=$(date -d "+$DIAS days" +"%Y-%m-%d %H:%M:%S")
        EXPIRA_FECHA=$(date -d "+$((DIAS + 1)) days" +"%Y-%m-%d")
        usermod -e "$EXPIRA_FECHA" "$USUARIO" 2>>"$ERROR_LOG"
        if [[ $? -ne 0 ]]; then
            echo -e "${ROJO}❌ Error configurando la expiración para $USUARIO. Eliminando usuario...${NC}"
            userdel -r "$USUARIO" 2>/dev/null
            [[ -n "$ERROR_LOG" ]] && echo "$(date): Error configurando expiración para $USUARIO" >> "$ERROR_LOG"
            ((FALLOS++))
            continue
        fi

        echo -e "$USUARIO\t$CLAVE\t$EXPIRA_DATETIME\t${DIAS} días\t$MOVILES móviles\tNO\t" >> "$REGISTROS" 2>>"$ERROR_LOG"
        if [[ $? -ne 0 ]]; then
            echo -e "${ROJO}❌ Error escribiendo en el archivo de registros para $USUARIO. Eliminando usuario...${NC}"
            userdel -r "$USUARIO" 2>/dev/null
            [[ -n "$ERROR_LOG" ]] && echo "$(date): Error escribiendo en registros para $USUARIO" >> "$ERROR_LOG"
            ((FALLOS++))
            continue
        fi

        echo -e "${VERDE}✅ Usuario $USUARIO creado exitosamente.${NC}"
        ((EXITOS++))
    done

    echo -e "${CIAN}===== 📊 RESUMEN DE CREACIÓN =====${NC}"
    echo -e "${VERDE}✅ Usuarios creados exitosamente: $EXITOS${NC}"
    echo -e "${ROJO}❌ Usuarios con error: $FALLOS${NC}"
    [[ -n "$ERROR_LOG" && $FALLOS -gt 0 ]] && echo -e "${AMARILLO}📝 Log de errores: $ERROR_LOG${NC}"
    
    read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
}


function ver_registros() {
    clear
    echo -e "${VIOLETA}===== 📋 REGISTROS =====${NC}"

    center_value() {
        local value="$1"
        local width="$2"
        local len=${#value}
        local padding_left=$(( (width - len) / 2 ))
        local padding_right=$(( width - len - padding_left ))
        printf "%*s%s%*s" "$padding_left" "" "$value" "$padding_right" ""
    }

    if [[ -f $REGISTROS ]]; then
        printf "${AMARILLO}%-3s %-12s %-12s %-12s %10s %-12s${NC}\n" \
            "Nº" "👤 Usuario" "🔑 Clave" "📅 Expira" "$(center_value '⏳ Días' 10)" "📱 Móviles"
        echo -e "${CIAN}-----------------------------------------------------------------------${NC}"

        NUM=1
        while IFS=$'\t' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL PRIMER_LOGIN; do
            if id "$USUARIO" &>/dev/null; then
                FECHA_EXPIRA_DIA=$(date -d "$EXPIRA_DATETIME" +%Y-%m-%d 2>/dev/null)
                FECHA_ACTUAL_DIA=$(date +%Y-%m-%d)
                if [[ -n "$FECHA_EXPIRA_DIA" ]]; then
                    DIAS_RESTANTES=$(( ( $(date -d "$FECHA_EXPIRA_DIA" +%s) - $(date -d "$FECHA_ACTUAL_DIA" +%s) ) / 86400 ))
                    if (( DIAS_RESTANTES < 0 )); then
                        DIAS_RESTANTES=0
                        COLOR_DIAS="${ROJO}"
                    else
                        COLOR_DIAS="${NC}"
                    fi
                    FORMATO_EXPIRA=$(date -d "$EXPIRA_DATETIME" +"%d/%B" | awk '{print $1 "/" tolower($2)}')
                else
                    DIAS_RESTANTES="Inválido"
                    FORMATO_EXPIRA="Desconocido"
                    COLOR_DIAS="${ROJO}"
                fi

                DIAS_CENTRADO=$(center_value "$DIAS_RESTANTES" 10)

                printf "${VERDE}%-3d ${AMARILLO}%-12s %-12s %-12s ${COLOR_DIAS}%s${NC} ${AMARILLO}%-12s${NC}\n" \
                    "$NUM" "$USUARIO" "$CLAVE" "$FORMATO_EXPIRA" "$DIAS_CENTRADO" "$MOVILES"
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

function eliminar_usuario() {
    clear
    echo -e "${VIOLETA}===== 🗑️ ELIMINAR USUARIO =====${NC}"

    # 1. Verificar si hay registros
    if [[ ! -f $REGISTROS ]]; then
        echo -e "${ROJO}❌ No hay registros para eliminar. El archivo '$REGISTROS' no existe.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    # 2. Mostrar usuarios existentes y construir mapa de selección
    echo -e "${AMARILLO}Nº\t👤 Usuario${NC}"
    echo -e "${CIAN}--------------------------${NC}"
    NUM=1
    declare -A USUARIOS_DISPONIBLES # Almacena {numero: usuario}
    declare -A USUARIOS_VISTOS    # Para evitar duplicados si el REGISTROS tiene líneas repetidas

    # Leer el archivo de registros y mostrar solo usuarios únicos que existen en el sistema
    while IFS=$'\t' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL PRIMER_LOGIN; do
        # Asegurarse de que el usuario exista en el sistema y no haya sido mostrado ya
        if id "$USUARIO" &>/dev/null && [[ -z "${USUARIOS_VISTOS[$USUARIO]}" ]]; then
            echo -e "${VERDE}${NUM}\t${AMARILLO}$USUARIO${NC}"
            USUARIOS_DISPONIBLES[$NUM]="$USUARIO"
            USUARIOS_VISTOS[$USUARIO]="1" # Marca como visto
            NUM=$((NUM+1))
        fi
    done < "$REGISTROS"

    # 3. Validar si hay usuarios para eliminar
    if [[ ${#USUARIOS_DISPONIBLES[@]} -eq 0 ]]; then
        echo -e "${ROJO}❌ No hay usuarios activos en el sistema listados en los registros para eliminar.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    echo
    echo -e "${AMARILLO}🗑️ Ingrese los números de los usuarios a eliminar (separados por espacios)${NC}"
    PROMPT=$(echo -e "${AMARILLO}   (0 para cancelar): ${NC}")
    read -p "$PROMPT" INPUT_NUMEROS

    # 4. Manejar cancelación
    if [[ "$INPUT_NUMEROS" == "0" ]]; then
        echo -e "${AZUL}🚫 Operación cancelada por el usuario.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    # 5. Construir lista de usuarios a eliminar (filtrando inválidos)
    read -ra NUMEROS_SELECCIONADOS <<< "$INPUT_NUMEROS"
    declare -a USUARIOS_A_ELIMINAR_FINAL # Esta será la lista final sin duplicados y válidos
    declare -A USUARIOS_SELECCIONADOS_VISTOS # Para evitar añadir el mismo usuario dos veces si se ingresa su número repetido

    for NUMERO in "${NUMEROS_SELECCIONADOS[@]}"; do
        if [[ -n "${USUARIOS_DISPONIBLES[$NUMERO]}" ]]; then
            USUARIO_TEMP="${USUARIOS_DISPONIBLES[$NUMERO]}"
            # Asegurarse de que no se añada el mismo usuario dos veces
            if [[ -z "${USUARIOS_SELECCIONADOS_VISTOS[$USUARIO_TEMP]}" ]]; then
                USUARIOS_A_ELIMINAR_FINAL+=("$USUARIO_TEMP")
                USUARIOS_SELECCIONADOS_VISTOS[$USUARIO_TEMP]="1"
            fi
        else
            echo -e "${ROJO}❌ Número inválido o no disponible: $NUMERO. Ignorando.${NC}"
        fi
    done

    # 6. Validar si se seleccionaron usuarios válidos
    if [[ ${#USUARIOS_A_ELIMINAR_FINAL[@]} -eq 0 ]]; then
        echo -e "${ROJO}❌ No se seleccionaron usuarios válidos para eliminar.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    # 7. Confirmación final
    echo -e "${CIAN}\n===== 🗑️ USUARIOS SELECCIONADOS PARA ELIMINAR =====${NC}"
    echo -e "${AMARILLO}👤 Se eliminarán los siguientes usuarios:${NC}"
    for USUARIO in "${USUARIOS_A_ELIMINAR_FINAL[@]}"; do
        echo -e "${VERDE}  - $USUARIO${NC}"
    done
    echo -e "${CIAN}--------------------------------------------------${NC}"
    echo -e "${AMARILLO}✅ ¿Confirmar eliminación de estos usuarios? (s/n)${NC}"
    read -p "" CONFIRMAR
    if [[ "$CONFIRMAR" != "s" && "$CONFIRMAR" != "S" ]]; then
        echo -e "${AZUL}🚫 Operación de eliminación cancelada.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    # 8. Proceso de eliminación
    echo -e "${CIAN}\n===== INICIANDO ELIMINACIÓN DE USUARIOS =====${NC}"
    for USUARIO in "${USUARIOS_A_ELIMINAR_FINAL[@]}"; do
        echo -e "${AMARILLO}Procesando usuario: $USUARIO...${NC}"

        # Verificar si el usuario existe en el sistema antes de intentar cualquier operación
        if id "$USUARIO" &>/dev/null; then
            # Intentar matar procesos asociados al usuario
            PIDS=$(pgrep -u "$USUARIO")
            if [[ -n $PIDS ]]; then
                echo -e "${ROJO}  ⚠️ Procesos activos detectados para $USUARIO (${PIDS}). Intentando terminarlos...${NC}"
                # Usar 'pkill -u' para mayor robustez o un bucle para 'kill -9' si hay muchos PIDs
                pkill -9 -u "$USUARIO" &>/dev/null
                sleep 1 # Dar un momento para que los procesos terminen
                # Volver a verificar si quedan procesos
                if pgrep -u "$USUARIO" &>/dev/null; then
                    echo -e "${ROJO}  ❌ Algunos procesos de $USUARIO no pudieron ser terminados. Esto podría causar fallos.${NC}"
                else
                    echo -e "${VERDE}  ✅ Procesos de $USUARIO terminados exitosamente.${NC}"
                fi
            else
                echo -e "${VERDE}  ✅ No se encontraron procesos activos para $USUARIO.${NC}"
            fi

            # Eliminar el usuario del sistema
            if userdel -r "$USUARIO" 2>/dev/null; then
                echo -e "${VERDE}  ✅ Usuario '$USUARIO' eliminado del sistema exitosamente.${NC}"
                
                # Eliminar todas las líneas asociadas a este usuario de los archivos de registro
                # El 'sed -i' modifica el archivo en su lugar
                # La expresión '/^USUARIO\t/d' busca líneas que empiecen con el nombre de usuario seguido de un tabulador
                # Esto es crucial para limpiar todas las referencias, incluso si el REGISTROS tenía duplicados.
                sed -i "/^$USUARIO\t/d" "$REGISTROS" &>/dev/null # Elimina del registro principal
                sed -i "/^$USUARIO|/d" "$HISTORIAL" &>/dev/null # Elimina del historial (asumiendo separador '|')
                sed -i "/^$USUARIO|/d" "$HISTORIAL_BLOQUEOS" &>/dev/null # Elimina del historial de bloqueos

                echo -e "${VERDE}  ✅ Registros de '$USUARIO' limpiados en los archivos.${NC}"
            else
                echo -e "${ROJO}  ❌ Falló la eliminación del usuario '$USUARIO' del sistema. Puede que aún esté en uso o haya permisos insuficientes.${NC}"
            fi
        else
            echo -e "${AMARILLO}  ⚠️ El usuario '$USUARIO' ya no existe en el sistema. Limpiando solo registros...${NC}"
            sed -i "/^$USUARIO\t/d" "$REGISTROS" &>/dev/null
            sed -i "/^$USUARIO|/d" "$HISTORIAL" &>/dev/null
            sed -i "/^$USUARIO|/d" "$HISTORIAL_BLOQUEOS" &>/dev/null
            echo -e "${VERDE}  ✅ Registros de '$USUARIO' limpiados en los archivos.${NC}"
        fi
        echo -e "${CIAN}------------------------------------------${NC}"
    done

    echo -e "${VERDE}✅ Eliminación de usuarios finalizada.${NC}"
    read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
}

# 

function verificar_online() {
    clear
    echo -e "${VIOLETA}===== 🟢 USUARIOS ONLINE =====${NC}"

    declare -A month_map=(
        ["Jan"]="Enero" ["Feb"]="Febrero" ["Mar"]="Marzo" ["Apr"]="Abril"
        ["May"]="Mayo" ["Jun"]="Junio" ["Jul"]="Julio" ["Aug"]="Agosto"
        ["Sep"]="Septiembre" ["Oct"]="Octubre" ["Nov"]="Noviembre" ["Dec"]="Diciembre"
    )

    if [[ ! -f $REGISTROS ]]; then
        echo -e "${ROJO}❌ No hay registros de usuarios.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    printf "${AMARILLO}%-15s %-15s %-10s %-25s${NC}\n" "👤 USUARIO" "🟢 CONEXIONES" "📱 MÓVILES" "⏰ TIEMPO CONECTADO"
    echo -e "${CIAN}------------------------------------------------------------${NC}"

    TOTAL_CONEXIONES=0
    TOTAL_USUARIOS=0
    INACTIVOS=0

    while IFS=$'\t' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL PRIMER_LOGIN; do
        if id "$USUARIO" &>/dev/null; then
            ((TOTAL_USUARIOS++))
            ESTADO="0"
            DETALLES="Nunca conectado"
            COLOR_ESTADO="${ROJO}"
            MOVILES_NUM=$(echo "$MOVILES" | grep -oE '[0-9]+' || echo "1")

            if grep -q "^$USUARIO:!" /etc/shadow; then
                DETALLES="🔒 Usuario bloqueado"
                ((INACTIVOS++))
            else
                CONEXIONES_SSH=$(ps -u "$USUARIO" -o comm= | grep -c "^sshd$")
                CONEXIONES_DROPBEAR=$(ps -u "$USUARIO" -o comm= | grep -c "^dropbear$")
                CONEXIONES=$((CONEXIONES_SSH + CONEXIONES_DROPBEAR))
                if [[ $CONEXIONES -gt 0 ]]; then
                    ESTADO="🟢 $CONEXIONES"
                    COLOR_ESTADO="${VERDE}"
                    TOTAL_CONEXIONES=$((TOTAL_CONEXIONES + CONEXIONES))

                    if [[ -n "$PRIMER_LOGIN" ]]; then
                        START=$(date -d "$PRIMER_LOGIN" +%s 2>/dev/null)
                        if [[ $? -eq 0 && -n "$START" ]]; then
                            CURRENT=$(date +%s)
                            ELAPSED_SEC=$((CURRENT - START))
                            D=$((ELAPSED_SEC / 86400))
                            H=$(( (ELAPSED_SEC % 86400) / 3600 ))
                            M=$(( (ELAPSED_SEC % 3600) / 60 ))
                            S=$((ELAPSED_SEC % 60 ))
                            DETALLES=$(printf "⏰ %02d:%02d:%02d" $H $M $S)
                            if [[ $D -gt 0 ]]; then
                                DETALLES="$D días $DETALLES"
                            fi
                        else
                            DETALLES="⏰ Tiempo no disponible"
                        fi
                    else
                        DETALLES="⏰ Tiempo no disponible"
                    fi
                else
                    ULTIMO_LOGOUT=$(grep "^$USUARIO|" "$HISTORIAL" | tail -1 | awk -F'|' '{print $3}')
                    if [[ -n "$ULTIMO_LOGOUT" ]]; then
                        ULTIMO_LOGOUT_FMT=$(date -d "$ULTIMO_LOGOUT" +"%d de %B %I:%M %p" 2>/dev/null | \
                            sed 's/January/enero/;s/February/febrero/;s/March/marzo/;s/April/abril/;s/May/mayo/;s/June/junio/;s/July/julio/;s/August/agosto/;s/September/septiembre/;s/October/octubre/;s/November/noviembre/;s/December/diciembre/' || echo "$ULTIMO_LOGOUT")
                        DETALLES="📅 Última: $ULTIMO_LOGOUT_FMT"
                    else
                        DETALLES="Nunca conectado"
                    fi
                    ((INACTIVOS++))
                fi
            fi
            printf "${AMARILLO}%-15s ${COLOR_ESTADO}%-15s ${AMARILLO}%-10s ${AZUL}%-25s${NC}\n" "$USUARIO" "$ESTADO" "$MOVILES_NUM" "$DETALLES"
        fi
    done < "$REGISTROS"

    echo
    echo -e "${CIAN}Total de Online: ${AMARILLO}${TOTAL_CONEXIONES}${NC}  ${CIAN}Total usuarios: ${AMARILLO}${TOTAL_USUARIOS}${NC}  ${CIAN}Inactivos: ${AMARILLO}${INACTIVOS}${NC}"
    echo -e "${CIAN}================================================${NC}"
    read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
}

function bloquear_desbloquear_usuario() {
    clear
    echo -e "${VIOLETA}===== 🔒 BLOQUEAR/DESBLOQUEAR USUARIO =====${NC}"

    if [[ ! -f $REGISTROS ]]; then
        echo -e "${ROJO}❌ El archivo de registros '$REGISTROS' no existe. No hay usuarios registrados.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    echo -e "${CIAN}===== 📋 USUARIOS REGISTRADOS =====${NC}"
    printf "${AMARILLO}%-5s %-15s %-15s %-22s %-15s %-15s${NC}\n" "Nº" "👤 Usuario" "🔑 Clave" "📅 Expira" "⏳ Duración" "🔐 Estado"
    echo -e "${CIAN}--------------------------------------------------------------------------${NC}"
    mapfile -t LINEAS < "$REGISTROS"
    INDEX=1
    for LINEA in "${LINEAS[@]}"; do
        IFS=$'\t' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL PRIMER_LOGIN <<< "$LINEA"
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

    read -p "$(echo -e ${AMARILLO}👤 Digite el número del usuario: ${NC})" NUM
    USUARIO_LINEA="${LINEAS[$((NUM-1))]}"
    IFS=$'\t' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL PRIMER_LOGIN <<< "$USUARIO_LINEA"

    if [[ -z "$USUARIO" || ! $(id -u "$USUARIO" 2>/dev/null) ]]; then
        echo -e "${ROJO}❌ Número inválido o el usuario ya no existe en el sistema.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

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

    echo -e "${AMARILLO}✅ ¿Desea $ACCION al usuario '$USUARIO'? (s/n)${NC}"
    read -p "" CONFIRMAR
    if [[ $CONFIRMAR != "s" && $CONFIRMAR != "S" ]]; then
        echo -e "${AZUL}🚫 Operación cancelada.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    if [[ $ACCION == "bloquear" ]]; then
        usermod -L "$USUARIO"
        pkill -u "$USUARIO" sshd
        pkill -u "$USUARIO" dropbear
        sed -i "/^$USUARIO\t/ s/\t[^\t]*\t[^\t]*$/\tSÍ\t$PRIMER_LOGIN/" "$REGISTROS"
        echo -e "${VERDE}🔒 Usuario '$USUARIO' bloqueado exitosamente y sesiones SSH/Dropbear terminadas.${NC}"
    else
        usermod -U "$USUARIO"
        sed -i "/^$USUARIO\t/ s/\t[^\t]*\t[^\t]*$/\tNO\t$PRIMER_LOGIN/" "$REGISTROS"
        echo -e "${VERDE}🔓 Usuario '$USUARIO' desbloqueado exitosamente.${NC}"
    fi

    read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
}

function mini_registro() {
    clear
    echo -e "${VIOLETA}===== 📋 MINI REGISTRO =====${NC}"

    if [[ ! -f $REGISTROS ]]; then
        echo -e "${ROJO}❌ No hay registros de usuarios.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    printf "${AMARILLO}%-15s %-15s %-10s %-15s${NC}\n" "👤 Nombre" "🔑 Contraseña" "⏳ Días" "📱 Móviles"
    echo -e "${CIAN}--------------------------------------------${NC}"

    TOTAL_USUARIOS=0

    while IFS=$'\t' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL PRIMER_LOGIN; do
        if id "$USUARIO" &>/dev/null; then
            FECHA_EXPIRA_DIA=$(date -d "$EXPIRA_DATETIME" +%Y-%m-%d 2>/dev/null)
            FECHA_ACTUAL_DIA=$(date +%Y-%m-%d)
            if [[ -n "$FECHA_EXPIRA_DIA" ]]; then
                DIAS_RESTANTES=$(( ( $(date -d "$FECHA_EXPIRA_DIA" +%s) - $(date -d "$FECHA_ACTUAL_DIA" +%s) ) / 86400 ))
                if (( DIAS_RESTANTES < 0 )); then
                    DIAS_RESTANTES=0
                fi
            else
                DIAS_RESTANTES="Inválido"
            fi
            MOVILES_NUM=$(echo "$MOVILES" | grep -oE '[0-9]+' || echo "1")
            printf "${VERDE}%-15s %-15s %-10s %-15s${NC}\n" "$USUARIO" "$CLAVE" "$DIAS_RESTANTES" "$MOVILES_NUM"
            ((TOTAL_USUARIOS++))
        fi
    done < "$REGISTROS"

    echo -e "${CIAN}============================================${NC}\n"
    echo -e "${AMARILLO}TOTAL: $TOTAL_USUARIOS${NC}"
    read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
}

function alternar_limitador() {
    clear
    LIMITADOR_ESTADO=$(cat "$LIMITADOR_FILE" 2>/dev/null)
    echo -e "${VIOLETA}===== ⚙️ CONTROL DEL LIMITADOR DE CONEXIONES =====${NC}"
    echo -e "${AMARILLO}Estado actual del limitador: ${VERDE}$LIMITADOR_ESTADO${NC}"
    echo

    if [[ "$LIMITADOR_ESTADO" == "ACTIVADO" ]]; then
        echo -e "${AMARILLO}🔴 ¿Desea DESACTIVAR el limitador de conexiones? (s/n)${NC}"
        echo -e "${AZUL}Nota: Si se desactiva, los usuarios podrán exceder el límite de conexiones sin ser bloqueados.${NC}"
        read -p "$(echo -e "${ROSA}Confirmar (s/n): ${NC}")" CONFIRMAR
        if [[ "$CONFIRMAR" == "s" || "$CONFIRMAR" == "S" ]]; then
            echo "DESACTIVADO" > "$LIMITADOR_FILE"
            LIMITADOR_ESTADO="DESACTIVADO"
            echo -e "${VERDE}✅ Limitador DESACTIVADO. Los usuarios ahora pueden exceder el límite de conexiones.${NC}"
        else
            echo -e "${AZUL}🚫 Operación cancelada.${NC}"
        fi
    else
        echo -e "${AMARILLO}🟢 ¿Desea ACTIVAR el limitador de conexiones? (s/n)${NC}"
        echo -e "${AZUL}Nota: Si se activa, los usuarios que excedan el límite de conexiones serán bloqueados automáticamente.${NC}"
        read -p "$(echo -e "${ROSA}Confirmar (s/n): ${NC}")" CONFIRMAR
        if [[ "$CONFIRMAR" == "s" || "$CONFIRMAR" == "S" ]]; then
            echo "ACTIVADO" > "$LIMITADOR_FILE"
            LIMITADOR_ESTADO="ACTIVADO"
            echo -e "${VERDE}✅ Limitador ACTIVADO. Los usuarios que excedan el límite de conexiones serán bloqueados.${NC}"
        else
            echo -e "${AZUL}🚫 Operación cancelada.${NC}"
        fi
    fi

    read -p "$(echo -e "${AZUL}Presiona Enter para continuar...${NC}")"
}

function ver_historial_bloqueos() {
    clear
    echo -e "${VIOLETA}===== 📜 HISTORIAL DE BLOQUEOS =====${NC}"
    if [[ ! -f "$HISTORIAL_BLOQUEOS" ]]; then
        echo -e "${ROJO}❌ No hay historial de bloqueos aún.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    # Verificar permisos de lectura
    if [[ ! -r "$HISTORIAL_BLOQUEOS" ]]; then
        echo -e "${ROJO}❌ No se puede leer $HISTORIAL_BLOQUEOS. Verifica permisos.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    echo -e "${AMARILLO}📋 Eventos de bloqueo/desbloqueo:${NC}"
    echo -e "${CIAN}--------------------------------${NC}"

    # Filtrar duplicados, mostrando solo la última entrada por usuario
    tac "$HISTORIAL_BLOQUEOS" | awk -F'|' '!seen[$1]++' | tac | while IFS='|' read -r USUARIO FECHA_BLOQUEO MOVILES_PERMITIDOS CONEXIONES ESTADO FECHA_DESBLOQUEO; do
        if [[ -z "$USUARIO" || -z "$FECHA_BLOQUEO" || -z "$MOVILES_PERMITIDOS" || -z "$CONEXIONES" || -z "$ESTADO" ]]; then
            echo -e "${ROJO}⚠️ Línea corrupta: $USUARIO|$FECHA_BLOQUEO|$MOVILES_PERMITIDOS|$CONEXIONES|$ESTADO${NC}"
            continue
        fi

        # Formatear fechas con LC_TIME o fallback a inglés con traducción
        if locale -a 2>/dev/null | grep -qi "es_ES.utf8"; then
            FECHA_BLOQUEO_FMT=$(LC_TIME=es_ES.UTF-8 date -d "$FECHA_BLOQUEO" +"%d/%b %H:%M" 2>/dev/null || echo "$FECHA_BLOQUEO")
            [[ "$ESTADO" == "Desbloqueado" && -n "$FECHA_DESBLOQUEO" ]] && \
                FECHA_DESBLOQUEO_FMT=$(LC_TIME=es_ES.UTF-8 date -d "$FECHA_DESBLOQUEO" +"%d/%b %H:%M" 2>/dev/null || echo "$FECHA_DESBLOQUEO")
        else
            FECHA_BLOQUEO_FMT=$(date -d "$FECHA_BLOQUEO" +"%d/%b %H:%M" 2>/dev/null | \
                sed 's/Jan/ene/;s/Feb/feb/;s/Mar/mar/;s/Apr/abr/;s/May/may/;s/Jun/jun/;s/Jul/jul/;s/Aug/ago/;s/Sep/sep/;s/Oct/oct/;s/Nov/nov/;s/Dec/dic/' || echo "$FECHA_BLOQUEO")
            [[ "$ESTADO" == "Desbloqueado" && -n "$FECHA_DESBLOQUEO" ]] && \
                FECHA_DESBLOQUEO_FMT=$(date -d "$FECHA_DESBLOQUEO" +"%d/%b %H:%M" 2>/dev/null | \
                sed 's/Jan/ene/;s/Feb/feb/;s/Mar/mar/;s/Apr/abr/;s/May/may/;s/Jun/jun/;s/Jul/jul/;s/Aug/ago/;s/Sep/sep/;s/Oct/oct/;s/Nov/nov/;s/Dec/dic/' || echo "$FECHA_DESBLOQUEO")
        fi

        # Generar mensaje según estado
        if [[ "$ESTADO" == "Desbloqueado" && -n "$FECHA_DESBLOQUEO" ]]; then
            MENSAJE="🔓 $USUARIO desbloqueado $FECHA_DESBLOQUEO_FMT"
        elif [[ "$ESTADO" == "Bloqueado" ]]; then
            MENSAJE="🔒 $USUARIO bloqueado $FECHA_BLOQUEO_FMT ($CONEXIONES/$MOVILES_PERMITIDOS)"
        else
            echo -e "${ROJO}⚠️ Estado inválido: $ESTADO${NC}"
            continue
        fi

        echo -e "${VERDE}$MENSAJE${NC}"
    done

    echo -e "${CIAN}--------------------------------${NC}"
    read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
}

if [[ -t 0 ]]; then
    while true; do
        clear
        barra_sistema
        echo
        echo -e "${VIOLETA}====== 😇 PANEL DE USUARIOS VPN/SSH ======${NC}"
        echo -e "${AMARILLO_SUAVE}1. 🆕 Crear usuario${NC}"
        echo -e "${AMARILLO_SUAVE}2. 📋 Ver registros${NC}"
        echo -e "${AMARILLO_SUAVE}3. 🗑️ Eliminar usuario${NC}"
        echo -e "${AMARILLO_SUAVE}4. 📊 Información${NC}"
        echo -e "${AMARILLO_SUAVE}5. 🟢 Verificar usuarios online${NC}"
        echo -e "${AMARILLO_SUAVE}6. 🔒 Bloquear/Desbloquear usuario${NC}"
        echo -e "${AMARILLO_SUAVE}7. 🆕 Crear múltiples usuarios${NC}"
        echo -e "${AMARILLO_SUAVE}8. 📋 Mini registro${NC}"
        LIMITADOR_ESTADO=$(cat "$LIMITADOR_FILE" 2>/dev/null)
        if [[ "$LIMITADOR_ESTADO" == "ACTIVADO" ]]; then
            LIMITADOR_MENU="${VERDE}(ACTIVADO)${NC}"
        else
            LIMITADOR_MENU="${ROJO}(DESACTIVADO)${NC}"
        fi
        echo -e "${AMARILLO_SUAVE}9. ⚙️ Activar/Desactivar limitador ${NC}${LIMITADOR_MENU}"
        echo -e "${AMARILLO_SUAVE}10. 📜 Ver historial de bloqueos automáticos${NC}"
        echo -e "${AMARILLO_SUAVE}11. 🚪 Salir${NC}"
        PROMPT=$(echo -e "${ROSA}➡️ Selecciona una opción: ${NC}")
        read -p "$PROMPT" OPCION
        case $OPCION in
            1) crear_usuario ;;
            2) ver_registros ;;
            3) eliminar_usuario ;;
            4) informacion_usuarios ;;
            5) verificar_online ;;
            6) bloquear_desbloquear_usuario ;;
            7) crear_multiples_usuarios ;;
            8) mini_registro ;;
            9) alternar_limitador ;;
            10) ver_historial_bloqueos ;;
            11) echo -e "${ROSA_CLARO}🚪 Saliendo...${NC}"; exit 0 ;;
            *) echo -e "${ROJO}❌ ¡Opción inválida!${NC}"; read -p "$(echo -e ${ROSA_CLARO}Presiona Enter para continuar...${NC})" ;;
        esac
    done
fi

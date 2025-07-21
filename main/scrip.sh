#!/bin/bash
export TZ="America/El_Salvador"
export LANG=es_ES.UTF-8
timedatectl set-timezone America/El_Salvador

REGISTROS="/root/registros.txt"
HISTORIAL="/root/historial_conexiones.txt"
PIDFILE="/var/run/monitorear_conexiones.pid"

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

    while true; do
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
                # Contar conexiones SSH y Dropbear
                CONEXIONES_SSH=$(ps -u "$USUARIO" -o comm= | grep -c "^sshd$")
                CONEXIONES_DROPBEAR=$(ps -u "$USUARIO" -o comm= | grep -c "^dropbear$")
                CONEXIONES=$((CONEXIONES_SSH + CONEXIONES_DROPBEAR))

                # Extraer número de móviles permitido
                MOVILES_NUM=$(echo "$MOVILES" | grep -oE '[0-9]+')

                # Verificar si el usuario está bloqueado en /etc/shadow
                ESTA_BLOQUEADO=$(grep "^$USUARIO:!" /etc/shadow)

                # SOLO si el bloqueo no es manual
                if [[ "$BLOQUEO_MANUAL" != "SÍ" ]]; then
                    # --- LIMPIEZA DE PROCESOS PROBLEMÁTICOS ---
                    # Elimina procesos Z (zombie), D (uninterruptible), T (stopped), S (sleep/desconectado), R (running no ssh/dropbear)
                    while read -r pid stat comm; do
                        case "$stat" in
                            *Z*) # Zombie
                                kill -9 "$pid" 2>/dev/null
                                echo "$(date '+%Y-%m-%d %H:%M:%S'): Proceso zombie (PID $pid, $comm) de '$USUARIO' eliminado." >> "$LOG"
                                ;;
                            *D*) # Uninterruptible sleep
                                kill -9 "$pid" 2>/dev/null
                                echo "$(date '+%Y-%m-%d %H:%M:%S'): Proceso D colgado (PID $pid, $comm) de '$USUARIO' eliminado." >> "$LOG"
                                ;;
                            *T*) # Stopped
                                kill -9 "$pid" 2>/dev/null
                                echo "$(date '+%Y-%m-%d %H:%M:%S'): Proceso detenido (PID $pid, $comm) de '$USUARIO' eliminado." >> "$LOG"
                                ;;
                            *S*) # Sleeping - revisa conexión real con ss
                                if [[ "$comm" == "sshd" || "$comm" == "dropbear" ]]; then
                                    # Si está dormido, pero no tiene conexión activa, elimínalo
                                    PORTS=$(ss -tp | grep "$pid," | grep -E 'ESTAB|ESTABLISHED')
                                    if [[ -z "$PORTS" ]]; then
                                        kill -9 "$pid" 2>/dev/null
                                        echo "$(date '+%Y-%m-%d %H:%M:%S'): Proceso sleeping sin conexión ($pid, $comm) de '$USUARIO' eliminado." >> "$LOG"
                                    fi
                                else
                                    # No es sshd/dropbear, elimínalo siempre
                                    kill -9 "$pid" 2>/dev/null
                                    echo "$(date '+%Y-%m-%d %H:%M:%S'): Proceso sleeping no-sshd ($pid, $comm) de '$USUARIO' eliminado." >> "$LOG"
                                fi
                                ;;
                            *R*) # Running - si no es sshd/dropbear, mátalo
                                if [[ "$comm" != "sshd" && "$comm" != "dropbear" ]]; then
                                    kill -9 "$pid" 2>/dev/null
                                    echo "$(date '+%Y-%m-%d %H:%M:%S'): Proceso running no-sshd ($pid, $comm) de '$USUARIO' eliminado." >> "$LOG"
                                fi
                                ;;
                        esac
                    done < <(ps -u "$USUARIO" -o pid=,stat=,comm=)
                    
                    # --- CONTROL DE SESIONES: CIERRA SOLO LAS EXTRAS ---
                    # Recolecta y ordena sesiones sshd y dropbear por antigüedad
                    PIDS_SSHD=($(ps -u "$USUARIO" -o pid=,comm=,lstart= | awk '$2=="sshd"{print $1 ":" $3" "$4" "$5" "$6" "$7}' | sort -t: -k2 | awk -F: '{print $1}'))
                    PIDS_DROPBEAR=($(ps -u "$USUARIO" -o pid=,comm=,lstart= | awk '$2=="dropbear"{print $1 ":" $3" "$4" "$5" "$6" "$7}' | sort -t: -k2 | awk -F: '{print $1}'))

                    # Mezcla ambos tipos y ordénalos por antigüedad
                    PIDS_TODOS=("${PIDS_SSHD[@]}" "${PIDS_DROPBEAR[@]}")
                    # Si por algún motivo faltan espacios, vuelve a ordenarlos bien
                    mapfile -t PIDS_ORDENADOS < <(for pid in "${PIDS_TODOS[@]}"; do
                        START=$(ps -p "$pid" -o lstart= 2>/dev/null)
                        echo "$pid:$START"
                    done | sort -t: -k2 | awk -F: '{print $1}')

                    TOTAL_CONEX=${#PIDS_ORDENADOS[@]}

                    MOVILES_NUM=$(echo "$MOVILES" | grep -oE '[0-9]+' || echo "1")
                    if (( TOTAL_CONEX > MOVILES_NUM )); then
                        # Conserva solo las primeras MOVILES_NUM, mata el resto
                        for PID in "${PIDS_ORDENADOS[@]:$MOVILES_NUM}"; do
                            kill -9 "$PID" 2>/dev/null
                            echo "$(date '+%Y-%m-%d %H:%M:%S'): Sesión extra de '$USUARIO' (PID $PID) cerrada automáticamente por exceso de conexiones." >> "$LOG"
                        done
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
    # Definimos colores explícitos (sin verde)
    BLANCO="\e[97m"   # Blanco brillante
    AZUL="\e[94m"     # Azul claro
    MAGENTA="\e[95m"  # Magenta
    ROJO="\e[91m"     # Rojo claro
    AMARILLO="\e[93m" # Amarillo brillante
    NC="\e[0m"        # Sin color

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
    FECHA_ACTUAL_DIA=$(date +%Y-%m-%d)

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

    # Salida con colores explícitos y emojis chidos
    echo -e "${AZUL}══════════════════════════════════════════════════${NC}"
    echo -e "${BLANCO} 💾 TOTAL: ${AMARILLO}${MEM_TOTAL_H}${NC} ∘ ${BLANCO}💿 DISPONIBLE: ${AMARILLO}${MEM_DISPONIBLE_H}${NC} ∘ ${BLANCO}⚡ EN USO: ${AMARILLO}${MEM_USO_H}${NC}"
    echo -e "${BLANCO} 📊 U/RAM: ${AMARILLO}${MEM_PORC}%${NC} ∘ ${BLANCO}🖥️ U/CPU: ${AMARILLO}${CPU_PORC}%${NC} ∘ ${BLANCO}🔧 CPU MHz: ${AMARILLO}${CPU_MHZ}${NC}"
    echo -e "${AZUL}══════════════════════════════════════════════════${NC}"
    echo -e "${BLANCO} 🌍 IP: ${AMARILLO}${IP_PUBLICA}${NC} ∘ ${BLANCO}🕒 FECHA: ${AMARILLO}${FECHA_ACTUAL}${NC}"
    echo -e "${MAGENTA}🚀 𝐌𝐜𝐜𝐚𝐫𝐭𝐡𝐞𝐲${NC}"
    echo -e "${BLANCO}🔗 ONLINE:${AMARILLO}${TOTAL_CONEXIONES}${NC}   ${BLANCO}👥 TOTAL:${AMARILLO}${TOTAL_USUARIOS}${NC}   ${BLANCO}🖼️ SO:${AMARILLO}${SO_NAME}${NC}"
    echo -e "${AZUL}══════════════════════════════════════════════════${NC}"

    # MOSTRAR USUARIOS CON 0 DÍAS (EXPIRAN HOY)
    if [[ -f $REGISTROS ]]; then
        USUARIOS_0DIAS=""
        while IFS=$'\t' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL PRIMER_LOGIN; do
            if id "$USUARIO" &>/dev/null; then
                FECHA_EXPIRA_DIA=$(date -d "$EXPIRA_DATETIME" +%Y-%m-%d 2>/dev/null)
                if [[ "$FECHA_EXPIRA_DIA" == "$FECHA_ACTUAL_DIA" ]]; then
                    USUARIOS_0DIAS+="${BLANCO}$USUARIO 0 días    ${NC}"
                fi
            fi
        done < "$REGISTROS"
        if [[ -n "$USUARIOS_0DIAS" ]]; then
            echo -e "\n${ROJO}⚠️ USUARIOS QUE EXPIRAN HOY:${NC}"
            echo -e "$USUARIOS_0DIAS"
            echo -e "${AZUL}══════════════════════════════════════════════════${NC}"
        fi
    fi
}
# Función para mostrar historial de conexiones
ROSADO='\033[38;5;218m'
LILA='\033[38;5;135m'
TURQUESA='\033[38;5;45m'
NC='\033[0m'
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
        # Formatear fechas: dd/mes hh:mm AM/PM (mes en español, AM/PM en MAYÚSCULA)
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

    # Verificar permisos de $REGISTROS
    if [[ ! -f "$REGISTROS" ]]; then
        touch "$REGISTROS" 2>/dev/null || {
            echo -e "${ROJO}❌ Error: No se pudo crear el archivo $REGISTROS. Verifica permisos.${NC}"
            read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
            return
        }
    fi
    if [[ ! -w "$REGISTROS" ]]; then
        echo -e "${ROJO}❌ Error: No se puede escribir en $REGISTROS. Verifica permisos.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    read -p "$(echo -e ${AMARILLO}👤 Nombre del usuario: ${NC})" USUARIO
    read -p "$(echo -e ${AMARILLO}🔑 Contraseña: ${NC})" CLAVE

    # Validar días
    while true; do
        read -p "$(echo -e ${AMARILLO}📅 Días de validez: ${NC})" DIAS
        if [[ "$DIAS" =~ ^[0-9]+$ ]] && [ "$DIAS" -gt 0 ]; then
            break
        else
            echo -e "${ROJO}Por favor, ingresa un número válido de días mayor a 0.${NC}"
        fi
    done

    # Validar móviles
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

    # Crear usuario
    if ! useradd -m -s /bin/bash "$USUARIO" 2>/dev/null; then
        echo -e "${ROJO}❌ Error creando usuario $USUARIO.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    # Establecer contraseña
    if ! echo "$USUARIO:$CLAVE" | chpasswd 2>/dev/null; then
        echo -e "${ROJO}❌ Error estableciendo la contraseña para $USUARIO. Eliminando usuario...${NC}"
        userdel -r "$USUARIO" 2>/dev/null
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    # Calcular fechas de expiración
    if ! EXPIRA_DATETIME=$(date -d "+$DIAS days" +"%Y-%m-%d %H:%M:%S" 2>/dev/null); then
        echo -e "${ROJO}❌ Error calculando la fecha de expiración para $USUARIO. Eliminando usuario...${NC}"
        userdel -r "$USUARIO" 2>/dev/null
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi
    if ! EXPIRA_FECHA=$(date -d "+$((DIAS + 1)) days" +"%Y-%m-%d" 2>/dev/null); then
        echo -e "${ROJO}❌ Error calculando la fecha de expiración para $USUARIO. Eliminando usuario...${NC}"
        userdel -r "$USUARIO" 2>/dev/null
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    # Establecer fecha de expiración
    if ! usermod -e "$EXPIRA_FECHA" "$USUARIO" 2>/dev/null; then
        echo -e "${ROJO}❌ Error configurando la fecha de expiración para $USUARIO. Eliminando usuario...${NC}"
        userdel -r "$USUARIO" 2>/dev/null
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    # Escribir en el archivo de registros con bloqueo
    {
        flock -x 200
        if ! echo -e "$USUARIO\t$CLAVE\t$EXPIRA_DATETIME\t${DIAS} días\t$MOVILES móviles\tNO\t" >> "$REGISTROS" 2>/dev/null; then
            echo -e "${ROJO}❌ Error escribiendo en el archivo de registros para $USUARIO. Eliminando usuario...${NC}"
            userdel -r "$USUARIO" 2>/dev/null
            read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
            return
        fi
    } 200>"$REGISTROS.lock"

    # Mostrar información del usuario creado
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
    echo -e "${CIAN}

===============================================================${NC}"
    read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
}

function crear_multiples_usuarios() {
    clear
    echo -e "${VIOLETA}===== 🆕 CREAR MÚLTIPLES USUARIOS SSH =====${NC}"
    echo -e "${AMARILLO}📝 Formato: nombre contraseña días móviles (separados por espacios, una línea por usuario)${NC}"
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

    # Crear un log de errores
    ERROR_LOG="/tmp/creacion_usuarios_$(date +%Y%m%d_%H%M%S).log"
    touch "$ERROR_LOG" || {
        echo -e "${ROJO}❌ No se pudo crear el archivo de log. Continuando sin registro de errores.${NC}"
        ERROR_LOG=""
    }

    # Contador de éxitos y fallos
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

        if id "$USUARIO" &>/dev/null; then
            echo -e "${ROJO}👤 El usuario '$USUARIO' ya existe. No se puede crear.${NC}"
            [[ -n "$ERROR_LOG" ]] && echo "$(date): Usuario '$USUARIO' ya existe" >> "$ERROR_LOG"
            ((FALLOS++))
            continue
        fi

        # === Creación robusta con rollback ===
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

    # Centrar texto en un ancho dado
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
                # -- Cálculo de días por calendario --
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

                # Centrar los días en 10 caracteres
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
    echo -e "${VIOLETA}===== 💣 ELIMINAR USUARIO (MODO NUCLEAR) =====${NC}"
    if [[ ! -f $REGISTROS ]]; then
        echo -e "${ROJO}❌ No hay registros para eliminar.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    echo -e "${AMARILLO}Nº\t👤 Usuario${NC}"
    echo -e "${CIAN}--------------------------${NC}"
    NUM=1
    declare -A USUARIOS_EXISTENTES
    while IFS=$'\t' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL PRIMER_LOGIN; do
        if id "$USUARIO" &>/dev/null; then
            echo -e "${VERDE}${NUM}\t${AMARILLO}$USUARIO${NC}"
            USUARIOS_EXISTENTES[$NUM]="$USUARIO"
            NUM=$((NUM+1))
        fi
    done < "$REGISTROS"

    if [[ ${#USUARIOS_EXISTENTES[@]} -eq 0 ]]; then
        echo -e "${ROJO}❌ No hay usuarios existentes en el sistema para eliminar.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    echo
    echo -e "${AMARILLO}🗑️ Ingrese los números de los usuarios a eliminar (separados por espacios)${NC}"
    PROMPT=$(echo -e "${AMARILLO}   (0 para cancelar): ${NC}")
    read -p "$PROMPT" INPUT_NUMEROS
    if [[ "$INPUT_NUMEROS" == "0" ]]; then
        echo -e "${AZUL}🚫 Operación cancelada.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    read -ra NUMEROS <<< "$INPUT_NUMEROS"
    declare -a USUARIOS_A_ELIMINAR
    for NUMERO in "${NUMEROS[@]}"; do
        if [[ -n "${USUARIOS_EXISTENTES[$NUMERO]}" ]]; then
            USUARIOS_A_ELIMINAR+=("${USUARIOS_EXISTENTES[$NUMERO]}")
        else
            echo -e "${ROJO}❌ Número inválido: $NUMERO${NC}"
        fi
    done

    if [[ ${#USUARIOS_A_ELIMINAR[@]} -eq 0 ]]; then
        echo -e "${ROJO}❌ No se seleccionaron usuarios válidos para eliminar.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    echo -e "${CIAN}===== 💣 USUARIOS A ELIMINAR =====${NC}"
    echo -e "${AMARILLO}👤 Usuarios seleccionados:${NC}"
    for USUARIO in "${USUARIOS_A_ELIMINAR[@]}"; do
        echo -e "${VERDE}$USUARIO${NC}"
    done
    echo -e "${CIAN}--------------------------${NC}"
    echo -e "${AMARILLO}✅ ¿Confirmar eliminación NUCLEAR de estos usuarios? (s/n)${NC}"
    read -p "" CONFIRMAR
    if [[ $CONFIRMAR != "s" && $CONFIRMAR != "S" ]]; then
        echo -e "${AZUL}🚫 Operación cancelada.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    for USUARIO in "${USUARIOS_A_ELIMINAR[@]}"; do
        echo -e "${ROJO}💣 Eliminando usuario: $USUARIO${NC}"

        echo -e "${ROJO}→ (1) Bloqueando usuario...${NC}"
        sudo usermod --lock "$USUARIO" 2>/dev/null

        echo -e "${ROJO}→ (2) Matando procesos activos...${NC}"
        sudo kill -9 $(pgrep -u "$USUARIO") 2>/dev/null
        sleep 1

        echo -e "${ROJO}→ (3) Eliminando con userdel --force...${NC}"
        sudo userdel --force "$USUARIO" 2>/dev/null

        echo -e "${ROJO}→ (4) Eliminando con deluser --remove-home...${NC}"
        sudo deluser --remove-home "$USUARIO" 2>/dev/null

        echo -e "${ROJO}→ (5) Borrando carpeta huérfana en /home/$USUARIO...${NC}"
        sudo rm -rf "/home/$USUARIO"

        echo -e "${ROJO}→ (6) Limpiando sesión con loginctl...${NC}"
        sudo loginctl kill-user "$USUARIO" 2>/dev/null

        echo -e "${ROJO}→ (7) Segunda pasada de limpieza...${NC}"
        sudo deluser "$USUARIO" 2>/dev/null

        echo -e "${ROJO}→ (8) Removiendo del registro e historial...${NC}"
        sed -i "/^$USUARIO\t/d" "$REGISTROS"
        sed -i "/^$USUARIO|/d" "$HISTORIAL"

        if ! id "$USUARIO" &>/dev/null; then
            echo -e "${VERDE}✅ Usuario $USUARIO eliminado completamente.${NC}"
        else
            echo -e "${ROJO}⚠️ El usuario $USUARIO aún persiste. Verifica manualmente.${NC}"
        fi

        echo -e "${CIAN}--------------------------------------${NC}"
    done

    echo -e "${VERDE}✅ Eliminación nuclear finalizada.${NC}"
    read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
}

verificar_online() {
    clear
    # Usar colores globales en lugar de redefinirlos
    ANARANJADO='\033[38;5;208m'
    AZUL_SUAVE='\033[38;5;45m'  # Color aplicado solo en DETALLES
    NC='\033[0m'

    declare -A month_map=(
        ["Jan"]="Enero" ["Feb"]="Febrero" ["Mar"]="Marzo" ["Apr"]="Abril"
        ["May"]="Mayo" ["Jun"]="Junio" ["Jul"]="Julio" ["Aug"]="Agosto"
        ["Sep"]="Septiembre" ["Oct"]="Octubre" ["Nov"]="Noviembre" ["Dec"]="Diciembre"
    )

    if [[ ! -f $HISTORIAL ]]; then
        touch "$HISTORIAL"
    fi
    if [[ ! -f $REGISTROS ]]; then
        echo -e "${ROJO}❌ No hay registros de usuarios.${NC}"
        read -p "$(echo -e ${ANARANJADO}Presiona Enter para continuar...${NC})"
        return
    fi

    echo -e "${VIOLETA}===== 🟢 USUARIOS ONLINE =====${NC}\n"
    printf "${AMARILLO}%-15s %-15s %-10s %-25s${NC}\n" "👤 USUARIO" "🟢 CONEXIONES" "📱 MÓVILES" "⏰ TIEMPO CONECTADO"
    printf "${CIAN}%.65s${NC}\n" "-----------------------------------------------------------------"

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
                COLOR_ESTADO="${ROJO}"
                ESTADO="🔴 BLOQ"
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
                            if [[ $D -gt 0 ]]; then
                                DETALLES="⏰ $D días %02d:%02d:%02d"
                                DETALLES=$(printf "$DETALLES" $H $M $S)
                            else
                                DETALLES=$(printf "⏰ %02d:%02d:%02d" $H $M $S)
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
                        ULTIMO_LOGOUT_FMT=$(date -d "$ULTIMO_LOGOUT" +"%d de %B %I:%M %p" 2>/dev/null || echo "$ULTIMO_LOGOUT")
                        MES=$(echo "$ULTIMO_LOGOUT_FMT" | awk '{print $4}')
                        for k in "${!month_map[@]}"; do
                            if [[ "$MES" =~ $k ]]; then
                                ULTIMO_LOGOUT_FMT=${ULTIMO_LOGOUT_FMT/$MES/${month_map[$k]}}
                                break
                            fi
                        done
                        DETALLES="📅 Última: $ULTIMO_LOGOUT_FMT"
                    else
                        DETALLES="Nunca conectado"
                    fi
                    ((INACTIVOS++))
                fi
            fi
            printf "${AMARILLO}%-15s${NC} " "$USUARIO"
            printf "${COLOR_ESTADO}%-15s${NC} " "$ESTADO"
            printf "%-10s " "$MOVILES_NUM"
            printf "${AZUL_SUAVE}%-25s${NC}\n" "$DETALLES"
        fi
    done < "$REGISTROS"

    echo
    echo -e "${CIAN}Total de Online: ${AMARILLO}${TOTAL_CONEXIONES}${NC} ${CIAN} Total usuarios: ${AMARILLO}${TOTAL_USUARIOS}${NC} ${CIAN} Inactivos: ${AMARILLO}${INACTIVOS}${NC}"
    echo -e "${ROJO}================================================${NC}"
    read -p "$(echo -e ${VIOLETA}Presiona Enter para continuar...${NC})"
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

function nuclear_eliminar() {
    clear
    echo -e "${VIOLETA}===== 💣 ELIMINACIÓN COMPLETA DE USUARIOS (MODO NUCLEAR) =====${NC}"
    read -p "👤 Ingresa los nombres de usuarios a eliminar (separados por espacio): " USUARIOS
    for USUARIO in $USUARIOS; do
        echo -e "${AMARILLO}Procesando usuario: $USUARIO${NC}"

        # Paso 0: Intento inicial de eliminar con deluser, por si no tiene recursos abiertos
        echo -e "${ROJO}→ (0) Primer intento con deluser...${NC}"
        sudo deluser "$USUARIO" 2>/dev/null

        # Paso 1: Bloquear usuario
        if id "$USUARIO" &>/dev/null; then
            echo -e "${ROJO}→ (1) Bloqueando usuario...${NC}"
            sudo usermod --lock "$USUARIO" 2>/dev/null
        fi

        # Paso 2: Matar todos sus procesos
        echo -e "${ROJO}→ (2) Matando procesos del usuario...${NC}"
        sudo kill -9 $(pgrep -u "$USUARIO") 2>/dev/null

        # Paso 3: Eliminar del sistema con máxima fuerza
        echo -e "${ROJO}→ (3) Eliminando cuentas y directorios...${NC}"
        sudo userdel --force "$USUARIO" 2>/dev/null
        sudo deluser --remove-home "$USUARIO" 2>/dev/null

        # Paso 4: Eliminar carpeta huérfana
        echo -e "${ROJO}→ (4) Eliminando carpeta /home/$USUARIO (si existe)...${NC}"
        sudo rm -rf "/home/$USUARIO"

        # Paso 5: Limpiar sesión con loginctl
        echo -e "${ROJO}→ (5) Limpiando sesiones residuales...${NC}"
        sudo loginctl kill-user "$USUARIO" 2>/dev/null

        # Paso 6: Segundo intento "por si acaso" con deluser para asegurar
        echo -e "${ROJO}→ (6) Segundo y último intento con deluser...${NC}"
        sudo deluser "$USUARIO" 2>/dev/null

        # Paso 7: Borrar del registro y del historial personalizado
        sed -i "/^$USUARIO\t/d" "$REGISTROS"
        sed -i "/^$USUARIO|/d" "$HISTORIAL"

        # Paso 8: Verificación final
        if ! id "$USUARIO" &>/dev/null; then
            echo -e "${VERDE}✅ Usuario $USUARIO eliminado completamente y sin residuos.${NC}"
        else
            echo -e "${ROJO}⚠️ Advertencia: El usuario $USUARIO aún existe. Verifica manualmente.${NC}"
        fi
        echo
    done
    read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
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

# Menú principal
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
        echo -e "${AMARILLO_SUAVE}9. 💣 Eliminar completamente usuario(s) (modo nuclear)${NC}"
        
        echo -e "${AMARILLO_SUAVE}0. 🚪 Salir${NC}"
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
            9) nuclear_eliminar ;;
            
            0) echo -e "${ROSA_CLARO}🚪 Saliendo...${NC}"; exit 0 ;;
            *) echo -e "${ROJO}❌ ¡Opción inválida!${NC}"; read -p "$(echo -e ${ROSA_CLARO}Presiona Enter para continuar...${NC})" ;;
        esac
    done
fi

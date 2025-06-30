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

# Funci贸n para configurar la autoejecuci贸n en ~/.bashrc
function configurar_autoejecucion() {
    BASHRC="/root/.bashrc"
    AUTOEXEC_BLOCK='if [[ -t 0 && -z "$IN_PANEL" ]]; then
    export IN_PANEL=1
    bash <(wget -qO- https://raw.githubusercontent.com/Mccarthey-Installer/Mccarthey-Installer/main/main/scrip.sh)
    unset IN_PANEL
fi'

    # Verificar si el bloque ya existe en ~/.bashrc
    if ! grep -Fx "$AUTOEXEC_BLOCK" "$BASHRC" >/dev/null 2>&1; then
        # Agregar el bloque al final de ~/.bashrc
        echo -e "\n$AUTOEXEC_BLOCK" >> "$BASHRC"
        echo -e "${VERDE}Autoejecuci贸n configurada en $BASHRC. El men煤 se cargar谩 autom谩ticamente en la pr贸xima sesi贸n.${NC}"
    fi
}

# Ejecutar la configuraci贸n de autoejecuci贸n
configurar_autoejecucion

# Funci贸n para monitoreo en tiempo real
function monitorear_conexiones() {
    LOG="/var/log/monitoreo_conexiones.log"
    INTERVALO=10

    # Archivo temporal para almacenar el estado anterior de conexiones
    TEMP_FILE="/tmp/conexiones_anteriores.txt"
    touch "$TEMP_FILE"

    while true; do
        if [[ ! -f $REGISTROS ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S'): El archivo de registros '$REGISTROS' no existe." >> "$LOG"
            sleep "$INTERVALO"
            continue
        fi

        # Crear un archivo temporal para el estado actual
        TEMP_CURRENT="/tmp/conexiones_actuales.txt"
        : > "$TEMP_CURRENT"

        while IFS=$'\t' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL PRIMER_LOGIN; do
            if id "$USUARIO" &>/dev/null; then
                # Extraer el n煤mero de m贸viles permitidos
                MOVILES_NUM=$(echo "$MOVILES" | grep -oE '[0-9]+')

                # Contar procesos sshd del usuario
                CONEXIONES=$(ps -u "$USUARIO" -o comm= | grep -c "^sshd$")

                # Guardar el estado actual
                echo "$USUARIO:$CONEXIONES" >> "$TEMP_CURRENT"

                # Obtener conexiones anteriores
                CONEXIONES_ANT=$(grep "^$USUARIO:" "$TEMP_FILE" | cut -d: -f2 || echo "0")

                # Registrar PRIMER_LOGIN si pasa de 0 a 1 o m谩s conexiones
                if [[ $CONEXIONES_ANT -eq 0 && $CONEXIONES -gt 0 && -z "$PRIMER_LOGIN" ]]; then
                    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
                    sed -i "/^$USUARIO\t/s/\t[^\t]*$/\t$TIMESTAMP/" "$REGISTROS" || {
                        echo "$(date '+%Y-%m-%d %H:%M:%S'): Error actualizando PRIMER_LOGIN para $USUARIO" >> "$LOG"
                    }
                    echo "$(date '+%Y-%m-%d %H:%M:%S'): Nueva conexi贸n detectada para $USUARIO. PRIMER_LOGIN establecido a $TIMESTAMP" >> "$LOG"
                fi

                # Limpiar PRIMER_LOGIN si no hay conexiones
                if [[ $CONEXIONES -eq 0 && -n "$PRIMER_LOGIN" ]]; then
                    sed -i "/^$USUARIO\t/s/\t[^\t]*$/\t/" "$REGISTROS" || {
                        echo "$(date '+%Y-%m-%d %H:%M:%S'): Error limpiando PRIMER_LOGIN para $USUARIO" >> "$LOG"
                    }
                    echo "$(date '+%Y-%m-%d %H:%M:%S'): Conexi贸n terminada para $USUARIO. PRIMER_LOGIN limpiado." >> "$LOG"
                fi

                # Verificar si el usuario est谩 bloqueado
                if grep -q "^$USUARIO:!" /etc/shadow; then
                    # Desbloquear solo si no es bloqueo manual y las conexiones est谩n dentro del l铆mite
                    if [[ "$BLOQUEO_MANUAL" != "S脥" && $CONEXIONES -le $MOVILES_NUM ]]; then
                        usermod -U "$USUARIO" 2>/dev/null
                        echo "$(date '+%Y-%m-%d %H:%M:%S'): Usuario '$USUARIO' desbloqueado autom谩ticamente (conexiones: $CONEXIONES, l铆mite: $MOVILES_NUM)." >> "$LOG"
                    fi
                else
                    # Bloquear si se supera el l铆mite
                    if [[ $CONEXIONES -gt $MOVILES_NUM ]]; then
                        usermod -L "$USUARIO" 2>/dev/null
                        pkill -u "$USUARIO" sshd 2>/dev/null
                        echo "$(date '+%Y-%m-%d %H:%M:%S'): Usuario '$USUARIO' bloqueado autom谩ticamente por exceder el l铆mite (conexiones: $CONEXIONES, l铆mite: $MOVILES_NUM)." >> "$LOG"
                    fi
                fi
            fi
        done < "$REGISTROS"

        # Actualizar el archivo de conexiones anteriores
        mv "$TEMP_CURRENT" "$TEMP_FILE"
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

    FECHA_ACTUAL=$(date +"%Y-%m-%d %I:%M %p")

    # Contar conexiones activas de todos los usuarios en REGISTROS
    TOTAL_CONEXIONES=0
    if [[ -f $REGISTROS ]]; then
        while IFS=$'\t' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL PRIMER_LOGIN; do
            if id "$USUARIO" &>/dev/null; then
                CONEXIONES=$(ps -u "$USUARIO" -o comm= | grep -c "^sshd$")
                TOTAL_CONEXIONES=$((TOTAL_CONEXIONES + CONEXIONES))
            fi
        done < "$REGISTROS"
    fi

    echo -e "${CIAN}鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣${NC}"
    echo -e " 鈭� TOTAL: ${AMARILLO}${MEM_TOTAL_H}${NC} 鈭� M|DISPONIBLE: ${AMARILLO}${MEM_DISPONIBLE_H}${NC} 鈭� EN USO: ${AMARILLO}${MEM_USO_H}${NC}"
    echo -e " 鈭� U/RAM: ${AMARILLO}${MEM_PORC}%${NC} 鈭� U/CPU: ${AMARILLO}${CPU_PORC}%${NC} 鈭� CPU MHz: ${AMARILLO}${CPU_MHZ}${NC}"
    echo -e "${CIAN}鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣鈹佲攣${NC}"
    echo -e " 鈭� IP: ${AMARILLO}${IP_PUBLICA}${NC} 鈭� FECHA: ${AMARILLO}${FECHA_ACTUAL}${NC}"
    echo -e " ${CIAN}饾悓饾悳饾悳饾悮饾惈饾惌饾悺饾悶饾惒 馃槆      ${CIAN}ONLINE: ${TOTAL_CONEXIONES}${NC}"
}

function crear_usuario() {
    clear
    echo -e "${VIOLETA}===== CREAR USUARIO SSH =====${NC}"
    read -p "$(echo -e ${AMARILLO}Nombre del usuario: ${NC})" USUARIO
    read -p "$(echo -e ${AMARILLO}Contrase帽a: ${NC})" CLAVE
    read -p "$(echo -e ${AMARILLO}D铆as de validez: ${NC})" DIAS

    while true; do
        read -p "$(echo -e ${AMARILLO}驴Cu谩ntos m贸viles? ${NC})" MOVILES
        if [[ "$MOVILES" =~ ^[1-9][0-9]{0,2}$ ]] && [ "$MOVILES" -le 999 ]; then
            break
        else
            echo -e "${ROJO}Por favor, ingresa un n煤mero del 1 al 999.${NC}"
        fi
    done

    if id "$USUARIO" &>/dev/null; then
        echo -e "${ROJO}El usuario '$USUARIO' ya existe. No se puede crear.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    useradd -m -s /bin/bash "$USUARIO"
    echo "$USUARIO:$CLAVE" | chpasswd

    EXPIRA_DATETIME=$(date -d "+$DIAS days" +"%Y-%m-%d %H:%M:%S")
    EXPIRA_FECHA=$(date -d "+$((DIAS + 1)) days" +"%Y-%m-%d")
    usermod -e "$EXPIRA_FECHA" "$USUARIO"

    # Agregar PRIMER_LOGIN como vac铆o inicialmente
    echo -e "$USUARIO\t$CLAVE\t$EXPIRA_DATETIME\t${DIAS} d铆as\t$MOVILES m贸viles\tNO\t" >> "$REGISTROS"
    echo

    FECHA_FORMAT=$(date -d "$EXPIRA_DATETIME" +"%Y-%m-%d %I:%M %p")
    echo -e "${VERDE}Usuario creado exitosamente:${NC}"
    echo -e "${AZUL}Usuario: ${AMARILLO}$USUARIO${NC}"
    echo -e "${AZUL}Clave: ${AMARILLO}$CLAVE${NC}"
    echo -e "${AZUL}Expira: ${AMARILLO}$FECHA_FORMAT${NC}"
    echo -e "${AZUL}M贸viles permitidos: ${AMARILLO}$MOVILES${NC}"
    echo

    echo -e "${CIAN}===== REGISTRO CREADO =====${NC}"
    printf "${AMARILLO}%-15s %-15s %-20s %-15s %-15s${NC}\n" "Usuario" "Clave" "Expira" "Duraci贸n" "M贸viles"
    echo -e "${CIAN}---------------------------------------------------------------${NC}"
    printf "${VERDE}%-15s %-15s %-20s %-15s %-15s${NC}\n" "$USUARIO" "$CLAVE" "$FECHA_FORMAT" "${DIAS} d铆as" "$MOVILES"
    echo -e "${CIAN}===============================================================${NC}"
    read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
}

function crear_multiples_usuarios() {
    clear
    echo -e "${VIOLETA}===== CREAR M脷LTIPLES USUARIOS SSH =====${NC}"
    echo -e "${AMARILLO}Formato: nombre contrase帽a d铆as m贸viles (separados por espacios, una l铆nea por usuario)${NC}"
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
    printf "${AMARILLO}%-15s %-15s %-15s %-15s${NC}\n" "Usuario" "Clave" "D铆as" "M贸viles"
    echo -e "${CIAN}---------------------------------------------------------------${NC}"
    for LINEA in "${USUARIOS[@]}"; do
        read -r USUARIO CLAVE DIAS MOVILES <<< "$LINEA"
        if [[ -z "$USUARIO" || -z "$CLAVE" || -z "$DIAS" || -z "$MOVILES" ]]; then
            echo -e "${ROJO}L铆nea inv谩lida: $LINEA${NC}"
            continue
        fi
        printf "${VERDE}%-15s %-15s %-15s %-15s${NC}\n" "$USUARIO" "$CLAVE" "$DIAS" "$MOVILES"
    done
    echo -e "${CIAN}===============================================================${NC}"
    echo -e "${AMARILLO}驴Confirmar creaci贸n de estos usuarios? (s/n)${NC}"
    read -p "" CONFIRMAR
    if [[ $CONFIRMAR != "s" && $CONFIRMAR != "S" ]]; then
        echo -e "${AZUL}Operaci贸n cancelada.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    for LINEA in "${USUARIOS[@]}"; do
        read -r USUARIO CLAVE DIAS MOVILES <<< "$LINEA"
        if [[ -z "$USUARIO" || -z "$CLAVE" || -z "$DIAS" || -z "$MOVILES" ]]; then
            echo -e "${ROJO}L铆nea inv谩lida: $LINEA${NC}"
            continue
        fi

        if ! [[ "$DIAS" =~ ^[0-9]+$ ]] || ! [[ "$MOVILES" =~ ^[1-9][0-9]{0,2}$ ]] || [ "$MOVILES" -gt 999 ]; then
            echo -e "${ROJO}Datos inv谩lidos para $USUARIO (D铆as: $DIAS, M贸viles: $MOVILES).${NC}"
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

        # Agregar PRIMER_LOGIN como vac铆o inicialmente
        echo -e "$USUARIO\t$CLAVE\t$EXPIRA_DATETIME\t${DIAS} d铆as\t$MOVILES m贸viles\tNO\t" >> "$REGISTROS"
        echo -e "${VERDE}Usuario $USUARIO creado exitosamente.${NC}"
    done

    echo -e "${VERDE}Creaci贸n de usuarios finalizada.${NC}"
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
        printf "${AMARILLO}%-3s %-12s %-12s %-22s %10s %-12s %-22s${NC}\n" \
            "N潞" "Usuario" "Clave" "Expira" "$(center_text 'D铆as' 10)" "M贸viles" "Primer Login"
        echo -e "${CIAN}--------------------------------------------------------------------------------${NC}"

        NUM=1
        while IFS=$'\t' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL PRIMER_LOGIN; do
            if id "$USUARIO" &>/dev/null; then
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
                    FORMATO_EXPIRA=$(date -d "$EXPIRA_DATETIME" +"%Y-%m-%d %I:%M %p")
                else
                    DIAS_RESTANTES="Inv谩lido"
                    FORMATO_EXPIRA="Desconocido"
                    COLOR_DIAS="${ROJO}"
                fi

                PRIMER_LOGIN_FORMAT=$(if [[ -n "$PRIMER_LOGIN" ]]; then date -d "$PRIMER_LOGIN" +"%Y-%m-%d %I:%M %p"; else echo "No registrado"; fi)
                printf "${VERDE}%-3d ${AMARILLO}%-12s %-12s %-22s ${COLOR_DIAS}%10s${NC} ${AMARILLO}%-12s %-22s${NC}\n" \
                    "$NUM" "$USUARIO" "$CLAVE" "$FORMATO_EXPIRA" "$(center_value "$DIAS_RESTANTES" 10)" "$MOVILES" "$PRIMER_LOGIN_FORMAT"
                NUM=$((NUM+1))
            fi
        done < "$REGISTROS"

        if [[ $NUM -eq 1 ]]; then
            echo -e "${ROJO}No hay usuarios existentes en el sistema o los registros no son v谩lidos.${NC}"
        fi
    else
        echo -e "${ROJO}No hay registros a煤n. El archivo '$REGISTROS' no existe.${NC}"
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

    echo -e "${AMARILLO}N潞\tUsuario\tClave\tExpira\t\tDuraci贸n\tM贸viles\tPrimer Login${NC}"
    echo -e "${CIAN}---------------------------------------------------------------${NC}"
    NUM=1
    declare -A USUARIOS_EXISTENTES
    while IFS=$'\t' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL PRIMER_LOGIN; do
        if id "$USUARIO" &>/dev/null; then
            PRIMER_LOGIN_FORMAT=$(if [[ -n "$PRIMER_LOGIN" ]]; then date -d "$PRIMER_LOGIN" +"%Y-%m-%d %I:%M %p"; else echo "No registrado"; fi)
            echo -e "${VERDE}${NUM}\t${AMARILLO}$USUARIO\t$CLAVE\t$EXPIRA_DATETIME\t$DURACION\t$MOVILES\t$PRIMER_LOGIN_FORMAT${NC}"
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
    PROMPT=$(echo -e "${AMARILLO}Ingrese los n煤meros de los usuarios a eliminar (separados por espacios, 0 para cancelar): ${NC}")
    read -p "$PROMPT" INPUT_NUMEROS
    if [[ "$INPUT_NUMEROS" == "0" ]]; then
        echo -e "${AZUL}Operaci贸n cancelada.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    read -ra NUMEROS <<< "$INPUT_NUMEROS"
    declare -a USUARIOS_A_ELIMINAR
    for NUMERO in "${NUMEROS[@]}"; do
        if [[ -n "${USUARIOS_EXISTENTES[$NUMERO]}" ]]; then
            USUARIOS_A_ELIMINAR+=("${USUARIOS_EXISTENTES[$NUMERO]}")
        else
            echo -e "${ROJO}N煤mero inv谩lido: $NUMERO${NC}"
        fi
    done

    if [[ ${#USUARIOS_A_ELIMINAR[@]} -eq 0 ]]; then
        echo -e "${ROJO}No se seleccionaron usuarios v谩lidos para eliminar.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    echo -e "${CIAN}===== USUARIOS A ELIMINAR =====${NC}"
    echo -e "${AMARILLO}Usuarios seleccionados:${NC}"
    for USUARIO in "${USUARIOS_A_ELIMINAR[@]}"; do
        echo -e "${VERDE}$USUARIO${NC}"
    done
    echo -e "${CIAN}---------------------------------------------------------------${NC}"
    echo -e "${AMARILLO}驴Confirmar eliminaci贸n de estos usuarios? (s/n)${NC}"
    read -p "" CONFIRMAR
    if [[ $CONFIRMAR != "s" && $CONFIRMAR != "S" ]]; then
        echo -e "${AZUL}Operaci贸n cancelada.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    for USUARIO in "${USUARIOS_A_ELIMINAR[@]}"; do
        PIDS=$(pgrep -u "$USUARIO")
        if [[ -n $PIDS ]]; then
            echo -e "${ROJO}Procesos activos detectados para $USUARIO. Cerr谩ndolos...${NC}"
            kill -9 $PIDS 2>/dev/null
            sleep 1
        fi
        if userdel -r "$USUARIO" 2>/dev/null; then
            sed -i "/^$USUARIO\t/d" "$REGISTROS"
            echo -e "${VERDE}Usuario $USUARIO eliminado exitosamente.${NC}"
        else
            echo -e "${ROJO}No se pudo eliminar el usuario $USUARIO. Puede que a煤n est茅 en uso.${NC}"
        fi
    done

    echo -e "${VERDE}Eliminaci贸n de usuarios finalizada.${NC}"
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
    while IFS=$'\t' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL PRIMER_LOGIN; do
        if id "$USUARIO" &>/dev/null; then
            USUARIOS_EXISTENTES+=("$USUARIO")
        fi
    done < "$REGISTROS"

    if [[ ${#USUARIOS_EXISTENTES[@]} -eq 0 ]]; then
        echo -e "${ROJO}No hay usuarios existentes en el sistema para eliminar.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    echo -e "${AMARILLO}Se eliminar谩n TODOS los usuarios existentes a continuaci贸n:${NC}"
    echo -e "${CIAN}---------------------------------------------------------------${NC}"
    for USUARIO in "${USUARIOS_EXISTENTES[@]}"; do
        echo -e "${VERDE}$USUARIO${NC}"
    done
    echo -e "${CIAN}---------------------------------------------------------------${NC}"
    echo -e "${ROJO}驴Est谩s seguro de que quieres eliminar TODOS estos usuarios? (s/n)${NC}"
    read -p "" CONFIRMAR
    if [[ $CONFIRMAR != "s" && $CONFIRMAR != "S" ]]; then
        echo -e "${AZUL}Operaci贸n cancelada.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    for USUARIO in "${USUARIOS_EXISTENTES[@]}"; do
        PIDS=$(pgrep -u "$USUARIO")
        if [[ -n $PIDS ]]; then
            echo -e "${ROJO}Procesos activos detectados para $USUARIO. Cerr谩ndolos...${NC}"
            kill -9 $PIDS 2>/dev/null
            sleep 1
        fi
        if userdel -r "$USUARIO" 2>/dev/null; then
            sed -i "/^$USUARIO\t/d" "$REGISTROS"
            echo -e "${VERDE}Usuario $USUARIO eliminado exitosamente.${NC}"
        else
            echo -e "${ROJO}No se pudo eliminar el usuario $USUARIO. Puede que a煤n est茅 en uso.${NC}"
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

    printf "${AMARILLO}%-15s %-15s %-25s %-15s${NC}\n" "USUARIO" "CONEXIONES" "TIEMPO CONECTADO" "M脫VILES"
    echo -e "${CIAN}------------------------------------------------------------${NC}"
    while IFS=$'\t' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL PRIMER_LOGIN; do
        if id "$USUARIO" &>/dev/null; then
            ESTADO="0"
            DETALLES="Nunca conectado"
            COLOR_ESTADO="${ROJO}"

            # Extraer el n煤mero de m贸viles permitidos
            MOVILES_NUM=$(echo "$MOVILES" | grep -oE '[0-9]+')

            # Verificar si el usuario est谩 bloqueado
            if grep -q "^$USUARIO:!" /etc/shadow; then
                DETALLES="Usuario bloqueado"
            else
                # Contar solo procesos sshd ejecutados como el usuario
                CONEXIONES=$(ps -u "$USUARIO" -o comm= | grep -c "^sshd$")
                if [[ $CONEXIONES -gt 0 ]]; then
                    ESTADO="$CONEXIONES"
                    COLOR_ESTADO="${VERDE}"

                    # Usar PRIMER_LOGIN existente para calcular el tiempo conectado
                    if [[ -n "$PRIMER_LOGIN" ]]; then
                        START=$(date -d "$PRIMER_LOGIN" +%s 2>/dev/null)
                        if [[ $? -eq 0 && -n "$START" ]]; then
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
                            DETALLES="Tiempo no disponible (PRIMER_LOGIN inv谩lido)"
                            # Limpiar PRIMER_LOGIN si es inv谩lido
                            sed -i "/^$USUARIO\t/s/\t[^\t]*$/\t/" "$REGISTROS" || {
                                echo "$(date '+%Y-%m-%d %H:%M:%S'): Error limpiando PRIMER_LOGIN inv谩lido para $USUARIO" >> /var/log/panel_errors.log
                            }
                        fi
                    else
                        DETALLES="Tiempo no disponible (PRIMER_LOGIN no establecido)"
                    fi
                else
                    # Mostrar 煤ltima conexi贸n conocida desde auth.log si no est谩 conectado
                    LOGIN_LINE=$( { grep -E "Accepted password for $USUARIO|session opened for user $USUARIO|session closed for user $USUARIO" /var/log/auth.log 2>/dev/null || grep -E "Accepted password for $USUARIO|session opened for user $USUARIO|session closed for user $USUARIO" /var/log/secure 2>/dev/null || grep -E "Accepted password for $USUARIO|session opened for user $USUARIO|session closed for user $USUARIO" /var/log/messages 2>/dev/null; } | tail -1)
                    if [[ -n "$LOGIN_LINE" ]]; then
                        MES=$(echo "$LOGIN_LINE" | awk '{print $1}')
                        DIA=$(echo "$LOGIN_LINE" | awk '{print $2}')
                        HORA=$(echo "$LOGIN_LINE" | awk '{print $3}')
                        MES_ES=${month_map["$MES"]}
                        if [ -z "$MES_ES" ]; then MES_ES="$MES"; fi
                        HORA_SIMPLE=$(date -d "$HORA" +"%I:%M %p" 2>/dev/null || echo "$HORA")
                        DETALLES="脷ltima: $DIA de $MES_ES $HORA_SIMPLE"
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
    printf "${AMARILLO}%-5s %-15s %-15s %-22s %-15s %-15s${NC}\n" "N潞" "Usuario" "Clave" "Expira" "Duraci贸n" "Estado"
    echo -e "${CIAN}--------------------------------------------------------------------------${NC}"
    mapfile -t LINEAS < "$REGISTROS"
    INDEX=1
    for LINEA in "${LINEAS[@]}"; do
        IFS=$'\t' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL PRIMER_LOGIN <<< "$LINEA"
        if id "$USUARIO" &>/dev/null; then
            if grep -q "^$USUARIO:!" /etc/shadow; then
                ESTADO="BLOQUEADO"
                COLOR_ESTADO="${ROJO}"
            else
                ESTADO="ACTIVO"
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

    read -p "$(echo -e ${AMARILLO}Digite el n煤mero del usuario: ${NC})" NUM
    USUARIO_LINEA="${LINEAS[$((NUM-1))]}"
    IFS=$'\t' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL PRIMER_LOGIN <<< "$USUARIO_LINEA"

    if [[ -z "$USUARIO" || ! $(id -u "$USUARIO" 2>/dev/null) ]]; then
        echo -e "${ROJO}N煤mero inv谩lido o el usuario ya no existe en el sistema.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    ESTADO=$(grep "^$USUARIO:" /etc/shadow | cut -d: -f2)
    if [[ $ESTADO == "!"* ]]; then
        echo -e "${AMARILLO}El usuario '$USUARIO' est谩 BLOQUEADO.${NC}"
        ACCION="desbloquear"
        ACCION_VERBO="Desbloquear"
    else
        echo -e "${AMARILLO}El usuario '$USUARIO' est谩 DESBLOQUEADO.${NC}"
        ACCION="bloquear"
        ACCION_VERBO="Bloquear"
    fi

    echo -e "${AMARILLO}驴Desea $ACCION al usuario '$USUARIO'? (s/n)${NC}"
    read -p "" CONFIRMAR
    if [[ $CONFIRMAR != "s" && $CONFIRMAR != "S" ]]; then
        echo -e "${AZUL}Operaci贸n cancelada.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    if [[ $ACCION == "bloquear" ]]; then
        usermod -L "$USUARIO"
        pkill -u "$USUARIO" sshd
        sed -i "/^$USUARIO\t/ s/\t[^\t]*\t[^\t]*$/\tS脥\t$PRIMER_LOGIN/" "$REGISTROS"
        echo -e "${VERDE}Usuario '$USUARIO' bloqueado exitosamente y sesiones SSH terminadas.${NC}"
    else
        usermod -U "$USUARIO"
        sed -i "/^$USUARIO\t/ s/\t[^\t]*\t[^\t]*$/\tNO\t$PRIMER_LOGIN/" "$REGISTROS"
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

    printf "${AMARILLO}%-15s %-15s %-10s %-15s${NC}\n" "nombre" "contrase帽a" "d铆as" "m贸viles"
    echo -e "${CIAN}--------------------------------------------${NC}"
    while IFS=$'\t' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL PRIMER_LOGIN; do
        if id "$USUARIO" &>/dev/null; then
            DIAS=$(echo "$DURACION" | grep -oE '[0-9]+')
            MOVILES_NUM=$(echo "$MOVILES" | grep -oE '[0-9]+')
            printf "${VERDE}%-15s %-15s %-10s %-15s${NC}\n" "$USUARIO" "$CLAVE" "$DIAS" "$MOVILES_NUM"
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
    echo -e "${VERDE}7. Crear m煤ltiples usuarios${NC}"
    echo -e "${VERDE}8. Mini registro${NC}"
    echo -e "${VERDE}9. Salir${NC}"
    PROMPT=$(echo -e "${AMARILLO}Selecciona una opci贸n: ${NC}")
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
        *) echo -e "${ROJO}隆Opci贸n inv谩lida!${NC}"; read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})" ;;
    esac
done

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


function monitorear_conexiones() {
    LOG="/var/log/monitoreo_conexiones.log"
    INTERVALO=5  # Intervalo de espera en segundos

    while true; do
        if [[ ! -f "$REGISTROS" ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S'): El archivo de registros '$REGISTROS' no existe." >> "$LOG"
            sleep "$INTERVALO"
            continue
        fi

        {
            if ! flock -x -w 10 200; then
                echo "$(date '+%Y-%m-%d %H:%M:%S'): No se pudo adquirir el bloqueo después de 10s." >> "$LOG"
                sleep "$INTERVALO"
                continue
            fi

            TEMP_FILE=$(mktemp "${REGISTROS}.tmp.XXXXXX") || {
                echo "$(date '+%Y-%m-%d %H:%M:%S'): Error creando archivo temporal." >> "$LOG"
                sleep "$INTERVALO"
                continue
            }

            TEMP_FILE_NEW=$(mktemp "${REGISTROS}.tmp.new.XXXXXX") || {
                echo "$(date '+%Y-%m-%d %H:%M:%S'): Error creando archivo temporal nuevo." >> "$LOG"
                rm -f "$TEMP_FILE"
                sleep "$INTERVALO"
                continue
            }

            cp "$REGISTROS" "$TEMP_FILE" 2>/dev/null || {
                echo "$(date '+%Y-%m-%d %H:%M:%S'): Error copiando $REGISTROS." >> "$LOG"
                rm -f "$TEMP_FILE" "$TEMP_FILE_NEW"
                sleep "$INTERVALO"
                continue
            }

            > "$TEMP_FILE_NEW"

            while IFS=':' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL PRIMER_LOGIN; do
                if id "$USUARIO" &>/dev/null; then
                    CONEXIONES_SSH=$(ps -u "$USUARIO" -o comm= | grep -c "^sshd$")
                    CONEXIONES_DROPBEAR=$(ps -u "$USUARIO" -o comm= | grep -c "^dropbear$")
                    CONEXIONES=$((CONEXIONES_SSH + CONEXIONES_DROPBEAR))

                    MOVILES_NUM=$(echo "$MOVILES" | grep -oE '[0-9]+' || echo "1")
                    ESTA_BLOQUEADO=$(grep "^$USUARIO:!" /etc/shadow)

                    if [[ "$BLOQUEO_MANUAL" != "SÍ" ]]; then
                        while read -r pid stat comm; do
                            case "$stat" in
                                *Z*) kill -9 "$pid" 2>/dev/null
                                     echo "$(date '+%Y-%m-%d %H:%M:%S'): Proceso zombie (PID $pid, $comm) de '$USUARIO' eliminado." >> "$LOG" ;;
                                *D*) kill -9 "$pid" 2>/dev/null
                                     echo "$(date '+%Y-%m-%d %H:%M:%S'): Proceso D colgado (PID $pid, $comm) de '$USUARIO' eliminado." >> "$LOG" ;;
                                *T*) kill -9 "$pid" 2>/dev/null
                                     echo "$(date '+%Y-%m-%d %H:%M:%S'): Proceso detenido (PID $pid, $comm) de '$USUARIO' eliminado." >> "$LOG" ;;
                                *S*) if [[ "$comm" != "sshd" && "$comm" != "dropbear" && "$comm" != "systemd" && "$comm" != "(sd-pam)" ]]; then
                                         PORTS=$(ss -tp | grep "$pid," | grep -E 'ESTAB|ESTABLISHED')
                                         if [[ -z "$PORTS" ]]; then
                                             kill -9 "$pid" 2>/dev/null
                                             echo "$(date '+%Y-%m-%d %H:%M:%S'): Proceso sleeping sin conexión ($pid, $comm) de '$USUARIO' eliminado." >> "$LOG"
                                         fi
                                     fi ;;
                                *R*) if [[ "$comm" != "sshd" && "$comm" != "dropbear" && "$comm" != "systemd" && "$comm" != "(sd-pam)" ]]; then
                                         kill -9 "$pid" 2>/dev/null
                                         echo "$(date '+%Y-%m-%d %H:%M:%S'): Proceso running no-sshd ($pid, $comm) de '$USUARIO' eliminado." >> "$LOG"
                                     fi ;;
                            esac
                        done < <(ps -u "$USUARIO" -o pid=,stat=,comm=)

                        PIDS_SSHD=($(ps -u "$USUARIO" -o pid=,comm=,lstart= | awk '$2=="sshd"{print $1 ":" $3" "$4" "$5" "$6" "$7}' | sort -t: -k2 | awk -F: '{print $1}'))
                        PIDS_DROPBEAR=($(ps -u "$USUARIO" -o pid=,comm=,lstart= | awk '$2=="dropbear"{print $1 ":" $3" "$4" "$5" "$6" "$7}' | sort -t: -k2 | awk -F: '{print $1}'))

                        PIDS_TODOS=("${PIDS_SSHD[@]}" "${PIDS_DROPBEAR[@]}")
                        mapfile -t PIDS_ORDENADOS < <(for pid in "${PIDS_TODOS[@]}"; do
                            START=$(ps -p "$pid" -o lstart= 2>/dev/null)
                            echo "$pid:$START"
                        done | sort -t: -k2 | awk -F: '{print $1}')

                        TOTAL_CONEX=${#PIDS_ORDENADOS[@]}
                        if (( TOTAL_CONEX > MOVILES_NUM )); then
                            for PID in "${PIDS_ORDENADOS[@]:$MOVILES_NUM}"; do
                                kill -9 "$PID" 2>/dev/null
                                echo "$(date '+%Y-%m-%d %H:%M:%S'): Sesión extra de '$USUARIO' (PID $PID) cerrada automáticamente por exceso de conexiones." >> "$LOG"
                            done
                        fi
                    fi

                    NEW_PRIMER_LOGIN="$PRIMER_LOGIN"
                    if [[ $CONEXIONES -gt 0 && -z "$PRIMER_LOGIN" ]]; then
                        NEW_PRIMER_LOGIN=$(date +"%Y-%m-%d %H:%M:%S")
                    elif [[ $CONEXIONES -eq 0 && -n "$PRIMER_LOGIN" ]]; then
                        NEW_PRIMER_LOGIN=""
                    fi

                    echo "$USUARIO:$CLAVE:$EXPIRA_DATETIME:$DURACION:$MOVILES:$BLOQUEO_MANUAL:$NEW_PRIMER_LOGIN" >> "$TEMP_FILE_NEW"
                else
                    echo "$USUARIO:$CLAVE:$EXPIRA_DATETIME:$DURACION:$MOVILES:$BLOQUEO_MANUAL:$PRIMER_LOGIN" >> "$TEMP_FILE_NEW"
                fi
            done < "$TEMP_FILE"

            cp "$REGISTROS" "${REGISTROS}.bak.$$" 2>/dev/null || {
                echo "$(date '+%Y-%m-%d %H:%M:%S'): Error creando respaldo de $REGISTROS." >> "$LOG"
                rm -f "$TEMP_FILE" "$TEMP_FILE_NEW"
                sleep "$INTERVALO"
                continue
            }

            if mv "$TEMP_FILE_NEW" "$REGISTROS" 2>/dev/null; then
                sync
                sleep 0.2
                local verify_attempts=3
                local verified=false
                for ((i=1; i<=verify_attempts; i++)); do
                    if [[ -f "$REGISTROS" ]] && [[ -r "$REGISTROS" ]]; then
                        verified=true
                        break
                    fi
                    echo "$(date '+%Y-%m-%d %H:%M:%S'): Verificación $i/$verify_attempts falló para $REGISTROS." >> "$LOG"
                    sleep 0.2
                done

                if [[ "$verified" != "true" ]]; then
                    echo "$(date '+%Y-%m-%d %H:%M:%S'): Verificación post-escritura falló después de $verify_attempts intentos." >> "$LOG"
                    [[ -f "${REGISTROS}.bak.$$" ]] && mv "${REGISTROS}.bak.$$" "$REGISTROS" 2>/dev/null
                    rm -f "$TEMP_FILE" "$TEMP_FILE_NEW"
                    sleep "$INTERVALO"
                    continue
                fi
            else
                echo "$(date '+%Y-%m-%d %H:%M:%S'): Error reemplazando $REGISTROS." >> "$LOG"
                [[ -f "${REGISTROS}.bak.$$" ]] && mv "${REGISTROS}.bak.$$" "$REGISTROS" 2>/dev/null
                rm -f "$TEMP_FILE" "$TEMP_FILE_NEW"
                sleep "$INTERVALO"
                continue
            fi

            rm -f "$TEMP_FILE" "$TEMP_FILE_NEW" "${REGISTROS}.bak.$$"
        } 200>"$REGISTROS.lock"

        # Registro de historial de conexiones —ahora también con ':'
        {
            if ! flock -x -w 10 200; then
                echo "$(date '+%Y-%m-%d %H:%M:%S'): No se pudo adquirir el bloqueo para historial." >> "$LOG"
                sleep "$INTERVALO"
                continue
            fi

            while IFS=':' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL PRIMER_LOGIN; do
                TMP_STATUS="/tmp/status_${USUARIO}.tmp"
                CONEXIONES_SSH=$(ps -u "$USUARIO" -o comm= | grep -c "^sshd$")
                CONEXIONES_DROPBEAR=$(ps -u "$USUARIO" -o comm= | grep -c "^dropbear$")
                CONEXIONES=$((CONEXIONES_SSH + CONEXIONES_DROPBEAR))

                if [[ $CONEXIONES -gt 0 ]]; then
                    [[ ! -f "$TMP_STATUS" ]] && date +"%Y-%m-%d %H:%M:%S" > "$TMP_STATUS"
                else
                    if [[ -f "$TMP_STATUS" ]]; then
                        HORA_CONEXION=$(cat "$TMP_STATUS")
                        HORA_DESCONECCION=$(date +"%Y-%m-%d %H:%M:%S")
                        SEC_CON=$(date -d "$HORA_CONEXION" +%s)
                        SEC_DES=$(date -d "$HORA_DESCONECCION" +%s)
                        DURACION_SEC=$((SEC_DES - SEC_CON))
                        HORAS=$((DURACION_SEC / 3600))
                        MINUTOS=$(( (DURACION_SEC % 3600) / 60 ))
                        SEGUNDOS=$((DURACION_SEC % 60))
                        DURACION_FORMAT=$(printf "%02d:%02d:%02d" $HORAS $MINUTOS $SEGUNDOS)
                        echo "$USUARIO:$HORA_CONEXION:$HORA_DESCONECCION:$DURACION_FORMAT" >> "$HISTORIAL"
                        rm -f "$TMP_STATUS"
                    fi
                fi
            done < "$REGISTROS"
        } 200>"$HISTORIAL.lock"

        sleep "$INTERVALO"
    done
}
#AAAAQUI VOY
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


    function crear_usuario() {
    clear
    echo -e "${ROJO}===== 🤪 CREAR USUARIO SSH =====${NC}"

    # Verificar si se puede escribir en $REGISTROS
    if [[ ! -f "$REGISTROS" ]]; then
        touch "$REGISTROS" 2>/dev/null || {
            echo -e "${ROJO}❌ No se pudo crear $REGISTROS. Revisa permisos o espacio en disco.${NC}"
            read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
            return 1
        }
        chmod 600 "$REGISTROS" 2>/dev/null || {
            echo -e "${ROJO}❌ No se pudo establecer permisos en $REGISTROS.${NC}"
            read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
            return 1
        }
    fi
    if [[ ! -w "$REGISTROS" ]]; then
        echo -e "${ROJO}❌ No se puede escribir en $REGISTROS. Revisa permisos.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return 1
    fi

    # Verificar espacio en disco
    df -h /root | tail -n 1 | grep -q '[0-9]' || {
        echo -e "${ROJO}❌ Error: No se puede verificar el espacio en disco para /root.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return 1
    }
    AVAILABLE_SPACE=$(df -k /root | tail -n 1 | awk '{print $4}')
    if [[ "$AVAILABLE_SPACE" -lt 1024 ]]; then
        echo -e "${ROJO}❌ Espacio en disco insuficiente en /root ($AVAILABLE_SPACE KB disponibles).${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return 1
    fi

    # Leer nombre del usuario
    while true; do
        read -p "$(echo -e ${AMARILLO}👤 Nombre del usuario: ${NC})" USUARIO
        [[ -z "$USUARIO" ]] && echo -e "${ROJO}❌ Ingresa un nombre válido.${NC}" && continue
        if id "$USUARIO" &>/dev/null; then
            echo -e "${ROJO}⚠️ El usuario '$USUARIO' ya existe en el sistema.${NC}"
            continue
        fi
        if grep -qw "^$USUARIO:" "$REGISTROS"; then
            echo -e "${ROJO}⚠️ Ya existe un registro con ese nombre en $REGISTROS.${NC}"
            continue
        fi
        break
    done

    read -p "$(echo -e ${AMARILLO}🔑 Contraseña: ${NC})" CLAVE
    [[ -z "$CLAVE" ]] && echo -e "${ROJO}❌ La contraseña no puede estar vacía.${NC}" && return 1

    # Días de validez
    while true; do
        read -p "$(echo -e ${AMARILLO}📅 Días de validez: ${NC})" DIAS
        [[ "$DIAS" =~ ^[0-9]+$ && "$DIAS" -ge 0 ]] && break
        echo -e "${ROJO}❌ Ingresa un número válido (0 o más).${NC}"
    done

    # Número de móviles
    while true; do
        read -p "$(echo -e ${AMARILLO}📱 ¿Cuántos móviles? ${NC})" MOVILES
        [[ "$MOVILES" =~ ^[1-9][0-9]{0,2}$ && "$MOVILES" -le 999 ]] && break
        echo -e "${ROJO}❌ Ingresa un número entre 1 y 999.${NC}"
    done

    # Fechas
    EXPIRA_DATETIME=$(date -d "+$DIAS days" +"%Y-%m-%d 00:00:00")
    EXPIRA_FECHA=$(date -d "+$((DIAS+1)) days" +"%Y-%m-%d")
    FECHA_CREACION=$(date +"%Y-%m-%d %H:%M:%S")

    # Agregar al REGISTRO con bloqueo y verificación
    {
        # Intentar adquirir el bloqueo con un timeout mayor (20 segundos) y reintentos
        local intentos=0
        local max_intentos=3
        local lock_acquired=false
        while [[ $intentos -lt $max_intentos ]]; do
            if flock -x -w 20 200; then
                lock_acquired=true
                break
            fi
            ((intentos++))
            echo "$(date '+%Y-%m-%d %H:%M:%S'): Intento $intentos/$max_intentos: No se pudo adquirir el bloqueo para $REGISTROS." >> "/var/log/monitoreo_conexiones.log"
            sleep 1
        done
        if [[ "$lock_acquired" != "true" ]]; then
            echo -e "${ROJO}❌ Error: No se pudo adquirir el bloqueo para $REGISTROS después de $max_intentos intentos.${NC}"
            read -p "$(echo -e ${AZUL}Presiona Enter...${NC})"
            return 1
        fi

        # Crear archivo temporal en el mismo directorio que REGISTROS
        TEMP_FILE=$(mktemp "${REGISTROS}.tmp.XXXXXX") || {
            echo "$(date '+%Y-%m-%d %H:%M:%S'): Error creando archivo temporal para $REGISTROS." >> "/var/log/monitoreo_conexiones.log"
            echo -e "${ROJO}❌ Error: No se pudo crear archivo temporal.${NC}"
            read -p "$(echo -e ${AZUL}Presiona Enter...${NC})"
            return 1
        }

        # Copiar contenido actual y agregar nuevo registro
        cp "$REGISTROS" "$TEMP_FILE" 2>/dev/null || {
            echo "$(date '+%Y-%m-%d %H:%M:%S'): Error copiando $REGISTROS a $TEMP_FILE." >> "/var/log/monitoreo_conexiones.log"
            rm -f "$TEMP_FILE"
            echo -e "${ROJO}❌ Error: No se pudo copiar $REGISTROS.${NC}"
            read -p "$(echo -e ${AZUL}Presiona Enter...${NC})"
            return 1
        }

        echo "${USUARIO}:${CLAVE}:${EXPIRA_DATETIME}:${DIAS}:${MOVILES}:NO:${FECHA_CREACION}" >> "$TEMP_FILE" || {
            echo "$(date '+%Y-%m-%d %H:%M:%S'): Error escribiendo en $TEMP_FILE." >> "/var/log/monitoreo_conexiones.log"
            rm -f "$TEMP_FILE"
            echo -e "${ROJO}❌ Error: Falló la escritura en el archivo temporal.${NC}"
            read -p "$(echo -e ${AZUL}Presiona Enter...${NC})"
            return 1
        }

        # Crear respaldo antes de mover
        cp "$REGISTROS" "${REGISTROS}.bak.$$" 2>/dev/null || {
            echo "$(date '+%Y-%m-%d %H:%M:%S'): Error creando respaldo de $REGISTROS." >> "/var/log/monitoreo_conexiones.log"
            rm -f "$TEMP_FILE"
            echo -e "${ROJO}❌ Error: No se pudo crear respaldo de $REGISTROS.${NC}"
            read -p "$(echo -e ${AZUL}Presiona Enter...${NC})"
            return 1
        }

        # Mover archivo temporal a REGISTROS
        if mv "$TEMP_FILE" "$REGISTROS" 2>/dev/null; then
            sync
            sleep 0.2
            # Verificar que el registro se escribió correctamente
            if ! grep -qw "^$USUARIO:" "$REGISTROS"; then
                echo "$(date '+%Y-%m-%d %H:%M:%S'): Error: Registro de '$USUARIO' no se encontró en $REGISTROS tras escritura." >> "/var/log/monitoreo_conexiones.log"
                mv "${REGISTROS}.bak.$$" "$REGISTROS" 2>/dev/null
                rm -f "$TEMP_FILE"
                echo -e "${ROJO}❌ Error: Falló la escritura del registro en $REGISTROS. Registro revertido.${NC}"
                read -p "$(echo -e ${AZUL}Presiona Enter...${NC})"
                return 1
            fi
            rm -f "${REGISTROS}.bak.$$"
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S'): Error moviendo $TEMP_FILE a $REGISTROS." >> "/var/log/monitoreo_conexiones.log"
            mv "${REGISTROS}.bak.$$" "$REGISTROS" 2>/dev/null
            rm -f "$TEMP_FILE"
            echo -e "${ROJO}❌ Error: No se pudo reemplazar $REGISTROS.${NC}"
            read -p "$(echo -e ${AZUL}Presiona Enter...${NC})"
            return 1
        fi
    } 200>"$REGISTROS.lock"

    # Crear usuario
    if ! useradd -m -s /bin/bash "$USUARIO"; then
        {
            flock -x -w 10 200
            sed -i "/^$USUARIO:/d" "$REGISTROS"
            sync
        } 200>"$REGISTROS.lock"
        echo "$(date '+%Y-%m-%d %H:%M:%S'): Error creando usuario '$USUARIO' en el sistema. Registro eliminado." >> "/var/log/monitoreo_conexiones.log"
        echo -e "${ROJO}❌ Error creando el usuario en el sistema.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter...${NC})"
        return 1
    fi

    # Establecer contraseña
    if ! echo "$USUARIO:$CLAVE" | chpasswd; then
        userdel -r "$USUARIO" 2>/dev/null
        {
            flock -x -w 10 200
            sed -i "/^$USUARIO:/d" "$REGISTROS"
            sync
        } 200>"$REGISTROS.lock"
        echo "$(date '+%Y-%m-%d %H:%M:%S'): Error estableciendo contraseña para '$USUARIO'. Registro y usuario eliminados." >> "/var/log/monitoreo_conexiones.log"
        echo -e "${ROJO}❌ Falló el cambio de contraseña. Registro revertido.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter...${NC})"
        return 1
    fi

    # Fecha de expiración
    if ! usermod -e "$EXPIRA_FECHA" "$USUARIO"; then
        userdel -r "$USUARIO" 2>/dev/null
        {
            flock -x -w 10 200
            sed -i "/^$USUARIO:/d" "$REGISTROS"
            sync
        } 200>"$REGISTROS.lock"
        echo "$(date '+%Y-%m-%d %H:%M:%S'): Error configurando expiración para '$USUARIO'. Registro y usuario eliminados." >> "/var/log/monitoreo_conexiones.log"
        echo -e "${ROJO}❌ Error configurando expiración. Registro eliminado.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter...${NC})"
        return 1
    fi

    # Mostrar resultado final
    FECHA_FORMAT=$(date -d "$EXPIRA_DATETIME" +"%d/%B/%Y" | awk '{print $1 "/" tolower($2) "/" $3}')
    echo
    echo -e "${VERDE}✅ Usuario creado correctamente:${NC}"
    echo -e "${AZUL}👤 Usuario: ${AMARILLO}$USUARIO"
    echo -e "${AZUL}🔑 Clave:   ${AMARILLO}$CLAVE"
    echo -e "${AZUL}📅 Expira:  ${AMARILLO}$FECHA_FORMAT"
    echo -e "${AZUL}📱 Límite móviles: ${AMARILLO}$MOVILES"
    echo -e "${AZUL}📅 Creado:  ${AMARILLO}$FECHA_CREACION"

    echo
    echo -e "${CIAN}===== 📝 RESUMEN DE REGISTRO =====${NC}"
    printf "${AMARILLO}%-15s %-20s %-15s %-15s %-20s${NC}\n" "👤 Usuario" "📅 Expira" "⏳ Días" "📱 Móviles" "📅 Creado"
    echo -e "${CIAN}---------------------------------------------------------------${NC}"
    printf "${VERDE}%-15s %-20s %-15s %-15s %-20s${NC}\n" "$USUARIO" "$FECHA_FORMAT" "${DIAS} días" "$MOVILES" "$FECHA_CREACION"
    echo -e "${CIAN}===============================================================${NC}"
    read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
}

#AQUI VOY 
function verificar_integridad_registros() {
    if [[ ! -f "$REGISTROS" ]]; then
        return
    fi

    ELIMINADOS=0
    TEMP_FILE=$(mktemp --tmpdir="$(dirname "$REGISTROS")")

    {
        # Bloqueo exclusivo para evitar condiciones de carrera
        if ! flock -x -w 10 200; then
            echo "$(date '+%Y-%m-%d %H:%M:%S'): No se pudo adquirir el bloqueo para verificar_integridad_registros." >> "/var/log/monitoreo_conexiones.log"
            rm -f "$TEMP_FILE"
            return 1
        fi

        while IFS=':' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL PRIMER_LOGIN; do
            if [[ -z "$USUARIO" ]]; then
                continue
            fi

            local user_exists=false
            for ((i=1; i<=3; i++)); do
                if id "$USUARIO" &>/dev/null; then
                    user_exists=true
                    break
                fi
                sleep 0.2
            done

            if ! $user_exists; then
                echo -e "${ROJO}⚠️ Registro huérfano encontrado: '$USUARIO' no existe en el sistema. Limpiando...${NC}"
                echo "$(date '+%Y-%m-%d %H:%M:%S'): Registro huérfano de '$USUARIO' eliminado." >> "/var/log/monitoreo_conexiones.log"
                ((ELIMINADOS++))
            else
                # Reescribir la línea usando ':' como separador
                printf '%s:%s:%s:%s:%s:%s:%s\n' \
                    "$USUARIO" "$CLAVE" "$EXPIRA_DATETIME" "$DURACION" "$MOVILES" "$BLOQUEO_MANUAL" "$PRIMER_LOGIN" >> "$TEMP_FILE"
            fi
        done < "$REGISTROS"

        if mv "$TEMP_FILE" "$REGISTROS" 2>/dev/null; then
            sync
            sleep 0.2
        else
            echo -e "${ROJO}❌ Error actualizando $REGISTROS después de limpiar.${NC}"
            echo "$(date '+%Y-%m-%d %H:%M:%S'): Error actualizando $REGISTROS después de limpiar." >> "/var/log/monitoreo_conexiones.log"
            rm -f "$TEMP_FILE"
            return 1
        fi
    } 200>"$REGISTROS.lock"

    if [[ $ELIMINADOS -gt 0 ]]; then
        echo -e "${CIAN}📊 Resumen: $ELIMINADOS registros huérfanos eliminados.${NC}"
    fi
}
#AQUI VOY


function barra_sistema() {
    # Colores
    BLANCO="\e[97m"
    AZUL="\e[94m"
    MAGENTA="\e[95m"
    ROJO="\e[91m"
    AMARILLO="\e[93m"
    NC="\e[0m"

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
        while IFS=':' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL PRIMER_LOGIN; do
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

    echo -e "${AZUL}══════════════════════════════════════════════════${NC}"
    echo -e "${BLANCO} 💾 TOTAL: ${AMARILLO}${MEM_TOTAL_H}${NC} ∘ ${BLANCO}💿 DISPONIBLE: ${AMARILLO}${MEM_DISPONIBLE_H}${NC} ∘ ${BLANCO}⚡ EN USO: ${AMARILLO}${MEM_USO_H}${NC}"
    echo -e "${BLANCO} 📊 U/RAM: ${AMARILLO}${MEM_PORC}%${NC} ∘ ${BLANCO}🖥️ U/CPU: ${AMARILLO}${CPU_PORC}%${NC} ∘ ${BLANCO}🔧 CPU MHz: ${AMARILLO}${CPU_MHZ}${NC}"
    echo -e "${AZUL}══════════════════════════════════════════════════${NC}"
    echo -e "${BLANCO} 🌍 IP: ${AMARILLO}${IP_PUBLICA}${NC} ∘ ${BLANCO}🕒 FECHA: ${AMARILLO}${FECHA_ACTUAL}${NC}"
    echo -e "${MAGENTA}🌸 𝐌𝐜𝐜𝐚𝐫𝐭𝐡𝐞𝐲${NC}"
    echo -e "${BLANCO}🔗 ONLINE:${AMARILLO}${TOTAL_CONEXIONES}${NC}   ${BLANCO}👥 TOTAL:${AMARILLO}${TOTAL_USUARIOS}${NC}   ${BLANCO}🖼️ SO:${AMARILLO}${SO_NAME}${NC}"
    echo -e "${AZUL}══════════════════════════════════════════════════${NC}"

    # Usuarios que expiran hoy
    if [[ -f $REGISTROS ]]; then
        USUARIOS_0DIAS=""
        while IFS=':' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL PRIMER_LOGIN; do
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


# Colores extras
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

    # Mostramos solo la última conexión por usuario
    tac "$HISTORIAL" | awk -F':' '!v[$1]++' | tac | while IFS=':' read -r USUARIO CONECTO DESCONECTO DURACION; do
        CONECTO_FMT=$(date -d "$CONECTO" +"%d/%B %I:%M %p" 2>/dev/null | \
            sed 's/January/enero/;s/February/febrero/;s/March/marzo/;s/April/abril/;s/May/mayo/;s/June/junio/;s/July/julio/;s/August/agosto/;s/September/septiembre/;s/October/octubre/;s/November/noviembre/;s/December/diciembre/' || echo "$CONECTO")

        DESCONECTO_FMT=$(date -d "$DESCONECTO" +"%d/%B %I:%M %p" 2>/dev/null | \
            sed 's/January/enero/;s/February/febrero/;s/March/marzo/;s/April/abril/;s/May/mayo/;s/June/junio/;s/July/julio/;s/August/agosto/;s/September/septiembre/;s/October/octubre/;s/November/noviembre/;s/December/diciembre/' || echo "$DESCONECTO")

        printf "${TURQUESA}%-15s %-22s %-22s %-12s${NC}\n" "$USUARIO" "$CONECTO_FMT" "$DESCONECTO_FMT" "$DURACION"
    done

    echo -e "${ROSADO}~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~${NC}"
    read -p "$(echo -e ${LILA}Presiona Enter para continuar, dulce... 🌟${NC})"
}

#AQUI VOY 


function eliminar_usuario() {
    clear
    echo -e "${VIOLETA}===== 💣 ELIMINAR USUARIO: NIVEL DIABLO - SATÁN ROOT 🔥 =====${NC}"

    if [[ ! -f $REGISTROS ]]; then
        echo -e "${ROJO}❌ No hay registros para eliminar (pero igual se procede con usuarios del sistema).${NC}"
    fi

    echo -e "${AMARILLO}Nº\t👤 Usuario${NC}"
    echo -e "${CIAN}--------------------------${NC}"
    NUM=1
    declare -A USUARIOS_EXISTENTES
    if [[ -f $REGISTROS ]]; then
        while IFS=':' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL PRIMER_LOGIN; do
            if id "$USUARIO" &>/dev/null; then
                echo -e "${VERDE}${NUM}\t${AMARILLO}$USUARIO${NC}"
                USUARIOS_EXISTENTES[$NUM]="$USUARIO"
                NUM=$((NUM+1))
            fi
        done < "$REGISTROS"
    fi

    if [[ ${#USUARIOS_EXISTENTES[@]} -eq 0 ]]; then
        echo -e "${AZUL}ℹ️ No hay usuarios en registros, pero puede ingresar nombres de usuarios del sistema para eliminar.${NC}"
    fi

    echo
    echo -e "${AMARILLO}🗑️ Ingrese los números o nombres de usuarios a eliminar (separados por espacios)${NC}"
    PROMPT=$(echo -e "${AMARILLO}   (0 para cancelar): ${NC}")
    read -p "$PROMPT" INPUT_ENTRADA
    if [[ "$INPUT_ENTRADA" == "0" ]]; then
        echo -e "${AZUL}🚫 Operación cancelada.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    read -ra ELEMENTOS <<< "$INPUT_ENTRADA"
    declare -a USUARIOS_A_ELIMINAR=()
    for ELEM in "${ELEMENTOS[@]}"; do
        if [[ "$ELEM" =~ ^[0-9]+$ ]]; then
            if [[ -n "${USUARIOS_EXISTENTES[$ELEM]}" ]]; then
                USUARIOS_A_ELIMINAR+=("${USUARIOS_EXISTENTES[$ELEM]}")
            else
                echo -e "${ROJO}❌ Número inválido: $ELEM${NC}"
            fi
        else
            if id "$ELEM" &>/dev/null; then
                USUARIOS_A_ELIMINAR+=("$ELEM")
            else
                echo -e "${ROJO}❌ Usuario inválido o no existe en el sistema: $ELEM${NC}"
            fi
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
    echo -e "${AMARILLO}✅ ¿Confirmar eliminación NUCLEAR NIVEL DIABLO? (s/n)${NC}"
    read -p "" CONFIRMAR
    if [[ $CONFIRMAR != [sS] ]]; then
        echo -e "${AZUL}🚫 Operación cancelada.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    for USUARIO in "${USUARIOS_A_ELIMINAR[@]}"; do
        USUARIO_LIMPIO=$(echo "$USUARIO" | tr -d '\r\n')
        USUARIO_ESCAPADO=$(printf '%s' "$USUARIO_LIMPIO" | sed 's/[^a-zA-Z0-9._-]//g')

        echo -e "${ROJO}💣 Eliminando usuario: $USUARIO_LIMPIO${NC}"

        sudo usermod --lock "$USUARIO_LIMPIO" 2>/dev/null || true
        sudo kill -9 $(pgrep -u "$USUARIO_LIMPIO") 2>/dev/null || true
        sleep 1
        sudo userdel --force "$USUARIO_LIMPIO" 2>/dev/null || true
        sudo deluser --remove-home "$USUARIO_LIMPIO" 2>/dev/null || true
        sudo rm -rf "/home/$USUARIO_LIMPIO" 2>/dev/null || true
        sudo loginctl kill-user "$USUARIO_LIMPIO" 2>/dev/null || true
        sudo deluser "$USUARIO_LIMPIO" 2>/dev/null || true

        # 🔃 Eliminar del archivo de registro (formato con :)
        if [[ -f $REGISTROS ]]; then
            awk -F':' -v user="$USUARIO_ESCAPADO" '$1 != user' "$REGISTROS" > /tmp/registros.tmp && mv /tmp/registros.tmp "$REGISTROS"
        fi

        # 🗑️ Eliminar del historial (formato con :)
        if [[ -f $HISTORIAL ]]; then
            sed -i "/^$USUARIO_ESCAPADO:/Id" "$HISTORIAL"
        fi

        # Limpiar historiales y carpetas
        HOME_DIR="/home/$USUARIO_LIMPIO"
        if [[ -d "$HOME_DIR" ]]; then
            sudo rm -f "$HOME_DIR/.bash_history" "$HOME_DIR/.zsh_history" "$HOME_DIR/.sh_history" "$HOME_DIR/.history" 2>/dev/null || true
        fi
        [[ "$USUARIO_LIMPIO" == "root" ]] && sudo rm -f /root/.bash_history 2>/dev/null || true

        # Limpiar logs de auth
        for LOGFILE in /var/log/auth.log /var/log/secure; do
            if [[ -f "$LOGFILE" ]]; then
                sudo sed -i "/$USUARIO_ESCAPADO/Id" "$LOGFILE" 2>/dev/null || true
            fi
        done

        sudo deluser "$USUARIO_LIMPIO" 2>/dev/null || true

        if [[ -f $REGISTROS ]]; then
            if grep -q "^$USUARIO_ESCAPADO:" "$REGISTROS"; then
                echo -e "${ROJO}⚡️⚡️⚡️  $USUARIO_LIMPIO sigue apareciendo en $REGISTROS después del intento. Revisión necesaria.${NC}"
            fi
        fi

        # 🧹 Limpiar líneas vacías
        sed -i '/^[[:space:]]*$/d' "$REGISTROS"

        if ! id "$USUARIO_LIMPIO" &>/dev/null; then
            echo -e "${VERDE}✅ Usuario $USUARIO_LIMPIO eliminado completamente y limpiado.${NC}"
        else
            echo -e "${ROJO}⚠️ El usuario $USUARIO_LIMPIO aún existe. Verifica manualmente.${NC}"
        fi

        echo -e "${CIAN}--------------------------------------${NC}"
    done

    echo -e "${VERDE}✅ Eliminación nuclear y limpieza completa (SATÁN ESTÁ ORGULLOSO).${NC}"
    read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
}

            
  function verificar_online() {
    clear
    ANARANJADO='\033[38;5;208m'
    AZUL_SUAVE='\033[38;5;45m'
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

    while IFS=':' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL PRIMER_LOGIN; do
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
                    ULTIMO_LOGOUT=$(grep "^$USUARIO:" "$HISTORIAL" | tail -1 | awk -F':' '{print $3}')
                    if [[ -n "$ULTIMO_LOGOUT" ]]; then
                        ULTIMO_LOGOUT_FMT=$(date -d "$ULTIMO_LOGOUT" +"%d de %B %I:%M %p" 2>/dev/null || echo "$ULTIMO_LOGOUT")
                        MES=$(echo "$ULTIMO_LOGOUT_FMT" | awk '{print $4}')
                        for k in "${!month_map[@]}"; do
                            if [[ "$MES" =~ ^$k ]]; then
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
        IFS=':' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL PRIMER_LOGIN <<< "$LINEA"
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
    IFS=':' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL PRIMER_LOGIN <<< "$USUARIO_LINEA"

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
        sed -i "s/^$USUARIO:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:/&SÍ:/" "$REGISTROS"
        echo -e "${VERDE}🔒 Usuario '$USUARIO' bloqueado exitosamente y sesiones SSH/Dropbear terminadas.${NC}"
    else
        usermod -U "$USUARIO"
        sed -i "s/^$USUARIO:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:/&NO:/" "$REGISTROS"
        echo -e "${VERDE}🔓 Usuario '$USUARIO' desbloqueado exitosamente.${NC}"
    fi

    read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
}
#Aquí Voy 

function mini_registro() {
    clear
    echo -e "${VIOLETA}===== 📋 MINI REGISTRO =====${NC}"

    verificar_integridad_registros

    if [[ ! -f "$REGISTROS" ]]; then
        echo -e "${ROJO}❌ No hay registros de usuarios.${NC}"
        read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
        return
    fi

    # Colores
    AZUL_SUAVE='\033[38;5;45m'
    SOFT_PINK='\033[38;5;211m'
    PASTEL_BLUE='\033[38;5;153m'
    LILAC='\033[38;5;183m'
    SOFT_CORAL='\033[38;5;217m'
    HOT_PINK='\033[38;5;198m'
    PASTEL_PURPLE='\033[38;5;189m'
    MINT_GREEN='\033[38;5;159m'
    NC='\033[0m'

    # Función para centrar valores
    center_value() {
        local value="$1"
        local width="$2"
        local len=${#value}
        local padding_left=$(( (width - len) / 2 ))
        local padding_right=$(( width - len - padding_left ))
        printf "%*s%s%*s" "$padding_left" "" "$value" "$padding_right" ""
    }

    # Encabezado
    printf "${SOFT_CORAL}%-15s ${PASTEL_BLUE}%-15s ${LILAC}%10s ${SOFT_PINK}%-15s${NC}\n" \
        "👤 Nombre" "🔑 Contraseña" "$(center_value '⏳ Días' 10)" "📱 Móviles"
    echo -e "${LILAC}--------------------------------------------${NC}"

    TOTAL_USUARIOS=0
    LOG="/var/log/monitoreo_conexiones.log"

    while IFS=':' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL FECHA_CREACION; do
        if id "$USUARIO" &>/dev/null; then
            USUARIO=${USUARIO:-"N/A"}
            CLAVE=${CLAVE:-"N/A"}
            EXPIRA_DATETIME=${EXPIRA_DATETIME:-"N/A"}
            MOVILES=${MOVILES:-"1"}

            # Calcular días restantes
            if [[ "$EXPIRA_DATETIME" != "N/A" ]] && FECHA_EXPIRA_DIA=$(date -d "$EXPIRA_DATETIME" +%Y-%m-%d 2>/dev/null); then
                FECHA_ACTUAL_DIA=$(date +%Y-%m-%d)
                DIAS_RESTANTES=$(( ( $(date -d "$FECHA_EXPIRA_DIA" +%s) - $(date -d "$FECHA_ACTUAL_DIA" +%s) ) / 86400 ))
                (( DIAS_RESTANTES < 0 )) && DIAS_RESTANTES=0
            else
                DIAS_RESTANTES="N/A"
            fi

            # Validar campo MOVILES
            if [[ "$MOVILES" =~ ^[0-9]+$ ]]; then
                MOVILES_NUM="$MOVILES"
            elif [[ "$MOVILES" =~ ^[0-9]+[[:space:]]*móviles$ ]]; then
                MOVILES_NUM=$(echo "$MOVILES" | grep -oE '[0-9]+')
            else
                echo "$(date '+%Y-%m-%d %H:%M:%S'): Formato inválido en campo MOVILES ('$MOVILES') para usuario '$USUARIO' en $REGISTROS." >> "$LOG"
                MOVILES_NUM="1"
            fi

            DIAS_RESTANTES_CENTRADO=$(center_value "$DIAS_RESTANTES" 10)
            printf "${SOFT_CORAL}%-15s ${PASTEL_BLUE}%-15s ${LILAC}%10s ${SOFT_PINK}%-15s${NC}\n" \
                "$USUARIO" "$CLAVE" "$DIAS_RESTANTES_CENTRADO" "$MOVILES_NUM"
            ((TOTAL_USUARIOS++))
        fi
    done < "$REGISTROS"

    echo -e "${LILAC}============================================${NC}\n"
    echo -e "${AMARILLO}TOTAL: $TOTAL_USUARIOS usuarios${NC}"
    read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
}




function nuclear_eliminar() {
    clear
    echo -e "${VIOLETA}===== 💣 ELIMINACIÓN COMPLETA DE USUARIOS (MODO NUCLEAR) =====${NC}"
    read -p "👤 Ingresa los nombres de usuarios a eliminar (separados por espacio): " USUARIOS

    for USUARIO in $USUARIOS; do
        USUARIO_LIMPIO=$(echo "$USUARIO" | tr -d '\r\n')
        echo -e "${AMARILLO}Procesando usuario: $USUARIO_LIMPIO${NC}"

        # Paso 0: Intento inicial de eliminar con deluser
        echo -e "${ROJO}→ (0) Primer intento con deluser...${NC}"
        sudo deluser "$USUARIO_LIMPIO" 2>/dev/null

        # Paso 1: Bloquear usuario si existe
        if id "$USUARIO_LIMPIO" &>/dev/null; then
            echo -e "${ROJO}→ (1) Bloqueando usuario...${NC}"
            sudo usermod --lock "$USUARIO_LIMPIO" 2>/dev/null
        fi

        # Paso 2: Matar todos sus procesos
        echo -e "${ROJO}→ (2) Matando procesos del usuario...${NC}"
        sudo kill -9 $(pgrep -u "$USUARIO_LIMPIO") 2>/dev/null

        # Paso 3: Eliminar usuario y home
        echo -e "${ROJO}→ (3) Eliminando cuentas y directorios...${NC}"
        sudo userdel --force "$USUARIO_LIMPIO" 2>/dev/null
        sudo deluser --remove-home "$USUARIO_LIMPIO" 2>/dev/null

        # Paso 4: Eliminar carpeta huérfana
        echo -e "${ROJO}→ (4) Eliminando carpeta /home/$USUARIO_LIMPIO (si existe)...${NC}"
        sudo rm -rf "/home/$USUARIO_LIMPIO"

        # Paso 5: Limpiar sesión con loginctl
        echo -e "${ROJO}→ (5) Limpiando sesiones residuales...${NC}"
        sudo loginctl kill-user "$USUARIO_LIMPIO" 2>/dev/null

        # Paso 6: Segundo intento con deluser
        echo -e "${ROJO}→ (6) Segundo y último intento con deluser...${NC}"
        sudo deluser "$USUARIO_LIMPIO" 2>/dev/null

        # Paso 7: Eliminar del archivo de registros e historial
        echo -e "${ROJO}→ (7) Borrando del registro y del historial...${NC}"
        if [[ -f "$REGISTROS" ]]; then
            sed -i "/^$USUARIO_LIMPIO:/d" "$REGISTROS"
        fi

        if [[ -f "$HISTORIAL" ]]; then
            sed -i "/^$USUARIO_LIMPIO:/d" "$HISTORIAL"
        fi

        # Verificar si aún está en registros (por formato mal aplicado quizá)
        if [[ -f "$REGISTROS" ]] && grep -q "^$USUARIO_LIMPIO:" "$REGISTROS"; then
            echo -e "${ROJO}⚠️ $USUARIO_LIMPIO sigue en $REGISTROS. Revisa el formato o limpieza manual.${NC}"
        fi

        # Paso 8: Verificación final
        if ! id "$USUARIO_LIMPIO" &>/dev/null; then
            echo -e "${VERDE}✅ Usuario $USUARIO_LIMPIO eliminado completamente y sin residuos.${NC}"
        else
            echo -e "${ROJO}⚠️ Advertencia: El usuario $USUARIO_LIMPIO aún existe. Verifica manualmente.${NC}"
        fi
        echo
    done

    read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"
}


#aquí voy 


function crear_multiples_usuarios() {
    clear
    echo -e "${VIOLETA}===== 🆕 CREAR MÚLTIPLES USUARIOS SSH =====${NC}"
    echo -e "${AMARILLO}📝 Formato: nombre contraseña días móviles (separados por espacios, una línea por usuario)${NC}"
    echo -e "${AMARILLO}📋 Ejemplo: lucy 123 5 4${NC}"
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
        return 1
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
        return 1
    fi

    ERROR_LOG="/tmp/creacion_usuarios_$(date +%Y%m%d_%H%M%S).log"
    touch "$ERROR_LOG" 2>/dev/null || ERROR_LOG=""

    [[ ! -f "$REGISTROS" ]] && touch "$REGISTROS" 2>/dev/null || {
        echo -e "${ROJO}❌ No se pudo crear o acceder a $REGISTROS.${NC}"
        return 1
    }

    [[ ! -w "$REGISTROS" ]] && {
        echo -e "${ROJO}❌ No se puede escribir en $REGISTROS. Verifica permisos.${NC}"
        return 1
    }

    EXITOS=0
    FALLOS=0

    garantizar_registro() {
        local USUARIO="$1" CLAVE="$2" EXPIRA_DATETIME="$3" DIAS="$4"
        local MOVILES="$5" FECHA_CREACION="$6"
        local intento=0 intento_max=5
        local registro_confirmado=false

        while [[ $intento -lt $intento_max ]] && [[ "$registro_confirmado" != "true" ]]; do
            intento=$((intento + 1))
            {
                flock -x 200 || { sleep 0.5; continue; }

                REGISTRO_LINEA="$USUARIO:$CLAVE:$EXPIRA_DATETIME:$DIAS:$MOVILES:NO:$FECHA_CREACION"

                TEMP_FILE=$(mktemp "${REGISTROS}.tmp.XXXXXX") || return 1

                grep -v "^$USUARIO:" "$REGISTROS" > "$TEMP_FILE" 2>/dev/null || {
                    cp "$REGISTROS" "$TEMP_FILE" 2>/dev/null
                    sed -i "/^$USUARIO:/d" "$TEMP_FILE"
                }

                echo "$REGISTRO_LINEA" >> "$TEMP_FILE" || {
                    rm -f "$TEMP_FILE"
                    return 1
                }

                cp "$REGISTROS" "${REGISTROS}.bak.$$" 2>/dev/null

                if mv "$TEMP_FILE" "$REGISTROS"; then
                    sync
                    if grep -q "^$USUARIO:$CLAVE" "$REGISTROS"; then
                        registro_confirmado=true
                        rm -f "${REGISTROS}.bak.$$"
                    else
                        [[ -f "${REGISTROS}.bak.$$" ]] && mv "${REGISTROS}.bak.$$" "$REGISTROS"
                    fi
                else
                    rm -f "$TEMP_FILE"
                    [[ -f "${REGISTROS}.bak.$$" ]] && mv "${REGISTROS}.bak.$$" "$REGISTROS"
                    sleep 0.2
                fi
            } 200>"$REGISTROS.lock"
        done
        rm -f "${REGISTROS}.bak.$$" 2>/dev/null
        [[ "$registro_confirmado" == "true" ]] && return 0 || return 1
    }

    for LINEA in "${USUARIOS[@]}"; do
        read -r USUARIO CLAVE DIAS MOVILES <<< "$LINEA"
        USUARIO_LIMPIO=$(echo "$USUARIO" | tr -d '\r\n')
        if [[ -z "$USUARIO_LIMPIO" || -z "$CLAVE" || -z "$DIAS" || -z "$MOVILES" ]]; then
            ((FALLOS++))
            continue
        fi

        if ! [[ "$DIAS" =~ ^[0-9]+$ && "$MOVILES" =~ ^[1-9][0-9]{0,2}$ && "$MOVILES" -le 999 ]]; then
            ((FALLOS++))
            continue
        fi

        if id "$USUARIO_LIMPIO" &>/dev/null; then
            ((FALLOS++))
            continue
        fi

        EXPIRA_DATETIME=$(date -d "+$DIAS days" +"%Y-%m-%d 00:00:00")
        EXPIRA_FECHA=$(date -d "+$((DIAS + 1)) days" +"%Y-%m-%d")
        FECHA_CREACION=$(date +"%Y-%m-%d %H:%M:%S")

        if ! garantizar_registro "$USUARIO_LIMPIO" "$CLAVE" "$EXPIRA_DATETIME" "$DIAS" "$MOVILES" "$FECHA_CREACION"; then
            ((FALLOS++))
            continue
        fi

        if ! useradd -m -s /bin/bash "$USUARIO_LIMPIO" 2>/dev/null; then
            {
                flock -x 200
                sed -i "/^$USUARIO_LIMPIO:/d" "$REGISTROS"
                sync
            } 200>"$REGISTROS.lock"
            ((FALLOS++))
            continue
        fi

        if ! echo "$USUARIO_LIMPIO:$CLAVE" | chpasswd 2>/dev/null; then
            userdel -r "$USUARIO_LIMPIO" 2>/dev/null
            {
                flock -x 200
                sed -i "/^$USUARIO_LIMPIO:/d" "$REGISTROS"
                sync
            } 200>"$REGISTROS.lock"
            ((FALLOS++))
            continue
        fi

        if ! usermod -e "$EXPIRA_FECHA" "$USUARIO_LIMPIO" 2>/dev/null; then
            userdel -r "$USUARIO_LIMPIO" 2>/dev/null
            {
                flock -x 200
                sed -i "/^$USUARIO_LIMPIO:/d" "$REGISTROS"
                sync
            } 200>"$REGISTROS.lock"
            ((FALLOS++))
            continue
        fi

        echo -e "${VERDE}✅ Usuario $USUARIO_LIMPIO creado exitosamente.${NC}"
        ((EXITOS++))
    done

    echo -e "${CIAN}===== 📊 RESUMEN DE CREACIÓN =====${NC}"
    echo -e "${VERDE}✅ Usuarios creados exitosamente: $EXITOS${NC}"
    echo -e "${ROJO}❌ Usuarios con error: $FALLOS${NC}"
    read -p "$(echo -e ${AZUL}Presiona Enter para continuar...${NC})"

    verificar_integridad_registros
}


function ver_registros() {
    clear
    echo -e "${AZUL_SUAVE}===== 🌸 REGISTROS =====${NC}"

    # Definir colores
    AZUL_SUAVE='\033[38;5;45m'
    SOFT_PINK='\033[38;5;211m'
    PASTEL_BLUE='\033[38;5;153m'
    LILAC='\033[38;5;183m'
    SOFT_CORAL='\033[38;5;217m'
    HOT_PINK='\033[38;5;198m'
    PASTEL_PURPLE='\033[38;5;189m'
    MINT_GREEN='\033[38;5;159m'
    NC='\033[0m'

    # Función para centrar un valor
    center_value() {
        local value="$1"
        local width="$2"
        local len=${#value}
        local padding_left=$(( (width - len) / 2 ))
        local padding_right=$(( width - len - padding_left ))
        printf "%*s%s%*s" "$padding_left" "" "$value" "$padding_right" ""
    }

    if [[ -f $REGISTROS ]]; then
        # Encabezado con colores
        printf "${SOFT_CORAL}%-3s ${PASTEL_BLUE}%-12s ${LILAC}%-12s ${PASTEL_PURPLE}%-12s ${MINT_GREEN}%10s ${SOFT_PINK}%-12s${NC}\n" \
            "Nº" "👩 Usuario" "🔒 Clave" "📅 Expira" "$(center_value '⏳ Días' 10)" "📲 Móviles"
        echo -e "${LILAC}-----------------------------------------------------------------------${NC}"

        NUM=1
        while IFS=':' read -r USUARIO CLAVE EXPIRA_DATETIME DURACION MOVILES BLOQUEO_MANUAL PRIMER_LOGIN; do
            if id "$USUARIO" &>/dev/null; then
                # Formato visual de fecha
                FORMATO_EXPIRA=$(date -d "$EXPIRA_DATETIME" +"%d/%B" | awk '{print $1 "/" tolower($2)}' 2>/dev/null || echo "$EXPIRA_DATETIME")

                # Calcular días restantes
                if FECHA_EXPIRA_DIA=$(date -d "$EXPIRA_DATETIME" +%Y-%m-%d 2>/dev/null); then
                    FECHA_ACTUAL_DIA=$(date +%Y-%m-%d)
                    DIAS_RESTANTES=$(( ($(date -d "$FECHA_EXPIRA_DIA" +%s) - $(date -d "$FECHA_ACTUAL_DIA" +%s)) / 86400 ))
                    (( DIAS_RESTANTES < 0 )) && DIAS_RESTANTES=0
                else
                    DIAS_RESTANTES="N/A"
                fi

                DURACION_CENTRADA=$(center_value "$DIAS_RESTANTES" 10)

                # Imprimir fila de usuario
                printf "${SOFT_CORAL}%-3d ${PASTEL_BLUE}%-12s ${LILAC}%-12s ${PASTEL_PURPLE}%-12s ${MINT_GREEN}%-10s ${SOFT_PINK}%-12s${NC}\n" \
                    "$NUM" "$USUARIO" "$CLAVE" "$FORMATO_EXPIRA" "$DURACION_CENTRADA" "$MOVILES"
                ((NUM++))
            fi
        done < "$REGISTROS"

        if [[ $NUM -eq 1 ]]; then
            echo -e "${HOT_PINK}❌ No hay usuarios existentes en el sistema o los registros no son válidos. 💔${NC}"
        fi
    else
        echo -e "${HOT_PINK}❌ No hay registros aún. El archivo '$REGISTROS' no existe. 📂${NC}"
    fi

    echo -e "${LILAC}=====================${NC}"
    read -p "$(echo -e ${PASTEL_PURPLE}Presiona Enter para continuar... ✨${NC})"
}


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
        echo -e "${AMARILLO_SUAVE}10. 🎨 Configurar banner SSH${NC}"
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
            10) configurar_banner_ssh ;;
            0) echo -e "${ROSA_CLARO}🚪 Saliendo...${NC}"; exit 0 ;;
            *) echo -e "${ROJO}❌ ¡Opción inválida!${NC}"; read -p "$(echo -e ${ROSA_CLARO}Presiona Enter para continuar...${NC})" ;;
        esac
    done
fi

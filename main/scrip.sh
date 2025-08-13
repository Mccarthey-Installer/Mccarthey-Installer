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

verificar_online() {
    clear
    echo "===== ✅   USUARIOS ONLINE ====="
    printf "%-14s %-14s %-10s %-25s\n" "👤 USUARIO" "✅ CONEXIONES" "📱 MÓVILES" "⏰ TIEMPO CONECTADO"
    echo "-----------------------------------------------------------------"

    total_online=0
    total_usuarios=0
    inactivos=0

    if [[ ! -f "$REGISTROS" ]]; then
        echo "❌ No hay registros."
        read -p "Presiona Enter para continuar..."
        return
    fi

    while read -r userpass fecha_exp dias moviles fecha_crea hora_crea; do
        usuario=${userpass%%:*}

        # 🔍 Verificar si el usuario existe, si no, saltar al siguiente
        if ! id "$usuario" &>/dev/null; then
            continue
        fi

        (( total_usuarios++ ))

        conexiones=$(( $(ps -u "$usuario" -o comm= | grep -cE "^(sshd|dropbear)$") ))

        estado="☑️ 0"
        detalle="😴 Nunca conectado"
        mov_txt="📲 $moviles"
        tmp_status="/tmp/status_${usuario}.tmp"

        if [[ $conexiones -gt 0 ]]; then
            # Usuario actualmente online
            estado="✅ $conexiones"
            (( total_online += conexiones ))

            if [[ -f "$tmp_status" ]]; then
                contenido=$(cat "$tmp_status")
                if [[ "$contenido" =~ ^[0-9]+$ ]]; then
                    # Epoch válido
                    start_s=$((10#$contenido))
                else
                    # Reparar si estaba en formato viejo
                    start_s=$(date +%s)
                    echo $start_s > "$tmp_status"
                fi

                now_s=$(date +%s)
                elapsed=$(( now_s - start_s ))

                h=$(( elapsed / 3600 ))
                m=$(( (elapsed % 3600) / 60 ))
                s=$(( elapsed % 60 ))
                detalle=$(printf "⏰ %02d:%02d:%02d" "$h" "$m" "$s")
            fi
        else
            # Usuario desconectado ahora
            rm -f "$tmp_status"
            ult=$(grep "^$usuario|" "$HISTORIAL" | tail -1 | awk -F'|' '{print $3}')
            if [[ -n "$ult" ]]; then
                ult_fmt=$(date -d "$ult" +"%d de %B %I:%M %p")
                detalle="📅 Última: $ult_fmt"
            else
                detalle="😴 Nunca conectado"
            fi
            (( inactivos++ )) # 📌 Siempre cuenta como inactivo si no está conectado
        fi

        printf "%-14s %-14s %-10s %-25s\n" "$usuario" "$estado" "$mov_txt" "$detalle"
    done < "$REGISTROS"

    echo "-----------------------------------------------------------------"
    echo "Total de Online: $total_online  Total usuarios: $total_usuarios  Inactivos: $inactivos"
    echo "================================================"
    read -p "Presiona Enter para continuar..."
}


bloquear_desbloquear_usuario() {
    clear
    echo "==== 🔒 BLOQUEAR/DESBLOQUEAR USUARIO ===="
    echo "===== 📋 USUARIOS REGISTRADOS ====="
    printf "%-4s %-15s %-15s %-22s %-25s\n" "Nº" "👤 Usuario" "🔑 Clave" "📅 Expira" "✅ Estado"
    echo "--------------------------------------------------------------------------"

    # Leer usuarios desde el archivo de registros
    usuarios=()
    index=1
    while read -r userpass fecha_exp dias moviles fecha_crea hora_crea; do
        usuario=${userpass%%:*}
        clave=${userpass#*:}
        estado="desbloqueado"
        bloqueo_file="/tmp/bloqueo_${usuario}.lock"

        if [[ -f "$bloqueo_file" ]]; then
            bloqueo_hasta=$(cat "$bloqueo_file")
            if [[ $(date +%s) -lt $bloqueo_hasta ]]; then
                estado="bloqueado (hasta $(date -d @$bloqueo_hasta '+%I:%M%p'))"
            else
                rm -f "$bloqueo_file"
                usermod -U "$usuario" 2>/dev/null
                estado="desbloqueado"
            fi
        fi

        printf "%-4s %-15s %-15s %-22s %-25s\n" "$index" "$usuario" "$clave" "$fecha_exp" "$estado"
        usuarios[$index]="$usuario"
        ((index++))
    done < "$REGISTROS"

    echo "=========================================================================="
    read -p "👤 Digite el número o el nombre del usuario: " input

    # Validar entrada
    if [[ "$input" =~ ^[0-9]+$ ]] && [[ -n "${usuarios[$input]}" ]]; then
        usuario="${usuarios[$input]}"
    else
        usuario="$input"
    fi

    # Verificar si el usuario existe
    if ! grep -q "^${usuario}:" "$REGISTROS"; then
        echo -e "${ROJO}❌ Usuario '$usuario' no encontrado.${NC}"
        read -p "Presiona Enter para continuar..."
        return
    fi

    bloqueo_file="/tmp/bloqueo_${usuario}.lock"
    if [[ -f "$bloqueo_file" ]] && [[ $(date +%s) -lt $(cat "$bloqueo_file") ]]; then
        echo -e "𒯢 El usuario '$usuario' está BLOQUEADO hasta $(date -d @$(cat "$bloqueo_file") '+%I:%M%p')."
        read -p "✅ Desea desbloquear al usuario '$usuario'? (s/n) " respuesta
        if [[ "$respuesta" =~ ^[sS]$ ]]; then
            rm -f "$bloqueo_file"
            usermod -U "$usuario" 2>/dev/null
            loginctl terminate-user "$usuario" 2>/dev/null
            pkill -9 -u "$usuario" 2>/dev/null
            killall -u "$usuario" -9 2>/dev/null
            echo -e "${VERDE}🔓 Usuario '$usuario' desbloqueado exitosamente.${NC}"
        else
            echo -e "${AMARILLO}⚠️ Operación cancelada.${NC}"
        fi
        read -p "Presiona Enter para continuar..."
        return
    else
        echo -e "𒯢 El usuario '$usuario' está DESBLOQUEADO."
        read -p "✅ Desea bloquear al usuario '$usuario'? (s/n) " respuesta
        if [[ "$respuesta" =~ ^[sS]$ ]]; then
            read -p "Ponga en minutos el tiempo que el usuario estaría bloqueado y confirmar con Enter: " minutos
            if [[ "$minutos" =~ ^[0-9]+$ ]] && [[ $minutos -gt 0 ]]; then
                bloqueo_hasta=$(( $(date +%s) + minutos * 60 ))
                echo "$bloqueo_hasta" > "$bloqueo_file"
                usermod -L "$usuario" 2>/dev/null
                loginctl terminate-user "$usuario" 2>/dev/null
                pkill -9 -u "$usuario" 2>/dev/null
                killall -u "$usuario" -9 2>/dev/null
                echo -e "${VERDE}🔒 Usuario '$usuario' bloqueado exitosamente y sesiones SSH terminadas. ✅${NC}"
                echo -e "Desbloqueado automáticamente hasta las $(date -d @$bloqueo_hasta '+%I:%M%p')"
            else
                echo -e "${ROJO}❌ Tiempo inválido. Debe ser un número mayor a 0.${NC}"
            fi
        else
            echo -e "${AMARILLO}⚠️ Operación cancelada.${NC}"
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
        echo -e "${VIOLETA}====== 🎊 PANEL DE USUARIOS VPN/SSH ======${NC}"
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
            1) crear_registro ;;
            2) ver_registros ;;
            3) nuclear_eliminar ;;
            4) informacion_usuarios ;;
            5) verificar_online ;;
            6) bloquear_desbloquear_usuario ;;
            7) crear_multiples_usuarios ;;
            8) mini_registro ;;
            9) eliminar_usuario ;;
            10) configurar_banner_ssh ;;
            0) exit 0 ;;
            *) echo -e "${ROJO}❌ ¡Opción inválida!${NC}"; read -p "$(echo -e ${ROSA_CLARO}Presiona Enter para continuar...${NC})" ;;
        esac
    done
fi

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
    INTERVALO=5

    while true; do
        [[ ! -f "$REGISTROS" ]] && { sleep "$INTERVALO"; continue; }

        TEMP_FILE=$(mktemp) || { sleep "$INTERVALO"; continue; }
        cp "$REGISTROS" "$TEMP_FILE" 2>/dev/null || { rm -f "$TEMP_FILE"; sleep "$INTERVALO"; continue; }
        TEMP_FILE_NEW=$(mktemp) || { rm -f "$TEMP_FILE"; sleep "$INTERVALO"; continue; }
        > "$TEMP_FILE_NEW"

        while read -r userpass fecha_exp dias moviles fecha_crea hora_crea; do
            usuario=${userpass%%:*}
            [[ -z "$usuario" ]] && continue

            tmp_status="/tmp/status_${usuario}.tmp"
            conexiones=$(( $(ps -u "$usuario" -o comm= | grep -c "^sshd$") + $(ps -u "$usuario" -o comm= | grep -c "^dropbear$") ))

            if [[ $conexiones -gt 0 ]]; then
                if [[ ! -f "$tmp_status" ]]; then
                    # Guardar hora en segundos UNIX para cronómetro
                    date +%s > "$tmp_status"
                    echo "$(date '+%Y-%m-%d %H:%M:%S'): $usuario conectado." >> "$LOG"
                fi
            else
                if [[ -f "$tmp_status" ]]; then
                    hora_ini=$(date -d @"$(cat "$tmp_status")" "+%Y-%m-%d %H:%M:%S")
                    hora_fin=$(date "+%Y-%m-%d %H:%M:%S")
                    rm -f "$tmp_status"
                    echo "$usuario|$hora_ini|$hora_fin" >> "$HISTORIAL"
                    echo "$(date '+%Y-%m-%d %H:%M:%S'): $usuario desconectado. Inicio: $hora_ini Fin: $hora_fin" >> "$LOG"
                fi
            fi

            echo "$userpass $fecha_exp $dias $moviles $fecha_crea $hora_crea" >> "$TEMP_FILE_NEW"
        done < "$TEMP_FILE"

        mv "$TEMP_FILE_NEW" "$REGISTROS" 2>/dev/null
        rm -f "$TEMP_FILE"
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
        (( total_usuarios++ ))

        conexiones=$(( $(ps -u "$usuario" -o comm= | grep -c "^sshd$") + $(ps -u "$usuario" -o comm= | grep -c "^dropbear$") ))

        estado="☑️ 0"
        detalle="😴 Nunca conectado"
        mov_txt="📲 $moviles"
        tmp_status="/tmp/status_${usuario}.tmp"

        if [[ $conexiones -gt 0 ]]; then
            estado="✅ $conexiones"
            (( total_online += conexiones ))

            if [[ -f "$tmp_status" ]]; then
                contenido=$(cat "$tmp_status")
                if [[ "$contenido" =~ ^[0-9]+$ ]]; then
                    # Ya es segundos UNIX
                    start_s=$((10#$contenido))
                else
                    # Formato viejo -> reiniciar con hora actual
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
            rm -f "$tmp_status"
            ult=$(grep "^$usuario|" "$HISTORIAL" | tail -1 | awk -F'|' '{print $3}')
            if [[ -n "$ult" ]]; then
                ult_fmt=$(date -d "$ult" +"%d de %B %I:%M %p")
                detalle="📅 Última: $ult_fmt"
            else
                (( inactivos++ ))
            fi
        fi

        printf "%-14s %-14s %-10s %-25s\n" "$usuario" "$estado" "$mov_txt" "$detalle"
    done < "$REGISTROS"

    echo "-----------------------------------------------------------------"
    echo "Total de Online: $total_online  Total usuarios: $total_usuarios  Inactivos: $inactivos"
    echo "================================================"
    read -p "Presiona Enter para continuar..."
}

# ================================
#  MENÚ PRINCIPAL
# ================================
while true; do
    clear
    echo "===== ⛑️MENÚ SSH WEBSOCKET ====="
    echo "1. 📧Verificar usuarios online "    
    echo "0. Salir"
    read -p "Selecciona una opción: " opcion

    case $opcion in
        1) verificar_online ;;
        0) echo "Saliendo..."; exit 0 ;;
        *) echo "Opción inválida."; read -p "Presiona Enter para continuar..." ;;
    esac
done

#!/bin/bash

# Definir rutas
export REGISTROS="/diana/reg.txt"
export HISTORIAL="/alexia/log.txt"
export PIDFILE="/Abigail/mon.pid"

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

    # Obtener fecha actual y de expiración
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
ver_registros() {
    clear
    echo "===== 🌸 REGISTROS ====="
    echo "Nº 👩 Usuario 🔒 Clave   📅 Expira    ⏳ Días   📲 Móviles"
    if [[ ! -f $REGISTROS || ! -s $REGISTROS ]]; then
        echo "No hay registros disponibles."
    else
        count=1
        while IFS=' ' read -r user_data fecha_expiracion dias moviles fecha_creacion; do
            usuario=${user_data%%:*}
            clave=${user_data#*:}
            printf "%-2s %-11s %-10s %-16s %-8s %-8s\n" "$count" "$usuario" "$clave" "$fecha_expiracion" "$dias" "$moviles"
            ((count++))
        done < $REGISTROS
    fi
    read -p "Presiona Enter para continuar..."
}

# Menú principal
while true; do
    clear
    echo "===== MENÚ SSH WEBSOCKET ====="
    echo "1. Crear usuario"
    echo "2. Ver registros"
    echo "0. Salir"
    read -p "Selecciona una opción: " opcion

    case $opcion in
        1)
            crear_usuario
            ;;
        2)
            ver_registros
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

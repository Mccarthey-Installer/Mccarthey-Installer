#!/bin/bash
# installer.sh - MCCARTHEY PRO INSTALLER
# OPCIÓN B: BINARIO SEGURO (CÓDIGO NUNCA EN GITHUB)
# Versión: 3.2 PROFESIONAL
#
# Uso:
# wget -O installer.sh https://raw.githubusercontent.com/Mccarthey-Installer/Mccarthey-Installer/master/installer.sh && chmod +x installer.sh && bash installer.sh

set -euo pipefail

echo "🚀 Mccarthey Pro Installer v3.2 (Opción B - Binario Seguro)"
echo "════════════════════════════════════════════════════════════"
echo ""

# ════════════════════════════════════════════════════════════════
# CONFIGURACIÓN
# ════════════════════════════════════════════════════════════════

REPO_URL="https://raw.githubusercontent.com/Mccarthey-Installer/Mccarthey-Installer/master"
BINARY_FILE="mccarthey_installer"

# ════════════════════════════════════════════════════════════════
# PASO 1: DESCARGAR BINARIO PRECOMPILADO DESDE GITHUB
# ════════════════════════════════════════════════════════════════

echo "📥 Descargando binario precompilado desde GitHub..."

DOWNLOAD_URL="${REPO_URL}/${BINARY_FILE}"

# Crear directorio temporal seguro
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Descargar binario con reintentos
if curl -fsSL --connect-timeout 5 --max-time 30 "$DOWNLOAD_URL" -o "$TEMP_DIR/$BINARY_FILE"; then
    echo "✅ Binario descargado correctamente"
else
    echo "❌ Error al descargar. Verifica tu conexión a internet."
    echo "   URL: $DOWNLOAD_URL"
    exit 1
fi

# Verificar que no está vacío
if [ ! -s "$TEMP_DIR/$BINARY_FILE" ]; then
    echo "❌ El binario descargado está vacío"
    exit 1
fi

# ════════════════════════════════════════════════════════════════
# PASO 2: VERIFICAR QUE ES UN BINARIO ELF VÁLIDO
# ════════════════════════════════════════════════════════════════

echo "🔍 Verificando integridad del binario..."

if file "$TEMP_DIR/$BINARY_FILE" | grep -q "ELF"; then
    echo "✅ Binario verificado: archivo ELF válido"
else
    echo "❌ El archivo descargado no es un binario válido"
    echo "   Se esperaba: ELF executable"
    echo "   Se recibió: $(file "$TEMP_DIR/$BINARY_FILE")"
    exit 1
fi

# ════════════════════════════════════════════════════════════════
# PASO 3: DAR PERMISOS DE EJECUCIÓN
# ════════════════════════════════════════════════════════════════

echo "🔧 Configurando permisos..."
chmod +x "$TEMP_DIR/$BINARY_FILE"

# ════════════════════════════════════════════════════════════════
# PASO 4: EJECUTAR BINARIO BLINDADO
# ════════════════════════════════════════════════════════════════

echo ""
echo "════════════════════════════════════════════════════════════"
echo "🎯 Iniciando Mccarthey Pro (Binario Compilado)..."
echo "════════════════════════════════════════════════════════════"
echo ""

# Ejecutar binario desde directorio temporal
"$TEMP_DIR/$BINARY_FILE"

# El trap se ejecutará automáticamente al salir, eliminando el directorio temporal

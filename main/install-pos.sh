#!/bin/bash
set -euo pipefail

# ===========================================================
# ===== CONFIGURACIÓN
# ===========================================================

DOMAIN="tienda.valeentina.shop"
REPO="https://github.com/Mccarthey-Installer/Mccarthey-Installer.git"
APP_DIR="/var/www/pos"
PORT="9092"
ENV_FILE="$APP_DIR/.env"

DEPLOY_LOCK="/tmp/pos-deploy.lock"
DEPLOY_LOG="/var/log/pos-deploy.log"

# ===========================================================
# ===== DEPLOY LOCK — evita ejecuciones simultáneas
# ===========================================================

if [ -e "$DEPLOY_LOCK" ]; then
  LOCK_PID=$(cat "$DEPLOY_LOCK" 2>/dev/null || echo "?")
  echo "  ✗ ERROR: ya hay un deploy corriendo (PID $LOCK_PID)"
  echo "  Si es un proceso muerto, borrá el lock con: rm $DEPLOY_LOCK"
  exit 1
fi

echo $$ > "$DEPLOY_LOCK"

cleanup() {
  local EXIT_CODE=$?
  rm -f "$DEPLOY_LOCK"
  rm -f "$APP_DIR/server.js.new" 2>/dev/null || true
  if [ $EXIT_CODE -ne 0 ]; then
    echo ""
    echo "  ✗ DEPLOY FALLÓ (código $EXIT_CODE) — $(date)" | tee -a "$DEPLOY_LOG"
    echo "  Revisá los errores arriba antes de correr el script de nuevo."
  else
    echo "  ✓ DEPLOY COMPLETADO OK — $(date)" | tee -a "$DEPLOY_LOG"
  fi
}
trap cleanup EXIT

echo "===== DEPLOY INICIADO — $(date) =====" | tee -a "$DEPLOY_LOG"

# ===========================================================
# ===== VALIDACIONES PREVIAS
# ===========================================================

echo "===== VERIFICANDO PERMISOS ====="
if [ "$(id -u)" -ne 0 ]; then
  echo "  ✗ Este script requiere root (corré con sudo)"
  exit 1
fi
echo "  ✓ Corriendo como root"

echo "===== DETENIENDO PROCESO ANTERIOR ====="
pm2 delete pos 2>/dev/null || true

echo "===== ACTUALIZANDO SISTEMA ====="
apt update -y

echo "===== INSTALANDO DEPENDENCIAS ====="
apt install -y git curl mysql-server jq

echo "===== VERIFICANDO MYSQL ====="
# Arrancar si no está corriendo
if ! systemctl is-active --quiet mysql; then
  echo "  → MySQL no está activo — arrancando..."
  systemctl start mysql
  sleep 2
fi

# Verificar que responde de verdad
MYSQL_RETRIES=5
MYSQL_OK=0
for i in $(seq 1 $MYSQL_RETRIES); do
  if mysqladmin ping --silent 2>/dev/null; then
    MYSQL_OK=1
    break
  fi
  echo "  ⏳ Esperando MySQL (intento $i/$MYSQL_RETRIES)..."
  sleep 2
done

if [ "$MYSQL_OK" -eq "0" ]; then
  echo "  ✗ ERROR: MySQL no responde después de $MYSQL_RETRIES intentos"
  echo "  Revisá con: systemctl status mysql"
  exit 1
fi

# Habilitar arranque automático
systemctl enable mysql --quiet
echo "  ✓ MySQL corriendo y habilitado en arranque"

echo "===== VERIFICANDO NODE ====="
NODE_REQUIRED=20
NODE_OK=0

if command -v node &>/dev/null; then
  NODE_CURRENT=$(node -e "console.log(process.versions.node.split('.')[0])" 2>/dev/null)
  if [ "$NODE_CURRENT" = "$NODE_REQUIRED" ]; then
    echo "  ✓ Node ya instalado en versión $NODE_CURRENT — sin cambios"
    NODE_OK=1
  else
    echo "  ⚠️  Node $NODE_CURRENT detectado, se requiere $NODE_REQUIRED — actualizando..."
  fi
else
  echo "  → Node no encontrado — instalando versión $NODE_REQUIRED..."
fi

if [ "$NODE_OK" -eq "0" ]; then
  curl -fsSL https://deb.nodesource.com/setup_${NODE_REQUIRED}.x | bash -
  apt install -y nodejs
  NODE_POST=$(node -e "console.log(process.versions.node.split('.')[0])" 2>/dev/null)
  if [ "$NODE_POST" != "$NODE_REQUIRED" ]; then
    echo "  ✗ ERROR: Node se instaló como versión $NODE_POST (esperado $NODE_REQUIRED)"
    exit 1
  fi
  echo "  ✓ Node $NODE_POST instalado correctamente"
fi

echo "===== VERIFICANDO PM2 ====="
if command -v pm2 &>/dev/null; then
  echo "  ✓ PM2 ya instalado ($(pm2 -v)) — sin cambios"
else
  echo "  → Instalando PM2..."
  npm install -g pm2
  echo "  ✓ PM2 instalado"
fi

echo "===== CLONANDO O ACTUALIZANDO POS ====="
mkdir -p /var/www
if [ ! -d "$APP_DIR" ]; then
  git clone "$REPO" "$APP_DIR"
else
  cd "$APP_DIR"

  # Guardar estado del repo por si el pull falla
  GIT_PREV_HASH=$(git rev-parse HEAD 2>/dev/null || echo "")

  # Stash de cambios locales no commiteados (protege trabajo manual)
  if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
    echo "  ⚠️  Cambios locales detectados — guardando en stash..."
    git stash push -m "auto-stash deploy $(date +%Y%m%d_%H%M%S)" || true
  fi

  # Pull con detección de fallo
  if ! git pull 2>&1; then
    echo "  ✗ git pull falló — abortando deploy"
    # Restaurar hash anterior si quedó a medias
    if [ -n "$GIT_PREV_HASH" ]; then
      echo "  → Restaurando commit anterior ($GIT_PREV_HASH)..."
      git reset --hard "$GIT_PREV_HASH" || true
    fi
    exit 1
  fi

  GIT_NEW_HASH=$(git rev-parse HEAD 2>/dev/null || echo "")
  if [ "$GIT_PREV_HASH" = "$GIT_NEW_HASH" ]; then
    echo "  · Repo sin cambios ($(git log -1 --format='%h %s'))"
  else
    echo "  ✓ Repo actualizado: $GIT_PREV_HASH → $GIT_NEW_HASH"
  fi
fi

cd "$APP_DIR"
echo ".env" >> .gitignore 2>/dev/null || true
sort -u .gitignore -o .gitignore 2>/dev/null || true

echo "===== CREANDO package.json SI NO EXISTE ====="
if [ ! -f "$APP_DIR/package.json" ]; then
cat <<'PKGJSON' > "$APP_DIR/package.json"
{
  "name": "pos-pro",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": {
    "express": "^4.18.2",
    "mysql2": "^3.9.0",
    "cors": "^2.8.5",
    "bcrypt": "^5.1.0",
    "uuid": "^9.0.0",
    "dotenv": "^16.0.0",
    "express-rate-limit": "^7.1.5"
  }
}
PKGJSON
echo "package.json creado"
else
  echo "package.json ya existe — conservado"
fi

echo "===== INSTALANDO LIBRERIAS ====="
npm install
npm install express-rate-limit

echo "===== GENERANDO SECRETO DE BACKUP (solo si no existe) ====="
if [ ! -f "$ENV_FILE" ]; then
  BACKUP_SECRET=$(openssl rand -hex 32)
  echo "BACKUP_SECRET=$BACKUP_SECRET" > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  echo "Secreto generado y guardado en $ENV_FILE"
else
  echo ".env ya existe — secreto conservado"
  BACKUP_SECRET=$(grep BACKUP_SECRET "$ENV_FILE" | cut -d= -f2)
fi

# ===========================================================
# ===== BASE DE DATOS
# ===========================================================

echo "===== CREANDO BASE DE DATOS Y USUARIO ====="

mysql -e "CREATE DATABASE IF NOT EXISTS posdb;"
mysql <<'EOF'
CREATE USER IF NOT EXISTS 'posuser'@'localhost' IDENTIFIED BY 'pos123';
GRANT ALL PRIVILEGES ON posdb.* TO 'posuser'@'localhost';
FLUSH PRIVILEGES;
EOF

mysql posdb <<'EOF'

CREATE TABLE IF NOT EXISTS products(
  id    INT AUTO_INCREMENT PRIMARY KEY,
  name  VARCHAR(100),
  price DECIMAL(10,2),
  cost  DECIMAL(10,2),
  stock INT DEFAULT 0,
  sold  INT DEFAULT 0,
  cat   VARCHAR(100)
);

CREATE TABLE IF NOT EXISTS admins(
  id            INT AUTO_INCREMENT PRIMARY KEY,
  username      VARCHAR(50),
  password_hash TEXT,
  recovery_key  VARCHAR(50),
  created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS sessions(
  id            INT AUTO_INCREMENT PRIMARY KEY,
  token         VARCHAR(200),
  admin_id      INT,
  created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  last_activity TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS sales(
  id            VARCHAR(36) NOT NULL,
  num           INT          NOT NULL AUTO_INCREMENT,
  date          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  total         DECIMAL(10,2),
  paid          DECIMAL(10,2),
  change_amount DECIMAL(10,2),
  PRIMARY KEY   (id),
  UNIQUE KEY    uk_num (num)
);

CREATE TABLE IF NOT EXISTS sale_items(
  id         INT AUTO_INCREMENT PRIMARY KEY,
  sale_id    VARCHAR(36) NOT NULL,
  product_id INT,
  name       VARCHAR(255),
  price      DECIMAL(10,2),
  cost       DECIMAL(10,2),
  qty        INT,
  CONSTRAINT fk_sale FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS expenses(
  id          INT AUTO_INCREMENT PRIMARY KEY,
  amount      DECIMAL(10,2) NOT NULL,
  description VARCHAR(255),
  category    VARCHAR(50)   DEFAULT 'General',
  created_at  TIMESTAMP     DEFAULT CURRENT_TIMESTAMP
);

EOF

# ===========================================================
# ===== SCHEMA GUARDIAN — BASH
# ===========================================================

ensure_column() {
  local TABLE="$1"
  local COLUMN="$2"
  local DEFINITION="$3"
  local EXPECTED_TYPE="$4"

  if [ "$COLUMN" = "id" ]; then
    echo "  · Saltando PK: $TABLE.$COLUMN (definida solo en CREATE TABLE)"
    return
  fi

  local EXISTS
  EXISTS=$(mysql posdb -sN -e "
    SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA='posdb'
      AND TABLE_NAME='$TABLE'
      AND COLUMN_NAME='$COLUMN';
  " 2>/dev/null)

  if [ "$EXISTS" -eq "0" ]; then
    echo "  → Agregando columna: $TABLE.$COLUMN ($DEFINITION)"
    if mysql posdb -e "ALTER TABLE \`$TABLE\` ADD COLUMN \`$COLUMN\` $DEFINITION;" 2>/dev/null; then
      echo "  ✓ Columna creada: $TABLE.$COLUMN"
    else
      echo "  ✗ ERROR al crear: $TABLE.$COLUMN — revisar manualmente"
    fi
  else
    if [ -n "$EXPECTED_TYPE" ]; then
      local ACTUAL_TYPE
      ACTUAL_TYPE=$(mysql posdb -sN -e "
        SELECT LOWER(DATA_TYPE) FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA='posdb'
          AND TABLE_NAME='$TABLE'
          AND COLUMN_NAME='$COLUMN';
      " 2>/dev/null)

      if [ "$ACTUAL_TYPE" != "$EXPECTED_TYPE" ]; then
        echo "  ⚠️  ALERTA TIPO: $TABLE.$COLUMN existe como '$ACTUAL_TYPE' (esperado: '$EXPECTED_TYPE')"
        echo "  ⚠️  No se modifica automáticamente para proteger datos — revisión manual requerida"
        echo "$(date) [SCHEMA_ALERT] $TABLE.$COLUMN tipo='$ACTUAL_TYPE' esperado='$EXPECTED_TYPE'" >> /var/log/pos-schema.log
      else
        echo "  · OK: $TABLE.$COLUMN ($ACTUAL_TYPE)"
      fi
    else
      echo "  · Columna ya existe: $TABLE.$COLUMN"
    fi
  fi
}

ensure_index() {
  local TABLE="$1"
  local INDEX_NAME="$2"
  local INDEX_DEF="$3"

  local EXISTS
  EXISTS=$(mysql posdb -sN -e "
    SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS
    WHERE TABLE_SCHEMA='posdb'
      AND TABLE_NAME='$TABLE'
      AND INDEX_NAME='$INDEX_NAME';
  " 2>/dev/null)

  if [ "$EXISTS" -eq "0" ]; then
    echo "  → Agregando índice: $TABLE.$INDEX_NAME $INDEX_DEF"
    if mysql posdb -e "ALTER TABLE \`$TABLE\` ADD INDEX \`$INDEX_NAME\` $INDEX_DEF;" 2>/dev/null; then
      echo "  ✓ Índice creado: $INDEX_NAME"
    else
      echo "  ✗ ERROR al crear índice: $INDEX_NAME — revisar manualmente"
    fi
  else
    echo "  · Índice ya existe: $INDEX_NAME en $TABLE"
  fi
}

echo "===== SCHEMA GUARDIAN (bash) ====="

ensure_column "products" "name"  "VARCHAR(100)"           "varchar"
ensure_column "products" "price" "DECIMAL(10,2)"          "decimal"
ensure_column "products" "cost"  "DECIMAL(10,2)"          "decimal"
ensure_column "products" "stock" "INT DEFAULT 0"          "int"
ensure_column "products" "sold"  "INT DEFAULT 0"          "int"
ensure_column "products" "cat"   "VARCHAR(100)"           "varchar"

ensure_column "admins" "username"      "VARCHAR(50)"      "varchar"
ensure_column "admins" "password_hash" "TEXT"             "text"
ensure_column "admins" "recovery_key"  "VARCHAR(50)"      "varchar"
ensure_column "admins" "created_at"    "TIMESTAMP DEFAULT CURRENT_TIMESTAMP" "timestamp"

ensure_column "sessions" "token"         "VARCHAR(200)"   "varchar"
ensure_column "sessions" "admin_id"      "INT"            "int"
ensure_column "sessions" "created_at"    "TIMESTAMP DEFAULT CURRENT_TIMESTAMP" "timestamp"
ensure_column "sessions" "last_activity" "TIMESTAMP DEFAULT CURRENT_TIMESTAMP" "timestamp"

ensure_column "sales" "num"           "INT NOT NULL AUTO_INCREMENT UNIQUE" "int"
ensure_column "sales" "date"          "DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP" "datetime"
ensure_column "sales" "total"         "DECIMAL(10,2)"            "decimal"
ensure_column "sales" "paid"          "DECIMAL(10,2)"            "decimal"
ensure_column "sales" "change_amount" "DECIMAL(10,2)"            "decimal"

ensure_column "sale_items" "sale_id"    "VARCHAR(36) NOT NULL"   "varchar"
ensure_column "sale_items" "product_id" "INT"                    "int"
ensure_column "sale_items" "name"       "VARCHAR(255)"           "varchar"
ensure_column "sale_items" "price"      "DECIMAL(10,2)"          "decimal"
ensure_column "sale_items" "cost"       "DECIMAL(10,2)"          "decimal"
ensure_column "sale_items" "qty"        "INT"                    "int"

ensure_column "expenses" "amount"      "DECIMAL(10,2) NOT NULL"              "decimal"
ensure_column "expenses" "description" "VARCHAR(255)"                        "varchar"
ensure_column "expenses" "category"    "VARCHAR(50) DEFAULT 'General'"       "varchar"
ensure_column "expenses" "created_at"  "TIMESTAMP DEFAULT CURRENT_TIMESTAMP" "timestamp"

ensure_index "sales"      "idx_num"        "(num)"
ensure_index "sales"      "idx_date"       "(date)"
ensure_index "sale_items" "idx_product_id" "(product_id)"
ensure_index "expenses"   "idx_exp_date"   "(created_at)"
ensure_index "expenses"   "idx_exp_cat"    "(category)"

echo "===== FIN SCHEMA GUARDIAN (bash) ====="

echo ""
echo "Estado final de la tabla sales:"
mysql posdb -e "DESCRIBE sales;"
echo ""
echo "Estado final de la tabla expenses:"
mysql posdb -e "DESCRIBE expenses;"
echo ""

# ===========================================================
# ===== ADMIN
# ===========================================================

echo "===== CREANDO ADMIN ====="

HASH=$(node -e "require('bcrypt').hash('admin123',10).then(h=>console.log(h))")
mysql posdb -e "
  INSERT IGNORE INTO admins(username, password_hash, recovery_key)
  VALUES('admin', '$HASH', 'POS-RECOVERY-123');
"

# ===========================================================
# ===== SERVER.JS  (escritura segura con backup + rollback)
# ===========================================================

echo "===== ESCRIBIENDO SERVER.JS ====="

SERVER_NEW="$APP_DIR/server.js.new"
SERVER_BAK=""

# Escribir SIEMPRE en archivo temporal primero
cat <<'SERVEREOF' > "$SERVER_NEW"
require("dotenv").config()
const express   = require("express")
const path      = require("path")
const fs        = require("fs")
const mysql     = require("mysql2")
const cors      = require("cors")
const bcrypt    = require("bcrypt")
const rateLimit = require("express-rate-limit")
const { v4: uuidv4 } = require("uuid")

const app  = express()
const PORT = __PORT_PLACEHOLDER__

app.use(cors())
app.use(express.json({ limit: '300mb' }))

/* ─── LOGGER ────────────────────────────────────────────────────────────── */

const LOG_FILE      = path.join(__dirname, "errors.log")
const LOG_MAX_BYTES = 5 * 1024 * 1024

function rotateLogs() {
  try {
    const stat = fs.statSync(LOG_FILE)
    if (stat.size > LOG_MAX_BYTES) {
      const archived = LOG_FILE + ".old"
      if (fs.existsSync(archived)) fs.unlinkSync(archived)
      fs.renameSync(LOG_FILE, archived)
    }
  } catch (_) {}
}

function logError(ctx, err) {
  rotateLogs()
  const line = new Date().toLocaleString("sv-SE") +
    " [" + ctx + "] " + (err.message || err) + "\n"
  console.error(line.trim())
  fs.appendFileSync(LOG_FILE, line)
}

function logInfo(ctx, msg) {
  const line = new Date().toLocaleString("sv-SE") + " [" + ctx + "] " + msg + "\n"
  console.log(line.trim())
}

/* ─── POOL ──────────────────────────────────────────────────────────────── */

const db = mysql.createPool({
  host:            "localhost",
  user:            "posuser",
  password:        "pos123",
  database:        "posdb",
  connectionLimit: 10
})

/* =========================================================
   VALIDACIÓN DE PRODUCTOS
   ========================================================= */

const CAT_INVALID_PATTERN = /^\d+$/
const CAT_VALID_PATTERN   = /^[a-zA-ZáéíóúÁÉÍÓÚüÜñÑ0-9 \-_&/]+$/

function validateProduct(body) {
  const errors = []

  if (typeof body.name !== "string" || body.name.trim().length === 0) {
    errors.push("name: es requerido y debe ser texto")
  } else if (body.name.trim().length > 100) {
    errors.push("name: máximo 100 caracteres")
  }

  const price = Number(body.price)
  if (isNaN(price) || price < 0) {
    errors.push("price: debe ser un número >= 0")
  } else if (price > 999999.99) {
    errors.push("price: valor demasiado alto (máx 999999.99)")
  }

  const cost = Number(body.cost)
  if (isNaN(cost) || cost < 0) {
    errors.push("cost: debe ser un número >= 0")
  } else if (cost > 999999.99) {
    errors.push("cost: valor demasiado alto (máx 999999.99)")
  }

  const stock = Number(body.stock)
  if (!Number.isInteger(stock) || stock < 0) {
    errors.push("stock: debe ser un entero >= 0")
  } else if (stock > 999999) {
    errors.push("stock: valor demasiado alto (máx 999999)")
  }

  const rawCat = typeof body.cat === "string" ? body.cat.trim() : ""

  if (rawCat.length === 0) {
    // vacía → "General", no es error
  } else if (rawCat.length > 60) {
    errors.push("cat: máximo 60 caracteres")
  } else if (CAT_INVALID_PATTERN.test(rawCat)) {
    errors.push(`cat: "${rawCat}" no es una categoría válida — no puede ser solo números`)
  } else if (!CAT_VALID_PATTERN.test(rawCat)) {
    errors.push(`cat: "${rawCat}" contiene caracteres no permitidos`)
  }

  return errors
}

function sanitizeProduct(body) {
  const rawCat = typeof body.cat === "string" ? body.cat.trim() : ""
  const normalizedCat = rawCat.length > 0
    ? rawCat.toLowerCase().replace(/\b\w/g, c => c.toUpperCase())
    : "General"

  return {
    name:  body.name.trim(),
    price: Math.round(Number(body.price) * 100) / 100,
    cost:  Math.round(Number(body.cost)  * 100) / 100,
    stock: Math.floor(Number(body.stock)),
    cat:   normalizedCat
  }
}

/* ─── SCHEMA GUARDIAN ───────────────────────────────────────────────────── */

const REQUIRED_SCHEMA = {
  products: {
    columns: [
      { name: "name",  def: "VARCHAR(100)",  type: "varchar" },
      { name: "price", def: "DECIMAL(10,2)", type: "decimal" },
      { name: "cost",  def: "DECIMAL(10,2)", type: "decimal" },
      { name: "stock", def: "INT DEFAULT 0", type: "int"     },
      { name: "sold",  def: "INT DEFAULT 0", type: "int"     },
      { name: "cat",   def: "VARCHAR(100)",  type: "varchar" }
    ],
    indexes: []
  },
  sessions: {
    columns: [
      { name: "token",         def: "VARCHAR(200)",                        type: "varchar"   },
      { name: "admin_id",      def: "INT",                                 type: "int"       },
      { name: "created_at",    def: "TIMESTAMP DEFAULT CURRENT_TIMESTAMP", type: "timestamp" },
      { name: "last_activity", def: "TIMESTAMP DEFAULT CURRENT_TIMESTAMP", type: "timestamp" }
    ],
    indexes: []
  },
  admins: {
    columns: [
      { name: "username",      def: "VARCHAR(50)",                         type: "varchar"   },
      { name: "password_hash", def: "TEXT",                                type: "text"      },
      { name: "recovery_key",  def: "VARCHAR(50)",                         type: "varchar"   },
      { name: "created_at",    def: "TIMESTAMP DEFAULT CURRENT_TIMESTAMP", type: "timestamp" }
    ],
    indexes: []
  },
  sales: {
    columns: [
      { name: "num",           def: "INT NOT NULL AUTO_INCREMENT UNIQUE",          type: "int"      },
      { name: "date",          def: "DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP", type: "datetime" },
      { name: "total",         def: "DECIMAL(10,2)",                               type: "decimal"  },
      { name: "paid",          def: "DECIMAL(10,2)",                               type: "decimal"  },
      { name: "change_amount", def: "DECIMAL(10,2)",                               type: "decimal"  }
    ],
    indexes: [
      { name: "idx_num",  def: "(num)"  },
      { name: "idx_date", def: "(date)" }
    ]
  },
  sale_items: {
    columns: [
      { name: "sale_id",    def: "VARCHAR(36) NOT NULL", type: "varchar" },
      { name: "product_id", def: "INT",                  type: "int"     },
      { name: "name",       def: "VARCHAR(255)",         type: "varchar" },
      { name: "price",      def: "DECIMAL(10,2)",        type: "decimal" },
      { name: "cost",       def: "DECIMAL(10,2)",        type: "decimal" },
      { name: "qty",        def: "INT",                  type: "int"     }
    ],
    indexes: [
      { name: "idx_product_id", def: "(product_id)" }
    ]
  },
  expenses: {
    columns: [
      { name: "amount",      def: "DECIMAL(10,2) NOT NULL",              type: "decimal"   },
      { name: "description", def: "VARCHAR(255)",                        type: "varchar"   },
      { name: "category",    def: "VARCHAR(50) DEFAULT 'General'",       type: "varchar"   },
      { name: "created_at",  def: "TIMESTAMP DEFAULT CURRENT_TIMESTAMP", type: "timestamp" }
    ],
    indexes: [
      { name: "idx_exp_date", def: "(created_at)" },
      { name: "idx_exp_cat",  def: "(category)"   }
    ]
  }
}

async function validateSchema() {
  const conn   = db.promise()
  const fixed  = []
  const ok     = []
  const alerts = []

  for (const [table, spec] of Object.entries(REQUIRED_SCHEMA)) {
    const [existingCols] = await conn.query(
      `SELECT COLUMN_NAME, LOWER(DATA_TYPE) AS data_type
       FROM INFORMATION_SCHEMA.COLUMNS
       WHERE TABLE_SCHEMA = 'posdb' AND TABLE_NAME = ?`,
      [table]
    )
    const colMap = new Map(existingCols.map(r => [r.COLUMN_NAME, r.data_type]))

    for (const col of spec.columns) {
      if (!colMap.has(col.name)) {
        try {
          await conn.query(`ALTER TABLE \`${table}\` ADD COLUMN \`${col.name}\` ${col.def}`)
          fixed.push(`+col ${table}.${col.name}`)
        } catch (e) {
          logError("SCHEMA_GUARDIAN", `No pude agregar ${table}.${col.name}: ${e.message}`)
        }
      } else {
        const actualType = colMap.get(col.name)
        if (col.type && actualType !== col.type) {
          const alertMsg = `TIPO INCORRECTO ${table}.${col.name}: actual='${actualType}' esperado='${col.type}'`
          alerts.push(alertMsg)
          logError("SCHEMA_TYPE_ALERT", alertMsg + " — requiere revisión manual")
        } else {
          ok.push(`${table}.${col.name}`)
        }
      }
    }

    const [existingIdx] = await conn.query(
      `SELECT INDEX_NAME FROM INFORMATION_SCHEMA.STATISTICS
       WHERE TABLE_SCHEMA = 'posdb' AND TABLE_NAME = ?
       GROUP BY INDEX_NAME`,
      [table]
    )
    const idxSet = new Set(existingIdx.map(r => r.INDEX_NAME))

    for (const idx of spec.indexes) {
      if (!idxSet.has(idx.name)) {
        try {
          await conn.query(`ALTER TABLE \`${table}\` ADD INDEX \`${idx.name}\` ${idx.def}`)
          fixed.push(`+idx ${table}.${idx.name}`)
        } catch (e) {
          logError("SCHEMA_GUARDIAN", `No pude agregar índice ${table}.${idx.name}: ${e.message}`)
        }
      }
    }
  }

  if (fixed.length > 0)  logInfo("SCHEMA_GUARDIAN", `✓ Autocorregido: ${fixed.join(", ")}`)
  if (alerts.length > 0) logError("SCHEMA_GUARDIAN", `⚠ Alertas de tipo: ${alerts.join(" | ")}`)
  if (fixed.length === 0 && alerts.length === 0)
    logInfo("SCHEMA_GUARDIAN", `✓ Todo OK — ${ok.length} columnas verificadas`)

  return { fixed, alerts, ok }
}

/* ─── RATE LIMITS ───────────────────────────────────────────────────────── */

const generalLimiter = rateLimit({
  windowMs:        15 * 60 * 1000,
  max:             200,
  standardHeaders: true,
  legacyHeaders:   false,
  message:         { error: "Demasiadas solicitudes" }
})

const loginLimiter = rateLimit({
  windowMs:        15 * 60 * 1000,
  max:             10,
  standardHeaders: true,
  legacyHeaders:   false,
  message:         { error: "Demasiados intentos, esperá 15 minutos" }
})

app.use("/api", generalLimiter)

/* ─── FRONTEND ──────────────────────────────────────────────────────────── */

const FRONT = path.join(__dirname, "main")
app.use(express.static(FRONT))
app.get("/", (req, res) => res.sendFile(path.join(FRONT, "index.html")))

/* ─── AUTH MIDDLEWARE ───────────────────────────────────────────────────── */

function auth(req, res, next) {
  const token = req.headers.authorization
  if (!token) return res.status(401).json({})

  db.promise()
    .query("SELECT last_activity FROM sessions WHERE token=?", [token])
    .then(([rows]) => {
      if (!rows.length) return res.status(401).json({})

      const diff = (Date.now() - new Date(rows[0].last_activity)) / 60000
      if (diff > 20) {
        return db.promise()
          .query("DELETE FROM sessions WHERE token=?", [token])
          .then(() => res.status(401).json({}))
      }

      return db.promise()
        .query("UPDATE sessions SET last_activity=NOW() WHERE token=?", [token])
        .then(() => next())
    })
    .catch(err => { logError("AUTH", err); res.status(401).json({}) })
}

/* ─── LOGIN ─────────────────────────────────────────────────────────────── */

app.post("/api/login", loginLimiter, async (req, res) => {
  const { username, password } = req.body
  try {
    const [admin] = await db.promise().query(
      "SELECT * FROM admins WHERE username=?", [username]
    )
    if (!admin.length) return res.status(401).json({ error: "login" })

    const valid = await bcrypt.compare(password, admin[0].password_hash)
    if (!valid) return res.status(401).json({ error: "login" })

    const token = uuidv4()
    await db.promise().query(
      "INSERT INTO sessions(token,admin_id,last_activity) VALUES(?,?,NOW())",
      [token, admin[0].id]
    )
    res.json({ token })
  } catch (err) {
    logError("LOGIN", err)
    res.status(500).json({ error: "server" })
  }
})

/* ─── SESSION CHECK ─────────────────────────────────────────────────────── */

app.get("/api/session", async (req, res) => {
  try {
    const token = req.headers.authorization
    if (!token) return res.status(401).json({})

    const [s] = await db.promise().query(
      "SELECT * FROM sessions WHERE token=?", [token]
    )
    if (!s.length) return res.status(401).json({})

    const diff = (Date.now() - new Date(s[0].last_activity)) / 60000
    if (diff > 20) {
      await db.promise().query("DELETE FROM sessions WHERE token=?", [token])
      return res.status(401).json({})
    }

    await db.promise().query(
      "UPDATE sessions SET last_activity=NOW() WHERE token=?", [token]
    )
    res.json({ ok: true })
  } catch (err) {
    logError("SESSION", err)
    res.status(500).json({})
  }
})

/* ─── LOGOUT ────────────────────────────────────────────────────────────── */

app.post("/api/logout", async (req, res) => {
  await db.promise().query(
    "DELETE FROM sessions WHERE token=?", [req.headers.authorization]
  )
  res.json({ ok: true })
})

/* ─── PRODUCTOS ─────────────────────────────────────────────────────────── */

app.get("/api/products", auth, (req, res) => {
  db.query("SELECT * FROM products", (err, data) => {
    if (err) { logError("GET_PRODUCTS", err); return res.status(500).json([]) }
    res.json(data)
  })
})

app.post("/api/products", auth, (req, res) => {
  const errors = validateProduct(req.body)
  if (errors.length > 0) {
    logError("CREATE_PRODUCT_VALIDATION", errors.join(" | "))
    return res.status(400).json({ error: "Datos inválidos", details: errors })
  }

  const p = sanitizeProduct(req.body)

  db.query(
    "INSERT INTO products(name,price,cost,stock,cat,sold) VALUES(?,?,?,?,?,0)",
    [p.name, p.price, p.cost, p.stock, p.cat],
    (err) => {
      if (err) { logError("CREATE_PRODUCT", err); return res.status(500).json({ error: "Error interno" }) }
      logInfo("CREATE_PRODUCT", `Creado: "${p.name}" cat="${p.cat}" price=${p.price}`)
      res.json({ ok: true })
    }
  )
})

app.put("/api/products/:id", auth, (req, res) => {
  const errors = validateProduct(req.body)
  if (errors.length > 0) {
    logError("UPDATE_PRODUCT_VALIDATION", `id=${req.params.id} — ` + errors.join(" | "))
    return res.status(400).json({ error: "Datos inválidos", details: errors })
  }

  const p = sanitizeProduct(req.body)

  db.query(
    "UPDATE products SET name=?,price=?,cost=?,stock=?,cat=? WHERE id=?",
    [p.name, p.price, p.cost, p.stock, p.cat, req.params.id],
    (err, result) => {
      if (err)                       { logError("UPDATE_PRODUCT", err); return res.status(500).json({ error: "Error interno" }) }
      if (result.affectedRows === 0) { return res.status(404).json({ error: "Producto no encontrado" }) }
      logInfo("UPDATE_PRODUCT", `Actualizado id=${req.params.id}: "${p.name}" cat="${p.cat}"`)
      res.json({ ok: true })
    }
  )
})

app.delete("/api/products/all", auth, async (req, res) => {
  try {
    // Nullear referencias en sale_items antes de eliminar productos
    // (por si en el entorno real existe un FK sobre product_id)
    await db.promise().query("UPDATE sale_items SET product_id = NULL")
    await db.promise().query("DELETE FROM products")
    res.json({ ok: true })
  } catch (err) {
    logError("DELETE_ALL_PRODUCTS", err)
    res.status(500).json({ error: err.message || "Error al eliminar inventario" })
  }
})

app.delete("/api/products/:id", auth, (req, res) => {
  db.query(
    "DELETE FROM products WHERE id=?", [req.params.id],
    (err) => {
      if (err) { logError("DELETE_PRODUCT", err); return res.status(500).json(err) }
      res.json({ ok: true })
    }
  )
})

/* ─── RESTOCK ───────────────────────────────────────────────────────────── */

app.post("/api/restock", auth, (req, res) => {
  const { id, qty } = req.body
  if (!id)              return res.status(400).json({ error: "Producto inválido" })
  if (!qty || qty <= 0) return res.status(400).json({ error: "Cantidad inválida" })
  if (qty > 999999)     return res.status(400).json({ error: "Cantidad demasiado alta" })

  db.query(
    "UPDATE products SET stock = stock + ? WHERE id=?", [qty, id],
    (err, result) => {
      if (err) { logError("RESTOCK", err); return res.status(500).json(err) }
      if (result.affectedRows === 0) return res.status(404).json({ error: "Producto no existe" })
      res.json({ ok: true })
    }
  )
})

/* ─── VENTAS ────────────────────────────────────────────────────────────── */

app.get("/api/sales", auth, (req, res) => {
  db.query("SELECT * FROM sales ORDER BY num DESC", (err, sales) => {
    if (err) { logError("GET_SALES", err); return res.json([]) }
    if (!sales.length) return res.json([])

    const ids = sales.map(s => s.id)
    db.query(
      "SELECT * FROM sale_items WHERE sale_id IN (?)", [ids],
      (err, items) => {
        if (err) { logError("GET_SALE_ITEMS", err); return res.json([]) }

        const result = sales.map(s => ({
          id:      s.id,
          num:     Number(s.num),
          date:    s.date,
          dateKey: s.date,
          total:   Number(s.total),
          paid:    Number(s.paid),
          change:  Number(s.change_amount),
          items:   items
            .filter(i => i.sale_id === s.id)
            .map(i => ({
              id:    Number(i.product_id),
              name:  i.name,
              price: Number(i.price),
              cost:  Number(i.cost),
              qty:   Number(i.qty)
            }))
        }))
        res.json(result)
      }
    )
  })
})

app.delete("/api/sales", auth, async (req, res) => {
  try {
    await db.promise().query("DELETE FROM sale_items")
    await db.promise().query("DELETE FROM sales")
    res.json({ ok: true })
  } catch (err) {
    logError("DELETE_SALES", err)
    res.status(500).json(err)
  }
})

app.post("/api/reset-stats", auth, async (req, res) => {
  try {
    await db.promise().query("UPDATE products SET sold = 0")
    await db.promise().query("DELETE FROM sale_items")
    await db.promise().query("DELETE FROM sales")
    res.json({ ok: true })
  } catch (err) {
    logError("RESET_STATS", err)
    res.status(500).json(err)
  }
})

/* ─── CREAR VENTA ───────────────────────────────────────────────────────── */

app.post("/api/sales", auth, async (req, res) => {
  const sale = req.body
  const conn = await db.promise().getConnection()

  try {
    await conn.beginTransaction()

    if (!Array.isArray(sale.items) || sale.items.length === 0)
      throw new Error("Carrito vacío")
    if (sale.items.length > 100)
      throw new Error("Demasiados productos")

    const paid = Number(sale.paid)
    if (!paid || isNaN(paid) || paid <= 0)
      throw new Error("Pago inválido")

    const saleId    = uuidv4()
    const saleDate  = new Date().toLocaleString("sv-SE").replace("T", " ")
    const validated = []
    let totalReal   = 0

    for (const item of sale.items) {
      if (!item.id)                   throw new Error("Producto inválido")
      if (!item.qty || item.qty <= 0) throw new Error("Cantidad inválida")

      const [rows] = await conn.query(
        "SELECT stock, price, cost FROM products WHERE id=? FOR UPDATE",
        [item.id]
      )
      if (!rows.length)             throw new Error("Producto no existe")
      if (rows[0].stock < item.qty) throw new Error("Sin stock: " + item.name)

      const realPrice = Number(rows[0].price)
      const realCost  = Number(rows[0].cost)
      totalReal      += realPrice * item.qty
      validated.push({ id: item.id, name: item.name, qty: item.qty, price: realPrice, cost: realCost })
    }

    totalReal   = Math.round(totalReal * 100) / 100
    if (paid < totalReal) throw new Error("Pago insuficiente")
    const changeReal = Math.round((paid - totalReal) * 100) / 100

    const [insertResult] = await conn.query(
      "INSERT INTO sales(id,date,total,paid,change_amount) VALUES(?,?,?,?,?)",
      [saleId, saleDate, totalReal, paid, changeReal]
    )
    const nextNum = insertResult.insertId

    for (const item of validated) {
      await conn.query(
        "INSERT INTO sale_items(sale_id,product_id,name,price,cost,qty) VALUES(?,?,?,?,?,?)",
        [saleId, item.id, item.name, item.price, item.cost, item.qty]
      )
      const [upd] = await conn.query(
        "UPDATE products SET stock = stock - ?, sold = sold + ? WHERE id=? AND stock >= ?",
        [item.qty, item.qty, item.id, item.qty]
      )
      if (upd.affectedRows === 0)
        throw new Error(`Fallo concurrencia en stock: ${item.name}`)
    }

    await conn.commit()
    res.json({ ok: true, id: saleId, num: nextNum })

  } catch (err) {
    await conn.rollback()
    logError("CREATE_SALE", err)
    res.status(400).json({ error: err.message })
  } finally {
    conn.release()
  }
})

/* =========================================================
   GASTOS
   ========================================================= */

const EXP_CAT_VALID = /^[a-zA-ZáéíóúÁÉÍÓÚüÜñÑ0-9 \-_&/]+$/

app.post("/api/expenses", auth, (req, res) => {
  const { amount, description, category } = req.body

  const amt = Number(amount)
  if (isNaN(amt) || amt <= 0)
    return res.status(400).json({ error: "Monto inválido" })
  if (amt > 999999)
    return res.status(400).json({ error: "Monto demasiado alto" })

  const desc = typeof description === "string" ? description.trim() : ""
  if (desc.length > 255)
    return res.status(400).json({ error: "Descripción demasiado larga (máx 255)" })

  const rawCat = typeof category === "string" ? category.trim() : ""
  if (rawCat.length > 50)
    return res.status(400).json({ error: "Categoría demasiado larga (máx 50)" })
  if (rawCat.length > 0 && !EXP_CAT_VALID.test(rawCat))
    return res.status(400).json({ error: "Categoría contiene caracteres no permitidos" })

  const cat = rawCat.length > 0
    ? rawCat.toLowerCase().replace(/\b\w/g, c => c.toUpperCase())
    : "General"

  db.query(
    "INSERT INTO expenses(amount, description, category) VALUES(?,?,?)",
    [Math.round(amt * 100) / 100, desc, cat],
    (err) => {
      if (err) {
        logError("CREATE_EXPENSE", err)
        return res.status(500).json({ error: "Error interno" })
      }
      logInfo("CREATE_EXPENSE", `Gasto $${amt} cat="${cat}" — "${desc}"`)
      res.json({ ok: true })
    }
  )
})

app.get("/api/expenses", auth, (req, res) => {
  db.query(
    "SELECT * FROM expenses ORDER BY id DESC",
    (err, data) => {
      if (err) {
        logError("GET_EXPENSES", err)
        return res.status(500).json([])
      }
      res.json(data)
    }
  )
})

app.put("/api/expenses/:id", auth, (req, res) => {
  const { amount, description, category } = req.body

  const amt = Number(amount)
  if (isNaN(amt) || amt <= 0)
    return res.status(400).json({ error: "Monto inválido" })
  if (amt > 999999)
    return res.status(400).json({ error: "Monto demasiado alto" })

  const desc = typeof description === "string" ? description.trim() : ""
  if (desc.length > 255)
    return res.status(400).json({ error: "Descripción muy larga" })

  const rawCat = typeof category === "string" ? category.trim() : ""
  if (rawCat.length > 50)
    return res.status(400).json({ error: "Categoría muy larga" })
  if (rawCat.length > 0 && !EXP_CAT_VALID.test(rawCat))
    return res.status(400).json({ error: "Categoría contiene caracteres no permitidos" })

  const cat = rawCat.length > 0
    ? rawCat.toLowerCase().replace(/\b\w/g, c => c.toUpperCase())
    : "General"

  db.query(
    "UPDATE expenses SET amount=?, description=?, category=? WHERE id=?",
    [Math.round(amt * 100) / 100, desc, cat, req.params.id],
    (err, result) => {
      if (err) {
        logError("UPDATE_EXPENSE", err)
        return res.status(500).json({ error: "Error interno" })
      }
      if (result.affectedRows === 0)
        return res.status(404).json({ error: "No existe" })
      logInfo("UPDATE_EXPENSE", `Actualizado id=${req.params.id} $${amt} cat="${cat}"`)
      res.json({ ok: true })
    }
  )
})

app.delete("/api/expenses/:id", auth, (req, res) => {
  db.query(
    "DELETE FROM expenses WHERE id=?",
    [req.params.id],
    (err) => {
      if (err) {
        logError("DELETE_EXPENSE", err)
        return res.status(500).json({})
      }
      res.json({ ok: true })
    }
  )
})

/* =========================================================
   RESUMEN FINANCIERO REAL  —  GET /api/summary
   ---------------------------------------------------------
   costos = SUM(sale_items.cost * qty)
   → usa sale_items, no products.sold
   → inmune a borrado de ventas: si borran una venta,
     el CASCADE elimina sus sale_items también, así que
     el costo calculado baja en consecuencia — siempre consistente.

   Soporta filtro opcional por fecha:
     ?desde=YYYY-MM-DD
     ?hasta=YYYY-MM-DD
     ?desde=YYYY-MM-DD&hasta=YYYY-MM-DD
   ========================================================= */

app.get("/api/summary", auth, async (req, res) => {
  try {
    const { desde, hasta } = req.query

    // construir condiciones de fecha para sales y expenses por separado
    // (sales usa columna "date", expenses usa "created_at")
    const salesWhere = []
    const salesVals  = []
    const expWhere   = []
    const expVals    = []

    if (desde) {
      salesWhere.push("s.date >= ?");      salesVals.push(desde)
      expWhere.push("created_at >= ?");    expVals.push(desde)
    }
    if (hasta) {
      // hasta incluye el día completo
      salesWhere.push("s.date < DATE_ADD(?, INTERVAL 1 DAY)");    salesVals.push(hasta)
      expWhere.push("created_at < DATE_ADD(?, INTERVAL 1 DAY)");  expVals.push(hasta)
    }

    const salesCondition = salesWhere.length ? "WHERE " + salesWhere.join(" AND ") : ""
    const expCondition   = expWhere.length   ? "WHERE " + expWhere.join(" AND ")   : ""

    // ventas brutas (lo cobrado)
    const [[salesRow]] = await db.promise().query(
      `SELECT COALESCE(SUM(s.total), 0) AS total
       FROM sales s ${salesCondition}`,
      salesVals
    )

    // costo real de lo vendido — desde sale_items
    const [[costsRow]] = await db.promise().query(
      `SELECT COALESCE(SUM(si.cost * si.qty), 0) AS total
       FROM sale_items si
       JOIN sales s ON s.id = si.sale_id
       ${salesCondition}`,
      salesVals
    )

    // gastos operativos totales
    const [[expRow]] = await db.promise().query(
      `SELECT COALESCE(SUM(amount), 0) AS total
       FROM expenses ${expCondition}`,
      expVals
    )

    // gastos agrupados por categoría
    const [byCat] = await db.promise().query(
      `SELECT category, COALESCE(SUM(amount), 0) AS total
       FROM expenses ${expCondition}
       GROUP BY category
       ORDER BY total DESC`,
      expVals
    )

    const totalSales    = Math.round(Number(salesRow.total) * 100) / 100
    const totalCosts    = Math.round(Number(costsRow.total) * 100) / 100
    const totalExpenses = Math.round(Number(expRow.total)   * 100) / 100
    const profit        = Math.round((totalSales - totalCosts - totalExpenses) * 100) / 100

    logInfo("SUMMARY", `sales=${totalSales} costs=${totalCosts} expenses=${totalExpenses} profit=${profit}`)

    res.json({
      sales:    totalSales,
      costs:    totalCosts,
      expenses: totalExpenses,
      profit,
      expenses_by_category: byCat.map(r => ({
        category: r.category,
        total:    Math.round(Number(r.total) * 100) / 100
      })),
      filter: { desde: desde || null, hasta: hasta || null }
    })

  } catch (err) {
    logError("SUMMARY", err)
    res.status(500).json({})
  }
})

/* ─── SNAPSHOT HELPER ───────────────────────────────────────────────────── */

async function snapshotQuery() {
  const conn = await db.promise().getConnection()
  try {
    await conn.query("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ")
    await conn.beginTransaction()

    const [[products], [sales], [items], [expenses]] = await Promise.all([
      conn.query("SELECT * FROM products"),
      conn.query("SELECT * FROM sales"),
      conn.query("SELECT * FROM sale_items"),
      conn.query("SELECT * FROM expenses")
    ])

    const [[sp]] = await conn.query("SHOW CREATE TABLE products")
    const [[ss]] = await conn.query("SHOW CREATE TABLE sales")
    const [[si]] = await conn.query("SHOW CREATE TABLE sale_items")
    const [[se]] = await conn.query("SHOW CREATE TABLE expenses")

    await conn.commit()
    return {
      backup_version: "2.0",
      created_at: new Date().toISOString(),
      products,
      sales,
      sale_items: items,
      expenses,
      schema: {
        products:   sp["Create Table"],
        sales:      ss["Create Table"],
        sale_items: si["Create Table"],
        expenses:   se["Create Table"]
      }
    }
  } catch (err) {
    await conn.rollback()
    throw err
  } finally {
    conn.release()
  }
}

/* ─── BACKUP INTERNO ────────────────────────────────────────────────────── */

app.get("/internal/backup", async (req, res) => {
  const key = req.headers["x-backup-key"]
  if (!key || key !== process.env.BACKUP_SECRET)
    return res.status(403).json({ error: "forbidden" })

  try {
    res.json(await snapshotQuery())
  } catch (err) {
    logError("INTERNAL_BACKUP", err)
    res.status(500).json({ error: "backup failed" })
  }
})

/* ─── BACKUP PÚBLICO ────────────────────────────────────────────────────── */

app.get("/api/backup", auth, async (req, res) => {
  try {
    res.json(await snapshotQuery())
  } catch (err) {
    logError("BACKUP", err)
    res.status(500).json(err)
  }
})

/* ─── RESTORE ───────────────────────────────────────────────────────────── */

// ═══════════════════════════════════════════════════════════════════════════
// BACKUP / RESTORE — diseño versionado con visibilidad y migración real
// ═══════════════════════════════════════════════════════════════════════════

// ── Fuente única de verdad: versión actual del backup ──
const BACKUP_VERSION = "2.0"

// ── Registro de migraciones ──────────────────────────────────────────────
// Cada entrada corresponde a una versión ORIGEN.
// La función recibe el payload crudo y devuelve { data, warnings[] }.
// Para agregar soporte a una versión nueva: solo agregar la entrada aquí.
// ─────────────────────────────────────────────────────────────────────────
const MIGRATIONS = {

  // Backups sin campo backup_version (anteriores al versionado)
  "legacy": function migrateLegacy(raw) {
    const warnings = []
    // change_amount pudo llamarse "change" en versiones viejas de sales
    const sales = (raw.sales || []).map(s => ({
      ...s,
      change_amount: s.change_amount ?? s.change ?? 0
    }))
    if (!raw.expenses) {
      warnings.push("Backup legacy: campo 'expenses' ausente — se omite esa sección")
    }
    return {
      data: { ...raw, sales, expenses: raw.expenses || [] },
      warnings
    }
  },

  // v1.0: igual que legacy más normalización de categoría en productos
  "1.0": function migrate1_0(raw) {
    const base = MIGRATIONS["legacy"](raw)
    const products = (base.data.products || []).map(p => ({
      ...p,
      cat: p.cat ?? p.category ?? "General"
    }))
    return {
      data: { ...base.data, products },
      warnings: base.warnings
    }
  }

  // v2.0 es la versión actual — no necesita migración
}

// ── Normalizadores ────────────────────────────────────────────────────────
// Cada función devuelve { result, warnings[] }.
// result === null significa que el registro es irrecuperable y debe omitirse.
// Nunca se descarta un registro en silencio — todo queda en warnings.
// ─────────────────────────────────────────────────────────────────────────

function normalizeProduct(p, index) {
  const warnings = []
  const tag = `products[${index}]`
  if (!p || typeof p !== "object") {
    return { result: null, warnings: [`${tag}: no es un objeto — omitido`] }
  }
  const rawName = p.name ?? p.nombre
  if (!rawName) {
    warnings.push(`${tag} (id:${p.id ?? "?"}): sin nombre — se usó "Producto importado"`)
  }
  const dec2 = v => Math.round(Number(v) * 100) / 100
  return {
    result: {
      id:    p.id != null ? Number(p.id) : null,
      name:  String(rawName ?? "Producto importado").trim().slice(0, 100),
      price: dec2(p.price ?? p.precio ?? 0),
      cost:  dec2(p.cost  ?? p.costo  ?? 0),
      stock: Math.max(0, Math.floor(Number(p.stock   ?? p.cantidad ?? 0))),
      sold:  Math.max(0, Math.floor(Number(p.sold    ?? p.vendidos ?? 0))),
      cat:   String(p.cat ?? p.category ?? p.categoria ?? "General").trim().slice(0, 100)
    },
    warnings
  }
}

// ── Convierte cualquier formato de fecha al formato MySQL "YYYY-MM-DD HH:MM:SS" ──
// Acepta: ISO 8601, MySQL datetime, Date objects, strings parciales, null/undefined.
// Nunca lanza excepción — si la fecha es irrecuperable devuelve la fecha actual.
// IMPORTANTE: preserva la hora local del servidor (no convierte a UTC) para que
// los backups con formato ISO "...Z" no sufran desplazamiento de timezone.
function toMySQLDatetime(raw) {
  // Helper: extrae componentes locales del Date y arma "YYYY-MM-DD HH:MM:SS"
  function dateToLocal(d) {
    const pad = n => String(n).padStart(2, "0")
    return (
      d.getFullYear() + "-" +
      pad(d.getMonth() + 1) + "-" +
      pad(d.getDate()) + " " +
      pad(d.getHours()) + ":" +
      pad(d.getMinutes()) + ":" +
      pad(d.getSeconds())
    )
  }

  // null / undefined / vacío → fecha actual
  if (!raw) return dateToLocal(new Date())

  // Si ya viene en formato MySQL "YYYY-MM-DD HH:MM:SS" lo retornamos directo
  // (evitamos re-parsear y posibles shifts de timezone)
  if (typeof raw === "string" && /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(raw.trim())) {
    return raw.trim()
  }

  // Intentar parseo genérico (ISO 8601, timestamps, etc.)
  const d = new Date(raw)
  if (!isNaN(d.getTime())) {
    // Si el raw es un ISO con "Z" o zona explícita, new Date() lo interpreta en UTC
    // correctamente y getHours() devuelve la hora local del servidor → correcto.
    return dateToLocal(d)
  }

  // Fallback: intentar formato legacy "DD/MM/YYYY" (versiones antiguas del frontend)
  const match = String(raw).match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})/)
  if (match) {
    const fallback = new Date(`${match[3]}-${match[2].padStart(2,"0")}-${match[1].padStart(2,"0")}T00:00:00`)
    if (!isNaN(fallback.getTime())) return dateToLocal(fallback)
  }

  // Irrecuperable → fecha actual como fallback seguro
  return dateToLocal(new Date())
}

function normalizeSale(s, index) {
  const tag = `sales[${index}]`
  if (!s || typeof s !== "object") {
    return { result: null, warnings: [`${tag}: no es un objeto — omitido`] }
  }
  if (!s.id) {
    return { result: null, warnings: [`${tag}: sin id (campo requerido) — omitido`] }
  }
  const dec2 = v => Math.round(Number(v) * 100) / 100
  return {
    result: {
      id:            String(s.id),
      num:           s.num != null ? Number(s.num) : null,
      date:          toMySQLDatetime(s.date ?? s.fecha),
      total:         dec2(s.total ?? 0),
      paid:          dec2(s.paid  ?? s.pago  ?? s.total ?? 0),
      change_amount: dec2(s.change_amount ?? s.change ?? s.vuelto ?? 0)
    },
    warnings: []
  }
}

function normalizeSaleItem(i, index) {
  const tag = `sale_items[${index}]`
  if (!i || typeof i !== "object") {
    return { result: null, warnings: [`${tag}: no es un objeto — omitido`] }
  }
  if (!i.sale_id) {
    return { result: null, warnings: [`${tag}: sin sale_id (campo requerido) — omitido`] }
  }
  const dec2 = v => Math.round(Number(v) * 100) / 100
  return {
    result: {
      sale_id:    String(i.sale_id),
      product_id: i.product_id != null ? Number(i.product_id) : null,
      name:       String(i.name ?? i.nombre ?? "Producto").trim().slice(0, 255),
      price:      dec2(i.price ?? i.precio ?? 0),
      cost:       dec2(i.cost  ?? i.costo  ?? 0),
      qty:        Math.max(1, Math.floor(Number(i.qty ?? i.cantidad ?? i.quantity ?? 1)))
    },
    warnings: []
  }
}

function normalizeExpense(e, index) {
  const warnings = []
  const tag = `expenses[${index}]`
  if (!e || typeof e !== "object") {
    return { result: null, warnings: [`${tag}: no es un objeto — omitido`] }
  }
  const amount = Math.round(Number(e.amount ?? e.monto ?? 0) * 100) / 100
  if (amount <= 0) {
    warnings.push(`${tag} (id:${e.id ?? "?"}): monto ${amount} inválido — se usó 0`)
  }
  return {
    result: {
      id:          e.id != null ? Number(e.id) : null,
      amount,
      description: String(e.description ?? e.descripcion ?? "").trim().slice(0, 255),
      category:    String(e.category ?? e.categoria ?? "General").trim().slice(0, 50),
      created_at:  toMySQLDatetime(e.created_at ?? e.date ?? e.fecha)
    },
    warnings
  }
}

// ── Normalizar una colección completa y recolectar todos los warnings ──
function normalizeCollection(items, normFn) {
  const results  = []
  const warnings = []
  ;(items || []).forEach((item, i) => {
    const { result, warnings: w } = normFn(item, i)
    warnings.push(...w)
    if (result !== null) results.push(result)
  })
  return { results, warnings }
}

// ── Detectar versión y aplicar migración si corresponde ──
function applyMigration(raw) {
  const version = raw.backup_version ?? "legacy"
  if (version === BACKUP_VERSION) {
    return { data: raw, warnings: [], version }
  }
  const migrateFn = MIGRATIONS[version]
  if (!migrateFn) {
    // Versión desconocida — advertir pero intentar sin migración
    return {
      data: raw,
      warnings: [`Versión de backup desconocida "${version}" — se intentará restaurar sin migración`],
      version
    }
  }
  const { data, warnings } = migrateFn(raw)
  return { data, warnings, version }
}

// ── Insertar con tracking: cuenta insertados, omitidos y errores ──
async function trackedInsert(conn, sql, params, entityStats) {
  const [result] = await conn.query(sql, params)
  // affectedRows: 0 = ignorado (IGNORE), 1 = insert, 2 = update (ON DUPLICATE KEY)
  if (result.affectedRows > 0) {
    entityStats.inserted++
  } else {
    entityStats.skipped++
  }
}

// ── Endpoint principal de restore ─────────────────────────────────────────
app.post("/api/restore", auth, async (req, res) => {
  const raw  = req.body
  const modo = req.query.modo || "parcial"

  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return res.status(400).json({ error: "Payload inválido: se esperaba un objeto JSON" })
  }

  // ── Fase 1: detectar versión y migrar ──
  const { data, warnings: migrationWarnings, version } = applyMigration(raw)

  // ── Fase 2: normalizar todas las entidades ANTES de tocar la DB ──
  const { results: normProducts, warnings: wProducts }  = normalizeCollection(data.products,   normalizeProduct)
  const { results: normSales,    warnings: wSales }     = normalizeCollection(data.sales,      normalizeSale)
  const { results: normItems,    warnings: wItems }     = normalizeCollection(data.sale_items, normalizeSaleItem)
  const { results: normExpenses, warnings: wExpenses }  = normalizeCollection(data.expenses,   normalizeExpense)

  const allWarnings = [
    ...migrationWarnings,
    ...wProducts,
    ...wSales,
    ...wItems,
    ...wExpenses
  ]

  if (allWarnings.length > 0) {
    logInfo("RESTORE_WARNINGS", allWarnings.join(" | "))
  }

  // ── Fase 3: insertar en DB dentro de una transacción ──
  const stats = {
    products:   { inserted: 0, skipped: 0 },
    sales:      { inserted: 0, skipped: 0 },
    sale_items: { inserted: 0, skipped: 0 },
    expenses:   { inserted: 0, skipped: 0 }
  }

  const conn = await db.promise().getConnection()
  try {
    await conn.beginTransaction()

    if (modo === "limpio") {
      await conn.query("DELETE FROM sale_items")
      await conn.query("DELETE FROM sales")
      await conn.query("DELETE FROM expenses")
    }

    for (const p of normProducts) {
      await trackedInsert(
        conn,
        "INSERT INTO products(id,name,price,cost,stock,sold,cat) VALUES(?,?,?,?,?,?,?) " +
        "ON DUPLICATE KEY UPDATE name=VALUES(name),price=VALUES(price),cost=VALUES(cost)," +
        "stock=VALUES(stock),sold=VALUES(sold),cat=VALUES(cat)",
        [p.id, p.name, p.price, p.cost, p.stock, p.sold, p.cat],
        stats.products
      )
    }

    for (const s of normSales) {
      const sql = modo === "limpio"
        ? "INSERT INTO sales(id,num,date,total,paid,change_amount) VALUES(?,?,?,?,?,?)"
        : "INSERT IGNORE INTO sales(id,num,date,total,paid,change_amount) VALUES(?,?,?,?,?,?)"
      await trackedInsert(conn, sql,
        [s.id, s.num, s.date, s.total, s.paid, s.change_amount],
        stats.sales
      )
    }

    for (const i of normItems) {
      const sql = modo === "limpio"
        ? "INSERT INTO sale_items(sale_id,product_id,name,price,cost,qty) VALUES(?,?,?,?,?,?)"
        : "INSERT IGNORE INTO sale_items(sale_id,product_id,name,price,cost,qty) VALUES(?,?,?,?,?,?)"
      await trackedInsert(conn, sql,
        [i.sale_id, i.product_id, i.name, i.price, i.cost, i.qty],
        stats.sale_items
      )
    }

    for (const e of normExpenses) {
      const sql = modo === "limpio"
        ? "INSERT INTO expenses(id,amount,description,category,created_at) VALUES(?,?,?,?,?)"
        : "INSERT IGNORE INTO expenses(id,amount,description,category,created_at) VALUES(?,?,?,?,?)"
      await trackedInsert(conn, sql,
        [e.id, e.amount, e.description, e.category, e.created_at],
        stats.expenses
      )
    }

    await conn.commit()

    // Reiniciar AUTO_INCREMENT en tablas donde se insertaron IDs explícitos.
    // Esto evita colisiones en inserciones posteriores al restore.
    try {
      await db.promise().query(`
        SET @max_prod = (SELECT IFNULL(MAX(id),0)+1 FROM products);
        SET @max_exp  = (SELECT IFNULL(MAX(id),0)+1 FROM expenses);
        SET @max_num  = (SELECT IFNULL(MAX(num),0)+1 FROM sales);
      `)
    } catch(_) {}
    // MySQL no soporta ALTER TABLE dentro de transacción, se ejecuta fuera
    await db.promise().query("ALTER TABLE products AUTO_INCREMENT = 1")
    await db.promise().query("ALTER TABLE expenses AUTO_INCREMENT = 1")
    // sales.num es AUTO_INCREMENT con UNIQUE — forzar al máximo actual
    const [[maxNumRow]] = await db.promise().query("SELECT IFNULL(MAX(num),0)+1 AS next FROM sales")
    await db.promise().query(`ALTER TABLE sales AUTO_INCREMENT = ${Number(maxNumRow.next)}`)

    logInfo("RESTORE_OK", `versión=${version} modo=${modo} ` +
      `productos=${stats.products.inserted}i/${stats.products.skipped}s ` +
      `ventas=${stats.sales.inserted}i/${stats.sales.skipped}s ` +
      `gastos=${stats.expenses.inserted}i/${stats.expenses.skipped}s`)

    res.json({
      ok:             true,
      modo,
      backup_version: version,
      stats,
      warnings:       allWarnings
    })

  } catch (err) {
    await conn.rollback()
    logError("RESTORE", err)
    res.status(500).json({
      error:          err.message || "Error al restaurar",
      backup_version: version,
      warnings:       allWarnings
    })
  } finally {
    conn.release()
  }
})

/* ─── HEALTH ENDPOINT ───────────────────────────────────────────────────── */

app.get("/internal/health", async (req, res) => {
  const key = req.headers["x-backup-key"]
  if (!key || key !== process.env.BACKUP_SECRET)
    return res.status(403).json({ error: "forbidden" })

  try {
    await db.promise().query("SELECT 1")
    const result = await validateSchema()

    res.json({
      ok:     result.alerts.length === 0,
      db:     "connected",
      schema: {
        fixed:    result.fixed,
        alerts:   result.alerts,
        ok_count: result.ok.length
      },
      ts: new Date().toISOString()
    })
  } catch (err) {
    logError("HEALTH", err)
    res.status(500).json({ ok: false, error: err.message })
  }
})

/* ─── ARRANQUE ──────────────────────────────────────────────────────────── */

validateSchema()
  .then((result) => {
    if (result.alerts.length > 0) {
      logError("STARTUP", `Schema corrupto — ${result.alerts.length} alerta(s) crítica(s). Corregir manualmente.`)
      logError("STARTUP", result.alerts.join(" | "))
      process.exit(1)
    }

    app.listen(PORT, () => {
      logInfo("STARTUP", `POS PRO corriendo en puerto ${PORT}`)
    })

    setInterval(() => {
      validateSchema()
        .then(r => {
          if (r.alerts.length > 0)
            logError("SCHEMA_INTERVAL", `⚠ Schema degradado en vivo: ${r.alerts.join(" | ")}`)
        })
        .catch(err => logError("SCHEMA_INTERVAL", err))
    }, 5 * 60 * 1000)
  })
  .catch(err => {
    logError("STARTUP", err)
    process.exit(1)
  })
SERVEREOF

# Inyectar el puerto en el archivo temporal
sed -i "s/__PORT_PLACEHOLDER__/$PORT/" "$SERVER_NEW"

# ── Validación de sintaxis JS ─────────────────────────────
echo "  → Validando sintaxis de server.js.new..."

TEMP_CHECK_FILE="$APP_DIR/server.check.js"
cp "$SERVER_NEW" "$TEMP_CHECK_FILE"

if ! node --check "$TEMP_CHECK_FILE" 2>/tmp/pos-syntax-error.txt; then
  echo "  ✗ ERROR SINTAXIS — server.js NO fue reemplazado"
  echo "  Detalle:"
  cat /tmp/pos-syntax-error.txt
  rm -f "$SERVER_NEW" "$TEMP_CHECK_FILE"
  echo "  El server.js anterior sigue intacto."
  exit 1
fi

rm -f "$TEMP_CHECK_FILE"
echo "  ✓ Sintaxis OK"

# ── Backup del server.js actual (si existe) ───────────────
if [ -f "$APP_DIR/server.js" ]; then
  SERVER_BAK="$APP_DIR/server.js.bak-$(date +%Y%m%d_%H%M%S)"
  cp "$APP_DIR/server.js" "$SERVER_BAK"
  echo "  → Backup guardado en: $SERVER_BAK"
fi

# ── Reemplazo atómico ─────────────────────────────────────
mv "$SERVER_NEW" "$APP_DIR/server.js"
echo "  ✓ server.js actualizado correctamente"

# función de rollback por si pm2 falla más adelante
rollback_server() {
  if [ -n "$SERVER_BAK" ] && [ -f "$SERVER_BAK" ]; then
    echo "  ⚠️  ROLLBACK: restaurando $SERVER_BAK"
    cp "$SERVER_BAK" "$APP_DIR/server.js"
    echo "  ✓ Rollback completado"
  else
    echo "  ⚠️  No hay backup disponible para rollback"
  fi
}

# ===========================================================
# ===== LOGIN HTML
# ===========================================================

echo "===== CREANDO LOGIN (solo si no existe) ====="

if [ ! -f "$APP_DIR/main/login.html" ]; then
  mkdir -p $APP_DIR/main
  cat <<'EOF' > /var/www/pos/main/login.html
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>POS PRO Login</title>
<style>
body{margin:0;font-family:sans-serif;background:#f1f5f9;display:flex;justify-content:center;align-items:center;height:100vh;}
.card{background:white;padding:30px;border-radius:16px;width:320px;box-shadow:0 10px 40px rgba(0,0,0,.15);animation:fade .4s;}
@keyframes fade{from{opacity:0;transform:translateY(20px);}to{opacity:1;transform:translateY(0);}}
h1{text-align:center;margin-bottom:20px;}
input{width:100%;padding:12px;margin-bottom:12px;border-radius:10px;border:1px solid #ddd;box-sizing:border-box;}
button{width:100%;padding:12px;border:none;background:#22c55e;color:white;border-radius:10px;font-weight:bold;cursor:pointer;}
button:hover{background:#16a34a;}
</style>
</head>
<body>
<div class="card">
<h1>📦 POS PRO</h1>
<input id="user" placeholder="👤 Usuario">
<input id="pass" type="password" placeholder="🔒 Contraseña">
<button onclick="login()">Entrar</button>
</div>
<script>
async function login(){
  const username = document.getElementById("user").value
  const password = document.getElementById("pass").value
  const res = await fetch("/api/login",{
    method:"POST",
    headers:{"Content-Type":"application/json"},
    body:JSON.stringify({username,password})
  })
  if(res.status !== 200){ alert("Login incorrecto"); return }
  const data = await res.json()
  localStorage.setItem("token", data.token)
  location.href = "/"
}
document.addEventListener("keydown", e => { if(e.key === "Enter") login() })
</script>
</body>
</html>
EOF
  echo "login.html creado"
else
  echo "login.html ya existe — conservado"
fi

# ===========================================================
# ===== BACKUP AUTOMÁTICO
# ===========================================================

echo "===== CONFIGURANDO BACKUP AUTOMÁTICO ====="
mkdir -p /var/backups/pos

cat <<BACKUP_SCRIPT > /usr/local/bin/pos-backup.sh
#!/bin/bash

SECRET=\$(grep BACKUP_SECRET $ENV_FILE | cut -d= -f2)
DEST="/var/backups/pos/backup-\$(date +%Y-%m-%d_%H-%M).json"
LOG="/var/log/pos-backup.log"

curl -s \
  -H "x-backup-key: \$SECRET" \
  "http://localhost:$PORT/internal/backup" \
  -o "\$DEST"

FAIL=0

if [ ! -s "\$DEST" ]; then
  echo "\$(date) [BACKUP] FAIL: archivo vacío o no creado" >> "\$LOG"
  FAIL=1
elif grep -q '"error"' "\$DEST"; then
  echo "\$(date) [BACKUP] FAIL: server retornó error" >> "\$LOG"
  FAIL=1
elif ! jq empty "\$DEST" 2>/dev/null; then
  echo "\$(date) [BACKUP] FAIL: JSON inválido o truncado" >> "\$LOG"
  FAIL=1
fi

if [ "\$FAIL" -eq "1" ]; then
  rm -f "\$DEST"
else
  sha256sum "\$DEST" > "\$DEST.sha256"
  echo "\$(date) [BACKUP] OK: \$DEST (\$(wc -c < \$DEST) bytes)" >> "\$LOG"
fi

find /var/backups/pos -type f -mtime +7 -delete
BACKUP_SCRIPT

chmod +x /usr/local/bin/pos-backup.sh
( crontab -l 2>/dev/null || true; echo "0 */6 * * * /usr/local/bin/pos-backup.sh" ) | grep -v "^$" | sort -u | crontab -

# ===========================================================
# ===== ARRANCAR
# ===========================================================

echo "===== INICIANDO POS ====="
pm2 restart pos 2>/dev/null || pm2 start "$APP_DIR/server.js" --name pos

# Esperar 3 segundos y verificar que el proceso siga vivo
sleep 3
if ! pm2 list | grep -q "pos.*online"; then
  echo ""
  echo "  ✗ ERROR: pm2 no pudo levantar el servidor"
  echo "  → Revisando logs:"
  pm2 logs pos --lines 20 --nostream 2>/dev/null || true
  rollback_server
  echo "  → Intentando reiniciar con versión anterior..."
  pm2 restart pos 2>/dev/null || pm2 start "$APP_DIR/server.js" --name pos
  sleep 2
  if pm2 list | grep -q "pos.*online"; then
    echo "  ✓ Servidor restaurado con versión anterior"
  else
    echo "  ✗ FALLO TOTAL — revisar manualmente con: pm2 logs pos"
  fi
  exit 1
fi

echo "  ✓ Servidor corriendo OK"
pm2 startup
pm2 save

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║               POS PRO INSTALADO ✓                            ║"
echo "╠═══════════════════════════════════════════════════════════════╣"
echo "║  usuario:  admin                                              ║"
echo "║  password: admin123                                           ║"
echo "╠═══════════════════════════════════════════════════════════════╣"
echo "║  URL:  http://$DOMAIN:$PORT/login.html"
echo "╠═══════════════════════════════════════════════════════════════╣"
echo "║  RESUMEN FINANCIERO REAL:                                     ║"
echo "║    GET /api/summary               → totales globales          ║"
echo "║    GET /api/summary?desde=&hasta= → filtro por fecha          ║"
echo "║    → { sales, costs, expenses, profit,                        ║"
echo "║        expenses_by_category[] }                               ║"
echo "║    costos calculados desde sale_items (no products.sold)      ║"
echo "╠═══════════════════════════════════════════════════════════════╣"
echo "║  GASTOS (con categoría):                                      ║"
echo "║    POST   /api/expenses      → { amount, description, cat }   ║"
echo "║    GET    /api/expenses      → lista ordenada por fecha        ║"
echo "║    PUT    /api/expenses/:id  → editar                         ║"
echo "║    DELETE /api/expenses/:id  → eliminar                       ║"
echo "╠═══════════════════════════════════════════════════════════════╣"
echo "║  ENDPOINTS INTERNOS (requieren x-backup-key):                 ║"
echo "║    /internal/backup  → snapshot completo                      ║"
echo "║    /internal/health  → estado DB + schema                     ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "Logs del servidor:   tail -f $APP_DIR/errors.log"
echo "Alertas de schema:   tail -f /var/log/pos-schema.log"
echo "Log de backups:      tail -f /var/log/pos-backup.log"
echo "Backups en:          /var/backups/pos/"
echo ""

#!/bin/bash

DOMAIN="tienda.valeentina.shop"
REPO="https://github.com/Mccarthey-Installer/Mccarthey-Installer.git"
APP_DIR="/var/www/pos"
PORT="9092"
ENV_FILE="$APP_DIR/.env"

echo "===== DETENIENDO PROCESO ANTERIOR ====="
pm2 delete pos 2>/dev/null

echo "===== ACTUALIZANDO SISTEMA ====="
apt update -y

echo "===== INSTALANDO DEPENDENCIAS ====="
apt install -y git curl mysql-server jq

echo "===== INSTALANDO NODE ====="
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

echo "===== INSTALANDO PM2 ====="
npm install -g pm2

echo "===== CLONANDO O ACTUALIZANDO POS ====="
mkdir -p /var/www
if [ ! -d "$APP_DIR" ]; then
  cd /var/www && git clone $REPO pos
else
  cd $APP_DIR && git pull
fi
cd $APP_DIR
echo ".env" >> .gitignore 2>/dev/null
sort -u .gitignore -o .gitignore 2>/dev/null

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

# ─── TABLAS BASE ────────────────────────────────────────────────────────────
# Solo crea la tabla si NO existe — nunca toca datos existentes

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

EOF

# ===========================================================
# ===== SCHEMA GUARDIAN — BASH (solo columnas no-PK)
# ===========================================================
#
# FIX #1: Ya NO toca columnas PRIMARY KEY (id).
#         MySQL no permite ADD COLUMN sobre una PK existente.
#         La PK solo se define en CREATE TABLE arriba.
#
# FIX #2: ensure_column ahora valida también el DATA_TYPE.
#         Si el tipo no coincide → lo reporta (no lo corrige
#         automáticamente para no romper datos, pero lo loguea
#         claramente para intervención manual).
#
# Regla:
#   columna no existe → la crea
#   columna existe, tipo correcto → pasa de largo
#   columna existe, tipo DIFERENTE → alerta visible, NO toca datos
#   columna es PK (id) → la ignora completamente

ensure_column() {
  local TABLE="$1"
  local COLUMN="$2"
  local DEFINITION="$3"
  local EXPECTED_TYPE="$4"   # solo el tipo base, ej: "varchar", "int", "decimal", "timestamp"

  # Nunca tocar PKs — FIX #1
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
    # FIX #2: Si se pasó tipo esperado, validar que coincida
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
        # Loguear en archivo también
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

# ─── products ─────────────────────────────────────────────
# FIX #1: "id" ya no se pasa a ensure_column
ensure_column "products" "name"  "VARCHAR(100)"           "varchar"
ensure_column "products" "price" "DECIMAL(10,2)"          "decimal"
ensure_column "products" "cost"  "DECIMAL(10,2)"          "decimal"
ensure_column "products" "stock" "INT DEFAULT 0"          "int"
ensure_column "products" "sold"  "INT DEFAULT 0"          "int"
ensure_column "products" "cat"   "VARCHAR(100)"           "varchar"

# ─── admins ───────────────────────────────────────────────
ensure_column "admins" "username"      "VARCHAR(50)"      "varchar"
ensure_column "admins" "password_hash" "TEXT"             "text"
ensure_column "admins" "recovery_key"  "VARCHAR(50)"      "varchar"
ensure_column "admins" "created_at"    "TIMESTAMP DEFAULT CURRENT_TIMESTAMP" "timestamp"

# ─── sessions ─────────────────────────────────────────────
ensure_column "sessions" "token"         "VARCHAR(200)"   "varchar"
ensure_column "sessions" "admin_id"      "INT"            "int"
ensure_column "sessions" "created_at"    "TIMESTAMP DEFAULT CURRENT_TIMESTAMP" "timestamp"
ensure_column "sessions" "last_activity" "TIMESTAMP DEFAULT CURRENT_TIMESTAMP" "timestamp"

# ─── sales ────────────────────────────────────────────────
ensure_column "sales" "num"           "INT NOT NULL AUTO_INCREMENT UNIQUE" "int"
ensure_column "sales" "date"          "DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP" "datetime"
ensure_column "sales" "total"         "DECIMAL(10,2)"            "decimal"
ensure_column "sales" "paid"          "DECIMAL(10,2)"            "decimal"
ensure_column "sales" "change_amount" "DECIMAL(10,2)"            "decimal"

# ─── sale_items ───────────────────────────────────────────
ensure_column "sale_items" "sale_id"    "VARCHAR(36) NOT NULL"   "varchar"
ensure_column "sale_items" "product_id" "INT"                    "int"
ensure_column "sale_items" "name"       "VARCHAR(255)"           "varchar"
ensure_column "sale_items" "price"      "DECIMAL(10,2)"          "decimal"
ensure_column "sale_items" "cost"       "DECIMAL(10,2)"          "decimal"
ensure_column "sale_items" "qty"        "INT"                    "int"

# ─── Índices ──────────────────────────────────────────────
ensure_index "sales"      "idx_num"        "(num)"
ensure_index "sales"      "idx_date"       "(date)"
ensure_index "sale_items" "idx_product_id" "(product_id)"

echo "===== FIN SCHEMA GUARDIAN (bash) ====="

echo ""
echo "Estado final de la tabla sales:"
mysql posdb -e "DESCRIBE sales;"
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
# ===== SERVER.JS  (siempre sobreescribe)
# ===========================================================

echo "===== ESCRIBIENDO SERVER.JS ====="
rm -f "$APP_DIR/server.js"

cat <<'SERVEREOF' > "$APP_DIR/server.js"
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
app.use(express.json())

/* ─── LOGGER ────────────────────────────────────────────────────────────── */

const LOG_FILE     = path.join(__dirname, "errors.log")
const LOG_MAX_BYTES = 5 * 1024 * 1024   // 5 MB — FIX #5: no crecer infinito

function rotateLogs() {
  try {
    const stat = fs.statSync(LOG_FILE)
    if (stat.size > LOG_MAX_BYTES) {
      const archived = LOG_FILE + ".old"
      if (fs.existsSync(archived)) fs.unlinkSync(archived)
      fs.renameSync(LOG_FILE, archived)
    }
  } catch (_) { /* primera vez que no existe el archivo */ }
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

/* ─── SCHEMA GUARDIAN ───────────────────────────────────────────────────── */
/*
   FIX #1: "id" (PK) ya NO se toca aquí.
           MySQL no permite ADD COLUMN de una PK existente.
           La PK viene del CREATE TABLE inicial.

   FIX #2: Ahora valida DATA_TYPE de cada columna.
           Si existe pero con tipo incorrecto → logea alerta clara,
           NO modifica automáticamente (protege datos reales).

   FIX #3: Se ejecuta al arranque Y cada 5 min (setInterval).
           Si alguien rompe la DB en vivo → se detecta y autocorrige.
*/

const REQUIRED_SCHEMA = {
  products: {
    columns: [
      // FIX #1: sin "id" — la PK no se toca desde aquí
      { name: "name",  def: "VARCHAR(100)",  type: "varchar"   },
      { name: "price", def: "DECIMAL(10,2)", type: "decimal"   },
      { name: "cost",  def: "DECIMAL(10,2)", type: "decimal"   },
      { name: "stock", def: "INT DEFAULT 0", type: "int"       },
      { name: "sold",  def: "INT DEFAULT 0", type: "int"       },
      { name: "cat",   def: "VARCHAR(100)",  type: "varchar"   }
    ],
    indexes: []
  },
  sessions: {
    columns: [
      { name: "token",         def: "VARCHAR(200)",                          type: "varchar"   },
      { name: "admin_id",      def: "INT",                                   type: "int"       },
      { name: "created_at",    def: "TIMESTAMP DEFAULT CURRENT_TIMESTAMP",   type: "timestamp" },
      { name: "last_activity", def: "TIMESTAMP DEFAULT CURRENT_TIMESTAMP",   type: "timestamp" }
    ],
    indexes: []
  },
  admins: {
    columns: [
      { name: "username",      def: "VARCHAR(50)",                           type: "varchar"   },
      { name: "password_hash", def: "TEXT",                                  type: "text"      },
      { name: "recovery_key",  def: "VARCHAR(50)",                           type: "varchar"   },
      { name: "created_at",    def: "TIMESTAMP DEFAULT CURRENT_TIMESTAMP",   type: "timestamp" }
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
  }
}

async function validateSchema() {
  const conn    = db.promise()
  const fixed   = []   // columnas/índices autocorregidos
  const ok      = []   // columnas verificadas y correctas
  const alerts  = []   // tipo incorrecto — requiere revisión manual

  for (const [table, spec] of Object.entries(REQUIRED_SCHEMA)) {

    /* ── columnas ── */
    const [existingCols] = await conn.query(
      `SELECT COLUMN_NAME, LOWER(DATA_TYPE) AS data_type
       FROM INFORMATION_SCHEMA.COLUMNS
       WHERE TABLE_SCHEMA = 'posdb' AND TABLE_NAME = ?`,
      [table]
    )
    const colMap = new Map(existingCols.map(r => [r.COLUMN_NAME, r.data_type]))

    for (const col of spec.columns) {
      if (!colMap.has(col.name)) {
        // No existe → crear
        try {
          await conn.query(
            `ALTER TABLE \`${table}\` ADD COLUMN \`${col.name}\` ${col.def}`
          )
          fixed.push(`+col ${table}.${col.name}`)
        } catch (e) {
          logError("SCHEMA_GUARDIAN", `No pude agregar ${table}.${col.name}: ${e.message}`)
        }
      } else {
        // FIX #2: Existe → validar tipo
        const actualType = colMap.get(col.name)
        if (col.type && actualType !== col.type) {
          // Tipo incorrecto — ALERTA pero NO modificar automáticamente
          const alertMsg = `TIPO INCORRECTO ${table}.${col.name}: actual='${actualType}' esperado='${col.type}'`
          alerts.push(alertMsg)
          logError("SCHEMA_TYPE_ALERT", alertMsg + " — requiere revisión manual")
        } else {
          ok.push(`${table}.${col.name}`)
        }
      }
    }

    /* ── índices ── */
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
          await conn.query(
            `ALTER TABLE \`${table}\` ADD INDEX \`${idx.name}\` ${idx.def}`
          )
          fixed.push(`+idx ${table}.${idx.name}`)
        } catch (e) {
          logError("SCHEMA_GUARDIAN", `No pude agregar índice ${table}.${idx.name}: ${e.message}`)
        }
      }
    }
  }

  // FIX #3: si hay alertas de tipo → schema corrupto → NO arrancar
  if (fixed.length > 0) {
    logInfo("SCHEMA_GUARDIAN", `✓ Autocorregido: ${fixed.join(", ")}`)
  }
  if (alerts.length > 0) {
    logError("SCHEMA_GUARDIAN", `⚠ Alertas de tipo (revisar manualmente): ${alerts.join(" | ")}`)
  }
  if (fixed.length === 0 && alerts.length === 0) {
    logInfo("SCHEMA_GUARDIAN", `✓ Todo OK — ${ok.length} columnas verificadas`)
  }

  return { fixed, alerts, ok }
}

/* ─── RATE LIMITS ───────────────────────────────────────────────────────── */
/*
   Dos capas:
   - generalLimiter: protege TODO /api → 200 req/15min por IP
     cubre /api/register, /api/recovery, cualquier endpoint futuro
   - loginLimiter: solo /api/login → 10 intentos/15min
     más estricto porque es el vector de brute force principal
*/

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
  const { name, price, cost, stock, cat } = req.body
  db.query(
    "INSERT INTO products(name,price,cost,stock,cat,sold) VALUES(?,?,?,?,?,0)",
    [name, price, cost, stock, cat],
    (err) => {
      if (err) { logError("CREATE_PRODUCT", err); return res.status(500).json(err) }
      res.json({ ok: true })
    }
  )
})

app.put("/api/products/:id", auth, (req, res) => {
  const { name, price, cost, stock, cat } = req.body
  db.query(
    "UPDATE products SET name=?,price=?,cost=?,stock=?,cat=? WHERE id=?",
    [name, price, cost, stock, cat, req.params.id],
    (err) => {
      if (err) { logError("UPDATE_PRODUCT", err); return res.status(500).json(err) }
      res.json({ ok: true })
    }
  )
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
      if (!item.id)                throw new Error("Producto inválido")
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
    // FIX #2: insertId es el AUTO_INCREMENT de num — sin SELECT extra
    const nextNum = insertResult.insertId

    for (const item of validated) {
      await conn.query(
        "INSERT INTO sale_items(sale_id,product_id,name,price,cost,qty) VALUES(?,?,?,?,?,?)",
        [saleId, item.id, item.name, item.price, item.cost, item.qty]
      )
      // FIX #5: stock >= qty ya fue verificado con FOR UPDATE arriba.
      // Doble-check post-UPDATE: si affectedRows = 0 algo muy raro pasó
      // (producto borrado entre el FOR UPDATE y el UPDATE) → rollback.
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

/* ─── SNAPSHOT HELPER ───────────────────────────────────────────────────── */

async function snapshotQuery() {
  const conn = await db.promise().getConnection()
  try {
    await conn.query("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ")
    await conn.beginTransaction()

    const [[products], [sales], [items]] = await Promise.all([
      conn.query("SELECT * FROM products"),
      conn.query("SELECT * FROM sales"),
      conn.query("SELECT * FROM sale_items")
    ])

    const [[sp]] = await conn.query("SHOW CREATE TABLE products")
    const [[ss]] = await conn.query("SHOW CREATE TABLE sales")
    const [[si]] = await conn.query("SHOW CREATE TABLE sale_items")

    await conn.commit()
    return {
      products,
      sales,
      sale_items: items,
      schema: {
        products:   sp["Create Table"],
        sales:      ss["Create Table"],
        sale_items: si["Create Table"]
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

app.post("/api/restore", auth, async (req, res) => {
  const data = req.body
  const modo = req.query.modo || "parcial"
  const conn = await db.promise().getConnection()

  try {
    await conn.beginTransaction()

    if (modo === "limpio") {
      await conn.query("DELETE FROM sale_items")
      await conn.query("DELETE FROM sales")

      for (const p of data.products) {
        await conn.query(
          "INSERT IGNORE INTO products(id,name,price,cost,stock,sold,cat) VALUES(?,?,?,?,?,?,?)",
          [p.id, p.name, p.price, p.cost, p.stock, p.sold, p.cat]
        )
      }
      for (const s of data.sales) {
        await conn.query(
          "INSERT INTO sales(id,num,date,total,paid,change_amount) VALUES(?,?,?,?,?,?)",
          [s.id, s.num, s.date, s.total, s.paid, s.change_amount]
        )
      }
      for (const i of data.sale_items) {
        await conn.query(
          "INSERT INTO sale_items(sale_id,product_id,name,price,cost,qty) VALUES(?,?,?,?,?,?)",
          [i.sale_id, i.product_id, i.name, i.price, i.cost, i.qty]
        )
      }
    } else {
      for (const p of data.products) {
        await conn.query(
          "INSERT IGNORE INTO products(id,name,price,cost,stock,sold,cat) VALUES(?,?,?,?,?,?,?)",
          [p.id, p.name, p.price, p.cost, p.stock, p.sold, p.cat]
        )
      }
      for (const s of data.sales) {
        await conn.query(
          "INSERT IGNORE INTO sales(id,num,date,total,paid,change_amount) VALUES(?,?,?,?,?,?)",
          [s.id, s.num, s.date, s.total, s.paid, s.change_amount]
        )
      }
      for (const i of data.sale_items) {
        await conn.query(
          "INSERT IGNORE INTO sale_items(sale_id,product_id,name,price,cost,qty) VALUES(?,?,?,?,?,?)",
          [i.sale_id, i.product_id, i.name, i.price, i.cost, i.qty]
        )
      }
    }

    await conn.commit()
    res.json({ ok: true, modo })
  } catch (err) {
    await conn.rollback()
    logError("RESTORE", err)
    res.status(500).json(err)
  } finally {
    conn.release()
  }
})

/* ─── HEALTH ENDPOINT ───────────────────────────────────────────────────── */
/*
   FIX nivel dios: /internal/health
   Verifica DB activa + schema en buen estado.
   Retorna { ok, db, schema: { fixed, alerts, ok_count } }
   Útil para monitoreo externo (uptime robots, etc.)
*/

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
/*
   FIX #3: validateSchema corre al arranque Y cada 5 minutos.
   Si alguien rompe la DB mientras el server está vivo → se detecta
   y autocorrige en el próximo ciclo sin necesidad de reiniciar.
*/

validateSchema()
  .then((result) => {
    // FIX #3: schema corrupto = NO arrancar
    // Columnas con tipo incorrecto en producción pueden romper silenciosamente.
    // Es mejor un arranque fallido visible que un sistema que corre y explota después.
    if (result.alerts.length > 0) {
      logError("STARTUP", `Schema corrupto — ${result.alerts.length} alerta(s) crítica(s). Corregir manualmente antes de arrancar.`)
      logError("STARTUP", result.alerts.join(" | "))
      process.exit(1)
    }

    app.listen(PORT, () => {
      logInfo("STARTUP", `POS PRO corriendo en puerto ${PORT}`)
    })

    // vigilancia periódica del schema — cada 5 minutos
    setInterval(() => {
      validateSchema()
        .then(r => {
          if (r.alerts.length > 0) {
            logError("SCHEMA_INTERVAL", `⚠ Schema degradado en vivo: ${r.alerts.join(" | ")}`)
          }
        })
        .catch(err => logError("SCHEMA_INTERVAL", err))
    }, 5 * 60 * 1000)
  })
  .catch(err => {
    logError("STARTUP", err)
    process.exit(1)
  })
SERVEREOF

sed -i "s/__PORT_PLACEHOLDER__/$PORT/" "$APP_DIR/server.js"
echo "server.js escrito"

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

# FIX #4: validación en 3 capas
# 1. archivo existe y no está vacío
# 2. no contiene clave "error" de respuesta fallida del server
# 3. JSON válido y parseable (jq empty)

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
( crontab -l 2>/dev/null | grep -v "pos-backup.sh"; echo "0 */6 * * * /usr/local/bin/pos-backup.sh" ) | crontab -

# ===========================================================
# ===== ARRANCAR
# ===========================================================

echo "===== INICIANDO POS ====="
pm2 restart pos 2>/dev/null || pm2 start server.js --name pos
pm2 startup
pm2 save

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║             POS PRO INSTALADO ✓                  ║"
echo "╠══════════════════════════════════════════════════╣"
echo "║  usuario:  admin                                 ║"
echo "║  password: admin123                              ║"
echo "╠══════════════════════════════════════════════════╣"
echo "║  URL:  http://$DOMAIN:$PORT/login.html"
echo "╠══════════════════════════════════════════════════╣"
echo "║  ENDPOINTS INTERNOS (requieren x-backup-key):   ║"
echo "║    /internal/backup  → snapshot completo         ║"
echo "║    /internal/health  → estado DB + schema        ║"
echo "╠══════════════════════════════════════════════════╣"
echo "║  CAMBIOS v4:                                     ║"
echo "║    ✓ sales: id=PK uuid, num=AI con UNIQUE KEY    ║"
echo "║    ✓ insertId en lugar de SELECT post-insert     ║"
echo "║    ✓ rate limit global /api + login estricto     ║"
echo "║    ✓ backup valida JSON con jq (3 capas)         ║"
echo "║    ✓ UPDATE stock con AND stock>=qty + check     ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "Estructura final de la tabla sales:"
mysql posdb -e "DESCRIBE sales;"
echo ""
echo "Logs del servidor:   tail -f $APP_DIR/errors.log"
echo "Alertas de schema:   tail -f /var/log/pos-schema.log"
echo "Log de backups:      tail -f /var/log/pos-backup.log"
echo "Backups en:          /var/backups/pos/"
echo ""

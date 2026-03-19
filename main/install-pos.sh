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

apt install -y git curl mysql-server

echo "===== INSTALANDO NODE ====="

curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

echo "===== INSTALANDO PM2 ====="

npm install -g pm2

echo "===== CLONANDO O ACTUALIZANDO POS ====="

mkdir -p /var/www

if [ ! -d "$APP_DIR" ]; then
  cd /var/www
  git clone $REPO pos
else
  cd $APP_DIR && git pull
fi

cd $APP_DIR

# proteger .env del repo
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
    "dotenv": "^16.0.0"
  }
}
PKGJSON
echo "package.json creado"
else
  echo "package.json ya existe — conservado"
fi

echo "===== INSTALANDO LIBRERIAS ====="

npm install

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

echo "===== CREANDO SERVER (solo si no existe) ====="

if [ ! -f "$APP_DIR/server.js" ]; then

cat <<EOF > server.js
require("dotenv").config()
const express = require("express")
const path = require("path")
const fs = require("fs")
const mysql = require("mysql2")
const cors = require("cors")
const bcrypt = require("bcrypt")
const { v4: uuidv4 } = require("uuid")

const app = express()

app.use(cors())
app.use(express.json())

/* ================= LOGGER ================= */

const LOG_FILE = path.join(__dirname, "errors.log")

function logError(context, err){
const line = new Date().toLocaleString("sv-SE") + " [" + context + "] " + (err.message || err) + "\n"
console.error(line.trim())
fs.appendFileSync(LOG_FILE, line)
}

/* FRONTEND */

const FRONT = path.join(__dirname,"main")

app.use(express.static(FRONT))

app.get("/",(req,res)=>{
res.sendFile(path.join(FRONT,"index.html"))
})

/* MYSQL */

const db = mysql.createPool({
host:"localhost",
user:"posuser",
password:"pos123",
database:"posdb",
connectionLimit:10
})

/* ================= HELPER: SNAPSHOT CONSISTENTE ================= */

async function snapshotQuery(){

const conn = await db.promise().getConnection()

try{

await conn.query("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ")
await conn.beginTransaction()

const [[products],[sales],[items]] = await Promise.all([
conn.query("SELECT * FROM products"),
conn.query("SELECT * FROM sales"),
conn.query("SELECT * FROM sale_items")
])

const [[schemaProducts]] = await conn.query("SHOW CREATE TABLE products")
const [[schemaSales]]    = await conn.query("SHOW CREATE TABLE sales")
const [[schemaItems]]    = await conn.query("SHOW CREATE TABLE sale_items")

await conn.commit()

return{
products,
sales,
sale_items: items,
schema:{
products:  schemaProducts["Create Table"],
sales:     schemaSales["Create Table"],
sale_items:schemaItems["Create Table"]
}
}

}catch(err){

await conn.rollback()
throw err

}finally{

conn.release()

}

}

/* ================= AUTH MIDDLEWARE ================= */

function auth(req,res,next){

const token = req.headers.authorization

if(!token){
return res.status(401).json({})
}

db.promise()
.query("SELECT last_activity FROM sessions WHERE token=?", [token])
.then(([rows])=>{

if(!rows.length){
return res.status(401).json({})
}

const last = new Date(rows[0].last_activity)
const now = new Date()
const diff = (now - last) / 1000 / 60

if(diff > 20){

return db.promise()
.query("DELETE FROM sessions WHERE token=?", [token])
.then(()=>{
return res.status(401).json({})
})

}

return db.promise()
.query("UPDATE sessions SET last_activity=NOW() WHERE token=?", [token])
.then(()=>{
next()
})

})
.catch((err)=>{
logError("AUTH", err)
return res.status(401).json({})
})

}

/* ================= LOGIN ================= */

app.post("/api/login", async (req,res)=>{

const {username,password} = req.body
const conn = db.promise()

try{

const [admin] = await conn.query(
"SELECT * FROM admins WHERE username=?",
[username]
)

if(admin.length === 0){
return res.status(401).json({error:"login"})
}

const valid = await bcrypt.compare(password,admin[0].password_hash)

if(!valid){
return res.status(401).json({error:"login"})
}

const token = uuidv4()

await conn.query(
"INSERT INTO sessions(token,admin_id,last_activity) VALUES(?,?,NOW())",
[token,admin[0].id]
)

res.json({token})

}catch(err){

logError("LOGIN", err)
res.status(500).json({error:"server"})

}

})

/* ================= SESSION CHECK ================= */

app.get("/api/session", async (req,res)=>{

try{

const token = req.headers.authorization

if(!token){
return res.status(401).json({})
}

const conn = db.promise()

const [s] = await conn.query(
"SELECT * FROM sessions WHERE token=?",
[token]
)

if(!s.length){
return res.status(401).json({})
}

const last = new Date(s[0].last_activity)
const now = new Date()
const diff = (now - last) / 1000 / 60

if(diff > 20){

await conn.query(
"DELETE FROM sessions WHERE token=?",
[token]
)

return res.status(401).json({})
}

await conn.query(
"UPDATE sessions SET last_activity=NOW() WHERE token=?",
[token]
)

res.json({ok:true})

}catch(err){

logError("SESSION", err)
res.status(500).json({})

}

})

/* LOGOUT */

app.post("/api/logout", async (req,res)=>{

const token = req.headers.authorization
const conn = db.promise()

await conn.query(
"DELETE FROM sessions WHERE token=?",
[token]
)

res.json({ok:true})

})

/* ================= PRODUCTOS ================= */

app.get("/api/products", auth, (req,res)=>{

db.query("SELECT * FROM products",(err,data)=>{

if(err){
logError("GET_PRODUCTS", err)
return res.status(500).json([])
}

res.json(data)

})

})

app.post("/api/products", auth, (req,res)=>{

const {name,price,cost,stock,cat} = req.body

db.query(
"INSERT INTO products(name,price,cost,stock,cat,sold) VALUES(?,?,?,?,?,0)",
[name,price,cost,stock,cat],
(err)=>{

if(err){
logError("CREATE_PRODUCT", err)
return res.status(500).json(err)
}

res.json({ok:true})

})

})

app.put("/api/products/:id", auth, (req,res)=>{

const {name,price,cost,stock,cat} = req.body
const id = req.params.id

db.query(
"UPDATE products SET name=?,price=?,cost=?,stock=?,cat=? WHERE id=?",
[name,price,cost,stock,cat,id],
(err)=>{

if(err){
logError("UPDATE_PRODUCT", err)
return res.status(500).json(err)
}

res.json({ok:true})

})

})

app.delete("/api/products/:id", auth, (req,res)=>{

db.query(
"DELETE FROM products WHERE id=?",
[req.params.id],
(err)=>{

if(err){
logError("DELETE_PRODUCT", err)
return res.status(500).json(err)
}

res.json({ok:true})

})

})

/* ================= RESTOCK ================= */

app.post("/api/restock", auth, (req,res)=>{

const {id,qty} = req.body

if(!id){
return res.status(400).json({error:"Producto inválido"})
}

if(!qty || qty <= 0){
return res.status(400).json({error:"Cantidad inválida"})
}

db.query(
"UPDATE products SET stock = stock + ? WHERE id=?",
[qty,id],
(err,result)=>{

if(err){
logError("RESTOCK", err)
return res.status(500).json(err)
}

if(result.affectedRows === 0){
return res.status(404).json({error:"Producto no existe"})
}

res.json({ok:true})

})

})

/* ================= OBTENER VENTAS ================= */

app.get("/api/sales", auth, (req,res)=>{

db.query(
"SELECT * FROM sales ORDER BY date DESC",
(err,sales)=>{

if(err){
logError("GET_SALES", err)
return res.json([])
}

if(sales.length === 0) return res.json([])

const ids = sales.map(s => s.id)

db.query(
"SELECT * FROM sale_items WHERE sale_id IN (?)",
[ids],
(err,items)=>{

if(err){
logError("GET_SALE_ITEMS", err)
return res.json([])
}

const result = sales.map(s=>{

const saleItems = items
.filter(i=>i.sale_id === s.id)
.map(i=>({

id:Number(i.product_id),
name:i.name,
price:Number(i.price),
cost:Number(i.cost),
qty:Number(i.qty)

}))

return{

id:s.id,
num:s.id,
date:s.date,
dateKey:s.date,
items:saleItems,
total:Number(s.total),
paid:Number(s.paid),
change:Number(s.change_amount)

}

})

res.json(result)

})

})

})

app.delete("/api/sales", auth, async (req,res)=>{

try{

await db.promise().query("DELETE FROM sale_items")
await db.promise().query("DELETE FROM sales")

res.json({ok:true})

}catch(err){

logError("DELETE_SALES", err)
res.status(500).json(err)

}

})


app.post("/api/reset-stats", auth, async (req,res)=>{

try{

await db.promise().query("UPDATE products SET sold = 0")
await db.promise().query("DELETE FROM sale_items")
await db.promise().query("DELETE FROM sales")

res.json({ok:true})

}catch(err){

logError("RESET_STATS", err)
res.status(500).json(err)

}

})


/* ================= CREAR VENTA ================= */

app.post("/api/sales", auth, async (req,res)=>{

const sale = req.body
const conn = await db.promise().getConnection()

try{

  await conn.beginTransaction()

  if(!Array.isArray(sale.items) || sale.items.length === 0){
    throw new Error("Carrito vacío")
  }

  if(sale.items.length > 100){
    throw new Error("Demasiados productos")
  }

  const paid = Number(sale.paid)

  if(!paid || isNaN(paid) || paid <= 0){
    throw new Error("Pago inválido")
  }

  const saleId = uuidv4()

  const saleDate = new Date().toLocaleString("sv-SE").replace("T"," ")

  const itemsValidados = []

  let totalReal = 0

  for(const item of sale.items){

    if(!item.id){
      throw new Error("Producto inválido")
    }

    if(!item.qty || item.qty <= 0){
      throw new Error("Cantidad inválida")
    }

    const [rows] = await conn.query(
      "SELECT stock, price, cost FROM products WHERE id=? FOR UPDATE",
      [item.id]
    )

    if(rows.length === 0){
      throw new Error("Producto no existe")
    }

    if(rows[0].stock < item.qty){
      throw new Error("Sin stock: " + item.name)
    }

    const realPrice = Number(rows[0].price)
    const realCost  = Number(rows[0].cost)

    totalReal += realPrice * item.qty

    itemsValidados.push({
      id:    item.id,
      name:  item.name,
      qty:   item.qty,
      price: realPrice,
      cost:  realCost
    })

  }

  totalReal = Math.round(totalReal * 100) / 100

  if(paid < totalReal){
    throw new Error("Pago insuficiente")
  }

  const changeReal = Math.round((paid - totalReal) * 100) / 100

  await conn.query(
    "INSERT INTO sales(id,date,total,paid,change_amount) VALUES(?,?,?,?,?)",
    [saleId, saleDate, totalReal, paid, changeReal]
  )

  for(const item of itemsValidados){

    await conn.query(
      "INSERT INTO sale_items(sale_id,product_id,name,price,cost,qty) VALUES(?,?,?,?,?,?)",
      [saleId, item.id, item.name, item.price, item.cost, item.qty]
    )

    await conn.query(
      "UPDATE products SET stock = stock - ?, sold = sold + ? WHERE id=?",
      [item.qty, item.qty, item.id]
    )

  }

  await conn.commit()

  res.json({ok:true, id:saleId})

}catch(err){

  await conn.rollback()

  logError("CREATE_SALE", err)

  res.status(400).json({error:err.message})

}finally{

  conn.release()

}

})


/* ================= BACKUP INTERNO ================= */

app.get("/internal/backup", async (req,res)=>{

const key = req.headers["x-backup-key"]

if(!key || key !== process.env.BACKUP_SECRET){
return res.status(403).json({error:"forbidden"})
}

try{

const data = await snapshotQuery()
res.json(data)

}catch(err){

logError("INTERNAL_BACKUP", err)
res.status(500).json({error:"backup failed"})

}

})

/* ================= BACKUP PÚBLICO ================= */

app.get("/api/backup", auth, async (req,res)=>{

try{

const data = await snapshotQuery()
res.json(data)

}catch(err){

logError("BACKUP", err)
res.status(500).json(err)

}

})

/* ================= RESTORE ================= */

app.post("/api/restore", auth, async (req,res)=>{

const data = req.body
const modo = req.query.modo || "parcial"
const conn = await db.promise().getConnection()

try{

await conn.beginTransaction()

if(modo === "limpio"){

await conn.query("DELETE FROM sale_items")
await conn.query("DELETE FROM sales")

for(const p of data.products){
await conn.query(
"INSERT IGNORE INTO products(id,name,price,cost,stock,sold,cat) VALUES(?,?,?,?,?,?,?)",
[p.id,p.name,p.price,p.cost,p.stock,p.sold,p.cat]
)
}

for(const s of data.sales){
await conn.query(
"INSERT INTO sales(id,date,total,paid,change_amount) VALUES(?,?,?,?,?)",
[s.id,s.date,s.total,s.paid,s.change_amount]
)
}

for(const i of data.sale_items){
await conn.query(
"INSERT INTO sale_items(sale_id,product_id,name,price,cost,qty) VALUES(?,?,?,?,?,?)",
[i.sale_id,i.product_id,i.name,i.price,i.cost,i.qty]
)
}

}else{

for(const p of data.products){
await conn.query(
"INSERT IGNORE INTO products(id,name,price,cost,stock,sold,cat) VALUES(?,?,?,?,?,?,?)",
[p.id,p.name,p.price,p.cost,p.stock,p.sold,p.cat]
)
}

for(const s of data.sales){
await conn.query(
"INSERT IGNORE INTO sales(id,date,total,paid,change_amount) VALUES(?,?,?,?,?)",
[s.id,s.date,s.total,s.paid,s.change_amount]
)
}

for(const i of data.sale_items){
await conn.query(
"INSERT IGNORE INTO sale_items(sale_id,product_id,name,price,cost,qty) VALUES(?,?,?,?,?,?)",
[i.sale_id,i.product_id,i.name,i.price,i.cost,i.qty]
)
}

}

await conn.commit()

res.json({ok:true, modo})

}catch(err){

await conn.rollback()
logError("RESTORE", err)
res.status(500).json(err)

}finally{

conn.release()

}

})


/* ================= START ================= */

const PORT = $PORT

app.listen(PORT,()=>{
console.log("POS PRO corriendo en puerto",PORT)
})
EOF

echo "server.js creado"

else
  echo "server.js ya existe — no se sobreescribe"
fi

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

body{
margin:0;
font-family:sans-serif;
background:#f1f5f9;
display:flex;
justify-content:center;
align-items:center;
height:100vh;
}

.card{
background:white;
padding:30px;
border-radius:16px;
width:320px;
box-shadow:0 10px 40px rgba(0,0,0,.15);
animation:fade .4s;
}

@keyframes fade{
from{opacity:0;transform:translateY(20px);}
to{opacity:1;transform:translateY(0);}
}

h1{text-align:center;margin-bottom:20px;}

input{
width:100%;
padding:12px;
margin-bottom:12px;
border-radius:10px;
border:1px solid #ddd;
}

button{
width:100%;
padding:12px;
border:none;
background:#22c55e;
color:white;
border-radius:10px;
font-weight:bold;
cursor:pointer;
}

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

const username=document.getElementById("user").value
const password=document.getElementById("pass").value

const res=await fetch("/api/login",{
method:"POST",
headers:{"Content-Type":"application/json"},
body:JSON.stringify({username,password})
})

if(res.status!==200){
alert("Login incorrecto")
return
}

const data=await res.json()

localStorage.setItem("token",data.token)

location.href="/"

}

</script>

</body>
</html>
EOF

echo "login.html creado"

else
  echo "login.html ya existe — no se sobreescribe"
fi

echo "===== CREANDO BASE DE DATOS ====="

mysql -e "CREATE DATABASE IF NOT EXISTS posdb;"

mysql <<EOF
CREATE USER IF NOT EXISTS 'posuser'@'localhost' IDENTIFIED BY 'pos123';
GRANT ALL PRIVILEGES ON posdb.* TO 'posuser'@'localhost';
FLUSH PRIVILEGES;
EOF

mysql posdb <<EOF

CREATE TABLE IF NOT EXISTS products(
id INT AUTO_INCREMENT PRIMARY KEY,
name VARCHAR(100),
price DECIMAL(10,2),
cost DECIMAL(10,2),
stock INT,
sold INT DEFAULT 0,
cat VARCHAR(100)
);

CREATE TABLE IF NOT EXISTS admins(
id INT AUTO_INCREMENT PRIMARY KEY,
username VARCHAR(50),
password_hash TEXT,
recovery_key VARCHAR(50),
created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS sessions(
id INT AUTO_INCREMENT PRIMARY KEY,
token VARCHAR(200),
admin_id INT,
created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
last_activity TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS sales(
id VARCHAR(36) PRIMARY KEY,
date DATETIME NOT NULL,
total DECIMAL(10,2),
paid DECIMAL(10,2),
change_amount DECIMAL(10,2)
);

CREATE TABLE IF NOT EXISTS sale_items(
id INT AUTO_INCREMENT PRIMARY KEY,
sale_id VARCHAR(36) NOT NULL,
product_id INT,
name VARCHAR(255),
price DECIMAL(10,2),
cost DECIMAL(10,2),
qty INT,
CONSTRAINT fk_sale FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE
);

EOF

echo "===== CREANDO INDICES (ignora si ya existen) ====="

mysql posdb -e "CREATE INDEX idx_product_id ON sale_items(product_id);" 2>/dev/null || true
mysql posdb -e "CREATE INDEX idx_date ON sales(date);" 2>/dev/null || true

echo "===== CREANDO ADMIN ====="

HASH=$(node -e "require('bcrypt').hash('admin123',10).then(h=>console.log(h))")

mysql posdb -e "
INSERT IGNORE INTO admins(username,password_hash,recovery_key)
VALUES('admin','$HASH','POS-RECOVERY-123');
"

echo "===== CONFIGURANDO BACKUP AUTOMÁTICO ====="

mkdir -p /var/backups/pos

cat <<BACKUP_SCRIPT > /usr/local/bin/pos-backup.sh
#!/bin/bash

SECRET=\$(grep BACKUP_SECRET $ENV_FILE | cut -d= -f2)
DEST="/var/backups/pos/backup-\$(date +%Y-%m-%d_%H-%M).json"

curl -s \
  -H "x-backup-key: \$SECRET" \
  "http://localhost:$PORT/internal/backup" \
  -o "\$DEST"

if [ ! -s "\$DEST" ] || grep -q '"error"' "\$DEST"; then
  rm -f "\$DEST"
  echo "\$(date) [BACKUP] falló — archivo eliminado" >> /var/log/pos-backup.log
else
  sha256sum "\$DEST" > "\$DEST.sha256"
  echo "\$(date) [BACKUP] OK: \$DEST" >> /var/log/pos-backup.log
fi

find /var/backups/pos -type f -mtime +7 -delete

BACKUP_SCRIPT

chmod +x /usr/local/bin/pos-backup.sh

( crontab -l 2>/dev/null | grep -v "pos-backup.sh" ; echo "0 */6 * * * /usr/local/bin/pos-backup.sh" ) | crontab -

echo "===== INICIANDO POS ====="

pm2 restart pos 2>/dev/null || pm2 start server.js --name pos
pm2 startup
pm2 save

echo ""
echo "===== POS PRO INSTALADO ====="
echo ""
echo "Login:"
echo "usuario: admin"
echo "password: admin123"
echo ""
echo "Abrir:"
echo "http://$DOMAIN:$PORT/login.html"
echo ""
echo "Logs de errores del servidor:"
echo "tail -f $APP_DIR/errors.log"
echo ""
echo "Log de backups automáticos:"
echo "tail -f /var/log/pos-backup.log"
echo ""
echo "Backups en: /var/backups/pos/"
echo ""
echo "Restore parcial: POST /api/restore"
echo "Restore limpio:  POST /api/restore?modo=limpio"
echo ""

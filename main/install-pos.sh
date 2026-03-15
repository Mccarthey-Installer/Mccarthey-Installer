#!/bin/bash

DOMAIN="tienda.valeentina.shop"
REPO="https://github.com/Mccarthey-Installer/Mccarthey-Installer.git"
APP_DIR="/var/www/pos"
PORT="9092"

echo "===== LIMPIANDO INSTALACION VIEJA ====="

pm2 delete pos 2>/dev/null
pm2 kill 2>/dev/null

rm -rf $APP_DIR

echo "===== ACTUALIZANDO SISTEMA ====="

apt update -y

echo "===== INSTALANDO DEPENDENCIAS ====="

apt install -y git curl mysql-server

echo "===== INSTALANDO NODE ====="

curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

echo "===== INSTALANDO PM2 ====="

npm install -g pm2

echo "===== CLONANDO POS ====="

mkdir -p /var/www
cd /var/www
git clone $REPO pos

cd $APP_DIR

echo "===== INSTALANDO LIBRERIAS ====="

npm init -y
npm install express mysql2 cors bcrypt uuid

echo "===== CREANDO SERVER ====="

cat <<EOF > server.js
const express = require("express")
const path = require("path")
const mysql = require("mysql2")
const cors = require("cors")
const bcrypt = require("bcrypt")
const { v4: uuidv4 } = require("uuid")

const app = express()

app.use(cors())
app.use(express.json())

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

/* sesión expirada */

if(diff > 20){

return db.promise()
.query("DELETE FROM sessions WHERE token=?", [token])
.then(()=>{
return res.status(401).json({})
})

}

/* actualizar actividad */

return db.promise()
.query("UPDATE sessions SET last_activity=NOW() WHERE token=?", [token])
.then(()=>{
next()
})

})
.catch((err)=>{
console.error("AUTH ERROR:", err)
return res.status(401).json({})
})

}

/* ================= LOGIN ================= */

app.post("/api/login", async (req,res)=>{

const {username,password} = req.body
const conn = db.promise()

try{

/* buscar admin */

const [admin] = await conn.query(
"SELECT * FROM admins WHERE username=?",
[username]
)

if(admin.length === 0){
return res.status(401).json({error:"login"})
}

/* verificar contraseña */

const valid = await bcrypt.compare(password,admin[0].password_hash)

if(!valid){
return res.status(401).json({error:"login"})
}

/* crear token */

const token = uuidv4()

/* guardar sesión con actividad inicial */

await conn.query(
"INSERT INTO sessions(token,admin_id,last_activity) VALUES(?,?,NOW())",
[token,admin[0].id]
)

/* responder */

res.json({token})

}catch(err){

console.error("LOGIN ERROR:",err)

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

/* verificar expiración 20 minutos */

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

/* actualizar actividad */

await conn.query(
"UPDATE sessions SET last_activity=NOW() WHERE token=?",
[token]
)

res.json({ok:true})

}catch(err){

res.status(500).json(err)

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

if(err) return res.status(500).json([])

res.json(data)

})

})

app.post("/api/products", auth, (req,res)=>{

const {name,price,cost,stock,cat} = req.body

db.query(
"INSERT INTO products(name,price,cost,stock,cat,sold) VALUES(?,?,?,?,?,0)",
[name,price,cost,stock,cat],
(err)=>{

if(err) return res.status(500).json(err)

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

if(err) return res.status(500).json(err)

res.json({ok:true})

})

})

app.delete("/api/products/:id", auth, (req,res)=>{

db.query(
"DELETE FROM products WHERE id=?",
[req.params.id],
(err)=>{

if(err) return res.status(500).json(err)

res.json({ok:true})

})

})

/* ================= RESTOCK ================= */

app.post("/api/restock", auth, (req,res)=>{

const {id,qty} = req.body

db.query(
"UPDATE products SET stock = stock + ? WHERE id=?",
[qty,id],
(err)=>{

if(err) return res.status(500).json(err)

res.json({ok:true})

})

})

/* ================= OBTENER VENTAS ================= */

app.get("/api/sales", auth, (req,res)=>{

db.query(
"SELECT * FROM sales ORDER BY id DESC",
(err,sales)=>{

if(err) return res.json([])

if(sales.length === 0) return res.json([])

const ids = sales.map(s => s.id)

db.query(
"SELECT * FROM sale_items WHERE sale_id IN (?)",
[ids],
(err,items)=>{

if(err) return res.json([])

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

id:Number(s.id),
num:Number(s.id),
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

res.status(500).json(err)

}

})


/* ================= CREAR VENTA ================= */

app.post("/api/sales", auth, (req,res)=>{

const sale=req.body

db.query(
"INSERT INTO sales(id,date,total,paid,change_amount) VALUES(?,?,?,?,?)",
[
sale.id,
sale.date,
sale.total,
sale.paid,
sale.change
],
(err)=>{

if(err) return res.status(500).json(err)

sale.items.forEach(item=>{

db.query(
"INSERT INTO sale_items(sale_id,product_id,name,price,cost,qty) VALUES(?,?,?,?,?,?)",
[
sale.id,
item.id,
item.name,
item.price,
item.cost,
item.qty
])

db.query(
"UPDATE products SET stock = stock - ?, sold = sold + ? WHERE id=?",
[
item.qty,
item.qty,
item.id
])

})

res.json({ok:true})

})

})


/* ================= BACKUP ================= */

app.get("/api/backup", auth, async (req,res)=>{

const conn = db.promise()

try{

const [products] = await conn.query("SELECT * FROM products")
const [sales] = await conn.query("SELECT * FROM sales")
const [items] = await conn.query("SELECT * FROM sale_items")

res.json({
products,
sales,
sale_items:items
})

}catch(err){
res.status(500).json(err)
}

})

/* ================= RESTORE ================= */

app.post("/api/restore", auth, async (req,res)=>{

const data = req.body
const conn = db.promise()

try{

await conn.query("DELETE FROM sale_items")
await conn.query("DELETE FROM sales")
await conn.query("DELETE FROM products")

for(const p of data.products){
await conn.query(
"INSERT INTO products(id,name,price,cost,stock,sold,cat) VALUES(?,?,?,?,?,?,?)",
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

res.json({ok:true})

}catch(err){

res.status(500).json(err)

}

})


/* ================= START ================= */

const PORT = $PORT

app.listen(PORT,()=>{
console.log("POS PRO corriendo en puerto",PORT)
})
EOF

echo "===== CREANDO LOGIN ====="

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

CREATE TABLE IF NOT EXISTS sales(
id BIGINT PRIMARY KEY,
date VARCHAR(50),
total DECIMAL(10,2),
paid DECIMAL(10,2),
change_amount DECIMAL(10,2)
);

CREATE TABLE IF NOT EXISTS sale_items(
id INT AUTO_INCREMENT PRIMARY KEY,
sale_id BIGINT,
product_id INT,
name VARCHAR(255),
price DECIMAL(10,2),
cost DECIMAL(10,2),
qty INT
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

EOF

echo "===== CREANDO ADMIN ====="

HASH=$(node -e "require('bcrypt').hash('admin123',10).then(h=>console.log(h))")

mysql posdb -e "
INSERT IGNORE INTO admins(username,password_hash,recovery_key)
VALUES('admin','$HASH','POS-RECOVERY-123');
"

echo "===== INICIANDO POS ====="

pm2 start server.js --name pos
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

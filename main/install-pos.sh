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

echo "===== INSTALANDO NODE 20 ====="

curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

echo "===== INSTALANDO PM2 ====="

npm install -g pm2

echo "===== CLONANDO POS ====="

mkdir -p /var/www
cd /var/www
git clone $REPO pos

cd $APP_DIR

echo "===== INSTALANDO LIBRERIAS NODE ====="

npm init -y
npm install express mysql2 cors

echo "===== CREANDO SERVER ====="

cat <<EOF > server.js
const express=require("express")
const path=require("path")
const mysql=require("mysql2")
const cors=require("cors")

const app=express()

app.use(cors())
app.use(express.json())

/* FRONTEND */

const FRONT=path.join(__dirname,"main")

app.use(express.static(FRONT))

app.get("/",(req,res)=>{
res.sendFile(path.join(FRONT,"index.html"))
})

/* MYSQL */

const db=mysql.createPool({
host:"localhost",
user:"posuser",
password:"pos123",
database:"posdb"
})

/* PRODUCTOS */

app.get("/api/products",(req,res)=>{

db.query("SELECT * FROM products",(err,data)=>{

if(err){
console.log(err)
return res.status(500).json(err)
}

res.json(data)

})

})

app.post("/api/products",(req,res)=>{
/* ===== PRODUCTOS ===== */

app.get("/api/products",(req,res)=>{
db.query("SELECT * FROM products",(err,data)=>{
if(err)return res.send(err)
res.json(data)
})
})

app.post("/api/products",(req,res)=>{
const {name,price,cost,stock,cat}=req.body
db.query(
"INSERT INTO products(name,price,cost,stock,cat,sold) VALUES(?,?,?,?,?,0)",
[name,price,cost,stock,cat],
(err)=>{
if(err)return res.send(err)
res.json({ok:true})
}
)
})

/* ===== ELIMINAR PRODUCTO ===== */

app.delete("/api/products/:id",(req,res)=>{

db.query(
"DELETE FROM products WHERE id=?",
[req.params.id],
(err)=>{

if(err){
console.log(err)
return res.status(500).json(err)
}

res.json({ok:true})

})

})

const {name,price,cost,stock,cat}=req.body

db.query(
"INSERT INTO products(name,price,cost,stock,cat,sold) VALUES(?,?,?,?,?,0)",
[name,price,cost,stock,cat],
(err)=>{

if(err){
console.log(err)
return res.status(500).json(err)
}

res.json({ok:true})

})

})

app.put("/api/products/:id",(req,res)=>{

const id=req.params.id
const {name,price,cost,stock,cat}=req.body

db.query(
"UPDATE products SET name=?,price=?,cost=?,stock=?,cat=? WHERE id=?",
[name,price,cost,stock,cat,id],
(err)=>{

if(err){
console.log(err)
return res.status(500).json(err)
}

res.json({ok:true})

})

})

app.delete("/api/products/:id",(req,res)=>{

db.query(
"DELETE FROM products WHERE id=?",
[req.params.id],
(err)=>{

if(err){
console.log(err)
return res.status(500).json(err)
}

res.json({ok:true})

})

})

/* RESTOCK */

app.post("/api/restock",(req,res)=>{

const {id,qty}=req.body

db.query(
"UPDATE products SET stock=stock+? WHERE id=?",
[qty,id],
(err)=>{

if(err){
console.log(err)
return res.status(500).json(err)
}

res.json({ok:true})

})

})

/* VENTAS */

app.get("/api/sales",(req,res)=>{

db.query("SELECT * FROM sales ORDER BY id DESC",(err,data)=>{

if(err){
console.log(err)
return res.json([])
}

res.json(data)

})

})

app.post("/api/sales",(req,res)=>{

const sale=req.body

db.query(
"INSERT INTO sales(id,date,total,paid,change_amount) VALUES(?,?,?,?,?)",
[sale.id,sale.date,sale.total,sale.paid,sale.change],
(err)=>{

if(err){
console.log(err)
return res.status(500).json(err)
}

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
"UPDATE products SET stock=stock-?, sold=sold+? WHERE id=?",
[item.qty,item.qty,item.id]
)

})

res.json({ok:true})

})

})

const PORT=$PORT

app.listen(PORT,()=>{
console.log("POS corriendo en puerto",PORT)
})
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

EOF

echo "===== INICIANDO POS ====="

pm2 start server.js --name pos
pm2 startup
pm2 save

echo ""
echo "===== POS INSTALADO ====="
echo ""
echo "Abre:"
echo "http://$DOMAIN:$PORT"
echo ""

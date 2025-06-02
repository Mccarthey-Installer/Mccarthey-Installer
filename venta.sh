<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>Acceso de Compra</title>
  <link href="https://fonts.googleapis.com/css2?family=Quicksand:wght@@400;600;700&display=swap" rel="stylesheet">
  <style>
    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }
    body {
      font-family: 'Quicksand', sans-serif;
      background: linear-gradient(135deg, #ff69b4, #00f7ff);
      display: flex;
      justify-content: center;
      align-items: center;
      min-height: 100vh;
      overflow: auto;
      padding: 20px;
    }
    .card {
      background: rgba(255, 255, 255, 0.9);
      width: 100%;
      max-width: 550px;
      border-radius: 25px;
      padding: 30px 20px; /* Reduced padding to make card shorter */
      text-align: center;
      box-shadow: 0 10px 40px rgba(0, 0, 0, 0.3);
      position: relative;
      overflow: hidden;
      border: 2px solid #00f7ff;
      animation: neonGlow 2s infinite alternate ease-in-out;
    }
    .card::before {
      content: '';
      position: absolute;
      top: -50%;
      left: -50%;
      width: 200%;
      height: 200%;
      background: radial-gradient(circle, rgba(255, 105, 180, 0.3), transparent);
      transform: rotate(45deg);
      z-index: -1;
    }
    .card h1 {
      font-size: 34px;
      color: #ff1493;
      text-transform: uppercase;
      margin-bottom: 20px; /* Reduced margin */
      letter-spacing: 3px;
      text-shadow: 0 0 10px #ff69b4;
      animation: flicker 3s infinite ease-in-out;
      font-weight: 700;
    }
    .card p {
      font-size: 18px;
      color: #1e1e1e;
      margin: 8px 0; /* Reduced margin for tighter spacing */
      font-weight: 600;
      transition: transform 0.3s ease, color 0.3s ease;
      background: rgba(0, 247, 255, 0.1);
      padding: 8px; /* Reduced padding */
      border-radius: 10px;
    }
    .card a {
      text-decoration: none;
      display: block;
    }
    .card a p:hover {
      color: #ff69b4;
      transform: translateX(10px);
    }
    .note {
      font-size: 14px;
      color: #ff0000;
      font-style: italic;
      margin-top: 15px; /* Reduced margin */
      font-weight: 500;
      text-shadow: 0 0 5px #ff0000;
    }
    .button {
      background: #ff1493;
      border: none;
      padding: 15px 35px;
      color: white;
      font-size: 18px;
      font-weight: bold;
      border-radius: 50px;
      cursor: pointer;
      transition: all 0.3s ease;
      display: inline-flex;
      align-items: center;
      gap: 10px;
      box-shadow: 0 0 15px #ff69b4;
      animation: bounce 2s infinite ease-in-out;
      text-decoration: none;
    }
    .button:hover {
      background: #00f7ff;
      color: #ff1493;
      transform: scale(1.1);
      box-shadow: 0 0 20px #00f7ff;
    }
    @keyframes bounce {
      0%, 100% { transform: translateY(0); }
      50% { transform: translateY(-8px); }
    }
    @keyframes neonGlow {
      0% { border-color: #00f7ff; box-shadow: 0 0 10px #00f7ff; }
      100% { border-color: #ff69b4; box-shadow: 0 0 20px #ff69b4; }
    }
    @keyframes flicker {
      0%, 100% { opacity: 1; }
      50% { opacity: 0.7; }
    }
    .claro-redes {
      font-size: 30px;
      color: #ff0000;
      font-weight: bold;
      text-transform: uppercase;
      margin: 0 10px;
      text-shadow: 0 0 10px #ff0000;
      animation: pulseText 1.5s infinite ease-in-out;
    }
    @keyframes pulseText {
      0%, 100% { transform: scale(1); }
      50% { transform: scale(1.1); }
    }
    .logo-contenedor, .acciones-contenedor {
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 15px;
      margin: 15px 0; /* Reduced margin */
    }
    .logo-contenedor img, .acciones-contenedor img {
      width: 65px;
      height: 65px;
      border-radius: 50%;
      object-fit: cover;
      border: 2px solid #ff69b4;
      transition: transform 0.5s ease;
    }
    .logo-contenedor img:hover, .acciones-contenedor img:hover {
      transform: rotate(360deg) scale(1.2);
      border-color: #00f7ff;
    }
    .plan-section {
      margin: 10px 0; /* Reduced margin for tighter spacing */
    }
    .plan-section h2 {
      font-size: 20px; /* Smaller font size */
      color: #ff1493;
      margin-bottom: 8px; /* Reduced margin */
      font-weight: 600;
      text-shadow: 0 0 5px #ff69b4;
    }
  </style>
</head>
<body>
  <div class="card">
    <h1>Acceso con McCarthey</h1>
    <p>Planes disponibles:</p>
    <div class="plan-section">
      <h2>7 días</h2>
      <a href="https://t.me/kalixto10" target="_blank" rel="noopener noreferrer">
        <p>1 conexión: $2</p>
      </a>
      <a href="https://t.me/kalixto10" target="_blank" rel="noopener noreferrer">
        <p>2 conexiones: $3</p>
      </a>
    </div>
    <div class="plan-section">
      <h2>15 días</h2>
      <a href="https://t.me/kalixto10" target="_blank" rel="noopener noreferrer">
        <p>1 conexión: $4</p>
      </a>
      <a href="https://t.me/kalixto10" target="_blank" rel="noopener noreferrer">
        <p>2 conexiones: $6</p>
      </a>
    </div>
    <div class="plan-section">
      <h2>30 días</h2>
      <a href="https://t.me/kalixto10" target="_blank" rel="noopener noreferrer">
        <p>1 conexión: $7</p>
      </a>
      <a href="https://t.me/kalixto10" target="_blank" rel="noopener noreferrer">
        <p>2 conexiones: $10</p>
      </a>
    </div>
    <p class="note">Nota: Los compradores que adquieran 4 conexiones o más pueden acceder a precios con descuento especial.</p>
    <div class="logo-contenedor">
      <img src="https://i.imgur.com/JtPKKEr.png" alt="Logo de Claro Redes">
      <p class="claro-redes">Claro Redes</p>
      <img src="https://i.imgur.com/pL7VMpt.png" alt="Ícono de Claro Redes">
    </div>
    <div class="acciones-contenedor">
      <a href="https://t.me/kalixto10" target="_blank" rel="noopener noreferrer">
        <button class="button">Compra ahora</button>
      </a>
      <img src="https://i.imgur.com/U7Wp4xa.png" alt="Ícono adicional">
    </div>
  </div>
</body>
</html>

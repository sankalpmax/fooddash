#!/usr/bin/env bash
set -e

BASE="/home/sankalp/Downloads/vscodefolder/fooddash"
mkdir -p "$BASE"/{frontend/src,user-service/src,restaurant-service/src,order-service/src}

cat > "$BASE/docker-compose.yml" <<'EOF'
services:
  db:
    image: postgres:15
    environment:
      POSTGRES_DB: fooddash
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    ports:
      - "5432:5432"
    volumes:
      - fooddash_db:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres -d fooddash"]
      interval: 5s
      timeout: 5s
      retries: 10

  user-service:
    build: ./user-service
    environment:
      PORT: 3001
      DB_HOST: db
      DB_USER: postgres
      DB_PASSWORD: postgres
      DB_NAME: fooddash
      JWT_SECRET: fooddash-secret
    ports:
      - "3001:3001"
    depends_on:
      db:
        condition: service_healthy

  restaurant-service:
    build: ./restaurant-service
    environment:
      PORT: 3002
      DB_HOST: db
      DB_USER: postgres
      DB_PASSWORD: postgres
      DB_NAME: fooddash
    ports:
      - "3002:3002"
    depends_on:
      db:
        condition: service_healthy

  order-service:
    build: ./order-service
    environment:
      PORT: 3003
      DB_HOST: db
      DB_USER: postgres
      DB_PASSWORD: postgres
      DB_NAME: fooddash
      JWT_SECRET: fooddash-secret
    ports:
      - "3003:3003"
    depends_on:
      db:
        condition: service_healthy

  frontend:
    build: ./frontend
    ports:
      - "3000:3000"
    depends_on:
      - user-service
      - restaurant-service
      - order-service

volumes:
  fooddash_db:
EOF

for service in user-service restaurant-service order-service; do
cat > "$BASE/$service/package.json" <<EOF
{
  "name": "$service",
  "version": "1.0.0",
  "scripts": { "start": "node src/index.js" },
  "dependencies": {
    "bcryptjs": "^2.4.3",
    "cors": "^2.8.5",
    "express": "^4.21.2",
    "jsonwebtoken": "^9.0.2",
    "pg": "^8.13.1"
  }
}
EOF

cat > "$BASE/$service/Dockerfile" <<EOF
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY src ./src
CMD ["npm", "start"]
EOF
done

cat > "$BASE/user-service/src/index.js" <<'EOF'
const express = require("express");
const cors = require("cors");
const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const { Pool } = require("pg");

const app = express();
const pool = new Pool({
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME
});

app.use(cors());
app.use(express.json());

app.get("/health", (_, res) => res.json({ status: "ok" }));

async function init() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS users (
      id SERIAL PRIMARY KEY,
      name TEXT NOT NULL,
      email TEXT UNIQUE NOT NULL,
      password TEXT NOT NULL
    )
  `);

  app.post("/api/users/register", async (req, res) => {
    try {
      const { name, email, password } = req.body;
      if (!name || !email || !password) {
        return res.status(400).json({ message: "All fields are required" });
      }

      const hash = await bcrypt.hash(password, 10);
      const result = await pool.query(
        "INSERT INTO users(name,email,password) VALUES($1,$2,$3) RETURNING id,name,email",
        [name, email, hash]
      );

      const user = result.rows[0];
      const token = jwt.sign({ userId: user.id }, process.env.JWT_SECRET);
      res.status(201).json({ token, user });
    } catch {
      res.status(409).json({ message: "Email already registered" });
    }
  });

  app.post("/api/users/login", async (req, res) => {
    const { email, password } = req.body;
    const result = await pool.query("SELECT * FROM users WHERE email=$1", [email]);

    if (!result.rows.length || !(await bcrypt.compare(password, result.rows[0].password))) {
      return res.status(401).json({ message: "Invalid credentials" });
    }

    const user = result.rows[0];
    const token = jwt.sign({ userId: user.id }, process.env.JWT_SECRET);
    res.json({
      token,
      user: { id: user.id, name: user.name, email: user.email }
    });
  });

  app.listen(process.env.PORT, () =>
    console.log("User service running on port 3001")
  );
}

init().catch(console.error);
EOF

cat > "$BASE/restaurant-service/src/index.js" <<'EOF'
const express = require("express");
const cors = require("cors");
const { Pool } = require("pg");

const app = express();
const pool = new Pool({
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME
});

app.use(cors());
app.use(express.json());

app.get("/health", (_, res) => res.json({ status: "ok" }));

async function init() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS restaurants (
      id SERIAL PRIMARY KEY,
      name TEXT NOT NULL,
      cuisine TEXT NOT NULL,
      location TEXT NOT NULL,
      rating NUMERIC DEFAULT 4.5
    );

    CREATE TABLE IF NOT EXISTS menu_items (
      id SERIAL PRIMARY KEY,
      restaurant_id INTEGER REFERENCES restaurants(id),
      name TEXT NOT NULL,
      price NUMERIC NOT NULL,
      description TEXT NOT NULL
    )
  `);

  const count = await pool.query("SELECT COUNT(*) FROM restaurants");

  if (Number(count.rows[0].count) === 0) {
    await pool.query(`
      INSERT INTO restaurants(name,cuisine,location,rating) VALUES
      ('Spice Route','Indian','Downtown',4.8),
      ('Bella Pasta','Italian','City Center',4.7),
      ('Sushi Haven','Japanese','Harbor Lane',4.9)
    `);

    await pool.query(`
      INSERT INTO menu_items(restaurant_id,name,price,description) VALUES
      (1,'Paneer Tikka',12.99,'Grilled cottage cheese with spices'),
      (1,'Butter Chicken',16.99,'Creamy tomato curry'),
      (2,'Margherita Pizza',13.99,'Tomato, mozzarella and basil'),
      (2,'Pesto Pasta',15.50,'Pasta with basil pesto'),
      (3,'Salmon Roll',18.50,'Fresh salmon and avocado'),
      (3,'Miso Soup',5.00,'Traditional Japanese soup')
    `);
  }

  app.get("/api/restaurants", async (_, res) => {
    const result = await pool.query("SELECT * FROM restaurants ORDER BY id");
    res.json(result.rows);
  });

  app.get("/api/restaurants/:id/menu", async (req, res) => {
    const restaurant = await pool.query(
      "SELECT * FROM restaurants WHERE id=$1",
      [req.params.id]
    );
    const menu = await pool.query(
      "SELECT * FROM menu_items WHERE restaurant_id=$1 ORDER BY id",
      [req.params.id]
    );

    if (!restaurant.rows.length) {
      return res.status(404).json({ message: "Restaurant not found" });
    }

    res.json({ restaurant: restaurant.rows[0], menuItems: menu.rows });
  });

  app.listen(process.env.PORT, () =>
    console.log("Restaurant service running on port 3002")
  );
}

init().catch(console.error);
EOF

cat > "$BASE/order-service/src/index.js" <<'EOF'
const express = require("express");
const cors = require("cors");
const jwt = require("jsonwebtoken");
const { Pool } = require("pg");

const app = express();
const pool = new Pool({
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME
});

app.use(cors());
app.use(express.json());

app.get("/health", (_, res) => res.json({ status: "ok" }));

function auth(req, res, next) {
  try {
    const token = req.headers.authorization.split(" ")[1];
    req.user = jwt.verify(token, process.env.JWT_SECRET);
    next();
  } catch {
    res.status(401).json({ message: "Authentication required" });
  }
}

async function init() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS orders (
      id SERIAL PRIMARY KEY,
      user_id INTEGER NOT NULL,
      restaurant_id INTEGER NOT NULL,
      items JSONB NOT NULL,
      total NUMERIC NOT NULL,
      status TEXT DEFAULT 'pending',
      created_at TIMESTAMP DEFAULT NOW()
    )
  `);

  app.post("/api/orders", auth, async (req, res) => {
    const { restaurant_id, items } = req.body;

    if (!restaurant_id || !Array.isArray(items) || !items.length) {
      return res.status(400).json({ message: "Restaurant and items are required" });
    }

    const total = items.reduce(
      (sum, item) => sum + Number(item.price) * Number(item.quantity),
      0
    );

    const result = await pool.query(
      `INSERT INTO orders(user_id,restaurant_id,items,total)
       VALUES($1,$2,$3,$4) RETURNING *`,
      [req.user.userId, restaurant_id, JSON.stringify(items), total]
    );

    res.status(201).json(result.rows[0]);
  });

  app.get("/api/orders/my-orders", auth, async (req, res) => {
    const result = await pool.query(
      "SELECT * FROM orders WHERE user_id=$1 ORDER BY created_at DESC",
      [req.user.userId]
    );
    res.json(result.rows);
  });

  app.listen(process.env.PORT, () =>
    console.log("Order service running on port 3003")
  );
}

init().catch(console.error);
EOF

cat > "$BASE/frontend/package.json" <<'EOF'
{
  "name": "fooddash-frontend",
  "version": "1.0.0",
  "private": true,
  "scripts": { "start": "vite --host 0.0.0.0 --port 3000" },
  "dependencies": {
    "@vitejs/plugin-react": "^4.3.4",
    "vite": "^6.0.5",
    "react": "^18.3.1",
    "react-dom": "^18.3.1"
  },
  "devDependencies": {}
}
EOF

cat > "$BASE/frontend/Dockerfile" <<'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
CMD ["npm", "start"]
EOF

cat > "$BASE/frontend/index.html" <<'EOF'
<div id="root"></div>
<script type="module" src="/src/main.jsx"></script>
EOF

cat > "$BASE/frontend/src/main.jsx" <<'EOF'
import React, { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";

const API = {
  users: "http://localhost:3001",
  restaurants: "http://localhost:3002",
  orders: "http://localhost:3003"
};

function App() {
  const [user, setUser] = useState(null);
  const [form, setForm] = useState({ name: "", email: "", password: "" });
  const [restaurants, setRestaurants] = useState([]);
  const [menu, setMenu] = useState(null);
  const [cart, setCart] = useState([]);

  async function register() {
    const r = await fetch(`${API.users}/api/users/register`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(form)
    });
    const data = await r.json();
    if (!r.ok) return alert(data.message);
    setUser(data);
  }

  async function loadRestaurants() {
    const r = await fetch(`${API.restaurants}/api/restaurants`);
    setRestaurants(await r.json());
  }

  async function loadMenu(id) {
    const r = await fetch(`${API.restaurants}/api/restaurants/${id}/menu`);
    setMenu(await r.json());
  }

  async function placeOrder() {
    if (!user) return alert("Register first");
    const r = await fetch(`${API.orders}/api/orders`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${user.token}`
      },
      body: JSON.stringify({
        restaurant_id: menu.restaurant.id,
        items: cart
      })
    });
    const data = await r.json();
    if (!r.ok) return alert(data.message);
    alert(`Order #${data.id} placed successfully`);
    setCart([]);
  }

  useEffect(() => { loadRestaurants(); }, []);

  return (
    <main style={{ maxWidth: 900, margin: "auto", fontFamily: "Arial", padding: 24 }}>
      <h1>FoodDash</h1>

      {!user && (
        <section>
          <h2>Register</h2>
          <input placeholder="Name" onChange={e => setForm({...form, name:e.target.value})} />
          <input placeholder="Email" onChange={e => setForm({...form, email:e.target.value})} />
          <input placeholder="Password" type="password" onChange={e => setForm({...form, password:e.target.value})} />
          <button onClick={register}>Register</button>
        </section>
      )}

      {user && <p>Welcome, {user.user.name}</p>}

      <h2>Restaurants</h2>
      {restaurants.map(r => (
        <button key={r.id} onClick={() => loadMenu(r.id)} style={{ margin: 6 }}>
          {r.name} ({r.cuisine})
        </button>
      ))}

      {menu && (
        <section>
          <h2>{menu.restaurant.name} Menu</h2>
          {menu.menuItems.map(item => (
            <div key={item.id} style={{ margin: 12 }}>
              <b>{item.name}</b> — ${item.price}
              <button onClick={() => setCart([...cart, {...item, quantity: 1}])}>
                Add
              </button>
            </div>
          ))}

          <h2>Cart</h2>
          <p>{cart.map(item => item.name).join(", ") || "Empty"}</p>
          <button disabled={!cart.length} onClick={placeOrder}>Place Order</button>
        </section>
      )}
    </main>
  );
}

createRoot(document.getElementById("root")).render(<App />);
EOF

echo "FoodDash files created successfully."

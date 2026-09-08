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

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

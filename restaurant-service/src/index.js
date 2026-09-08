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

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

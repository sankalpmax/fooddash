import React, { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";

// ── Animations ──────────────────────────────────────────────────────────────
const STYLES = `
  @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap');

  * { box-sizing: border-box; }

  body {
    margin: 0;
    background: linear-gradient(135deg, #667eea15, #764ba215);
    min-height: 100vh;
    font-family: 'Inter', Arial, sans-serif;
  }

  @keyframes fadeInUp {
    from { opacity: 0; transform: translateY(20px); }
    to   { opacity: 1; transform: translateY(0); }
  }

  @keyframes fadeIn {
    from { opacity: 0; }
    to   { opacity: 1; }
  }

  @keyframes slideIn {
    from { opacity: 0; transform: translateX(-20px); }
    to   { opacity: 1; transform: translateX(0); }
  }

  @keyframes pulse {
    0%, 100% { transform: scale(1); }
    50%       { transform: scale(1.05); }
  }

  @keyframes spin {
    to { transform: rotate(360deg); }
  }

  @keyframes statusPop {
    0%   { transform: scale(0.8); opacity: 0; }
    70%  { transform: scale(1.1); }
    100% { transform: scale(1);   opacity: 1; }
  }

  @keyframes progressFill {
    from { width: 0%; }
    to   { width: var(--progress); }
  }

  @keyframes shimmer {
    0%   { background-position: -200% 0; }
    100% { background-position: 200% 0; }
  }

  .fade-in-up  { animation: fadeInUp 0.4s ease both; }
  .fade-in     { animation: fadeIn 0.3s ease both; }
  .slide-in    { animation: slideIn 0.3s ease both; }

  .card {
    background: white;
    border-radius: 16px;
    padding: 20px;
    box-shadow: 0 2px 12px rgba(0,0,0,0.08);
    transition: box-shadow 0.2s, transform 0.2s;
  }
  .card:hover { box-shadow: 0 6px 24px rgba(0,0,0,0.12); transform: translateY(-2px); }

  .btn {
    border: none; cursor: pointer; font-family: inherit;
    font-weight: 600; border-radius: 10px;
    transition: transform 0.15s, box-shadow 0.15s, opacity 0.15s;
  }
  .btn:hover  { transform: translateY(-1px); box-shadow: 0 4px 12px rgba(0,0,0,0.15); }
  .btn:active { transform: translateY(0); }
  .btn:disabled { opacity: 0.6; cursor: not-allowed; transform: none; box-shadow: none; }

  .btn-primary { background: linear-gradient(135deg, #667eea, #764ba2); color: white; }
  .btn-success { background: linear-gradient(135deg, #11998e, #38ef7d); color: white; }
  .btn-outline { background: white; color: #667eea; border: 2px solid #667eea; }

  input {
    font-family: inherit;
    border: 2px solid #e8e8e8;
    border-radius: 10px;
    padding: 10px 14px;
    font-size: 14px;
    outline: none;
    transition: border-color 0.2s, box-shadow 0.2s;
  }
  input:focus { border-color: #667eea; box-shadow: 0 0 0 3px rgba(102,126,234,0.15); }

  .status-track {
    display: flex;
    align-items: center;
    margin: 16px 0;
    position: relative;
  }

  .status-step {
    display: flex;
    flex-direction: column;
    align-items: center;
    flex: 1;
    position: relative;
    z-index: 1;
  }

  .status-dot {
    width: 32px; height: 32px;
    border-radius: 50%;
    display: flex; align-items: center; justify-content: center;
    font-size: 14px;
    transition: all 0.4s ease;
    border: 3px solid #e0e0e0;
    background: white;
  }

  .status-dot.done {
    background: linear-gradient(135deg, #11998e, #38ef7d);
    border-color: #11998e;
    color: white;
    animation: statusPop 0.4s ease;
  }

  .status-dot.active {
    background: linear-gradient(135deg, #667eea, #764ba2);
    border-color: #667eea;
    color: white;
    animation: pulse 1.5s ease-in-out infinite;
  }

  .status-label {
    font-size: 10px;
    font-weight: 600;
    margin-top: 6px;
    color: #999;
    text-align: center;
    text-transform: uppercase;
    letter-spacing: 0.5px;
  }

  .status-label.active { color: #667eea; }
  .status-label.done   { color: #11998e; }

  .status-line {
    position: absolute;
    top: 16px;
    left: 50%; right: -50%;
    height: 3px;
    background: #e0e0e0;
    z-index: 0;
  }
  .status-line.done { background: linear-gradient(90deg, #11998e, #38ef7d); }

  .spinner {
    width: 18px; height: 18px;
    border: 3px solid rgba(255,255,255,0.4);
    border-top-color: white;
    border-radius: 50%;
    animation: spin 0.7s linear infinite;
    display: inline-block;
    vertical-align: middle;
    margin-right: 6px;
  }

  .restaurant-card {
    background: white;
    border-radius: 14px;
    padding: 16px 20px;
    cursor: pointer;
    border: 2px solid transparent;
    transition: all 0.2s;
    box-shadow: 0 2px 8px rgba(0,0,0,0.06);
  }
  .restaurant-card:hover { border-color: #667eea; box-shadow: 0 4px 16px rgba(102,126,234,0.2); }
  .restaurant-card.active { border-color: #667eea; background: linear-gradient(135deg, #667eea08, #764ba208); }

  .menu-item {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 12px 0;
    border-bottom: 1px solid #f0f0f0;
    animation: slideIn 0.3s ease both;
  }

  .cart-item {
    display: flex;
    justify-content: space-between;
    padding: 8px 0;
    border-bottom: 1px solid #f5f5f5;
    animation: fadeIn 0.2s ease;
  }

  .nav-btn {
    padding: 8px 18px;
    border-radius: 20px;
    font-size: 14px;
  }

  .badge {
    display: inline-flex;
    align-items: center;
    padding: 4px 12px;
    border-radius: 20px;
    font-size: 12px;
    font-weight: 700;
    letter-spacing: 0.5px;
  }

  .order-card {
    background: white;
    border-radius: 16px;
    padding: 20px;
    margin: 12px 0;
    box-shadow: 0 2px 12px rgba(0,0,0,0.07);
    animation: fadeInUp 0.35s ease both;
    border-left: 4px solid #667eea;
  }
`;

// ── Constants ────────────────────────────────────────────────────────────────
const API_BASE_URL = import.meta.env.VITE_API_BASE_URL
  || "http://fooddash-production-1133168556.ap-south-2.elb.amazonaws.com";

// Use Vite's build mode to detect environment — reliable in all cases
// In production build: import.meta.env.DEV is false
// In local dev server: import.meta.env.DEV is true
const IS_LOCAL = import.meta.env.DEV;

const API = {
  users:       IS_LOCAL ? "http://localhost:3001" : API_BASE_URL,
  restaurants: IS_LOCAL ? "http://localhost:3002" : API_BASE_URL,
  orders:      IS_LOCAL ? "http://localhost:3003" : API_BASE_URL,
};

const STATUS_FLOW = [
  { key: "pending",          icon: "🕐", label: "Pending" },
  { key: "confirmed",        icon: "✅", label: "Confirmed" },
  { key: "preparing",        icon: "👨‍🍳", label: "Preparing" },
  { key: "out_for_delivery", icon: "🛵", label: "On the way" },
  { key: "delivered",        icon: "🎉", label: "Delivered" },
];

const STATUS_BADGE = {
  pending:          { bg: "#fff3cd", color: "#856404" },
  confirmed:        { bg: "#cce5ff", color: "#004085" },
  preparing:        { bg: "#fde8d8", color: "#c0571d" },
  out_for_delivery: { bg: "#d1ecf1", color: "#0c5460" },
  delivered:        { bg: "#d4edda", color: "#155724" },
};

// ── Status Tracker Component ─────────────────────────────────────────────────
function StatusTracker({ status }) {
  const currentIdx = STATUS_FLOW.findIndex(s => s.key === status);

  return (
    <div style={{ margin: "16px 0" }}>
      <div className="status-track">
        {STATUS_FLOW.map((step, i) => {
          const isDone   = i < currentIdx;
          const isActive = i === currentIdx;
          return (
            <div key={step.key} className="status-step">
              {i < STATUS_FLOW.length - 1 && (
                <div className={`status-line ${isDone ? "done" : ""}`} />
              )}
              <div className={`status-dot ${isDone ? "done" : isActive ? "active" : ""}`}>
                {isDone ? "✓" : step.icon}
              </div>
              <div className={`status-label ${isDone ? "done" : isActive ? "active" : ""}`}>
                {step.label}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

// ── Order Card Component ─────────────────────────────────────────────────────
function OrderCard({ order, token, onStatusUpdate }) {
  const [loading, setLoading] = useState(false);
  const currentIdx = STATUS_FLOW.findIndex(s => s.key === order.status);
  const nextStep   = STATUS_FLOW[currentIdx + 1];

  async function updateStatus() {
    if (!nextStep) return;
    setLoading(true);
    const r = await fetch(`${API.orders}/api/orders/${order.id}/status`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
      body: JSON.stringify({ status: nextStep.key })
    });
    const data = await r.json();
    setLoading(false);
    if (r.ok) onStatusUpdate(order.id, data.status);
  }

  const badgeStyle = STATUS_BADGE[order.status] || { bg: "#eee", color: "#333" };

  return (
    <div className="order-card">
      {/* Order Header */}
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 4 }}>
        <div>
          <span style={{ fontWeight: 700, fontSize: 16 }}>Order #{order.id}</span>
          <span style={{ color: "#888", marginLeft: 10, fontSize: 13 }}>
            ${Number(order.total).toFixed(2)}
          </span>
        </div>
        <span className="badge" style={{ background: badgeStyle.bg, color: badgeStyle.color }}>
          {order.status?.replace(/_/g, " ").toUpperCase()}
        </span>
      </div>

      {/* Items */}
      <div style={{ fontSize: 13, color: "#666", marginBottom: 12 }}>
        {order.items?.map((item, i) => (
          <span key={i}>
            {item.name} ×{item.quantity}
            {i < order.items.length - 1 ? " · " : ""}
          </span>
        ))}
      </div>

      {/* Status Tracker */}
      <StatusTracker status={order.status} />

      {/* Action Button */}
      {nextStep ? (
        <button
          className="btn btn-primary"
          onClick={updateStatus}
          disabled={loading}
          style={{ padding: "10px 20px", fontSize: 14, marginTop: 8 }}
        >
          {loading ? (
            <><span className="spinner" /> Updating...</>
          ) : (
            `${nextStep.icon} Mark as ${nextStep.label}`
          )}
        </button>
      ) : (
        <div style={{ marginTop: 8, color: "#11998e", fontWeight: 600, fontSize: 14 }}>
          🎉 Order delivered successfully!
        </div>
      )}
    </div>
  );
}

// ── Main App ─────────────────────────────────────────────────────────────────
function App() {
  const [user, setUser]               = useState(null);
  const [form, setForm]               = useState({ name: "", email: "", password: "" });
  const [restaurants, setRestaurants] = useState([]);
  const [menu, setMenu]               = useState(null);
  const [cart, setCart]               = useState([]);
  const [orders, setOrders]           = useState([]);
  const [view, setView]               = useState("home");
  const [regLoading, setRegLoading]   = useState(false);
  const [orderLoading, setOrderLoading] = useState(false);

  async function register() {
    setRegLoading(true);
    const r = await fetch(`${API.users}/api/users/register`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(form)
    });
    const data = await r.json();
    setRegLoading(false);
    if (!r.ok) return alert(data.message);
    setUser(data);
  }

  async function loadRestaurants() {
    const r = await fetch(`${API.restaurants}/api/restaurants`);
    setRestaurants(await r.json());
  }

  async function loadMenu(id) {
    setMenu(null);
    const r = await fetch(`${API.restaurants}/api/restaurants/${id}/menu`);
    setMenu(await r.json());
  }

  async function placeOrder() {
    if (!user) return alert("Register first");
    setOrderLoading(true);
    const r = await fetch(`${API.orders}/api/orders`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${user.token}` },
      body: JSON.stringify({ restaurant_id: menu.restaurant.id, items: cart })
    });
    const data = await r.json();
    setOrderLoading(false);
    if (!r.ok) return alert(data.message);
    setCart([]);
    setMenu(null);
    await loadOrders();
    setView("orders");
  }

  async function loadOrders() {
    if (!user) return;
    const r = await fetch(`${API.orders}/api/orders/my-orders`, {
      headers: { Authorization: `Bearer ${user.token}` }
    });
    setOrders(await r.json());
  }

  function handleStatusUpdate(orderId, newStatus) {
    setOrders(prev => prev.map(o => o.id === orderId ? { ...o, status: newStatus } : o));
  }

  useEffect(() => { loadRestaurants(); }, []);
  useEffect(() => { if (user) loadOrders(); }, [user]);

  return (
    <>
      <style>{STYLES}</style>

      <div style={{ maxWidth: 960, margin: "0 auto", padding: "24px 16px" }}>

        {/* ── Header ── */}
        <div className="fade-in" style={{
          display: "flex", justifyContent: "space-between", alignItems: "center",
          background: "linear-gradient(135deg, #667eea, #764ba2)",
          borderRadius: 20, padding: "16px 24px", marginBottom: 28,
          boxShadow: "0 8px 32px rgba(102,126,234,0.35)"
        }}>
          <div>
            <h1 style={{ margin: 0, color: "white", fontSize: 26, fontWeight: 700 }}>
              🍔 FoodDash
            </h1>
            <div style={{ color: "rgba(255,255,255,0.8)", fontSize: 13, marginTop: 2 }}>
              Order your favourite food
            </div>
          </div>
          {user && (
            <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
              <span style={{ color: "rgba(255,255,255,0.9)", fontSize: 14 }}>
                Hi, {user.user.name} 👋
              </span>
              <button
                className={`btn nav-btn ${view === "home" ? "btn-outline" : ""}`}
                onClick={() => setView("home")}
                style={{ background: view === "home" ? "white" : "rgba(255,255,255,0.2)", color: view === "home" ? "#667eea" : "white", border: "none" }}
              >
                🍽 Menu
              </button>
              <button
                className="btn nav-btn"
                onClick={() => { setView("orders"); loadOrders(); }}
                style={{ background: view === "orders" ? "white" : "rgba(255,255,255,0.2)", color: view === "orders" ? "#667eea" : "white", border: "none" }}
              >
                📦 Orders {orders.length > 0 && `(${orders.length})`}
              </button>
            </div>
          )}
        </div>

        {/* ── Register ── */}
        {!user && (
          <div className="card fade-in-up" style={{ marginBottom: 28 }}>
            <h2 style={{ margin: "0 0 16px", color: "#333" }}>Create Account</h2>
            <div style={{ display: "flex", gap: 10, flexWrap: "wrap" }}>
              <input placeholder="Your name" onChange={e => setForm({...form, name: e.target.value})} />
              <input placeholder="Email address" onChange={e => setForm({...form, email: e.target.value})} />
              <input placeholder="Password" type="password" onChange={e => setForm({...form, password: e.target.value})} />
              <button
                className="btn btn-primary"
                onClick={register}
                disabled={regLoading}
                style={{ padding: "10px 24px", fontSize: 14 }}
              >
                {regLoading ? <><span className="spinner" />Creating...</> : "Get Started →"}
              </button>
            </div>
          </div>
        )}

        {/* ── Home View ── */}
        {view === "home" && (
          <div className="fade-in">
            <h2 style={{ color: "#333", marginBottom: 16 }}>Restaurants</h2>
            <div style={{ display: "flex", gap: 12, flexWrap: "wrap", marginBottom: 28 }}>
              {restaurants.map((r, i) => (
                <div
                  key={r.id}
                  className={`restaurant-card fade-in-up ${menu?.restaurant?.id === r.id ? "active" : ""}`}
                  style={{ animationDelay: `${i * 0.08}s` }}
                  onClick={() => loadMenu(r.id)}
                >
                  <div style={{ fontWeight: 700, fontSize: 15 }}>{r.name}</div>
                  <div style={{ color: "#888", fontSize: 13, marginTop: 2 }}>{r.cuisine}</div>
                  <div style={{ color: "#f4a62a", fontWeight: 600, marginTop: 4, fontSize: 13 }}>
                    ⭐ {r.rating}
                  </div>
                </div>
              ))}
            </div>

            {menu && (
              <div style={{ display: "grid", gridTemplateColumns: "1fr 380px", gap: 24 }}>
                {/* Menu Items */}
                <div className="card slide-in">
                  <h2 style={{ margin: "0 0 16px", color: "#333" }}>
                    {menu.restaurant.name}
                  </h2>
                  {menu.menuItems.map(item => (
                    <div key={item.id} className="menu-item">
                      <div>
                        <div style={{ fontWeight: 600, fontSize: 15 }}>{item.name}</div>
                        <div style={{ fontSize: 12, color: "#888", marginTop: 2 }}>{item.description}</div>
                      </div>
                      <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
                        <span style={{ fontWeight: 700, color: "#667eea", fontSize: 15 }}>
                          ${item.price}
                        </span>
                        <button
                          className="btn btn-success"
                          onClick={() => setCart([...cart, {...item, quantity: 1}])}
                          style={{ padding: "6px 14px", fontSize: 13 }}
                        >
                          + Add
                        </button>
                      </div>
                    </div>
                  ))}
                </div>

                {/* Cart */}
                <div className="card" style={{ alignSelf: "start", position: "sticky", top: 20 }}>
                  <h2 style={{ margin: "0 0 16px", color: "#333" }}>
                    🛒 Cart {cart.length > 0 && <span style={{ fontSize: 14, color: "#667eea" }}>({cart.length})</span>}
                  </h2>
                  {cart.length === 0 ? (
                    <p style={{ color: "#bbb", textAlign: "center", padding: "20px 0" }}>
                      Add items to get started
                    </p>
                  ) : (
                    <>
                      {cart.map((item, i) => (
                        <div key={i} className="cart-item">
                          <span style={{ fontSize: 14 }}>{item.name}</span>
                          <span style={{ color: "#667eea", fontWeight: 600 }}>${item.price}</span>
                        </div>
                      ))}
                      <div style={{ fontWeight: 700, fontSize: 16, margin: "14px 0 10px", borderTop: "2px solid #f0f0f0", paddingTop: 12 }}>
                        Total: ${cart.reduce((s, i) => s + Number(i.price), 0).toFixed(2)}
                      </div>
                      <button
                        className="btn btn-primary"
                        onClick={placeOrder}
                        disabled={!user || orderLoading}
                        style={{ width: "100%", padding: 14, fontSize: 15 }}
                      >
                        {orderLoading
                          ? <><span className="spinner" /> Placing order...</>
                          : user ? "🚀 Place Order" : "Register to Order"}
                      </button>
                    </>
                  )}
                </div>
              </div>
            )}
          </div>
        )}

        {/* ── Orders View ── */}
        {view === "orders" && (
          <div className="fade-in">
            <h2 style={{ color: "#333", marginBottom: 20 }}>📦 My Orders</h2>
            {orders.length === 0 ? (
              <div className="card" style={{ textAlign: "center", padding: 40, color: "#bbb" }}>
                <div style={{ fontSize: 48, marginBottom: 12 }}>🍽</div>
                <div style={{ fontSize: 16 }}>No orders yet</div>
                <div style={{ fontSize: 13, marginTop: 6 }}>Place your first order!</div>
                <button
                  className="btn btn-primary"
                  onClick={() => setView("home")}
                  style={{ marginTop: 16, padding: "10px 24px", fontSize: 14 }}
                >
                  Browse Restaurants
                </button>
              </div>
            ) : (
              orders.map(order => (
                <OrderCard
                  key={order.id}
                  order={order}
                  token={user?.token}
                  onStatusUpdate={handleStatusUpdate}
                />
              ))
            )}
          </div>
        )}

      </div>
    </>
  );
}

createRoot(document.getElementById("root")).render(<App />);

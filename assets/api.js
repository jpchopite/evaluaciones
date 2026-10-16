// Cliente mínimo para las funciones RPC de Supabase (sin dependencias).
async function rpc(nombre, args) {
  const { SUPABASE_URL, SUPABASE_KEY } = window.PARCIAL_CONFIG;
  let res;
  try {
    res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${nombre}`, {
      method: "POST",
      headers: { apikey: SUPABASE_KEY, "Content-Type": "application/json" },
      body: JSON.stringify(args || {}),
    });
  } catch (e) {
    throw new Error("Sin conexión con el servidor. Revisa tu internet e inténtalo de nuevo.");
  }
  let data = null;
  try { data = await res.json(); } catch (e) { /* respuesta vacía (funciones void) */ }
  if (!res.ok) throw new Error((data && data.message) || `Error del servidor (${res.status})`);
  return data;
}

// Almacenamiento tolerante a fallos (modo privado, bloqueado, etc.)
const store = {
  get(k) { try { return localStorage.getItem(k); } catch (e) { return null; } },
  set(k, v) { try { localStorage.setItem(k, v); } catch (e) { /* ignorar */ } },
  del(k) { try { localStorage.removeItem(k); } catch (e) { /* ignorar */ } },
};

function esc(s) {
  return String(s ?? "").replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

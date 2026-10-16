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

// ── Iconos (trazos estilo Lucide) ─────────────────────────────────────────
const ICONS = {
  dashboard: '<rect width="7" height="9" x="3" y="3" rx="1"/><rect width="7" height="5" x="14" y="3" rx="1"/><rect width="7" height="9" x="14" y="12" rx="1"/><rect width="7" height="5" x="3" y="16" rx="1"/>',
  users: '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
  chart: '<path d="M3 3v18h18"/><path d="M18 17V9"/><path d="M13 17V5"/><path d="M8 17v-3"/>',
  book: '<path d="M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z"/><path d="M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z"/>',
  settings: '<line x1="21" x2="14" y1="4" y2="4"/><line x1="10" x2="3" y1="4" y2="4"/><line x1="21" x2="12" y1="12" y2="12"/><line x1="8" x2="3" y1="12" y2="12"/><line x1="21" x2="16" y1="20" y2="20"/><line x1="12" x2="3" y1="20" y2="20"/><line x1="14" x2="14" y1="2" y2="6"/><line x1="8" x2="8" y1="10" y2="14"/><line x1="16" x2="16" y1="18" y2="22"/>',
  search: '<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>',
  download: '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" x2="12" y1="15" y2="3"/>',
  upload: '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" x2="12" y1="3" y2="15"/>',
  clock: '<circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>',
  plus: '<path d="M5 12h14"/><path d="M12 5v14"/>',
  x: '<path d="M18 6 6 18"/><path d="m6 6 12 12"/>',
  check: '<path d="M20 6 9 17l-5-5"/>',
  refresh: '<path d="M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8"/><path d="M21 3v5h-5"/><path d="M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16"/><path d="M8 16H3v5"/>',
  more: '<circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/><circle cx="5" cy="12" r="1"/>',
  key: '<circle cx="7.5" cy="15.5" r="5.5"/><path d="m21 2-9.6 9.6"/><path d="m15.5 7.5 3 3L22 7l-3-3"/>',
  logout: '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" x2="9" y1="12" y2="12"/>',
  menu: '<line x1="4" x2="20" y1="12" y2="12"/><line x1="4" x2="20" y1="6" y2="6"/><line x1="4" x2="20" y1="18" y2="18"/>',
  sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2"/><path d="M12 20v2"/><path d="m4.93 4.93 1.41 1.41"/><path d="m17.66 17.66 1.41 1.41"/><path d="M2 12h2"/><path d="M20 12h2"/><path d="m6.34 17.66-1.41 1.41"/><path d="m19.07 4.93-1.41 1.41"/>',
  moon: '<path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"/>',
  alert: '<path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"/><path d="M12 9v4"/><path d="M12 17h.01"/>',
  flag: '<path d="M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z"/><line x1="4" x2="4" y1="22" y2="15"/>',
  undo: '<path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/><path d="M3 3v5h5"/>',
  trash: '<path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/><line x1="10" x2="10" y1="11" y2="17"/><line x1="14" x2="14" y1="11" y2="17"/>',
  eye: '<path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7Z"/><circle cx="12" cy="12" r="3"/>',
  copy: '<rect width="14" height="14" x="8" y="8" rx="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/>',
  chevron: '<path d="m9 18 6-6-6-6"/>',
  target: '<circle cx="12" cy="12" r="10"/><circle cx="12" cy="12" r="6"/><circle cx="12" cy="12" r="2"/>',
  trend: '<polyline points="22 7 13.5 15.5 8.5 10.5 2 17"/><polyline points="16 7 22 7 22 13"/>',
  info: '<circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/>',
  lock: '<rect width="18" height="11" x="3" y="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>',
};
function icon(name, cls) {
  return `<svg class="i ${cls || ""}" viewBox="0 0 24 24" aria-hidden="true">${ICONS[name] || ""}</svg>`;
}
// Marca: gota de petróleo
let logoN = 0;
function LOGO_SVG() {
  const id = "lg" + (++logoN); // id único: un degradado dentro de un bloque oculto no se pinta en los demás
  return `<svg viewBox="0 0 32 32" width="30" height="30" aria-hidden="true"><defs><linearGradient id="${id}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ffd166"/><stop offset="1" stop-color="#ff8a1f"/></linearGradient></defs><path d="M16 2.5c5.6 6.6 9.5 11.1 9.5 16A9.5 9.5 0 0 1 6.5 18.5c0-4.9 3.9-9.4 9.5-16Z" fill="url(#${id})"/><path d="M11.2 19.6a5 5 0 0 0 4 4.2" stroke="#fff" stroke-opacity=".75" stroke-width="2" stroke-linecap="round" fill="none"/></svg>`;
}

// ── Tema claro/oscuro ─────────────────────────────────────────────────────
function aplicarTema(t) {
  if (t) document.documentElement.setAttribute("data-theme", t);
  else document.documentElement.removeAttribute("data-theme");
}
aplicarTema(store.get("parcial_tema"));
function temaActual() {
  const t = document.documentElement.getAttribute("data-theme");
  return t || (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
}
function alternarTema() {
  const n = temaActual() === "dark" ? "light" : "dark";
  store.set("parcial_tema", n); aplicarTema(n);
  document.querySelectorAll("[data-theme-btn]").forEach(pintarBtnTema);
}
function pintarBtnTema(b) { b.innerHTML = icon(temaActual() === "dark" ? "sun" : "moon"); b.title = "Cambiar tema"; }
document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll("[data-theme-btn]").forEach((b) => { pintarBtnTema(b); b.addEventListener("click", alternarTema); });
  document.querySelectorAll("[data-logo]").forEach((el) => { el.innerHTML = LOGO_SVG(); });
});

// ── Avisos (toasts) ───────────────────────────────────────────────────────
function toast(texto, tipo, ms) {
  let cont = document.getElementById("toasts");
  if (!cont) { cont = document.createElement("div"); cont.id = "toasts"; cont.className = "toasts"; cont.setAttribute("role", "status"); document.body.appendChild(cont); }
  const t = document.createElement("div");
  t.className = "toast " + (tipo || "");
  t.textContent = texto;
  cont.appendChild(t);
  setTimeout(() => t.remove(), ms || 4500);
}

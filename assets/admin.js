// Panel del profesor: navegación por vistas, datos en vivo y acciones de control.
const $ = (id) => document.getElementById(id);
const S = {
  clave: null, filas: [], an: null, banco: null, view: "resumen",
  est: { q: "", filtro: "todos", sort: "nombre", dir: 1 },
  ana: { q: "", dif: 0, revisar: false, sort: "dificultad", dir: 1 },
  ban: { q: "", dif: 0, act: "todas" },
  abiertas: new Set(), detalleId: null, csvPreguntas: [],
};
const VISTAS = {
  resumen: ["Panel de control", "Seguimiento en vivo del parcial"],
  estudiantes: ["Estudiantes", "Códigos de acceso, avance y acciones por estudiante"],
  analisis: ["Análisis de resultados", "Desempeño por pregunta, nivel y tema"],
  banco: ["Banco de preguntas", "Carga, activación y cobertura por nivel"],
  ajustes: ["Ajustes", "Parámetros del parcial y seguridad"],
};
const ETIQ = { sin_iniciar: "Sin iniciar", en_curso: "En curso", finalizado: "Finalizado" };
const MOTIVO = { completado: "Completó todas", entregado: "Entregó", tiempo_agotado: "Tiempo agotado", entregado_por_profesor: "Cerrado por el profesor" };

// ── Utilidades ────────────────────────────────────────────────────────────
const norm = (s) => String(s ?? "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
const fmtN = (n, d = 2) => (n == null || isNaN(n) ? "—" : Number(n).toFixed(d).replace(".", ","));
const pctColor = (p) => (p == null ? "c-brand" : p >= 70 ? "c-ok" : p >= 40 ? "c-warn" : "c-bad");
const gradeCls = (n) => (n >= 15 ? "hi" : n >= 10 ? "mid" : "lo");
function hms(s) {
  s = Math.max(0, Math.round(s));
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), x = s % 60;
  return (h ? h + ":" + String(m).padStart(2, "0") : m) + ":" + String(x).padStart(2, "0");
}
function restante(iso) { return (Date.parse(iso) - Date.now()) / 1000; }
function minutos(a, b) { return a && b ? Math.round((Date.parse(b) - Date.parse(a)) / 60000) : null; }
function iniciales(n) { return String(n || "?").split(/\s+/).filter(Boolean).slice(0, 2).map((p) => p[0]).join("").toUpperCase(); }
function avatar(n) {
  let h = 0; for (const c of String(n)) h = (h * 31 + c.charCodeAt(0)) % 360;
  return `<span class="avatar" style="background:hsl(${h} 55% 46%)">${esc(iniciales(n))}</span>`;
}
function ordenar(arr, k, dir) {
  return [...arr].sort((a, b) => {
    const x = a[k], y = b[k];
    if (x == null && y == null) return 0; if (x == null) return 1; if (y == null) return -1;
    return (typeof x === "string" ? x.localeCompare(y, "es") : x - y) * dir;
  });
}
function th(label, key, st, cls) {
  const ar = st.sort === key ? (st.dir > 0 ? "↑" : "↓") : "↕";
  return `<th class="sort ${cls || ""}" data-sort="${key}">${label}<span class="ar">${ar}</span></th>`;
}
function bindSort(root, st, repaint) {
  root.querySelectorAll("th[data-sort]").forEach((t) => t.addEventListener("click", () => {
    const k = t.dataset.sort;
    st.dir = st.sort === k ? -st.dir : (k === "nombre" || k === "dificultad" ? 1 : -1);
    st.sort = k; repaint();
  }));
}
function vacio(ic, txt) { return `<div class="empty"><div class="ic">${icon(ic)}</div>${txt}</div>`; }
function pintarIconos(root) { root.querySelectorAll("[data-ic]").forEach((el) => { el.innerHTML = icon(el.dataset.ic); }); }

// ── CSV ───────────────────────────────────────────────────────────────────
function parseCSV(text) {
  text = text.replace(/^﻿/, "");
  const first = text.split(/\r?\n/)[0] || "";
  const delim = [";", "\t", ","].map((d) => [d, first.split(d).length]).sort((a, b) => b[1] - a[1])[0][0];
  const rows = []; let row = [], cur = "", q = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) { if (c === '"') { if (text[i + 1] === '"') { cur += '"'; i++; } else q = false; } else cur += c; }
    else if (c === '"') q = true;
    else if (c === delim) { row.push(cur); cur = ""; }
    else if (c === "\n" || c === "\r") {
      if (c === "\r" && text[i + 1] === "\n") i++;
      row.push(cur); cur = "";
      if (row.some((x) => x.trim() !== "")) rows.push(row);
      row = [];
    } else cur += c;
  }
  row.push(cur);
  if (row.some((x) => x.trim() !== "")) rows.push(row);
  return rows;
}
function descargarCSV(nombre, filas) {
  const csv = "﻿" + filas.map((f) => f.map((v) => `"${String(v ?? "").replace(/"/g, '""')}"`).join(";")).join("\r\n");
  const a = document.createElement("a");
  a.href = URL.createObjectURL(new Blob([csv], { type: "text/csv;charset=utf-8" }));
  a.download = nombre; a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 2000);
}
// Excel en español guarda «CSV (delimitado por comas)» en Windows-1252, no en UTF-8:
// si el archivo no es UTF-8 válido se relee con esa codificación para no dañar los acentos.
async function leerArchivo(f) {
  const buf = await f.arrayBuffer();
  try { return new TextDecoder("utf-8", { fatal: true }).decode(buf); }
  catch (e) { return new TextDecoder("windows-1252").decode(buf); }
}
const fechaCSV = (iso) => (iso ? new Date(iso).toLocaleString("es-VE") : "");

// ── Modales ───────────────────────────────────────────────────────────────
function abrirModal(html, wide) {
  const ov = document.createElement("div"); ov.className = "overlay top";
  const m = document.createElement("div"); m.className = "card modal" + (wide ? " wide" : ""); m.setAttribute("role", "dialog"); m.setAttribute("aria-modal", "true");
  m.innerHTML = html;
  document.body.append(ov, m);
  pintarIconos(m);
  const cerrar = () => { ov.remove(); m.remove(); document.removeEventListener("keydown", esc_); };
  const esc_ = (e) => { if (e.key === "Escape") cerrar(); };
  document.addEventListener("keydown", esc_);
  ov.addEventListener("click", cerrar);
  m.querySelectorAll("[data-close]").forEach((b) => b.addEventListener("click", cerrar));
  setTimeout(() => (m.querySelector("input,textarea,button.btn:not(.secondary)") || m).focus(), 30);
  return { m, cerrar };
}
function confirmar(titulo, texto, ok = "Confirmar", peligro = false) {
  return new Promise((res) => {
    const { m, cerrar } = abrirModal(`<h3>${esc(titulo)}</h3><p class="d">${esc(texto)}</p>
      <div class="foot"><button class="btn secondary" data-close>Cancelar</button><button class="btn ${peligro ? "danger" : ""}" id="m-ok">${esc(ok)}</button></div>`);
    m.querySelector("[data-close]").addEventListener("click", () => res(false));
    m.querySelector("#m-ok").addEventListener("click", () => { cerrar(); res(true); });
  });
}
function pedirMinutos(nombre) {
  return new Promise((res) => {
    const { m, cerrar } = abrirModal(`<h3>Tiempo adicional</h3><p class="d">Se suma al tiempo restante de ${esc(nombre)}.</p>
      <div class="seg" style="margin-top:16px" id="m-seg">${[5, 10, 15, 30].map((n) => `<button data-n="${n}">+${n} min</button>`).join("")}</div>
      <label class="field"><span>Minutos</span><input class="input" id="m-n" type="number" min="1" max="240" value="10"></label>
      <div class="foot"><button class="btn secondary" data-close>Cancelar</button><button class="btn" id="m-ok">Agregar tiempo</button></div>`);
    m.querySelectorAll("#m-seg button").forEach((b) => b.addEventListener("click", () => { m.querySelector("#m-n").value = b.dataset.n; }));
    m.querySelector("[data-close]").addEventListener("click", () => res(null));
    m.querySelector("#m-ok").addEventListener("click", () => { const n = Number(m.querySelector("#m-n").value); cerrar(); res(n || null); });
  });
}

// ── Datos ─────────────────────────────────────────────────────────────────
async function cargarResultados() {
  S.filas = await rpc("parcial_admin_resultados", { p_clave: S.clave });
  const n = S.filas.filter((f) => f.estado === "en_curso").length;
  $("nav-curso").textContent = n; $("nav-curso").classList.toggle("hide", !n);
}
async function cargarAnalisis() { S.an = await rpc("parcial_admin_analisis", { p_clave: S.clave }); }
async function cargarBanco() { S.banco = await rpc("parcial_admin_banco", { p_clave: S.clave }); }
async function refrescar(todo) {
  try {
    await Promise.all([cargarResultados(), todo ? cargarAnalisis() : null, todo ? cargarBanco() : null]);
    pintarVista();
    $("live").textContent = "En vivo · " + new Date().toLocaleTimeString("es-VE", { hour: "2-digit", minute: "2-digit" });
  } catch (e) { toast(e.message, "err"); }
}

// ── Acceso ────────────────────────────────────────────────────────────────
async function entrar(c) {
  S.clave = c;
  await Promise.all([cargarBanco(), cargarResultados(), cargarAnalisis()]);
  try { sessionStorage.setItem("adm", c); } catch (e) { /* ignorar */ }
  $("login").classList.add("hide"); $("app").classList.remove("hide");
  irA((location.hash || "#resumen").slice(1));
  let ciclo = 0;
  setInterval(() => { if (!document.hidden) refrescar(++ciclo % 3 === 0); }, 20000);
  setInterval(tickRelojes, 1000);
}
$("f-login").addEventListener("submit", async (e) => {
  e.preventDefault();
  const b = $("b-login"), msg = $("login-msg");
  msg.classList.add("hide"); b.disabled = true; b.innerHTML = `<span class="spinner"></span> Verificando…`;
  try { await entrar($("clave").value); }
  catch (err) { S.clave = null; msg.innerHTML = icon("alert") + `<span>${esc(err.message)}</span>`; msg.classList.remove("hide"); }
  finally { b.disabled = false; b.textContent = "Entrar al panel"; }
});
$("b-salir").addEventListener("click", () => { try { sessionStorage.removeItem("adm"); } catch (e) { /* ignorar */ } location.hash = ""; location.reload(); });
$("b-refresh").addEventListener("click", () => refrescar(true).then(() => toast("Datos actualizados", "ok", 1800)));
$("b-menu").addEventListener("click", () => $("side").classList.toggle("open"));
function pintarTema() { $("b-tema").innerHTML = icon(temaActual() === "dark" ? "sun" : "moon") + (temaActual() === "dark" ? "Tema claro" : "Tema oscuro"); }
$("b-tema").addEventListener("click", () => { alternarTema(); pintarTema(); });
pintarTema();
pintarIconos(document);

// ── Navegación ────────────────────────────────────────────────────────────
window.addEventListener("hashchange", () => { if (S.clave) irA(location.hash.slice(1)); });
function irA(v) {
  if (!VISTAS[v]) v = "resumen";
  S.view = v;
  document.querySelectorAll(".nav a[data-v]").forEach((a) => a.classList.toggle("on", a.dataset.v === v));
  $("v-title").textContent = VISTAS[v][0]; $("v-sub").textContent = VISTAS[v][1];
  $("side").classList.remove("open");
  cerrarMenu();
  const view = $("view");
  view.innerHTML = CONSTRUIR[v]();
  pintarIconos(view);
  ENLAZAR[v] && ENLAZAR[v](view);
  pintarVista();
  window.scrollTo(0, 0);
}
function pintarVista() { cerrarMenu(); PINTAR[S.view] && PINTAR[S.view](); pintarIconos($("view")); tickRelojes(); }
function tickRelojes() {
  document.querySelectorAll("[data-fin]").forEach((el) => {
    const s = restante(el.dataset.fin);
    el.textContent = s > 0 ? hms(s) : "vencido";
    el.classList.toggle("warn", s <= 600 && s > 120); el.classList.toggle("bad", s <= 120);
  });
}

// ── Indicadores de calidad de preguntas ───────────────────────────────────
function alertas(q) {
  if (!q.n || q.n < 3) return [];
  const a = [];
  if (q.distractor && q.distractor.n > q.aciertos) a.push("Un distractor supera a la correcta");
  if (q.pct < 15) a.push("Casi nadie acierta");
  else if (q.dificultad <= 2 && q.pct < 40) a.push("Más difícil de lo esperado");
  if (q.dificultad >= 4 && q.pct > 85) a.push("Más fácil de lo esperado");
  if (q.disc != null && q.disc < 0) a.push("Discriminación negativa");
  return a;
}

// ═════════ VISTAS ═════════
const CONSTRUIR = {}, ENLAZAR = {}, PINTAR = {};

// ── Panel de control ──────────────────────────────────────────────────────
CONSTRUIR.resumen = () => `
  <div class="kpis" id="r-kpis"></div>
  <div class="grid-3-2">
    <div class="card panel">
      <div class="panel-h"><h3>Respondiendo ahora</h3><div class="right"><span class="pill en_curso" id="r-ncurso"></span></div></div>
      <div class="live-list" id="r-live" style="margin-top:14px"></div>
    </div>
    <div class="card panel">
      <div class="panel-h"><h3>Distribución de notas</h3><p class="desc">Exámenes finalizados, en tramos de 2 puntos</p></div>
      <div class="panel-b" id="r-hist"></div>
    </div>
  </div>
  <div class="grid-2">
    <div class="card panel"><div class="panel-h"><h3>Aciertos por nivel de dificultad</h3><p class="desc">Si el banco está bien calibrado, el porcentaje baja a medida que sube el nivel</p></div><div class="panel-b" id="r-dif"></div></div>
    <div class="card panel"><div class="panel-h"><h3>Aciertos por tema</h3><p class="desc">Porcentaje de respuestas correctas en cada área</p></div><div class="panel-b" id="r-tema"></div></div>
  </div>
  <div class="card panel">
    <div class="panel-h"><h3>Preguntas que conviene revisar</h3><div class="right"><a class="btn secondary sm" href="#analisis">Ver análisis completo<span data-ic="chevron"></span></a></div>
      <p class="desc">Detectadas automáticamente a partir de las respuestas (mínimo 3 respuestas por pregunta)</p></div>
    <div id="r-rev"></div>
  </div>`;

PINTAR.resumen = () => {
  const F = S.filas, c = (e) => F.filter((f) => f.estado === e).length;
  const fin = c("finalizado"), cur = c("en_curso"), sin = c("sin_iniciar");
  const R = (S.an && S.an.resumen) || {};
  const apr = R.aprobados || 0;
  const pctFin = F.length ? Math.round((fin / F.length) * 100) : 0;
  $("r-kpis").innerHTML = [
    ["users", "", "Inscritos", F.length, "", `${sin} sin iniciar`],
    ["clock", "warn", "En curso", cur, "", "respondiendo ahora"],
    ["check", "ok", "Finalizados", fin, "", `${pctFin}% del grupo`, pctFin],
    ["target", "", "Promedio", fmtN(R.promedio), " /20", `Mediana ${fmtN(R.mediana)}`],
    ["trend", "ok", "Aprobados", apr, fin ? ` /${fin}` : "", fin ? `${Math.round((apr / fin) * 100)}% con nota ≥ 10` : "sin finalizados aún"],
    ["flag", "amber", "Duración", R.minutos_med ?? "—", R.minutos_med != null ? " min" : "", "mediana para terminar"],
  ].map(([ic, cl, lab, val, unit, foot, meter]) => `
    <div class="card kpi"><div class="lab"><span class="ic ${cl}">${icon(ic)}</span>${lab}</div>
      <div class="val">${esc(val)}<small>${esc(unit)}</small></div>
      ${meter != null ? `<div class="meter"><i style="width:${meter}%"></i></div>` : ""}
      <div class="foot">${esc(foot)}</div></div>`).join("");

  const vivos = ordenar(F.filter((f) => f.estado === "en_curso"), "termina_en", 1);
  $("r-ncurso").textContent = `${vivos.length} en curso`;
  $("r-live").innerHTML = vivos.length ? vivos.map((f) => `
    <div class="live-item" data-det="${f.id}">
      ${avatar(f.nombre)}
      <div style="min-width:0"><div class="nm">${esc(f.nombre)}</div>
        <div class="sm">${f.respondidas}/${f.total} respondidas · nivel actual ${f.nivel} · ${f.correctas} aciertos</div>
        <div class="mini"><i style="width:${(f.respondidas / f.total) * 100}%"></i></div></div>
      <div style="display:grid;gap:4px;justify-items:end"><span class="tleft" data-fin="${esc(f.termina_en)}"></span>
        <button class="btn ghost sm" data-mas="${f.id}" title="Agregar 10 minutos">+10 min</button></div>
    </div>`).join("") : vacio("clock", "Nadie está presentando el parcial en este momento.");
  $("r-live").querySelectorAll("[data-det]").forEach((el) => el.addEventListener("click", (e) => {
    const mas = e.target.closest("[data-mas]");
    if (mas) { e.stopPropagation(); return accion("extender10", S.filas.find((f) => f.id == mas.dataset.mas)); }
    abrirDetalle(Number(el.dataset.det));
  }));

  const dist = (S.an && S.an.distribucion) || [];
  const max = Math.max(1, ...dist);
  $("r-hist").innerHTML = R.finalizados ? `
    <div class="hist">${dist.map((n, i) => `
      <div class="col"><div class="bar ${i < 5 ? "low" : ""}" style="height:${(n / max) * 82}%" title="${n} estudiantes"><b>${n || ""}</b></div>
      <span class="lab">${i * 2}–${i * 2 + 2}</span></div>`).join("")}</div>
    <div class="legend"><span><i style="background:var(--bad)"></i>Menos de 10</span><span><i style="background:var(--brand)"></i>10 o más</span>
      <span>Desviación: <b>${fmtN(R.desv)}</b></span><span>Rango: <b>${fmtN(R.min)} – ${fmtN(R.max)}</b></span></div>`
    : vacio("chart", "La distribución aparecerá cuando haya exámenes finalizados.");

  const hb = (rows, lab, sub) => rows.length ? `<div class="hbars">${rows.map((r) => `
    <div class="hb"><div class="l">${esc(lab(r))}<small>${esc(sub(r))}</small></div>
      <div class="t"><i class="${pctColor(r.pct)}" style="width:${r.pct}%"></i></div><div class="v">${fmtN(r.pct, 0)}%</div></div>`).join("")}</div>`
    : vacio("chart", "Sin respuestas todavía.");
  $("r-dif").innerHTML = hb((S.an && S.an.por_dificultad) || [], (r) => `Nivel ${r.dificultad}`, (r) => `${r.n} resp. · ${r.seg_med ?? "—"} s`);
  $("r-tema").innerHTML = hb((S.an && S.an.por_tema) || [], (r) => r.tema, (r) => `${r.n} respuestas`);

  const rev = ((S.an && S.an.por_pregunta) || []).map((q) => ({ ...q, al: alertas(q) })).filter((q) => q.al.length)
    .sort((a, b) => b.al.length - a.al.length || a.pct - b.pct).slice(0, 6);
  $("r-rev").innerHTML = rev.length ? `<div class="tablewrap" style="margin-top:12px"><table class="t"><thead><tr>
      <th>Pregunta</th><th>Nivel</th><th class="r">% acierto</th><th>Alerta</th></tr></thead><tbody>
      ${rev.map((q) => `<tr class="click" data-q="${q.id}">
        <td class="qcell"><b>${esc(q.enunciado)}</b><small>${esc(q.tema || "")} · #${q.id}</small></td>
        <td><span class="lvl">${q.dificultad}</span></td><td class="r num"><b>${fmtN(q.pct, 0)}%</b></td>
        <td><span class="flag">${icon("alert")}${esc(q.al[0])}</span></td></tr>`).join("")}</tbody></table></div>`
    : `<div class="panel-b">${vacio("check", "No hay alertas por ahora. Las preguntas se comportan como se esperaba.")}</div>`;
  $("r-rev").querySelectorAll("[data-q]").forEach((tr) => tr.addEventListener("click", () => {
    S.abiertas.add(Number(tr.dataset.q)); S.ana.q = "#" + tr.dataset.q; location.hash = "#analisis";
  }));
};

// ── Estudiantes ───────────────────────────────────────────────────────────
CONSTRUIR.estudiantes = () => `
  <div class="card panel">
    <div class="toolbar">
      <div class="search">${icon("search")}<input class="input sm" id="e-q" placeholder="Buscar por nombre, cédula o código" value="${esc(S.est.q)}"></div>
      <div class="seg" id="e-seg"></div>
      <div class="end">
        <button class="btn secondary sm" id="e-exp"><span data-ic="download"></span>Exportar</button>
        <button class="btn sm" id="e-add"><span data-ic="plus"></span>Agregar estudiantes</button>
      </div>
    </div>
    <div class="tablewrap"><table class="t" id="e-tab"><thead></thead><tbody></tbody></table></div>
  </div>`;
ENLAZAR.estudiantes = (v) => {
  v.querySelector("#e-q").addEventListener("input", (e) => { S.est.q = e.target.value; PINTAR.estudiantes(); });
  v.querySelector("#e-exp").addEventListener("click", exportarResultados);
  v.querySelector("#e-add").addEventListener("click", modalAgregar);
};
PINTAR.estudiantes = () => {
  const st = S.est, F = S.filas;
  const cnt = (e) => (e === "todos" ? F.length : F.filter((f) => f.estado === e).length);
  $("e-seg").innerHTML = ["todos", "sin_iniciar", "en_curso", "finalizado"].map((k) =>
    `<button class="${st.filtro === k ? "on" : ""}" data-f="${k}">${k === "todos" ? "Todos" : ETIQ[k]}<span class="n">${cnt(k)}</span></button>`).join("");
  $("e-seg").querySelectorAll("button").forEach((b) => b.addEventListener("click", () => { st.filtro = b.dataset.f; PINTAR.estudiantes(); }));
  const q = norm(st.q);
  let rows = F.filter((f) => (st.filtro === "todos" || f.estado === st.filtro) &&
    (!q || norm(f.nombre + " " + f.cedula + " " + f.codigo).includes(q)));
  rows = ordenar(rows, st.sort, st.dir);
  const tab = $("e-tab");
  tab.querySelector("thead").innerHTML = `<tr>${th("Estudiante", "nombre", st)}<th>Código</th>${th("Estado", "estado", st)}
    ${th("Avance", "respondidas", st)}${th("Aciertos", "correctas", st, "r")}${th("Nota", "nota", st, "r")}<th class="r">Tiempo</th><th></th></tr>`;
  bindSort(tab, st, PINTAR.estudiantes);
  tab.querySelector("tbody").innerHTML = rows.length ? rows.map((f) => {
    const t = f.estado === "en_curso" ? `<span class="tleft" data-fin="${esc(f.termina_en)}"></span><div class="muted" style="font-size:11.5px">restante</div>`
      : f.estado === "finalizado" ? `<b class="num">${minutos(f.iniciado_en, f.finalizado_en) ?? "—"} min</b><div class="muted" style="font-size:11.5px">${esc(MOTIVO[f.motivo] || "")}</div>` : `<span class="muted">—</span>`;
    return `<tr class="click" data-id="${f.id}">
      <td><div class="who">${avatar(f.nombre)}<div><b>${esc(f.nombre)}</b><span>${esc(f.cedula)}</span></div></div></td>
      <td><button class="codebtn" data-copy="${esc(f.codigo)}" title="Copiar código">${esc(f.codigo)}${icon("copy")}</button></td>
      <td><span class="pill ${f.estado}">${ETIQ[f.estado]}</span></td>
      <td class="prog">${f.estado === "sin_iniciar" ? `<span class="muted">—</span>` : `<small>${f.respondidas} / ${f.total}</small><div class="mini"><i style="width:${(f.respondidas / f.total) * 100}%"></i></div>`}</td>
      <td class="r num">${f.estado === "sin_iniciar" ? "—" : f.correctas}</td>
      <td class="r">${f.nota == null ? `<span class="muted">—</span>` : `<span class="grade ${gradeCls(f.nota)}">${fmtN(f.nota)}</span>`}</td>
      <td class="r">${t}</td>
      <td class="r"><button class="btn ghost sm icon" data-menu="${f.id}" aria-label="Acciones">${icon("more")}</button></td></tr>`;
  }).join("") : `<tr><td colspan="8">${vacio("users", F.length ? "Ningún estudiante coincide con la búsqueda." : "Aún no hay estudiantes. Usa “Agregar estudiantes” para cargar la lista.")}</td></tr>`;
  tab.querySelectorAll("tbody tr[data-id]").forEach((tr) => tr.addEventListener("click", (e) => {
    const f = S.filas.find((x) => x.id == tr.dataset.id);
    const cp = e.target.closest("[data-copy]"), mn = e.target.closest("[data-menu]");
    if (cp) { e.stopPropagation(); return copiar(cp.dataset.copy, "Código copiado"); }
    if (mn) { e.stopPropagation(); return abrirMenu(mn, f); }
    abrirDetalle(f.id);
  }));
};

function copiar(txt, okMsg) {
  (navigator.clipboard ? navigator.clipboard.writeText(txt) : Promise.reject())
    .then(() => toast(okMsg || "Copiado", "ok", 1600)).catch(() => toast("No se pudo copiar: " + txt));
}

// Menú contextual de acciones
let menuEl = null;
function cerrarMenu() { if (menuEl) { menuEl.remove(); menuEl = null; } }
document.addEventListener("click", (e) => { if (menuEl && !menuEl.contains(e.target)) cerrarMenu(); });
window.addEventListener("scroll", cerrarMenu, true);
function abrirMenu(btn, f) {
  cerrarMenu();
  const curso = f.estado === "en_curso", ini = f.estado !== "sin_iniciar";
  const items = [
    ["eye", "Ver detalle", "detalle"], ["copy", "Copiar código", "copiar"], null,
    curso && ["clock", "Agregar 10 minutos", "extender10"], curso && ["plus", "Tiempo adicional…", "extender"],
    curso && ["flag", "Cerrar y calificar ahora", "entregar"], ["key", "Generar nuevo código", "codigo"],
    ini && ["undo", "Reiniciar intento", "reiniciar", true], ["trash", "Quitar de la lista", "quitar", true],
  ];
  menuEl = document.createElement("div"); menuEl.className = "dd-menu"; menuEl.style.position = "fixed";
  menuEl.innerHTML = items.filter((x) => x !== false).map((x) => x === null ? "<hr>" :
    `<button data-a="${x[2]}" class="${x[3] ? "danger" : ""}">${icon(x[0])}${x[1]}</button>`).join("");
  document.body.appendChild(menuEl);
  const r = btn.getBoundingClientRect(), h = menuEl.offsetHeight;
  menuEl.style.top = (r.bottom + h + 8 > innerHeight ? r.top - h - 6 : r.bottom + 6) + "px";
  menuEl.style.left = Math.max(8, r.right - menuEl.offsetWidth) + "px";
  menuEl.querySelectorAll("button").forEach((b) => b.addEventListener("click", (e) => { e.stopPropagation(); cerrarMenu(); accion(b.dataset.a, f); }));
}

async function accion(tipo, f) {
  const P = { p_clave: S.clave, p_estudiante_id: f.id };
  try {
    if (tipo === "detalle") return abrirDetalle(f.id);
    if (tipo === "copiar") return copiar(f.codigo, "Código copiado");
    if (tipo === "extender10" || tipo === "extender") {
      const n = tipo === "extender10" ? 10 : await pedirMinutos(f.nombre);
      if (!n) return;
      await rpc("parcial_admin_extender", { ...P, p_minutos: n });
      toast(`+${n} minutos para ${f.nombre}`, "ok");
    } else if (tipo === "entregar") {
      if (!(await confirmar("¿Cerrar el parcial ahora?", `Se calificará el parcial de ${f.nombre} con lo que lleva respondido (${f.respondidas} de ${f.total}). Las preguntas pendientes cuentan 0.`, "Cerrar y calificar", true))) return;
      await rpc("parcial_admin_forzar_entrega", P);
      toast("Parcial cerrado y calificado", "ok");
    } else if (tipo === "codigo") {
      if (!(await confirmar("¿Generar un código nuevo?", `El código actual de ${f.nombre} (${f.codigo}) dejará de funcionar. Si está presentando, su sesión abierta continúa.`, "Generar código"))) return;
      const c = await rpc("parcial_admin_nuevo_codigo", P);
      toast(`Nuevo código de ${f.nombre}: ${c}`, "ok", 8000);
    } else if (tipo === "reiniciar") {
      if (!(await confirmar("¿Reiniciar el intento?", `El intento actual de ${f.nombre} se anulará (queda registrado) y podrá empezar de nuevo con otras preguntas y el tiempo completo.`, "Reiniciar intento", true))) return;
      await rpc("parcial_admin_reiniciar", P);
      toast("Intento reiniciado", "ok");
    } else if (tipo === "quitar") {
      if (!(await confirmar("¿Quitar de la lista?", `${f.nombre} ya no podrá ingresar y no aparecerá en los resultados.`, "Quitar", true))) return;
      await rpc("parcial_admin_eliminar_estudiante", P);
      toast("Estudiante quitado", "ok");
      if (S.detalleId === f.id) cerrarDetalle();
    }
    await refrescar(true);
    if (S.detalleId === f.id) abrirDetalle(f.id);
  } catch (e) { toast(e.message, "err"); }
}

function modalAgregar() {
  const { m, cerrar } = abrirModal(`<h3>Agregar estudiantes</h3>
    <p class="d">Una línea por estudiante: <b>cédula, nombre</b>. Puedes pegar directamente desde Excel. Si la cédula ya existe, solo se actualiza el nombre.</p>
    <textarea class="textarea" id="m-txt" style="margin-top:14px" placeholder="V12345678, María Pérez&#10;V23456789, Juan Rodríguez"></textarea>
    <div style="margin-top:10px"><label class="btn secondary sm"><span data-ic="upload"></span>Importar CSV<input type="file" id="m-file" accept=".csv,.txt" hidden></label>
      <span class="muted" id="m-cnt" style="font-size:13px;margin-left:10px"></span></div>
    <div class="foot"><button class="btn secondary" data-close>Cancelar</button><button class="btn" id="m-ok">Agregar y generar códigos</button></div>`, true);
  const txt = m.querySelector("#m-txt");
  const lista = () => {
    let rows = parseCSV(txt.value);
    if (rows.length && /c[eé]dula/i.test(rows[0][0])) rows = rows.slice(1);
    return rows.filter((r) => (r[0] || "").trim() && (r[1] || "").trim()).map((r) => ({ cedula: r[0].trim(), nombre: r[1].trim() }));
  };
  const cuenta = () => { m.querySelector("#m-cnt").textContent = txt.value.trim() ? `${lista().length} estudiantes detectados` : ""; };
  txt.addEventListener("input", cuenta);
  m.querySelector("#m-file").addEventListener("change", async (e) => { if (e.target.files[0]) { txt.value = await leerArchivo(e.target.files[0]); cuenta(); } });
  m.querySelector("#m-ok").addEventListener("click", async (e) => {
    const L = lista();
    if (!L.length) return toast("No encontré filas válidas (cédula, nombre).", "err");
    e.target.disabled = true;
    try {
      const r = await rpc("parcial_admin_cargar_estudiantes", { p_clave: S.clave, p_estudiantes: L });
      cerrar(); toast(`${r.procesados} estudiantes cargados con su código`, "ok");
      await refrescar(false);
    } catch (err) { toast(err.message, "err"); e.target.disabled = false; }
  });
}
function exportarResultados() {
  const cab = ["Nombre", "Cédula", "Código", "Estado", "Motivo", "Respondidas", "Total", "Aciertos", "Puntos", "Puntos máx.", "Nota /20", "Inicio", "Fin", "Minutos"];
  descargarCSV("resultados_parcial.csv", [cab, ...S.filas.map((f) => [
    f.nombre, f.cedula, f.codigo, ETIQ[f.estado], MOTIVO[f.motivo] || "", f.respondidas ?? "", f.total ?? "", f.correctas ?? "",
    f.puntos ?? "", f.puntos_max ?? "", f.nota == null ? "" : fmtN(f.nota), fechaCSV(f.iniciado_en), fechaCSV(f.finalizado_en),
    minutos(f.iniciado_en, f.finalizado_en) ?? ""])]);
}

// ── Detalle de un estudiante (cajón lateral) ──────────────────────────────
let drawerEls = null;
function cerrarDetalle() { if (drawerEls) { drawerEls.forEach((e) => e.remove()); drawerEls = null; } S.detalleId = null; }
document.addEventListener("keydown", (e) => { if (e.key === "Escape" && drawerEls && !document.querySelector(".modal")) cerrarDetalle(); });
async function abrirDetalle(id) {
  const nuevo = !drawerEls;
  if (nuevo) {
    const ov = document.createElement("div"); ov.className = "overlay"; ov.addEventListener("click", cerrarDetalle);
    const dr = document.createElement("aside"); dr.className = "drawer"; dr.setAttribute("role", "dialog"); dr.setAttribute("aria-modal", "true");
    dr.innerHTML = `<div class="drawer-h"><div class="skeleton" style="width:40px;height:40px;border-radius:50%"></div><div style="flex:1"><div class="skeleton" style="height:18px;width:60%"></div></div></div>
      <div class="drawer-b">${'<div class="skeleton" style="height:80px"></div>'.repeat(3)}</div>`;
    document.body.append(ov, dr); drawerEls = [ov, dr];
  }
  S.detalleId = id;
  try {
    const d = await rpc("parcial_admin_detalle", { p_clave: S.clave, p_estudiante_id: id });
    if (S.detalleId === id && drawerEls) pintarDetalle(drawerEls[1], d);
  } catch (e) { toast(e.message, "err"); cerrarDetalle(); }
}
function trayectoria(R) {
  const W = 600, H = 180, l = 34, r = 10, t = 14, b = 26, N = Math.max(R.length, 2);
  const pres = R.filter((x) => x.orden != null);
  const X = (i) => l + (i / (N - 1)) * (W - l - r), Y = (n) => t + ((5 - n) / 4) * (H - t - b);
  const grid = [1, 2, 3, 4, 5].map((n) => `<line x1="${l}" x2="${W - r}" y1="${Y(n)}" y2="${Y(n)}" stroke="var(--line)" stroke-dasharray="${n === 1 || n === 5 ? "0" : "3 4"}"/><text class="ax" x="${l - 10}" y="${Y(n) + 4}" text-anchor="end">N${n}</text>`).join("");
  const ticks = [1, Math.round(N / 2), N].map((n) => `<text class="ax" x="${X(n - 1)}" y="${H - 6}" text-anchor="middle">${n}</text>`).join("");
  const pts = pres.map((x, i) => `${X(i)},${Y(x.nivel)}`).join(" ");
  const dots = pres.map((x, i) => `<circle cx="${X(i)}" cy="${Y(x.nivel)}" r="5" fill="${x.es_correcta ? "var(--ok)" : x.respondida ? "var(--bad)" : "var(--muted)"}" stroke="var(--surface)" stroke-width="2"><title>Pregunta ${x.orden}: nivel ${x.nivel} · ${x.es_correcta ? "acierto" : x.respondida ? "fallo" : "pendiente"}</title></circle>`).join("");
  return `<svg viewBox="0 0 ${W} ${H}" role="img" aria-label="Nivel de dificultad de cada pregunta presentada">${grid}${ticks}
    <polyline points="${pts}" fill="none" stroke="var(--brand)" stroke-width="2.5" stroke-linejoin="round" opacity=".55"/>${dots}</svg>`;
}
function pintarDetalle(dr, d) {
  const s = d.estudiante, e = d.examen, R = d.respuestas || [];
  const f = S.filas.find((x) => x.id === s.id) || { ...s, estado: e ? e.estado : "sin_iniciar" };
  const resp = R.filter((x) => x.respondida), ok = resp.filter((x) => x.es_correcta).length;
  const tiempo = !e ? "—" : e.estado === "en_curso" ? `<span data-fin="${esc(e.termina_en)}"></span>` : `${minutos(e.iniciado_en, e.finalizado_en) ?? "—"} min`;
  const total = (e && e.total) || R.length;
  const porNivel = [1, 2, 3, 4, 5].map((n) => { const a = resp.filter((x) => x.nivel === n); return { n, tot: a.length, ok: a.filter((x) => x.es_correcta).length }; });
  const curso = e && e.estado === "en_curso";
  dr.innerHTML = `
    <div class="drawer-h">${avatar(s.nombre)}
      <div style="flex:1;min-width:0"><h2>${esc(s.nombre)}</h2>
        <div class="sm"><span>${esc(s.cedula)}</span><button class="codebtn" data-copy="${esc(s.codigo)}">${esc(s.codigo)}${icon("copy")}</button>
          <span class="pill ${f.estado}">${ETIQ[f.estado]}</span>${d.intentos_anulados ? `<span class="pill">${d.intentos_anulados} intento(s) anulado(s)</span>` : ""}</div></div>
      <button class="btn ghost icon" id="d-x" aria-label="Cerrar">${icon("x")}</button></div>
    <div class="drawer-b">
      ${!e ? vacio("clock", "Este estudiante aún no ha iniciado el parcial.") : `
      <div class="dstats">
        <div class="card dstat"><span>Nota</span><b>${e.nota == null ? "—" : `<span class="grade ${gradeCls(e.nota)}" style="padding:0 6px">${fmtN(e.nota)}</span>`}</b></div>
        <div class="card dstat"><span>Aciertos</span><b>${ok}<small class="muted" style="font-size:14px"> / ${resp.length}</small></b></div>
        <div class="card dstat"><span>Puntos</span><b>${e.puntos ?? R.reduce((a, x) => a + Number(x.puntos || 0), 0)}<small class="muted" style="font-size:14px"> / ${e.puntos_max ?? "—"}</small></b></div>
        <div class="card dstat"><span>${curso ? "Restante" : "Duración"}</span><b class="num">${tiempo}</b></div>
      </div>
      <div class="actions">
        ${curso ? `<button class="btn secondary sm" data-a="extender10">${icon("clock")}+10 min</button><button class="btn secondary sm" data-a="extender">${icon("plus")}Otro tiempo</button><button class="btn secondary sm" data-a="entregar">${icon("flag")}Cerrar y calificar</button>` : ""}
        <button class="btn secondary sm" data-a="codigo">${icon("key")}Nuevo código</button>
        <button class="btn danger sm" data-a="reiniciar">${icon("undo")}Reiniciar intento</button>
      </div>
      <div class="card panel"><div class="panel-h"><h3>Recorrido adaptativo</h3><p class="desc">Nivel de cada pregunta presentada, en orden. Verde: acierto · rojo: fallo · gris: pendiente${curso ? ` · nivel actual: ${e.nivel}` : ""}</p></div>
        <div class="panel-b traj">${trayectoria(R)}</div></div>
      <div class="card panel"><div class="panel-h"><h3>Aciertos por nivel</h3></div><div class="panel-b"><div class="hbars">
        ${porNivel.map((p) => { const pc = p.tot ? Math.round((p.ok / p.tot) * 100) : null; return `<div class="hb"><div class="l">Nivel ${p.n}<small>${p.ok} de ${p.tot}</small></div><div class="t"><i class="${pctColor(pc)}" style="width:${pc || 0}%"></i></div><div class="v">${pc == null ? "—" : pc + "%"}</div></div>`; }).join("")}
      </div></div></div>
      <div><h3 style="font-size:16px;margin:4px 0 12px">Respuestas (${resp.length} de ${total})</h3><div class="resp-list">
        ${R.filter((x) => x.orden != null).map((x) => `
          <div class="resp"><div class="n ${x.es_correcta ? "ok" : x.respondida ? "bad" : "pend"}">${x.orden}</div><div style="min-width:0">
            <div class="meta"><span class="lvl" style="width:22px;height:22px;font-size:11px">${x.dificultad}</span><span>${esc(x.tema || "")}</span>${x.segundos != null ? `<span>· ${x.segundos} s</span>` : ""}<span>· ${x.puntos} pts</span></div>
            <div class="q">${esc(x.enunciado)}</div>
            <div class="a">${!x.respondida ? `<span class="muted">En pantalla, sin responder</span>` : x.es_correcta ? `<span class="ok">✓ ${esc(x.elegida)}</span>`
              : `<span class="bad">✗ Respondió: ${esc(x.elegida)}</span><span class="muted">Correcta: ${esc(x.correcta_txt)}</span>`}</div></div></div>`).join("")}
        ${R.some((x) => x.orden == null) ? `<p class="muted" style="font-size:13px;text-align:center;padding:8px">${R.filter((x) => x.orden == null).length} preguntas de su pool aún no se le han presentado.</p>` : ""}
      </div></div>`}
    </div>`;
  dr.querySelector("#d-x").addEventListener("click", cerrarDetalle);
  dr.querySelectorAll("[data-copy]").forEach((b) => b.addEventListener("click", () => copiar(b.dataset.copy, "Código copiado")));
  dr.querySelectorAll("[data-a]").forEach((b) => b.addEventListener("click", () => accion(b.dataset.a, { ...f, id: s.id, nombre: s.nombre, codigo: s.codigo, respondidas: resp.length, total })));
  tickRelojes();
}

// ── Análisis ──────────────────────────────────────────────────────────────
CONSTRUIR.analisis = () => `
  <div class="kpis" id="a-kpis"></div>
  <div class="card panel">
    <div class="toolbar">
      <div class="search">${icon("search")}<input class="input sm" id="a-q" placeholder="Buscar pregunta, tema o #id" value="${esc(S.ana.q)}"></div>
      <div class="seg" id="a-dif"></div>
      <label class="check" style="font-size:13.5px"><input type="checkbox" id="a-rev" ${S.ana.revisar ? "checked" : ""}> Solo con alertas</label>
      <div class="end">
        <button class="btn secondary sm" id="a-exp1"><span data-ic="download"></span>Análisis</button>
        <button class="btn secondary sm" id="a-exp2"><span data-ic="download"></span>Todas las respuestas</button>
      </div>
    </div>
    <div class="tablewrap"><table class="t" id="a-tab"><thead></thead><tbody></tbody></table></div>
    <div class="panel-b muted" style="font-size:12.5px;border-top:1px solid var(--line-2)">
      <b>Discriminación</b>: correlación entre acertar la pregunta y la nota final (−1 a 1). Sobre 0,3 la pregunta separa bien a quienes dominan el tema; un valor negativo indica que los mejores estudiantes la fallan más — conviene revisar el enunciado o la clave.
    </div>
  </div>`;
ENLAZAR.analisis = (v) => {
  v.querySelector("#a-q").addEventListener("input", (e) => { S.ana.q = e.target.value; PINTAR.analisis(); });
  v.querySelector("#a-rev").addEventListener("change", (e) => { S.ana.revisar = e.target.checked; PINTAR.analisis(); });
  v.querySelector("#a-exp1").addEventListener("click", () => {
    const P = (S.an && S.an.por_pregunta) || [];
    descargarCSV("analisis_preguntas.csv", [["ID", "Tema", "Enunciado", "Nivel", "Activa", "Respuestas", "Aciertos", "% acierto", "Tiempo mediano (s)", "Discriminación", "Distractor más elegido", "Veces", "Alertas"],
      ...P.map((q) => [q.id, q.tema, q.enunciado, q.dificultad, q.activa ? "Sí" : "No", q.n, q.aciertos, q.pct == null ? "" : fmtN(q.pct, 1), q.seg_med ?? "",
        q.disc == null ? "" : fmtN(q.disc), q.distractor ? q.distractor.texto : "", q.distractor ? q.distractor.n : "", alertas(q).join(" | ")])]);
  });
  v.querySelector("#a-exp2").addEventListener("click", async (e) => {
    e.currentTarget.disabled = true;
    try {
      const R = await rpc("parcial_admin_respuestas", { p_clave: S.clave });
      descargarCSV("respuestas_detalladas.csv", [["Nombre", "Cédula", "Orden", "Tema", "Enunciado", "Nivel pregunta", "Nivel del estudiante", "Respuesta elegida", "Respuesta correcta", "Correcta", "Puntos", "Segundos"],
        ...R.map((x) => [x.nombre, x.cedula, x.orden, x.tema, x.enunciado, x.dificultad, x.nivel, x.elegida ?? "(sin responder)", x.correcta_txt,
          x.es_correcta == null ? "" : x.es_correcta ? "Sí" : "No", x.puntos, x.segundos ?? ""])]);
    } catch (err) { toast(err.message, "err"); }
    e.currentTarget.disabled = false;
  });
};
PINTAR.analisis = () => {
  const R = (S.an && S.an.resumen) || {}, P = (S.an && S.an.por_pregunta) || [], st = S.ana;
  const totResp = P.reduce((a, q) => a + q.n, 0), totOk = P.reduce((a, q) => a + q.aciertos, 0);
  $("a-kpis").innerHTML = [
    ["target", "", "Promedio", fmtN(R.promedio), " /20", `${R.finalizados || 0} finalizados`],
    ["chart", "", "Mediana", fmtN(R.mediana), " /20", `Desviación ${fmtN(R.desv)}`],
    ["trend", "ok", "Nota más alta", fmtN(R.max), "", `Más baja ${fmtN(R.min)}`],
    ["check", "ok", "Acierto global", totResp ? Math.round((totOk / totResp) * 100) : "—", totResp ? "%" : "", `${totResp} respuestas registradas`],
    ["alert", "amber", "Con alertas", P.filter((q) => alertas(q).length).length, ` /${P.length}`, "preguntas a revisar"],
  ].map(([ic, cl, lab, val, unit, foot]) => `<div class="card kpi"><div class="lab"><span class="ic ${cl}">${icon(ic)}</span>${lab}</div>
      <div class="val">${esc(val)}<small>${esc(unit)}</small></div><div class="foot">${esc(foot)}</div></div>`).join("");
  $("a-dif").innerHTML = [0, 1, 2, 3, 4, 5].map((n) => `<button class="${st.dif === n ? "on" : ""}" data-d="${n}">${n ? "N" + n : "Todos"}</button>`).join("");
  $("a-dif").querySelectorAll("button").forEach((b) => b.addEventListener("click", () => { st.dif = Number(b.dataset.d); PINTAR.analisis(); }));
  const q = norm(st.q).replace(/^#/, "");
  let rows = P.map((x) => ({ ...x, al: alertas(x), nal: alertas(x).length })).filter((x) =>
    (!st.dif || x.dificultad === st.dif) && (!st.revisar || x.nal) &&
    (!q || (/^\d+$/.test(q) ? String(x.id) === q : norm(x.enunciado + " " + x.tema).includes(q))));
  rows = ordenar(rows, st.sort, st.dir);
  const tab = $("a-tab");
  tab.querySelector("thead").innerHTML = `<tr><th>Pregunta</th>${th("Nivel", "dificultad", st)}${th("Resp.", "n", st, "r")}${th("% acierto", "pct", st)}
    ${th("Tiempo", "seg_med", st, "r")}${th("Discrim.", "disc", st, "r")}${th("Alertas", "nal", st)}<th></th></tr>`;
  bindSort(tab, st, PINTAR.analisis);
  tab.querySelector("tbody").innerHTML = rows.length ? rows.map((x) => {
    const abierta = S.abiertas.has(x.id);
    const discCls = x.disc == null ? "" : x.disc < 0 ? "bad" : x.disc >= 0.3 ? "ok" : "";
    return `<tr class="click" data-q="${x.id}" style="${x.activa ? "" : "opacity:.55"}">
      <td class="qcell"><b>${esc(x.enunciado)}</b><small>#${x.id} · ${esc(x.tema || "Sin tema")}${x.activa ? "" : " · inactiva"}</small></td>
      <td><span class="lvl">${x.dificultad}</span></td>
      <td class="r num">${x.n}</td>
      <td>${x.pct == null ? `<span class="muted">sin datos</span>` : `<div class="pctbar"><div class="t2"><i class="${pctColor(x.pct)}" style="width:${x.pct}%"></i></div><b>${fmtN(x.pct, 0)}%</b></div>`}</td>
      <td class="r num">${x.seg_med == null ? "—" : x.seg_med + " s"}</td>
      <td class="r">${x.disc == null ? `<span class="muted">—</span>` : `<span class="pill ${discCls}" style="padding-left:9px">${fmtN(x.disc)}</span>`}</td>
      <td>${x.al.map((a) => `<span class="flag">${icon("alert")}${esc(a)}</span>`).join(" ") || `<span class="muted">—</span>`}</td>
      <td class="r"><span style="display:inline-block;transition:transform .2s;transform:rotate(${abierta ? 90 : 0}deg)">${icon("chevron")}</span></td></tr>
      ${abierta ? `<tr class="expand"><td colspan="8"><div class="qdetail">
        ${(x.opciones || []).map((o, i) => {
          const esOk = i === x.correcta, esDis = x.distractor && x.distractor.texto === o && !esOk;
          return `<div class="qopt ${esOk ? "ok" : esDis ? "dis" : ""}"><span class="k">${"ABCDE"[i]}</span><span>${esc(o)}</span>
            ${esOk ? `<span class="tag" style="color:var(--ok)">✓ Correcta · ${x.aciertos} veces</span>` : esDis ? `<span class="tag" style="color:var(--bad)">Distractor más elegido · ${x.distractor.n} veces</span>` : ""}</div>`;
        }).join("")}
        <div class="muted" style="font-size:12.5px">Las opciones se muestran a cada estudiante en orden aleatorio. Respondida ${x.n} veces.</div></div></td></tr>` : ""}`;
  }).join("") : `<tr><td colspan="8">${vacio("search", "Ninguna pregunta coincide con el filtro.")}</td></tr>`;
  tab.querySelectorAll("tbody tr[data-q]").forEach((tr) => tr.addEventListener("click", () => {
    const id = Number(tr.dataset.q); S.abiertas.has(id) ? S.abiertas.delete(id) : S.abiertas.add(id); PINTAR.analisis();
  }));
};

// ── Banco de preguntas ────────────────────────────────────────────────────
CONSTRUIR.banco = () => `
  <div class="levels" id="b-lv"></div>
  <div class="grid-3-2">
    <div class="card panel"><div class="panel-h"><h3>Cargar preguntas</h3><div class="right"><a class="btn ghost sm" href="plantilla_preguntas.xlsx" download><span data-ic="download"></span>Plantilla Excel</a><a class="btn ghost sm" href="plantilla_preguntas.csv" download><span data-ic="download"></span>Plantilla CSV</a></div></div>
      <div class="panel-b">
        <label class="drop" id="b-drop"><div class="ic">${icon("upload")}</div><b>Arrastra tu archivo CSV aquí</b><span>o haz clic para elegirlo</span>
          <input type="file" id="b-file" accept=".csv,.txt" hidden></label>
        <div id="b-prev"></div>
        <label class="check" style="margin-top:14px"><input type="checkbox" id="b-rep"><span>Reemplazar el banco actual<br><small class="muted">Las preguntas anteriores se desactivan (no se borran) y quedan solo las del archivo.</small></span></label>
        <button class="btn" id="b-ok" style="margin-top:16px" disabled><span data-ic="upload"></span>Cargar preguntas</button>
      </div></div>
    <div class="card panel"><div class="panel-h"><h3>Formato del archivo</h3></div><div class="panel-b" style="font-size:14px;color:var(--ink-2)">
      <p>Una fila por pregunta, separada por punto y coma (como guarda Excel en español):</p>
      <pre class="mono" style="background:var(--surface-2);border:1px solid var(--line);border-radius:10px;padding:12px;font-size:12px;overflow-x:auto;margin:12px 0">tema;enunciado;opcion_a;opcion_b;opcion_c;opcion_d;correcta;dificultad</pre>
      <ul style="padding-left:18px;margin:0;display:grid;gap:6px"><li><b>correcta</b>: letra A, B, C o D.</li><li><b>dificultad</b>: 1 (básica) a 5 (avanzada). Es también su valor en puntos.</li>
        <li>Se aceptan de 2 a 4 opciones; deja vacías las que no uses.</li><li>Recomendado: al menos <b id="b-need">25</b> preguntas por nivel. Si un nivel se agota, se usa el más cercano.</li></ul></div></div>
  </div>
  <div class="card panel">
    <div class="toolbar">
      <div class="search">${icon("search")}<input class="input sm" id="b-q" placeholder="Buscar en el banco" value="${esc(S.ban.q)}"></div>
      <div class="seg" id="b-dif"></div><div class="seg" id="b-act"></div>
    </div>
    <div class="tablewrap"><table class="t" id="b-tab"><thead><tr><th>Pregunta</th><th>Nivel</th><th>Respuesta correcta</th><th class="r">Uso</th><th class="r">Activa</th></tr></thead><tbody></tbody></table></div>
  </div>`;
ENLAZAR.banco = (v) => {
  const drop = v.querySelector("#b-drop"), file = v.querySelector("#b-file");
  file.addEventListener("change", () => file.files[0] && leerPreguntas(file.files[0]));
  ["dragenter", "dragover"].forEach((t) => drop.addEventListener(t, (e) => { e.preventDefault(); drop.classList.add("over"); }));
  ["dragleave", "drop"].forEach((t) => drop.addEventListener(t, (e) => { e.preventDefault(); drop.classList.remove("over"); }));
  drop.addEventListener("drop", (e) => e.dataTransfer.files[0] && leerPreguntas(e.dataTransfer.files[0]));
  v.querySelector("#b-q").addEventListener("input", (e) => { S.ban.q = e.target.value; PINTAR.banco(); });
  v.querySelector("#b-ok").addEventListener("click", subirPreguntas);
};
PINTAR.banco = () => {
  const B = S.banco || {}, pd = B.por_dificultad || {}, need = Math.ceil(Number(B.n_preguntas || 50) / 2), st = S.ban;
  $("b-need").textContent = need;
  $("b-lv").innerHTML = [1, 2, 3, 4, 5].map((n) => {
    const v = pd[n] || 0, okk = v >= need;
    return `<div class="card level"><div class="h">Nivel ${n}<span class="pill ${okk ? "ok" : "warn"}">${okk ? "Suficiente" : "Faltan " + (need - v)}</span></div>
      <b>${v}</b><div class="meter"><i class="${okk ? "c-ok" : "c-warn"}" style="width:${Math.min(100, (v / need) * 100)}%"></i></div>
      <small>${n} ${n === 1 ? "punto" : "puntos"} c/u · recomendado ${need}</small></div>`;
  }).join("");
  $("b-dif").innerHTML = [0, 1, 2, 3, 4, 5].map((n) => `<button class="${st.dif === n ? "on" : ""}" data-d="${n}">${n ? "N" + n : "Todos"}</button>`).join("");
  $("b-dif").querySelectorAll("button").forEach((b) => b.addEventListener("click", () => { st.dif = Number(b.dataset.d); PINTAR.banco(); }));
  $("b-act").innerHTML = [["todas", "Todas"], ["activas", "Activas"], ["inactivas", "Inactivas"]].map(([k, l]) => `<button class="${st.act === k ? "on" : ""}" data-a="${k}">${l}</button>`).join("");
  $("b-act").querySelectorAll("button").forEach((b) => b.addEventListener("click", () => { st.act = b.dataset.a; PINTAR.banco(); }));
  const q = norm(st.q);
  const rows = ((S.an && S.an.por_pregunta) || []).filter((x) => (!st.dif || x.dificultad === st.dif) &&
    (st.act === "todas" || (st.act === "activas") === x.activa) && (!q || norm(x.enunciado + " " + x.tema).includes(q)));
  $("b-tab").querySelector("tbody").innerHTML = rows.length ? rows.map((x) => `<tr style="${x.activa ? "" : "opacity:.6"}">
      <td class="qcell"><b>${esc(x.enunciado)}</b><small>#${x.id} · ${esc(x.tema || "Sin tema")}</small></td>
      <td><span class="lvl">${x.dificultad}</span></td>
      <td style="white-space:normal;min-width:180px;max-width:280px;font-size:13.5px">${esc((x.opciones || [])[x.correcta])}</td>
      <td class="r num">${x.n}</td>
      <td class="r"><label class="switch" title="${x.activa ? "Desactivar" : "Activar"}"><input type="checkbox" data-t="${x.id}" ${x.activa ? "checked" : ""}><i></i></label></td></tr>`).join("")
    : `<tr><td colspan="5">${vacio("book", "No hay preguntas que coincidan.")}</td></tr>`;
  $("b-tab").querySelectorAll("[data-t]").forEach((cb) => cb.addEventListener("change", async () => {
    try {
      await rpc("parcial_admin_activar_pregunta", { p_clave: S.clave, p_pregunta_id: Number(cb.dataset.t), p_activa: cb.checked });
      toast(cb.checked ? "Pregunta activada" : "Pregunta desactivada: no saldrá en exámenes nuevos", "ok", 2500);
      await Promise.all([cargarAnalisis(), cargarBanco()]); PINTAR.banco();
    } catch (e) { toast(e.message, "err"); cb.checked = !cb.checked; }
  }));
};
async function leerPreguntas(f) {
  S.csvPreguntas = [];
  let rows = parseCSV(await leerArchivo(f));
  if (rows.length && /^tema$/i.test((rows[0][0] || "").trim())) rows = rows.slice(1);
  const err = [];
  rows.forEach((r, i) => {
    const n = i + 2, t = (x) => (x ?? "").trim();
    const ops = r.slice(2, 6).map(t); while (ops.length && !ops[ops.length - 1]) ops.pop();
    const idx = "ABCDE".indexOf(t(r[6]).toUpperCase()), dif = Number(t(r[7]));
    if (!t(r[1])) return err.push(`Fila ${n}: falta el enunciado`);
    if (ops.length < 2 || ops.some((o) => !o)) return err.push(`Fila ${n}: necesita al menos 2 opciones sin huecos`);
    if (!t(r[6]) || idx < 0 || idx >= ops.length) return err.push(`Fila ${n}: “correcta” debe ser la letra de una opción`);
    if (!(Number.isInteger(dif) && dif >= 1 && dif <= 5)) return err.push(`Fila ${n}: la dificultad debe ser 1 a 5`);
    S.csvPreguntas.push({ tema: t(r[0]), enunciado: t(r[1]), opciones: ops, correcta: idx, dificultad: dif });
  });
  const por = [1, 2, 3, 4, 5].map((d) => `N${d}: <b>${S.csvPreguntas.filter((p) => p.dificultad === d).length}</b>`).join(" · ");
  $("b-prev").innerHTML = `<div class="msg ${err.length ? "err" : "ok"}">${icon(err.length ? "alert" : "check")}<div><b>${esc(f.name)}</b> — ${S.csvPreguntas.length} preguntas válidas<br><span style="font-weight:500">${por}</span>
    ${err.length ? `<div style="margin-top:6px">${err.slice(0, 6).map(esc).join("<br>")}${err.length > 6 ? `<br>…y ${err.length - 6} errores más` : ""}</div>` : ""}</div></div>`;
  $("b-ok").disabled = !S.csvPreguntas.length || err.length > 0;
}
async function subirPreguntas() {
  const rep = $("b-rep").checked;
  if (rep && !(await confirmar("¿Reemplazar el banco?", `Se desactivarán todas las preguntas actuales y quedarán solo las ${S.csvPreguntas.length} del archivo. Los exámenes ya iniciados no cambian.`, "Reemplazar banco", true))) return;
  $("b-ok").disabled = true;
  try {
    const r = await rpc("parcial_admin_cargar_preguntas", { p_clave: S.clave, p_preguntas: S.csvPreguntas, p_reemplazar: rep });
    toast(`${r.insertadas} preguntas cargadas`, "ok");
    S.csvPreguntas = []; $("b-prev").innerHTML = ""; $("b-file").value = "";
    await Promise.all([cargarAnalisis(), cargarBanco()]); PINTAR.banco();
  } catch (e) { toast(e.message, "err"); $("b-ok").disabled = false; }
}

// ── Ajustes ───────────────────────────────────────────────────────────────
CONSTRUIR.ajustes = () => {
  const url = new URL("index.html", location.href).href.replace(/index\.html$/, "");
  return `<div class="settings">
    <div class="card panel"><div class="panel-h"><h3>Parámetros del parcial</h3><p class="desc">Aplican a los exámenes que se inicien después de guardar</p></div><div class="panel-b">
      <label class="field" style="margin-top:0"><span>Duración (minutos)</span><input class="input" id="s-dur" type="number" min="1"></label>
      <label class="field"><span>Preguntas por estudiante</span><input class="input" id="s-n" type="number" min="5"></label>
      <p class="muted" style="font-size:12.5px;margin-top:8px">Todas las notas son sobre 20, con el mismo puntaje máximo para todos.</p>
      <button class="btn" id="s-ok" style="margin-top:16px">${icon("check")}Guardar parámetros</button></div></div>
    <div class="card panel"><div class="panel-h"><h3>Enlace para estudiantes</h3><p class="desc">Compártelo junto con el código de cada estudiante</p></div><div class="panel-b">
      <div class="linkbox"><input class="input" id="s-url" readonly value="${esc(url)}"><button class="btn secondary icon" id="s-copy" title="Copiar">${icon("copy")}</button></div>
      <a class="btn secondary sm" href="index.html" target="_blank" rel="noopener" style="margin-top:12px">${icon("eye")}Abrir página del estudiante</a></div></div>
    <div class="card panel"><div class="panel-h"><h3>Seguridad</h3><p class="desc">Cambia la clave de este panel (mínimo 8 caracteres)</p></div><div class="panel-b">
      <label class="field" style="margin-top:0"><span>Nueva clave</span><input class="input" id="s-c1" type="password" autocomplete="new-password"></label>
      <label class="field"><span>Repite la nueva clave</span><input class="input" id="s-c2" type="password" autocomplete="new-password"></label>
      <button class="btn secondary" id="s-cok" style="margin-top:16px">${icon("lock")}Cambiar clave</button></div></div>
    <div class="card panel"><div class="panel-h"><h3>Cómo funciona el algoritmo</h3></div><div class="panel-b">
      <ol class="algo" style="margin:0;padding:0">
        <li>Empieza en el nivel 1. Cada pregunta se saca al azar de todo el banco, entre las del nivel actual que aún no ha visto.</li>
        <li>Si acierta, la siguiente es de un nivel más (hasta el 5); si falla, de un nivel menos (nunca por debajo del 1).</li>
        <li>Cada acierto vale su nivel: N1 = 1 punto … N5 = 5 puntos.</li>
        <li>Nota = puntos obtenidos ÷ puntaje de un recorrido perfecto (1+2+3+4+5+5+…) × 20. Es igual para todos; lo no respondido cuenta 0.</li>
      </ol></div></div>
  </div>`;
};
ENLAZAR.ajustes = (v) => {
  v.querySelector("#s-copy").addEventListener("click", () => copiar(v.querySelector("#s-url").value, "Enlace copiado"));
  v.querySelector("#s-ok").addEventListener("click", async () => {
    try {
      await rpc("parcial_admin_config", { p_clave: S.clave, p_duracion_min: Number($("s-dur").value), p_n_preguntas: Number($("s-n").value) });
      await cargarBanco(); toast("Parámetros guardados", "ok");
    } catch (e) { toast(e.message, "err"); }
  });
  v.querySelector("#s-cok").addEventListener("click", async () => {
    const a = $("s-c1").value, b = $("s-c2").value;
    if (a !== b) return toast("Las claves no coinciden", "err");
    try {
      await rpc("parcial_admin_cambiar_clave", { p_clave: S.clave, p_nueva: a });
      S.clave = a; try { sessionStorage.setItem("adm", a); } catch (e) { /* ignorar */ }
      $("s-c1").value = $("s-c2").value = ""; toast("Clave actualizada", "ok");
    } catch (e) { toast(e.message, "err"); }
  });
};
PINTAR.ajustes = () => {
  const B = S.banco || {};
  if (document.activeElement !== $("s-dur")) $("s-dur").value = B.duracion_min ?? "";
  if (document.activeElement !== $("s-n")) $("s-n").value = B.n_preguntas ?? "";
};

// Reanudar sesión del profesor en la misma pestaña
(function () {
  let g = null; try { g = sessionStorage.getItem("adm"); } catch (e) { /* ignorar */ }
  if (g) entrar(g).catch(() => { S.clave = null; try { sessionStorage.removeItem("adm"); } catch (e) { /* ignorar */ } });
})();

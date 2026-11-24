// Backend mock de gestion de clientes (Claro CENAM PoC). Sin dependencias externas.
// Rutas: GET/POST /poc-customers/v0/customers, GET /poc-customers/v0/customers/{id}, GET /healthz
// Seguridad: exige header x-api-secret == API_SECRET (inyectado por Cloud Run desde Secret Manager).
const http = require("http");
const crypto = require("crypto");

const PORT = process.env.PORT || 8080;
const ENVIRONMENT = process.env.ENVIRONMENT || "local";
const API_SECRET = process.env.API_SECRET || "";
const BASE = "/poc-customers/v0/customers";

const customers = new Map();
[
  { nombre: "Cliente Uno", documento: "10000001", segmento: "CENAM", correo: "uno@cenam.claro.com" },
  { nombre: "Cliente Dos", documento: "10000002", segmento: "GT", correo: "dos@cenam.claro.com" },
  { nombre: "Cliente Tres", documento: "10000003", segmento: "SV", correo: "tres@cenam.claro.com" },
].forEach((c, i) => customers.set(String(i + 1), { id: String(i + 1), ...c }));

function send(res, status, body, cid) {
  res.writeHead(status, { "Content-Type": "application/json", "x-correlation-id": cid || "", "x-backend-env": ENVIRONMENT });
  res.end(JSON.stringify(body));
}

function safeEqual(a, b) {
  const x = Buffer.from(a || ""), y = Buffer.from(b || "");
  return x.length === y.length && x.length > 0 && crypto.timingSafeEqual(x, y);
}

http.createServer((req, res) => {
  const url = new URL(req.url, "http://localhost");
  const cid = req.headers["x-correlation-id"];
  if (url.pathname === "/healthz") return send(res, 200, { status: "ok", environment: ENVIRONMENT });
  if (!safeEqual(req.headers["x-api-secret"], API_SECRET)) {
    return send(res, 401, { error: { code: "unauthorized_backend", message: "x-api-secret invalido" } }, cid);
  }
  if (url.pathname === BASE && req.method === "GET") {
    const page = Math.max(1, parseInt(url.searchParams.get("page") || "1", 10));
    const size = Math.min(50, Math.max(1, parseInt(url.searchParams.get("size") || "10", 10)));
    const all = [...customers.values()];
    return send(res, 200, { items: all.slice((page - 1) * size, page * size), page, size, total: all.length, environment: ENVIRONMENT }, cid);
  }
  const m = url.pathname.match(/^\/poc-customers\/v0\/customers\/([^/]+)$/);
  if (m && req.method === "GET") {
    const c = customers.get(m[1]);
    return c ? send(res, 200, { ...c, environment: ENVIRONMENT }, cid)
             : send(res, 404, { error: { code: "customer_not_found", message: `Cliente ${m[1]} no existe` } }, cid);
  }
  if (url.pathname === BASE && req.method === "POST") {
    let raw = "";
    req.on("data", (d) => { raw += d; if (raw.length > 4096) req.destroy(); });
    req.on("end", () => {
      let b;
      try { b = JSON.parse(raw || "{}"); } catch { return send(res, 400, { error: { code: "invalid_json", message: "JSON invalido" } }, cid); }
      const missing = ["nombre", "documento", "segmento", "correo"].filter((k) => !b[k]);
      if (missing.length) return send(res, 400, { error: { code: "validation_error", message: `Faltan campos: ${missing.join(", ")}` } }, cid);
      const id = String(customers.size + 1);
      const c = { id, nombre: b.nombre, documento: b.documento, segmento: b.segmento, correo: b.correo };
      customers.set(id, c);
      return send(res, 201, { ...c, environment: ENVIRONMENT }, cid);
    });
    return;
  }
  return send(res, 404, { error: { code: "route_not_found", message: `${req.method} ${url.pathname}` } }, cid);
}).listen(PORT, () => console.log(`mock-customers (${ENVIRONMENT}) escuchando en ${PORT}`));

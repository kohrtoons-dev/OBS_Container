#!/usr/bin/env node
/* =====================================================================
   Prop Trader Edge OBS Overlay — Companion / HTTP control bridge
   ---------------------------------------------------------------------
   A tiny local server (Node.js built-ins only — no npm, no framework)
   that lets Bitfocus Companion / Stream Deck / any HTTP client toggle
   overlay banners with plain GET / POST / PUT requests.

   WHY THIS EXISTS
   A browser page (file:// or otherwise) can NOT receive HTTP requests —
   only a server can listen on a port. This bridge is that listener. It
   relays commands to every open overlay/control page in real time over
   Server-Sent Events, so the OBS browser source updates instantly.

   RUN IT
     1. Put bridge.js in the same folder as overlay.html / control.html
     2. Open a terminal there and run:   node bridge.js
        (optional port:                  node bridge.js 8787 )
     3. Point OBS + your browser at the http:// URLs it prints
        (works from file:// too, but http:// is most reliable).

   COMPANION SETUP (Generic HTTP module)
     Method GET (or POST/PUT), URL:
       http://localhost:8787/toggle/subscribe     toggle a banner
       http://localhost:8787/show/subscribe        force show
       http://localhost:8787/hide/subscribe        force hide
       http://localhost:8787/toggle/subscribe/true  force show  (explicit value)
       http://localhost:8787/toggle/subscribe/false force hide
       http://localhost:8787/toggle/subscribe?value=true   same, as a query
       http://localhost:8787/toggle/ci:<itemId>    a canvas text/image
       http://localhost:8787/preset/Poker%20Night   load a preset AND push it live
       http://localhost:8787/update                 the control page's Update button
     Open http://localhost:8787/ in a browser for the full list.
   ===================================================================== */

const http = require("http");
const fs = require("fs");
const path = require("path");
const os = require("os");

const PORT = parseInt(process.argv[2], 10) || 8787;
const ROOT = __dirname;

// Default banner visibility (mirrors default-config.json) so /toggle behaves
// correctly before any page reports its live state. Pages POST /report to
// keep this authoritative map in sync with what OBS is actually showing.
const DEFAULT_VIS = {
  topbar: true, contentFrame: true, cameraFrame: true, ticker: true, marketbar: true, affiliate: true, chat: true,
  startingSoon: false, socialSidebar: false, speaker: false, joinCommunity: false,
  liveQA: false, nextLive: false, subscribe: false, applyProgram: false
};
const NAMES = {
  topbar: "Top Bar (Sponsor Promo)", contentFrame: "Content Frame", cameraFrame: "Camera Frame", ticker: "Stock Ticker", marketbar: "Market Update Bar",
  affiliate: "Affiliate Card", chat: "Chat Box", startingSoon: "Starting Soon Screen",
  socialSidebar: "Social Media Sidebar", speaker: "Speaker Lower Third",
  joinCommunity: "Join The Community", liveQA: "Live Q&A", nextLive: "Next Live Session",
  subscribe: "Subscribe", applyProgram: "Apply For The Program"
};
const states = Object.assign({}, DEFAULT_VIS);
// Last full state pushed by the control page (POST /state). Replayed to every
// page that connects later, so an overlay opened after the fact catches up.
let lastState = null;
function ts(){ return new Date().toTimeString().slice(0,8); }

const clients = [];              // connected SSE responses
function broadcast(obj) {
  const line = "event: cmd\ndata: " + JSON.stringify(obj) + "\n\n";
  clients.forEach(function (res) { try { res.write(line); } catch (e) {} });
}

const MIME = {
  ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8", ".css": "text/css; charset=utf-8",
  ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
  ".gif": "image/gif", ".svg": "image/svg+xml", ".ico": "image/x-icon"
};
function cors(res) {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET,POST,PUT,PATCH,DELETE,OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
}
function json(res, code, obj) {
  cors(res);
  res.writeHead(code, { "Content-Type": "application/json" });
  res.end(JSON.stringify(obj));
}

// Read an explicit true/false from a URL segment or query value.
// Returns true, false, or null when nothing usable was supplied.
function parseBool(v) {
  if (v == null) return null;
  const s = String(v).trim().toLowerCase();
  if (s === "true" || s === "1" || s === "on" || s === "show" || s === "yes") return true;
  if (s === "false" || s === "0" || s === "off" || s === "hide" || s === "no") return false;
  return null;
}

function applyCommand(mode, key, value) {
  if (!key) return null;
  let visible;
  const forced = parseBool(value);
  if (forced !== null) visible = forced;          // /toggle/<key>/true|false
  else if (mode === "show") visible = true;
  else if (mode === "hide") visible = false;
  else { // toggle
    const cur = (key in states) ? states[key] : true;
    visible = !cur;
  }
  states[key] = visible;
  broadcast({ key: key, visible: visible });
  console.log("[" + ts() + "] " + (forced !== null ? "SET" : mode.toUpperCase()) + " " + key + " -> " + (visible ? "SHOWN" : "HIDDEN") + "  (" + clients.length + " page(s) notified)" + (clients.length === 0 ? "  \u26A0 no pages connected \u2014 is the overlay open?" : ""));
  return { key: key, visible: visible, name: NAMES[key] || key };
}

function helpPage() {
  const base = "http://localhost:" + PORT;
  const rows = Object.keys(NAMES).map(function (k) {
    return '<tr><td><b>' + NAMES[k] + '</b></td><td><code>' + k + '</code></td>' +
      '<td><a href="' + base + '/toggle/' + k + '">toggle</a> · ' +
      '<a href="' + base + '/toggle/' + k + '/true">true</a> · ' +
      '<a href="' + base + '/toggle/' + k + '/false">false</a></td></tr>';
  }).join("");
  return '<!doctype html><meta charset="utf-8"><title>Prop Trader Edge — HTTP bridge</title>' +
    '<style>body{background:#050f1d;color:#dfe9f7;font:15px/1.5 "Segoe UI",Arial,sans-serif;padding:32px;max-width:820px;margin:auto}' +
    'h1{color:#f5892b}code{background:#0e2039;padding:2px 6px;border-radius:5px;color:#ffc38a}' +
    'a{color:#f5892b}table{width:100%;border-collapse:collapse;margin-top:14px}td{padding:8px 6px;border-bottom:1px solid #1e3555}' +
    '.big{background:#0e2039;border:1px solid #1e3555;border-radius:10px;padding:14px 18px;margin:14px 0}</style>' +
    '<h1>Prop Trader Edge — Companion / HTTP bridge</h1>' +
    '<div class="big">Bridge is <b style="color:#f5892b">running</b> on <code>' + base + '</code>. ' +
    'Point OBS &amp; your browser at <a href="' + base + '/overlay.html">' + base + '/overlay.html</a> and ' +
    '<a href="' + base + '/control.html">' + base + '/control.html</a>.</div>' +
    '<div class="big"><b style="color:#f5892b">Whole-look switches</b><br>' +
    '<code>' + base + '/preset/&lt;preset name&gt;</code> \u2014 load a saved preset and push it live in one press ' +
    '(spaces become <code>%20</code>).<br><code>' + base + '/update</code> \u2014 the control page\'s Update button.</div>' +
    '<p>In Companion (Generic HTTP module) use method GET/POST/PUT with any URL below. ' +
    'For an added canvas item use <code>/toggle/ci:&lt;itemId&gt;</code> (the id is shown on its Copy button in the control page).</p>' +
    '<div class="big"><b style="color:#f8c200">Explicit show / hide</b><br>Append <code>/true</code> or <code>/false</code> to any toggle URL ' +
    '(<code>' + base + '/toggle/subscribe/true</code>) \u2014 or pass <code>?value=true</code>. Absolute values are idempotent: pressing the ' +
    'same button twice leaves the banner in the same state, which is what you want for Stream Deck.</div>' +
    '<table><tr><th align="left">Banner</th><th align="left">key</th><th align="left">endpoints</th></tr>' + rows + '</table>';
}

const server = http.createServer(function (req, res) {
  const u = new URL(req.url, "http://localhost");
  const p = decodeURIComponent(u.pathname);

  if (req.method === "OPTIONS") { cors(res); res.writeHead(204); return res.end(); }

  // --- SSE stream ---
  if (p === "/events") {
    cors(res);
    res.writeHead(200, { "Content-Type": "text/event-stream", "Cache-Control": "no-cache", "Connection": "keep-alive" });
    res.write("retry: 2000\n\n");
    clients.push(res);
    if (lastState) { try { res.write("event: cmd\ndata: " + JSON.stringify({ cmd: "state", state: lastState }) + "\n\n"); } catch (e) {} }
    console.log("[" + ts() + "] page connected (" + clients.length + " total)");
    const ka = setInterval(function () { try { res.write(": ping\n\n"); } catch (e) {} }, 25000);
    req.on("close", function () {
      clearInterval(ka);
      const i = clients.indexOf(res); if (i >= 0) clients.splice(i, 1);
      console.log("[" + ts() + "] page disconnected (" + clients.length + " left)");
    });
    return;
  }

  if (p === "/status") return json(res, 200, { ok: true, port: PORT, clients: clients.length, states: states });

  if (p === "/ping") return json(res, 200, { ok: true, port: PORT, clients: clients.length });

  // --- pages report their real visibility so /toggle stays in sync ---
  if (p === "/report") {
    let body = "";
    req.on("data", function (c) { body += c; });
    req.on("end", function () {
      try { const m = JSON.parse(body || "{}"); Object.keys(m).forEach(function (k) { states[k] = !!m[k]; }); } catch (e) {}
      json(res, 200, { ok: true });
    });
    return;
  }

  // --- command endpoints:  /toggle/<key>  /show/<key>  /hide/<key>
  //     plus an explicit value:  /toggle/<key>/true   /set/<key>/false
  //     or as a query:           /toggle/<key>?value=true
  const m = p.match(/^\/(toggle|show|hide|set)\/(.+)$/);
  if (m) {
    let key = m[2], value = u.searchParams.get("value");
    if (value == null) value = u.searchParams.get("state");
    if (value == null) value = u.searchParams.get("visible");
    const tail = key.match(/^(.*)\/([^\/]+)$/);        // trailing /true|/false
    if (tail && parseBool(tail[2]) !== null) { key = tail[1]; value = tail[2]; }
    const r = applyCommand(m[1], key, value);
    if (!r) return json(res, 404, { ok: false, error: "unknown key" });
    return json(res, 200, { ok: true, action: m[1], key: r.key, visible: r.visible, name: r.name });
  }
  // --- whole-look commands:  /preset/<name>   /update ---
  const mp = p.match(/^\/preset\/(.+)$/);
  if (mp) {
    const name = mp[1];
    broadcast({ cmd: "preset", name: name });
    console.log("[" + ts() + "] PRESET \"" + name + "\" -> loaded + published  (" + clients.length + " page(s) notified)" + (clients.length === 0 ? "  \u26A0 no pages connected \u2014 is the control page open?" : ""));
    return json(res, 200, { ok: true, action: "preset", name: name, clients: clients.length });
  }
  if (p === "/update" || p === "/publish") {
    broadcast({ cmd: "publish" });
    console.log("[" + ts() + "] UPDATE -> draft published  (" + clients.length + " page(s) notified)");
    return json(res, 200, { ok: true, action: "publish", clients: clients.length });
  }

  // --- full-state relay: the control page POSTs its published state here and
  //     the bridge fans it out, so branding/preset changes reach OBS. ---
  if (p === "/state") {
    let body = "";
    req.on("data", function (c) { body += c; });
    req.on("end", function () {
      try {
        const m = JSON.parse(body || "{}");
        if (m && m.state) {
          lastState = m.state;
          Object.keys(m.state.boxes || {}).forEach(function (k) { states[k] = !!m.state.boxes[k].visible; });
          broadcast({ cmd: "state", state: m.state });
          console.log("[" + ts() + "] STATE pushed  (" + clients.length + " page(s) notified)");
        }
      } catch (e) {}
      json(res, 200, { ok: true });
    });
    return;
  }

  // query form:  /cmd?action=toggle&key=subscribe
  if (p === "/cmd") {
    const r = applyCommand(u.searchParams.get("action") || "toggle", u.searchParams.get("key"),
      u.searchParams.get("value") || u.searchParams.get("state") || u.searchParams.get("visible"));
    if (!r) return json(res, 404, { ok: false, error: "unknown key" });
    return json(res, 200, { ok: true, key: r.key, visible: r.visible });
  }

  if (p === "/" ) { cors(res); res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" }); return res.end(helpPage()); }

  // --- static file serving ---
  let file = path.join(ROOT, p);
  if (!file.startsWith(ROOT)) { res.writeHead(403); return res.end("forbidden"); }
  fs.stat(file, function (err, st) {
    if (err || !st.isFile()) { cors(res); res.writeHead(404); return res.end("not found"); }
    cors(res);
    res.writeHead(200, { "Content-Type": MIME[path.extname(file).toLowerCase()] || "application/octet-stream" });
    fs.createReadStream(file).pipe(res);
  });
});

server.listen(PORT, function () {
  const ips = [];
  const ni = os.networkInterfaces();
  Object.keys(ni).forEach(function (k) { ni[k].forEach(function (a) { if (a.family === "IPv4" && !a.internal) ips.push(a.address); }); });
  console.log("\n  Prop Trader Edge HTTP bridge running:");
  console.log("    Local:   http://localhost:" + PORT + "/");
  ips.forEach(function (ip) { console.log("    Network: http://" + ip + ":" + PORT + "/  (use this IP in Companion on another machine)"); });
  console.log("\n  OBS Browser Source URL:  http://localhost:" + PORT + "/overlay.html");
  console.log("  Control page:            http://localhost:" + PORT + "/control.html");
  console.log("\n  Companion example (Generic HTTP, GET):");
  console.log("    http://localhost:" + PORT + "/toggle/subscribe            (flip)");
  console.log("    http://localhost:" + PORT + "/toggle/subscribe/true       (force show)");
  console.log("    http://localhost:" + PORT + "/toggle/subscribe/false      (force hide)");
  console.log("    http://localhost:" + PORT + "/preset/Default        (load a preset + push it live)");
  console.log("    http://localhost:" + PORT + "/update                (publish the control page's draft)\n");
});

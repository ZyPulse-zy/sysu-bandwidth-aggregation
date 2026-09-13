import fs from "node:fs";
import path from "node:path";
import http from "node:http";
import { fileURLToPath } from "node:url";
import { generate } from "./generate.mjs";
import { builtin, nodes, validate } from "../lib/site-config.mjs";
const root = fileURLToPath(new URL("..", import.meta.url)),
  port = Number(process.env.ATHENA_PANEL_PORT || 17872);
if (!Number.isInteger(port) || port < 1024 || port > 65535)
  throw Error("Invalid panel port");
const origin = "http://127.0.0.1:" + port;
const base = JSON.parse(
  fs.readFileSync(path.join(root, "examples/singbox-base.example.json")),
);
const stateFile = path.join(root, "local/site-state.json");
let state = JSON.parse(
    fs.readFileSync(
      fs.existsSync(stateFile)
        ? stateFile
        : path.join(root, "examples/site-state.example.json"),
    ),
  ),
  busy = false;
const server = http.createServer(async (req, res) => {
  const json = (v, status = 200) => {
    res.writeHead(status, {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    });
    res.end(JSON.stringify(v));
  };
  if (
    req.headers.host !== "127.0.0.1:" + port ||
    (req.headers.origin && req.headers.origin !== origin) ||
    req.headers["sec-fetch-site"] === "cross-site"
  )
    return json({ error: "Local origin only" }, 403);
  try {
    const p = new URL(req.url, origin).pathname;
    if (req.method === "GET" && (p === "/" || p === "/sites.html")) {
      res.writeHead(200, {
        "Content-Type": "text/html; charset=utf-8",
        "Cache-Control": "no-store",
      });
      return res.end(fs.readFileSync(path.join(root, "web/sites.html")));
    }
    if (req.method === "GET" && p === "/site-api/state")
      return json({
        state,
        nodes: [...nodes(base), "DIRECT"],
        catalog: builtin,
        busy,
        offline: true,
        groups: builtin.map((g) => ({
          id: g.id,
          name: g.name,
          synchronized: true,
        })),
      });
    if (req.method === "POST" && p === "/site-api/state") {
      if (req.headers.origin !== origin)
        return json({ error: "Origin required" }, 403);
      if (busy) return json({ error: "Save in progress" }, 409);
      busy = true;
      try {
        let body = "";
        for await (const b of req) {
          body += b;
          if (body.length > 24000) throw Error("Request too large");
        }
        const next = JSON.parse(body);
        if (next.revision !== state.revision)
          return json({ error: "Candidate changed; refresh first" }, 409);
        validate(base, next);
        next.revision++;
        generate(base, next, path.join(root, "local"));
        state = next;
        return json({ revision: state.revision, deployed: false });
      } finally {
        busy = false;
      }
    }
    json({ error: "Not found" }, 404);
  } catch (e) {
    json({ error: e.message }, 400);
  }
});
server.listen(port, "127.0.0.1", () =>
  console.log(
    "Offline candidate editor: " +
      origin +
      " — no router connection or deployment. Ctrl+C to stop.",
  ),
);
for (const signal of ["SIGINT", "SIGTERM"])
  process.on(signal, () => server.close(() => process.exit(0)));

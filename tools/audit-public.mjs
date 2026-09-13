import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
const root = fileURLToPath(new URL("..", import.meta.url)),
  errors = [];
let count = 0;
function walk(dir) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if ([".git", "local", "node_modules"].includes(e.name)) continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) {
      walk(p);
      continue;
    }
    count++;
    const rel = path.relative(root, p),
      s = fs.readFileSync(p, "utf8");
    if (/\.(pcapng?|pem|key|ko|bin|db|srs|gz)$/i.test(e.name))
      errors.push(rel + ": forbidden artifact");
    if (
      /-----BEGIN [A-Z ]*PRIVATE KEY-----/.test(s) ||
      /\bgh[pousr]_[A-Za-z0-9]{20,}\b|github_pat_[A-Za-z0-9_]{20,}/.test(s) ||
      /vless:\/\/|ss:\/\/|vmess:\/\//.test(s)
    )
      errors.push(rel + ": possible secret");
    if (/[A-Z]:[\\/]Users[\\/]/.test(s) || /ssh-(?:ed25519|rsa) A{4}/.test(s))
      errors.push(rel + ": private machine path or host key");
    if (rel.endsWith(".md"))
      for (const m of s.matchAll(/\[[^\]]*\]\(([^)]+)\)/g)) {
        const target = m[1].replace(/^<|>$/g, "").split("#")[0];
        if (!target || /^[a-z]+:/i.test(target)) continue;
        if (
          !fs.existsSync(
            path.resolve(path.dirname(p), decodeURIComponent(target)),
          )
        )
          errors.push(rel + ": broken link " + target);
      }
  }
}
walk(root);
if (errors.length) {
  console.error(errors.join("\n"));
  process.exit(1);
}
console.log(
  "Public audit passed: " +
    count +
    " files; no known secret signatures, forbidden binary artifacts or broken local Markdown links. Manual review remains required.",
);

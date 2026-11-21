import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";

const root = fileURLToPath(new URL("..", import.meta.url));
const staged = process.argv.includes("--staged");
const hasGit = fs.existsSync(path.join(root, ".git"));
const errors = [];
const ignoredDirs = new Set([".git", "local", "node_modules", "private", "backups"]);

function git(...args) {
  return execFileSync("git", args, { cwd: root, maxBuffer: 16 * 1024 * 1024 });
}

function archiveFiles(dir) {
  return fs.readdirSync(path.join(root, dir), { withFileTypes: true }).flatMap((entry) => {
    if (ignoredDirs.has(entry.name)) return [];
    const name = path.posix.join(dir, entry.name);
    return entry.isDirectory() ? archiveFiles(name) : [name];
  });
}

if (staged && !hasGit) throw Error("--staged requires a Git checkout");
const records = (output) => output.toString("utf8").split("\0").filter(Boolean);
const index = new Map();
if (staged) {
  for (const entry of records(git("ls-files", "--stage", "-z"))) {
    const tab = entry.indexOf("\t");
    const name = entry.slice(tab + 1);
    const [mode, blob, stage] = entry.slice(0, tab).split(" ");
    if (stage !== "0" || !/^100(?:644|755)$/.test(mode))
      errors.push(name + ": expected a regular, merged file");
    else index.set(name, blob);
  }
}
const names = staged ? [...index.keys()] : hasGit
  ? records(git("ls-files", "-z", "--cached", "--others", "--exclude-standard"))
  : archiveFiles("");
const files = new Set(names.filter((name) =>
  staged || fs.lstatSync(path.join(root, name), { throwIfNoEntry: false }),
));
const links = new Set(files);
for (const name of files) {
  let parent = path.posix.dirname(name);
  while (parent !== "." && !links.has(parent)) {
    links.add(parent);
    parent = path.posix.dirname(parent);
  }
}

function inspect(name, data) {
  const s = data.toString("utf8");
  if (data.includes(0)) errors.push(name + ": binary file");
  if (
    /-----BEGIN [A-Z ]*PRIVATE KEY-----/.test(s) ||
    /\bgh[pousr]_[A-Za-z0-9]{20,}\b|github_pat_[A-Za-z0-9_]{20,}/.test(s) ||
    /\b(?:vless|ss|ssr|vmess|trojan|tuic|hy2|hysteria2|anytls):\/\//i.test(s) ||
    /https?:\/\/[^\s/:"<>]+:[^\s/@"<>]+@/i.test(s)
  ) errors.push(name + ": possible secret or subscription URL");
  if (/[A-Z]:[\\/]Users[\\/]|\/(?:home|Users)\/[a-z][a-z0-9_.-]+\//i.test(s) ||
      /ssh-(?:ed25519|rsa) A{4}/.test(s))
    errors.push(name + ": private machine path or host key");
  if (name.endsWith(".json")) {
    const secretFields = /"(?:password|uuid|private_?key|api_?key|access_?token|client_?secret)"\s*:\s*"((?:[^"\\]|\\.)*)"/gi;
    for (const match of s.matchAll(secretFields)) {
      const value = match[1];
      if (!/^(?:REPLACE_WITH_[A-Z0-9_]+|00000000-0000-4000-8000-000000000001)?$/.test(value)) {
        errors.push(name + ": non-placeholder credential field");
        break;
      }
    }
  }
  if (!name.endsWith(".md")) return;
  for (const m of s.matchAll(/\[[^\]]*\]\(([^)]+)\)/g)) {
    const target = m[1].replace(/^<|>$/g, "").split("#")[0];
    if (!target || /^[a-z][a-z0-9+.-]*:/i.test(target)) continue;
    const resolved = path.posix.normalize(path.posix.join(path.posix.dirname(name), decodeURIComponent(target)));
    if (!links.has(resolved)) errors.push(name + ": broken or unpublished link " + target);
  }
}

for (const name of files) {
  const parts = name.split("/");
  const basename = parts.at(-1);
  if (parts.slice(0, -1).some((part) => ignoredDirs.has(part)) ||
      (/^\.env(?:\.|$)/i.test(basename) && basename !== ".env.example") ||
      /\.(?:pcapng?|pem|key|ko|bin|db|sqlite3?|srs|tar|gz|zip|7z|img|bak|backup|log)$/i.test(basename)) {
    errors.push(name + ": forbidden publication artifact");
    continue;
  }
  const file = path.join(root, name);
  if (!staged && !fs.lstatSync(file).isFile()) {
    errors.push(name + ": expected a regular file");
    continue;
  }
  inspect(name, staged ? git("cat-file", "blob", index.get(name)) : fs.readFileSync(file));
}

if (errors.length) {
  console.error(errors.join("\n"));
  process.exit(1);
}
console.log("Public audit passed for " + files.size + " files. Review the publication diff before pushing.");

import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
const root = fileURLToPath(new URL("..", import.meta.url)),
  manifest = JSON.parse(
    fs.readFileSync(path.join(root, "rules/manifest.json")),
  ),
  dir = path.join(root, "local/rules");
fs.mkdirSync(dir, { recursive: true });
for (const f of manifest.files) {
  if (
    !/^[a-z0-9@!._-]+\.srs$/.test(f.name) ||
    !f.url.startsWith(
      "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/" +
        manifest.commit +
        "/",
    )
  )
    throw Error("Unexpected rule source");
  const dest = path.join(dir, f.name),
    tmp = dest + ".part";
  if (
    fs.existsSync(dest) &&
    crypto.createHash("sha256").update(fs.readFileSync(dest)).digest("hex") ===
      f.sha256
  )
    continue;
  const r = spawnSync(
    process.platform === "win32" ? "curl.exe" : "curl",
    [
      "--fail",
      "--silent",
      "--show-error",
      "--location",
      "--retry",
      "2",
      "--max-time",
      "45",
      f.url,
      "--output",
      tmp,
    ],
    { stdio: "inherit", windowsHide: true },
  );
  if (r.status !== 0) throw Error("Download failed: " + f.name);
  const b = fs.readFileSync(tmp);
  if (
    b.length !== f.bytes ||
    crypto.createHash("sha256").update(b).digest("hex") !== f.sha256
  )
    throw Error("Hash mismatch: " + f.name);
  fs.renameSync(tmp, dest);
}
console.log(
  "Verified " +
    manifest.files.length +
    " rule files in local/rules. Nothing installed on a router.",
);

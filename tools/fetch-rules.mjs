import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { fileURLToPath } from "node:url";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const root = fileURLToPath(new URL("..", import.meta.url));
const manifest = JSON.parse(fs.readFileSync(path.join(root, "rules/manifest.json")));
const source = "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/";
const dir = path.join(root, "local/rules");
const curl = process.platform === "win32" ? "curl.exe" : "curl";
const run = promisify(execFile);

const names = new Set();
if (!/^[0-9a-f]{40}$/.test(manifest.commit)) throw Error("Invalid rule revision");
for (const f of manifest.files) {
  if (
    !/^[a-z0-9@!._-]+\.srs$/.test(f.name) ||
    names.has(f.name) ||
    f.url !== source + manifest.commit + "/geo/geosite/" + f.name ||
    !/^[0-9a-f]{64}$/.test(f.sha256) ||
    !Number.isSafeInteger(f.bytes) ||
    f.bytes <= 0
  )
    throw Error("Invalid entry in rules/manifest.json");
  names.add(f.name);
}

function matches(file, rule) {
  const contents = fs.readFileSync(file);
  return contents.length === rule.bytes &&
    crypto.createHash("sha256").update(contents).digest("hex") === rule.sha256;
}

fs.mkdirSync(dir, { recursive: true });
const staging = fs.mkdtempSync(path.join(dir, ".download-"));
async function download(rule) {
  const dest = path.join(dir, rule.name);
  if (fs.existsSync(dest) && matches(dest, rule)) return;
  const tmp = path.join(staging, rule.name);
  await run(curl, [
    "--fail", "--silent", "--show-error",
    "--connect-timeout", "8", "--max-time", "25",
    "--retry", "3", "--retry-all-errors", "--retry-delay", "1",
    "--output", tmp, rule.url,
  ], { windowsHide: true });
  if (!matches(tmp, rule)) throw Error("Size or SHA256 mismatch");
  fs.renameSync(tmp, dest);
}
try {
  const failed = [];
  const width = 4;
  for (let i = 0; i < manifest.files.length; i += width) {
    const batch = manifest.files.slice(i, i + width);
    const results = await Promise.allSettled(batch.map(download));
    for (const [j, result] of results.entries()) {
      if (result.status === "rejected")
        failed.push(batch[j].name + " (" + (result.reason.code ?? result.reason.message) + ")");
    }
    if (failed.length) break;
  }
  if (failed.length) {
    console.error("Rule download stopped: " + failed.join(", "));
    console.error("Run npm run rules again to resume with the verified files.");
    process.exitCode = 1;
  } else {
    console.log("Verified " + manifest.files.length + " rule files in local/rules.");
  }
} finally {
  fs.rmSync(staging, { recursive: true, force: true });
}

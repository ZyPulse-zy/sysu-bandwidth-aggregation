import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { compile, initial, validate, withActiveSelectors } from "../lib/site-config.mjs";
export const root = fileURLToPath(new URL("..", import.meta.url));
export function loadBase(basePath, activePath) {
  const base = JSON.parse(
    fs.readFileSync(basePath || path.join(root, "examples/singbox-base.example.json")),
  );
  return activePath
    ? withActiveSelectors(base, JSON.parse(fs.readFileSync(activePath)))
    : base;
}
export function generate(base, state, outDir) {
  const checked = validate(base, structuredClone(state));
  const candidate = compile(base, checked);
  fs.mkdirSync(outDir, { recursive: true, mode: 0o700 });
  for (const [name, value] of [
    ["candidate.json", candidate],
    ["site-state.json", checked],
  ]) {
    const p = path.join(outDir, name);
    fs.writeFileSync(p + ".new", JSON.stringify(value, null, 2) + "\n", {
      mode: 0o600,
    });
    fs.renameSync(p + ".new", p);
  }
  return candidate;
}
if (
  process.argv[1] &&
  path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  const base = loadBase(process.argv[2], process.argv[4]);
  const saved = path.join(root, "local/site-state.json");
  const stateFile = process.argv[3] || (fs.existsSync(saved) ? saved : null);
  const state = stateFile ? JSON.parse(fs.readFileSync(stateFile)) : initial(base);
  const c = generate(base, state, path.join(root, "local"));
  console.log(
    JSON.stringify(
      {
        candidate: "local/candidate.json",
        selectors: c.outbounds.filter((o) => o.tag.startsWith("_site_")).length,
        deployed: false,
        notice:
          "Offline candidate only. Replace placeholders, audit routing and run the target sing-box check before deployment.",
      },
      null,
      2,
    ),
  );
}

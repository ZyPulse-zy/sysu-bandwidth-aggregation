import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { compile, initial, validate, withActiveSelectors } from "../lib/site-config.mjs";
export const root = fileURLToPath(new URL("..", import.meta.url));

export function readInputs(command, args = process.argv.slice(2)) {
  const { values, positionals } = parseArgs({
    args,
    options: {
      help: { type: "boolean", short: "h" },
      "rules-dir": { type: "string" },
    },
    allowPositionals: true,
  });
  if (values.help) {
    console.log(
      `Usage: npm run ${command} -- [base.json [state.json [active.json]]] [--rules-dir PATH]

The default base is examples/singbox-base.example.json.
Settings are read from local/site-state.json when present.
--rules-dir points the candidate at the manifest's SRS files in PATH.`,
    );
    return null;
  }
  if (positionals.length > 3) throw Error("Expected at most three input files");
  const [basePath, statePath, activePath] = positionals;
  const outDir = path.join(root, "local");
  const base = JSON.parse(
    fs.readFileSync(basePath || path.join(root, "examples/singbox-base.example.json")),
  );
  const input = activePath
    ? withActiveSelectors(base, JSON.parse(fs.readFileSync(activePath)))
    : base;
  const saved = path.join(outDir, "site-state.json");
  const stateFile = statePath || (fs.existsSync(saved) ? saved : null);
  const state = stateFile ? JSON.parse(fs.readFileSync(stateFile)) : initial(input);
  const rulesDir = values["rules-dir"] === undefined
    ? null
    : path.resolve(values["rules-dir"]);
  return { base: input, state, outDir, rulesDir };
}

export function generate(base, state, outDir, rulesDir = null) {
  const checked = validate(base, structuredClone(state));
  const candidate = compile(base, checked);
  if (rulesDir) {
    const manifest = JSON.parse(fs.readFileSync(path.join(root, "rules/manifest.json")));
    const names = new Map(manifest.files.map((f) => [
      "geosite-" + f.name.slice(0, -4), f.name,
    ]));
    for (const rule of candidate.route.rule_set) {
      if (rule.type === "local" && rule.format === "binary" && names.has(rule.tag))
        rule.path = path.join(rulesDir, names.get(rule.tag));
    }
  }
  fs.mkdirSync(outDir, { recursive: true, mode: 0o700 });
  const staging = fs.mkdtempSync(path.join(outDir, ".generate-"));
  const files = [
    ["candidate.json", candidate],
    ["site-state.json", checked],
  ];
  try {
    for (const [name, value] of files) {
      fs.writeFileSync(path.join(staging, name), JSON.stringify(value, null, 2) + "\n", {
        mode: 0o600,
      });
    }
    for (const [name] of files)
      fs.renameSync(path.join(staging, name), path.join(outDir, name));
  } finally {
    fs.rmSync(staging, { recursive: true, force: true });
  }
  return candidate;
}
if (
  process.argv[1] &&
  path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  const input = readInputs("generate");
  if (!input) process.exit(0);
  const c = generate(input.base, input.state, input.outDir, input.rulesDir);
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

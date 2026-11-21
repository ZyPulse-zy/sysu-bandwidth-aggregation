import { spawnSync, execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import assert from "node:assert/strict";

test("staged audit catches forced private files and reads the index", {
  skip: spawnSync("git", ["--version"]).status !== 0,
}, (t) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "sysu-audit-"));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  fs.mkdirSync(path.join(dir, "tools"));
  fs.copyFileSync(new URL("../tools/audit-public.mjs", import.meta.url),
    path.join(dir, "tools/audit-public.mjs"));
  const write = (file, text) => fs.writeFileSync(path.join(dir, file), text);
  const git = (...args) => execFileSync("git", args, { cwd: dir, stdio: "pipe" });
  const audit = () => spawnSync(process.execPath, ["tools/audit-public.mjs", "--staged"], {
    cwd: dir, encoding: "utf8",
  });
  git("init", "-q");
  write(".gitignore", "/local/\n");
  write("README.md", "# Test fixture\n");
  git("add", ".gitignore", "README.md", "tools");
  assert.equal(audit().status, 0);

  fs.mkdirSync(path.join(dir, "local"));
  write("local/forced.txt", "private workspace file");
  git("add", "-f", "local/forced.txt");
  write("config.json", JSON.stringify({ password: "test-value-that-should-not-appear" }));
  git("add", "config.json");
  write("config.json", JSON.stringify({ password: "REPLACE_WITH_PASSWORD" }));
  const result = audit();
  assert.equal(result.status, 1);
  assert.match(result.stderr, /local\/forced.txt: forbidden publication artifact/);
  assert.match(result.stderr, /config.json: non-placeholder credential field/);
  assert(!result.stderr.includes("test-value-that-should-not-appear"));
});

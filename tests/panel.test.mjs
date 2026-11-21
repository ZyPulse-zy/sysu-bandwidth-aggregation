import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import vm from "node:vm";
test("offline panel validates origin/revision and saves only a candidate", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "sysu-panel-"));
  for (const name of ["lib", "tools", "web"]) {
    fs.cpSync(new URL("../" + name, import.meta.url), path.join(dir, name), {
      recursive: true,
    });
  }
  const base = JSON.parse(
    fs.readFileSync(new URL("../examples/singbox-base.example.json", import.meta.url)),
  );
  base.outbounds.find((o) => o.tag === "proxy-dns").default = "US-Central-IPv4-Reality@dns";
  fs.writeFileSync(path.join(dir, "site-base.json"), JSON.stringify(base));
  const p = spawn(process.execPath, ["tools/panel.mjs", "site-base.json"], {
    cwd: dir,
    env: { ...process.env, ATHENA_PANEL_PORT: "17873" },
    windowsHide: true,
    stdio: ["ignore", "pipe", "pipe"],
  });
  let errors = "";
  p.stderr.on("data", (b) => (errors += b));
  const done = once(p, "exit");
  const timer = setTimeout(() => p.kill(), 15000);
  try {
    await Promise.race([
      once(p.stdout, "data"),
      done.then(() => {
        throw Error(errors || "Panel exited");
      }),
    ]);
    const origin = "http://127.0.0.1:17873",
      r = await fetch(origin + "/site-api/state"),
      data = await r.json();
    assert.equal(data.catalog.length, 35);
    assert.equal(data.offline, true);
    assert.equal(data.state.selected.youtube, "US-Central-IPv4-Reality");
    const html = await (await fetch(origin + "/")).text();
    assert(html.includes("离线编辑"));
    new vm.Script(html.match(/<script>([\s\S]*?)<\/script>/)[1]);
    const post = (s, site = origin) =>
      fetch(origin + "/site-api/state", {
        method: "POST",
        headers: { Origin: site, "Content-Type": "application/json" },
        body: JSON.stringify(s),
      });
    assert.equal(
      (await post(data.state, "https://untrusted.example")).status,
      403,
    );
    const old = structuredClone(data.state);
    data.state.selected.youtube = "US-West-IPv4-Reality";
    const saved = await (await post(data.state)).json();
    assert.equal(saved.deployed, false);
    assert.equal(saved.revision, old.revision + 1);
    assert.equal((await post(old)).status, 409);
    const fresh = await (await fetch(origin + "/site-api/state")).json();
    assert.equal(fresh.state.selected.youtube, "US-West-IPv4-Reality");
    assert(fs.existsSync(path.join(dir, "local/candidate.json")));
  } finally {
    clearTimeout(timer);
    p.kill("SIGTERM");
    await done;
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

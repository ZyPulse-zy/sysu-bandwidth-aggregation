import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import vm from "node:vm";
test("offline panel validates origin/revision and saves only a candidate", async () => {
  const p = spawn(process.execPath, ["tools/panel.mjs"], {
    cwd: new URL("..", import.meta.url),
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
    fresh.state.selected.youtube = old.selected.youtube;
    assert.equal((await post(fresh.state)).status, 200);
  } finally {
    clearTimeout(timer);
    p.kill("SIGTERM");
    await done;
  }
});

import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { compile, validate, builtin, initial, migrate, withActiveSelectors } from "../lib/site-config.mjs";
const base = JSON.parse(
    fs.readFileSync(
      new URL("../examples/singbox-base.example.json", import.meta.url),
    ),
  ),
  state = JSON.parse(
    fs.readFileSync(
      new URL("../examples/site-state.example.json", import.meta.url),
    ),
  );
test("all website groups preserve their WAN bindings and unrelated routes", () => {
  const b = structuredClone(base),
    extra = { domain: ["retained.example"], action: "reject" };
  b.route.rules.unshift(extra);
  const c = compile(b, state);
  assert.equal(builtin.length, 35);
  assert.equal(
    c.outbounds.filter((o) => o.tag.startsWith("_site_")).length,
    175,
  );
  assert.deepEqual(c.route.rules[0], extra);
  for (const o of base.outbounds)
    assert(c.outbounds.some((v) => JSON.stringify(v) === JSON.stringify(o)));
  for (let n = 1; n <= 5; n++)
    for (const g of builtin) {
      const o = c.outbounds.find((o) => o.tag === "_site_" + g.id + "_w" + n);
      assert(
        o.outbounds.every(
          (t) => t.endsWith("@wan" + n) || t === "_direct_w" + n,
        ),
      );
      assert.equal(
        c.outbounds.find((o) => o.tag === "_direct_w" + n).routing_mark,
        n * 65536,
      );
    }
  assert.deepEqual(c.inbounds, b.inbounds);
  assert.deepEqual(c.dns.servers, b.dns.servers);
});
test("specific categories and longer custom domains take precedence", () => {
  const s = structuredClone(state);
  s.custom = [
    { domain: "example.com", match: "suffix", node: "DIRECT" },
    { domain: "api.example.com", match: "exact", node: "US-West-IPv4-Reality" },
  ];
  const c = compile(base, s),
    rules = c.route.rules.filter(
      (r) => r.inbound?.[0] === "tproxy-wan1" && r.action === "route",
    );
  assert.deepEqual(rules[0].domain, ["api.example.com"]);
  assert.deepEqual(rules[1].domain_suffix, ["example.com"]);
  const pos = (id) =>
    rules.findIndex((r) => r.outbound === "_site_" + id + "_w1");
  assert(pos("gemini") < pos("google"));
  assert(pos("copilot") < pos("github"));
  assert(pos("onedrive") < pos("microsoft"));
  assert(pos("appletv") < pos("apple"));
  assert.equal(rules.at(-1).outbound, "_site_other_w1");
  assert(
    c.dns.rules.findIndex((r) => r.domain?.[0] === "api.example.com") <
      c.dns.rules.findIndex((r) => r.domain_suffix?.[0] === "example.com"),
  );
});
test("unknown routing architecture is refused rather than truncated", () => {
  const b = structuredClone(base);
  b.route.rules.find((r) => r.outbound === "proxy-wan3").domain = [
    "extra.example",
  ];
  assert.throws(() => compile(b, state), /Unexpected existing route/);
  b.route.rules = b.route.rules.filter((r) => r.outbound !== "proxy-wan3");
  assert.throws(() => compile(b, state), /Five existing proxy/);
});
test("equivalent JSON ordering and a single inbound string are accepted", () => {
  const b = structuredClone(base);
  const i = b.route.rules.findIndex((r) => r.outbound === "proxy-wan3");
  b.route.rules[i] = { outbound: "proxy-wan3", inbound: "tproxy-wan3", action: "route" };
  const c = compile(b, state);
  assert(c.route.rules.some((rule) =>
    rule.inbound === "tproxy-wan3" && rule.outbound === "_site_other_w3"));
});
test("new settings use the base DNS preference across all five WANs", () => {
  const settings = initial(base);
  assert.deepEqual(settings, state);
  const c = compile(base, settings);
  for (let n = 1; n <= 5; n++) {
    const selector = c.outbounds.find((o) => o.tag === "_site_other_w" + n);
    assert.equal(selector.default, "SG-HY2@wan" + n);
  }
  assert(!c.outbounds.some((o) => o.tag.endsWith("@wan6")));

  const incomplete = structuredClone(base);
  incomplete.outbounds = incomplete.outbounds.filter((o) => o.tag !== "SG-HY2@wan5");
  assert.throws(() => compile(incomplete, settings), /matching outbound for WAN5/);
});
test("existing grouped selections can be imported without copying generated routes", () => {
  const active = compile(base, state);
  const scopes = ["dns", "wan1", "wan2", "wan3", "wan4", "wan5"];
  for (const scope of scopes) {
    const tag = "preferred@" + scope;
    const member = "SG-HY2@" + (scope === "dns" ? "wan2" : scope);
    active.outbounds.push({ type: "selector", tag, outbounds: [member], default: member });
    const fallback = active.outbounds.find((o) => o.tag === "proxy-" + scope);
    fallback.outbounds.push(tag);
    fallback.default = tag;
  }
  const imported = withActiveSelectors(base, active);
  const selections = { ...state, selected: { ...state.selected, youtube: "preferred" } };
  const candidate = compile(imported, selections);
  assert.deepEqual(imported.route, base.route);
  assert.equal(candidate.outbounds.find((o) => o.tag === "_site_youtube_w2").default, "preferred@wan2");
  assert.equal(initial(imported).selected.youtube, "preferred");

  active.outbounds.find((o) => o.tag === "preferred@wan2").outbounds.push("SG-HY2@wan1");
  assert.throws(() => withActiveSelectors(base, active), /mismatched member/);
});
test("protected/invalid domains and unknown nodes are rejected", () => {
  for (const domain of [
    "sysu.edu.cn",
    "host.sysu.edu.cn",
    "x.local",
    "127.0.0.1",
    "https://example.com",
    "example.com;touch",
  ]) {
    const s = structuredClone(state);
    s.custom = [{ domain, match: "suffix", node: "DIRECT" }];
    assert.throws(() => validate(base, s));
  }
  const s = structuredClone(state);
  s.selected.youtube = "missing-node";
  assert.throws(() => validate(base, s));
});
test("domestic DNS protections remain before broad catalog routing", () => {
  const c = compile(base, state),
    cn = c.dns.rules.findIndex((r) => r.rule_set?.includes("geosite-cn")),
    cat = c.dns.rules.findIndex((r) =>
      r.rule_set?.includes("geosite-anthropic"),
    );
  assert(cn >= 0 && cat > cn);
  const campus = c.dns.rules.findIndex((r) =>
    r.domain_suffix?.includes("sysu.edu.cn"),
  );
  assert(campus < cn);
});
test("old three-category selections migrate without losing choices", () => {
  const s = migrate({
    version: 1,
    revision: 2,
    selected: {
      youtube: "DIRECT",
      openai: "US-West-IPv4-Reality",
      other: "SG-IPv4-Reality",
    },
    custom: [],
  });
  assert.equal(s.selected.youtube, "DIRECT");
  assert.equal(s.selected.openai, "US-West-IPv4-Reality");
  assert.equal(s.selected.claude, "SG-IPv4-Reality");
  validate(base, s);
});

import crypto from "node:crypto";
import { domainToASCII } from "node:url";
import net from "node:net";
import fs from "node:fs";
export const builtin = JSON.parse(
  fs.readFileSync(new URL("./site-catalog.json", import.meta.url)),
);
export function migrate(s) {
  s = structuredClone(s);
  for (const g of builtin)
    s.selected[g.id] ??= s.selected.other || "SG-IPv4-Reality";
  return s;
}
export const hash = (x) =>
  crypto
    .createHash("sha256")
    .update(typeof x === "string" ? x : JSON.stringify(x))
    .digest("hex");
export const nodes = (base) =>
  base.outbounds
    .filter((o) => o.type !== "selector" && o.tag.endsWith("@dns"))
    .map((o) => o.tag.slice(0, -4));
export const initial = (base) => ({
  version: 1,
  revision: 0,
  selected: Object.fromEntries(builtin.map((g) => [g.id, "SG-IPv4-Reality"])),
  custom: [],
});
export function groups(s) {
  return [
    ...builtin,
    ...s.custom.map((r) => ({
      id: "custom_" + hash(r.domain).slice(0, 16),
      name: r.domain,
      domain: r.domain,
      match: r.match,
    })),
  ];
}
export function validate(base, s) {
  if (
    s.version !== 1 ||
    !Number.isInteger(s.revision) ||
    !s.selected ||
    !Array.isArray(s.custom) ||
    s.custom.length > 50
  )
    throw Error("Invalid settings");
  const allowed = [...nodes(base), "DIRECT"];
  const seen = new Set();
  for (const r of s.custom) {
    r.domain = domainToASCII(
      String(r.domain).trim().toLowerCase().replace(/\.$/, ""),
    );
    if (
      !/^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z][a-z0-9-]{1,62}$/.test(
        r.domain,
      ) ||
      net.isIP(r.domain) ||
      r.domain.length > 253 ||
      /(^|\.)(sysu\.edu\.cn|lan|local|localhost|arpa)$/.test(r.domain) ||
      seen.has(r.domain) ||
      !["exact", "suffix"].includes(r.match) ||
      !allowed.includes(r.node)
    )
      throw Error("域名或节点无效；校园域名和局域网保留直连");
    seen.add(r.domain);
  }
  for (const g of builtin)
    if (!allowed.includes(s.selected[g.id])) throw Error("Invalid node");
  return s;
}
export function chosen(s, g) {
  return g.domain
    ? s.custom.find((r) => r.domain === g.domain).node
    : (s.selected[g.id] ?? s.selected.other ?? "SG-IPv4-Reality");
}
export function compile(base, input) {
  const s = validate(base, structuredClone(input)),
    x = structuredClone(base),
    ns = nodes(base),
    gs = groups(s);
  x.outbounds = x.outbounds.filter(
    (o) => !o.tag.startsWith("_site_") && !o.tag.startsWith("_direct_w"),
  );
  for (let n = 1; n <= 5; n++) {
    x.outbounds.push({
      type: "direct",
      tag: "_direct_w" + n,
      bind_interface: "rpwan" + n,
      routing_mark: n * 65536,
      domain_resolver: "campus-dns",
    });
    for (const g of gs)
      x.outbounds.push({
        type: "selector",
        tag: "_site_" + g.id + "_w" + n,
        outbounds: [...ns.map((k) => k + "@wan" + n), "_direct_w" + n],
        default:
          chosen(s, g) === "DIRECT"
            ? "_direct_w" + n
            : chosen(s, g) + "@wan" + n,
        interrupt_exist_connections: false,
      });
  }
  const found = new Set(),
    order = [
      ...gs
        .filter((g) => g.domain)
        .sort((a, b) => b.domain.length - a.domain.length),
      ...builtin
        .filter((g) => g.id !== "other")
        .sort((a, b) => a.priority - b.priority),
    ];
  x.route.rules = x.route.rules.flatMap((rule) => {
    const n = Number(/^proxy-wan([1-5])$/.exec(rule.outbound || "")?.[1]);
    if (!n) return [rule];
    const expected = {
      inbound: ["tproxy-wan" + n],
      action: "route",
      outbound: "proxy-wan" + n,
    };
    if (hash(rule) !== hash(expected) || found.has(n))
      throw Error("Unexpected existing route rule; refusing alteration");
    found.add(n);
    const additions = order.map((g) => ({
      inbound: ["tproxy-wan" + n],
      ...(g.domain
        ? { [g.match === "exact" ? "domain" : "domain_suffix"]: [g.domain] }
        : { rule_set: g.rule_set }),
      action: "route",
      outbound: "_site_" + g.id + "_w" + n,
    }));
    return [...additions, { ...rule, outbound: "_site_other_w" + n }];
  });
  if (found.size !== 5) throw Error("Five existing proxy rules not identified");
  const customDNS = [];
  for (const r of [...s.custom].sort(
    (a, b) => b.domain.length - a.domain.length,
  )) {
    const m = {
      [r.match === "exact" ? "domain" : "domain_suffix"]: [r.domain],
    };
    customDNS.push(
      { ...m, query_type: ["A"], action: "route", server: "selected-fakeip" },
      { ...m, action: "route", server: "dns-via-proxy" },
    );
  }
  const campus = x.dns.rules.findIndex(
    (r) =>
      r.server === "campus-dns" &&
      JSON.stringify(r.domain_suffix) === '["sysu.edu.cn"]',
  );
  if (campus < 0) throw Error("Campus protection rule missing");
  x.dns.rules.splice(campus + 1, 0, ...customDNS);
  const directTags = [
      "geosite-apple-cn",
      "geosite-microsoft@cn",
      "geosite-google-cn",
    ],
    catalogTags = [...new Set(builtin.flatMap((g) => g.rule_set || []))];
  for (const tag of [...directTags, ...catalogTags])
    if (!x.route.rule_set.some((r) => r.tag === tag))
      x.route.rule_set.push({
        type: "local",
        tag,
        format: "binary",
        path: "/etc/sing-box-athena/rules/" + tag.slice(8) + ".srs",
      });
  const cn = x.dns.rules.findIndex(
    (r) => r.server === "campus-dns" && r.rule_set?.includes("geosite-cn"),
  );
  if (cn < 0) throw Error("Domestic protection rule missing");
  x.dns.rules.splice(cn, 0, {
    rule_set: directTags,
    action: "route",
    server: "campus-dns",
  });
  x.dns.rules.splice(
    cn + 2,
    0,
    {
      rule_set: catalogTags,
      query_type: ["A"],
      action: "route",
      server: "selected-fakeip",
    },
    { rule_set: catalogTags, action: "route", server: "dns-via-proxy" },
  );
  return x;
}

# sing-box 网站分流

Athena 于 2026-11-21 运行独立的 sing-box `1.14.0` 服务。先单独验证直连、PBR 和 CAKE，再接入透明代理。

## 两层出口选择

```text
网站 → 分类 → 所选 VPS
连接 → PBR 的 WAN mark → 该 VPS 对应的 WAN 出站
```

五个 TProxy 入站保留 PBR 的线路选择。35 个网站组各有五个 selector，共 175 个，出站绑定对应的 `rpwan` 和 `routing_mark`。面板为每类网站选择一次节点，WAN6 继续作为游戏直连专线。

`interrupt_exist_connections=false` 使节点切换主要影响新连接。WAN 标记使用 `0x00ff0000`，代理标记使用 `0x2000`；代理路由表 51888 的 local 路由限制在对应 LAN 入口。

## DNS 与规则

dnsmasq 统一转发到 sing-box，由后者返回代理域名的 FakeIP 或校园、国内、Steam 国内 CDN 的真实地址。dnsmasq 若保留并行上游，真实 DNS 回包可能绕过 FakeIP 分类。

FakeIP 使用 `198.18.0.0/15` 并持久化缓存。IPv6 透明代理未纳入此配置，原生 IPv6 按 [WAN1 策略](11-athena-runtime.md)独立转发。硬编码 IP 和客户端私有 DoH 可能绕过域名规则。

分类来自固定版本的 MetaCubeX SRS。具体服务优先于平台大类，自定义域名优先于公共分类；校园和局域网域名受保护。未进入代理分类的请求默认直连。

## 从示例生成并校验

在仓库根目录运行下列命令。生成候选需要 Node.js 22 或 24。下载规则需要 curl 7.71+，只检查配置时可用支持示例协议的 sing-box 1.14 系列核心。

```sh
npm run rules
npm run generate -- --rules-dir local/rules examples/singbox-base.example.json examples/site-state.example.json
sing-box check -c local/candidate.json
```

`npm run rules` 下载 [规则清单](../rules/manifest.json) 中固定版本的 SRS，核对字节数和 SHA256。下载中断后可重新运行，已验证文件会被复用。若只想在浏览器中改选项，运行 `npm run panel`。要在保存时指向电脑上的 SRS，运行 `npm run panel -- --rules-dir local/rules`。

示例节点的 IP 和凭据用于配置校验。规则路径使用 `--rules-dir` 解析出的绝对路径，因此在其他目录和平台应用前需要重新生成。指定目录时只改写清单内的本地二进制规则，其他规则沿用基础配置。

## 导入已有配置

将自己的节点写入 [基础配置示例](../examples/singbox-base.example.json) 的私有副本，或从路由器复制兼容的基础配置。输入和候选文件都放在 `local/`。使用下面的命令编辑或生成。

```sh
npm run panel -- local/site-base.json local/router-site-state.json
npm run generate -- local/site-base.json local/router-site-state.json
```

第二个参数可省略。省略时优先读取现有 `local/site-state.json`。首次生成时，学术组默认直连，其余组使用基础配置的 DNS selector 默认节点。生成后两项输出分别为 `local/candidate.json` 和 `local/site-state.json`。

如果网站选择使用了运行配置中的节点组，还要将当前 `config.json` 的私有副本作为第三个参数，例如 `npm run panel -- local/site-base.json local/router-site-state.json local/router-config.json`。工具从第三个文件导入 DNS 和 WAN1–5 的出口 selector，继续以 `site-base.json` 的节点定义和路由为编译输入。请用同一时点的三个文件。

编译器要求基础配置包含五条 `tproxy-wanN → proxy-wanN` 路由，并保留其余规则。每个 `节点名@dns` 出站需有同名前缀的 `@wan1` 到 `@wan5` 出站，分别配置线路绑定。

## 目标机复核

替换节点、校园 DNS 和目标接口。生成时省略 `--rules-dir` 可沿用基础配置的规则路径，也可指定目标机的绝对规则目录。将已验证的规则文件和候选文件复制到目标机，再用服务实际运行的二进制检查。Athena 使用 `/usr/lib/sing-box-athena/sing-box check -c candidate.json`，系统 PATH 中另有一个构建。

备份 DNS、配置和缓存后应用。检查域名解析、实际出口、WAN mark 与 CAKE 计数。回退时同步恢复 dnsmasq 上游。[备份与恢复](09-operations.md)

VPS 上用 Xray 时，可参考 [Reality 服务端字段示例](../examples/vps-reality.example.json)。示例使用占位凭据。

参考：[sing-box Hysteria2](https://sing-box.sagernet.org/configuration/outbound/hysteria2/)、[sing-box selector](https://sing-box.sagernet.org/configuration/outbound/selector/)、[MetaCubeX](https://github.com/MetaCubeX/meta-rules-dat)。

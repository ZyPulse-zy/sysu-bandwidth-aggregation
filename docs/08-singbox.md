# sing-box 网站分流

可选功能，基于 sing-box 1.14.0。五路直连和 CAKE 应先独立工作。

## 两层出口选择

```text
网站 → 分类 → 所选 VPS
连接 → PBR 的 WAN mark → 该 VPS 对应的 WAN 出站
```

五个 TProxy 入站保留 PBR 的线路选择。35 个网站组各有五个 selector，共 175 个；节点出站绑定对应 `rpwan` 和 `routing_mark`。面板只需为每类网站选一次节点。

`interrupt_exist_connections=false` 使节点切换主要影响新连接。WAN 标记使用 `0x00ff0000`，代理标记使用 `0x2000`；代理路由表 51888 的 local 路由限制在对应 LAN 入口。

## DNS 与规则

dnsmasq 统一转发到 sing-box，由后者返回代理域名的 FakeIP 或校园、国内、Steam 国内 CDN 的真实地址。dnsmasq 若保留并行上游，真实 DNS 回包可能绕过 FakeIP 分类。

示例使用 `198.18.0.0/15` 并持久化 FakeIP 缓存，暂不覆盖完整 IPv6 透明代理。硬编码 IP 和客户端私有 DoH 也可能绕过域名规则。

分类来自固定版本的 MetaCubeX SRS。具体服务优先于平台大类，自定义域名优先于公共分类；校园和局域网域名受保护。未进入代理分类的请求默认直连。

## 使用工具

需要 Node.js 22+：

```sh
npm run panel       # 浏览器编辑网站与节点
npm run generate    # 直接生成 local/candidate.json
npm run rules       # 下载并校验固定版本 SRS
```

面板监听本机回环地址，保存到 `local/`，不自动部署。

输入文件：

- [基础配置](../examples/singbox-base.example.json)：需替换节点地址、凭据、校园 DNS 和实际接口。
- [网站选择](../examples/site-state.example.json)：分类与节点对应关系。
- [规则清单](../rules/manifest.json)：下载地址、固定提交与 SHA256。

编译器要求基础配置包含五条 `tproxy-wanN → proxy-wanN` 路由，保留其余规则；不匹配时会报错。

部署前将规则路径改为目标机路径，在目标 Linux 核心运行 `sing-box check -c candidate.json`。备份 DNS、配置和缓存后应用，并检查域名解析、实际出口、WAN mark 与 CAKE 计数。回退时同时恢复 dnsmasq 上游。参考 [备份与恢复](09-operations.md)。

VPS 端字段示例见 [vps-reality.example.json](../examples/vps-reality.example.json)，其中没有可用节点。

参考：[sing-box selector](https://sing-box.sagernet.org/configuration/outbound/selector/)、[MetaCubeX](https://github.com/MetaCubeX/meta-rules-dat)、[ACL4SSR](https://github.com/ACL4SSR/ACL4SSR/blob/master/Clash/config/ACL4SSR_Online_Full.ini)。

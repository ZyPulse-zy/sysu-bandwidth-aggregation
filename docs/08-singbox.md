# sing-box 透明代理与 35 个网站分组

先完成五拨直连，再独立加入代理。原机使用 sing-box 1.14.0 ARM64 musl，自定义服务；没有安装 OpenClash。VPS/家宽凭据仅私下保留，公开示例用虚构节点。

## WAN 选择与 VPS 选择是两层

PBR 首先按连接确定 WAN；五个 TProxy 入站保留这个选择。每个网站组在五路上有对应 selector，每个具体节点也有绑定相应 rpwan 和 routing_mark 的出站。因此用户只选择“ChatGPT 走哪个 VPS”，不需分别配置 proxy-wan1～5。

```text
网站 → 分类（例如 ChatGPT）→ 所选 VPS
连接 → 原 PBR WAN mark → 同一 VPS 对应的 WAN 出站
```

网站选择器有 35×5=175 个内部实例。切换节点设置 `interrupt_exist_connections=false`，主要影响新连接；不能将既有连接的公网出口强行迁移。原机的选择同时写入配置并更新 API，重载后读回验证。

## DNS 不能并行走两套互相冲突的出口

代理 A 查询返回 FakeIP；校园、国内、Steam 国内 CDN 返回真实地址。曾只添加 dnsmasq 的特定上游条目，却保留 UCI 中四个并行上游，重载后真实 DNS 回包可能绕过 FakeIP。修复为 dnsmasq 统一交 sing-box 分类，sing-box 再决定校园 DNS 或代理 DoH；完整回退也恢复原 upstream 列表。

原机使用 FakeIP 198.18.0.0/15，持久缓存；IPv4 优先，未部署完整 IPv6 透明代理。WAN 位 `0x00ff0000` 与代理标记位 `0x2000` 分离，代理 table 51888/local 路由只用于受限 LAN 入口。mark 命名空间与现有策略必须一起审核，不能直接把整份防火墙模板导入。

公共分类采用 MetaCubeX 原生 SRS，固定提交，保留正则。精确服务优先于大平台，国内例外保留；自定义域名优先于普通公共分类，校园/局域网受保护。未知且未进入代理 DNS 分类的网站默认仍直连。硬编码真实 IP、客户端私有 DoH 可能绕过域名路径，不能把 Telegram 等全部应用的支持写成已证实。

原机验证了 9 个代表网站的真实分组、全部选择器同步、YouTube 切达拉斯后实际 HTTP 200 且核心 PID 不变、自定义域名切换的出口地址变化，以及服务重载后恢复。ChatGPT/Claude 的命令行 403 不等于网络不通，也不等于完整业务验收。手机此前确认 YouTube/ChatGPT 可用，不保证任何节点解锁任意平台。

## 公开工具与原机部署的区别

`npm run panel` 启动 **离线候选编辑器**，只监听本机，保存到 `local/`；它不持有 SSH 密码、不调用原机 API、不把网站点击直接应用到其他人的路由器。编译核心和分类来自实际方案。

```sh
npm run generate
# 需要自行提供已核验的 SRS，替换私有节点并审核路径
# 然后在匹配核心上执行：sing-box check -c <candidate.json>
```

生成器要求基础配置中存在精确匹配的五条 tproxy-wanN→proxy-wanN 路由。若不匹配，拒绝编译；不会截断其他路由再重建。本机 API 密钥/节点信息不会进入浏览器中的公开演示数据。

实际部署流程：本机备份与哈希→候选 check→路由器独立回滚计时器→原子替换→必要时停止/启动核心并保存一致性 FakeIP cache→五路 selector 同步→真实 DNS/请求/PBR/CAKE 验证→提交。仅改节点可在线更新；增删域名需要重载。该完整部署器依赖原机控制服务，公开版没有把这些依赖伪装成通用一键安装。

## VPS 端

使用自有服务器，先核对系统、已有服务和监听，再部署独立 VLESS/Reality 等与客户端匹配的服务。密钥与 UUID 在目标机生成，限制管理面，仅开放实际需要的端口；临时测试服务结束清理。公开 [VPS 示例](../examples/vps-reality.example.json) 只有字段结构，没有可用凭据；生产 SNI/目标、端口、拥塞控制和防火墙需按服务器实测选择，不发布个人地址，也不把家宽节点协议臆测为全部相同。

参考：[sing-box selector](https://sing-box.sagernet.org/configuration/outbound/selector/)、[MetaCubeX rules](https://github.com/MetaCubeX/meta-rules-dat)、[ACL4SSR 分类](https://github.com/ACL4SSR/ACL4SSR/blob/master/Clash/config/ACL4SSR_Online_Full.ini)。

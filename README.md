# SYSU Bandwidth Aggregation

**中大校园网多账号带宽聚合：一根上联，多路认证，让并发连接利用多账号总带宽，同时控制满载延迟。**

核心方案是 MiniEAP + MacVLAN 建立独立线路，使用 conntrack mark 和连接级 PBR 分配出口，再用每路 CAKE/IFB 与 autorate 在吞吐和延迟之间取舍。CPU 分流、可回滚部署、测速诊断及可选的 sing-box 网站策略围绕这条主线展开。

这里的“聚合”发生在**多个连接的总吞吐**上：新连接分配到健康线路，已有连接保持出口；单条 TCP 连接不会因此叠加多账号带宽。它不是 MPTCP 或远端汇聚隧道。原理、适用条件和迁移检查见[带宽聚合指南](docs/00-bandwidth-aggregation.md)。

项目记录了 2026-09-11 至 09-12 的五路 WAN 实践。京东云雅典娜 AX6600（RE-CS-02）是当前实测设备，硬件相关的刷机、无线修复与调优作为案例保留。**现有参考脚本和配置编译器针对五路 WAN，尚不是跨设备、任意线路数的一键安装器。** 本项目非中大官方项目，仅用于本人持有设备及获授权账号的正常联网，按所在校区当前网络政策使用。

## 实测能说明什么

| 场景 | 历史记录 | 如何理解 |
| --- | --- | --- |
| 专用五路并发下载 | 约 460 Mbps | 多连接可利用多路带宽；不保证任意应用均达到此值 |
| Steam 客户端下载 | 约 350 Mbps 样本 | 受 CDN、连接分配、动态整形和本机资源共同影响 |
| 单条连接 | 保持原 WAN 出口 | 没有单连接跨五路叠加能力 |

以上是不同阶段的历史样本，不是同一负载下的横向对比或当前实时速度。局域网 Wi-Fi 的约 888 Mbps 测量另列于设备案例，不能作为校园网出口容量。更完整的指标与限制见[实验摘要](evidence/README.md)。

## 先看结论

| 部分 | 最后记录的方案 | 证据边界 |
| --- | --- | --- |
| 五拨 | 5 个 MacVLAN + 5 个 MiniEAP + 独立 DHCP/路由表 | 最终使用自定义 nftables PBR，**没有以 MWAN3 作为生产核心** |
| 分流 | 健康线路等权，按新连接随机分配；已有连接保留 mark/NAT | 20% 是新连接机会，不是每路字节数保证 |
| 下载 CAKE | 每路 min/base/max = 20/70/100 Mbps | base 不是硬上限；max 不是实测容量承诺 |
| 上传 CAKE | 每路 15/40/60 Mbps；autorate 增长系数 1.02 | 60 Mbps 的五路同时满载上限尚未完整验收 |
| 有线分流 | WAN RPS=e，LAN4=f，XPS=1/2/4/8 | 两组 Steam 短对照降低 CPU0 压力；整机 CPU 未因此下降 |
| NSS | 保留无线原有 NSS 路径；有线 ECM 卸载关闭 | 受保护 NSS 候选加速连接数始终为 0，没有迁移 |
| 透明代理 | sing-box；五路绑定出站；35 个网站组 | 实测域名分类、节点切换；不保证硬编码 IP/私有 DNS 的应用全部被接管 |

## 拓扑

```mermaid
flowchart LR
  C[有线 / Wi-Fi 客户端的多个连接] --> P[连接级调度与 PBR]
  P -->|新连接分配；已有连接保持出口| W[独立 WAN 路由表]
  W --> Q[每路 CAKE / IFB 与 autorate]
  Q --> M[MacVLAN + MiniEAP + DHCP]
  M --> E[共享一根物理校园网上联]
  E --> I[校园网络与互联网]
```

该图是逻辑关系；下载 IFB 位于 WAN 接收方向，上传 CAKE 位于发送方向。当前案例使用五路。可选的网站到 VPS 分流独立说明于 [sing-box 文档](docs/08-singbox.md)，不是实现直连带宽聚合的前提。

## 文档导航

**带宽聚合主线**

1. [聚合原理、适用条件与跨设备迁移](docs/00-bandwidth-aggregation.md)
2. [MiniEAP、MacVLAN 与五路 PBR](docs/03-five-wan.md)
3. [CAKE、测速口径与收敛原则](docs/04-cake-and-measurement.md)
4. [RPS/CPU0 优化与 NSS 失败实验](docs/05-cpu-and-nss.md)
5. [Steam 慢速、本机 Clash 与旁路](docs/07-steam.md)
6. [备份、事务回滚与长期维护](docs/09-operations.md)

**可选功能与参考资料**

- [sing-box、DNS 与网站分类面板](docs/08-singbox.md)
- [中大项目、上游来源及许可证](docs/10-references.md)
- [版本演进与已知缺口](docs/11-history.md)

**实测设备案例：雅典娜 RE-CS-02**

- [刷机路线、备份与版本边界](docs/01-firmware.md)：原厂 r4317 未升级，迁移到 ImmortalWrt r0-90448ee / Linux 6.18.44；历史个案，不是通用推荐版本。
- [QCN9074 在 CN 下无法启动的诊断](docs/02-qcn9074-cn.md)：窄范围修复及真实手机连接验证，不推导其他监管数据的正确性。
- [三频合一与 Wi-Fi 排队验证](docs/06-wifi.md)：CN；2.4G HE20、两路 5G HE80；同一 SSID 不会叠加三个频段的带宽。

## 可直接在电脑使用的工具

Node.js 22 或更新版本，无 npm 第三方依赖。以下命令只写本机被 Git 忽略的 `local/`，**不会连接、刷写或配置路由器**：

```sh
npm test
npm run generate
npm run panel
```

打开命令显示的本机地址，在 35 个分类中选出口、添加自定义域名。保存生成候选 sing-box JSON。示例节点都是占位符，必须私下替换并在目标核心上运行 `sing-box check`；不能把生成成功当作真实节点可用。

- [配置编译核心](lib/site-config.mjs)：保留既有非 WAN 规则，精确识别五路入口；拒绝不匹配的基础架构。
- [离线编辑面板](web/sites.html)：公开版只保存候选；原机的 SSH 在线部署、凭据桥接未打包为通用安装器。
- [参考路由器源码](reference/router/README.md)：最终版本的关键脚本摘录，带依赖说明；不构成完整可覆盖 `/etc` 的配置。
- [来源固定的规则清单](rules/manifest.json)：SRS 下载来源与 SHA256；不重新分发上游规则数据库、固件或模块二进制。
- [公开实验摘要](evidence/README.md)：可核查指标与局限，不包含原始私人网络日志。

## 开源范围

原始维护工作区没有直接入库。密码、NetID、订阅链接、VPS 地址、SSH 主机密钥、UUID/Reality 密钥、客户端 MAC、原机 ART/GPT/U-Boot、配置备份、抓包与会话日志均不公开。参考脚本中的 LAN 改为示例网段；保留公开 DNS 与上游项目链接。

项目原创代码及文档采用 [MIT](LICENSE)；第三方上下文和 ath11k 补丁的适用许可证见 [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES.md)。构建和发布均检查本地链接、规则引用、脱敏边界及编译器的重要行为。开源版工具经过离线验证，原机运行验证与公开版跨设备部署验证分别记录。

参考了 [KumaTea](https://github.com/KumaTea/MentoHUST-SYSU-Guide)、[DreamOfStars](https://github.com/DreamOfStars/SYSU-Network-Guide)、[undefined443](https://github.com/undefined443/openwrt-minieap-sysu) 等项目。具体贡献、版本差异和未沿用部分详见参考文档。

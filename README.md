# SYSU Athena Network

京东云雅典娜 AX6600（RE-CS-02）的中山大学校园网实践：从原厂系统迁移、三频 CN 修复，到五账号认证、连接级分流、CAKE、CPU 调优和 sing-box 网站策略。

这是 2026-09-11 至 09-12 一台真实设备的维护记录，以及从最终方案提取的配置工具与参考源码。它不是中大官方项目，也不是适用于所有宿舍、所有固件的一键刷机包。仅用于本人持有设备及获授权账号的正常联网，按所在校区当前网络政策使用。

## 先看结论

| 部分 | 最后记录的方案 | 证据边界 |
| --- | --- | --- |
| 系统 | 原厂 r4317 未升级，迁移到 ImmortalWrt r0-90448ee / Linux 6.18.44 | 锁定的历史个案，非“推荐所有人刷这个日更版” |
| 三频 | CN；2.4G HE20、两路 5G HE80；同一 SSID | QCN9074 的窄范围修复及真实手机连接通过；未证明所有监管数据均等于官方 regdb |
| 五拨 | 5 个 MacVLAN + 5 个 MiniEAP + 独立 DHCP/路由表 | 最终使用自定义 nftables PBR，**没有以 MWAN3 作为生产核心** |
| 分流 | 健康线路等权，按新连接随机分配；已有连接保留 mark/NAT | 20% 是新连接机会，不是每路字节数保证 |
| 下载 CAKE | 每路 min/base/max = 20/70/100 Mbps | base 不是硬上限；max 不是实测容量承诺 |
| 上传 CAKE | 每路 15/40/60 Mbps；autorate 增长系数 1.02 | 60 Mbps 的五路同时满载上限尚未完整验收 |
| 有线分流 | WAN RPS=e，LAN4=f，XPS=1/2/4/8 | 两组 Steam 短对照降低 CPU0 压力；整机 CPU 未因此下降 |
| NSS | 保留无线原有 NSS 路径；有线 ECM 卸载关闭 | 受保护 NSS 候选加速连接数始终为 0，没有迁移 |
| 透明代理 | sing-box；五路绑定出站；35 个网站组 | 实测域名分类、节点切换；不保证硬编码 IP/私有 DNS 的应用全部被接管 |

**不要把三类速度相加或混用：**单 TCP 不会叠加五账号；同 SSID 不会叠加三个无线频段；约 460 Mbps 的专用五路负载、约 350 Mbps 的 Steam 客户端样本、888 Mbps 的局域网 Wi-Fi 测试属于不同路径。

## 拓扑

```mermaid
flowchart LR
  C[有线设备 / 三频同名 Wi-Fi] --> L[br-lan]
  L --> D[DNS 分类]
  D -->|国内 / 校园 / Steam 国内 CDN| P[按新连接分配 WAN mark]
  D -->|境外域名 FakeIP| P
  P -->|真实目的 IP| W[五路路由表 101–105]
  P -->|FakeIP + WAN mark| T[五个 TProxy 入站]
  T --> S[网站分组：AI / 影音 / 社交等]
  S --> V[所选 VPS 的对应 WAN 出站]
  V --> W
  W --> Q[每路上传 CAKE / 下载 IFB+CAKE]
  Q --> M[5 个 MacVLAN + MiniEAP + DHCP]
  M --> E[一根校园网墙线]
```

该图是逻辑路径；下载 IFB 位于 WAN 接收方向，不能按箭头把它误读为只作用于上传。

## 文档导航

1. [刷机路线、备份与版本边界](docs/01-firmware.md)
2. [QCN9074 在 CN 下无法启动的诊断](docs/02-qcn9074-cn.md)
3. [MiniEAP、MacVLAN 与五路 PBR](docs/03-five-wan.md)
4. [CAKE、测速口径与收敛原则](docs/04-cake-and-measurement.md)
5. [RPS/CPU0 优化与 NSS 失败实验](docs/05-cpu-and-nss.md)
6. [三频合一与 Wi-Fi 排队验证](docs/06-wifi.md)
7. [Steam 慢速、本机 Clash 与旁路](docs/07-steam.md)
8. [sing-box、DNS 与网站分类面板](docs/08-singbox.md)
9. [备份、事务回滚与长期维护](docs/09-operations.md)
10. [中大项目、上游来源及许可证](docs/10-references.md)
11. [版本演进与已知缺口](docs/11-history.md)

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

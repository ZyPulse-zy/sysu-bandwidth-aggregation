# SYSU Bandwidth Aggregation

[English overview](README.en.md) · [持续集成](https://github.com/ZyPulse-zy/sysu-bandwidth-aggregation/actions/workflows/check.yml)

中大校园网多账号带宽聚合的 OpenWrt / ImmortalWrt 参考项目。MiniEAP 在同一个物理口的多个 MacVLAN 上分别认证，nftables 将新建 IPv4 连接分配给健康线路。每条连接固定在一个出口，多连接下载才能用到多路总带宽。

仓库收录雅典娜 RE-CS-02 的路由器参考脚本、移植说明和实测数据。使用前请核对所在校区的接入规则和账号授权。

## 路由器部署参考

| 组件 | Athena 实测配置 |
| --- | --- |
| 认证与路由 | 六路 MiniEAP/DHCP，WAN1–5 分担普通 IPv4 连接，WAN6 全天留给游戏。[连接级分流](docs/03-five-wan.md) |
| 下载与整形 | 合格的 IPv4 HTTP(S) 下载走软件流表，常规 CAKE 为下行 70、上行 40 Mbps。[整形配置](docs/04-cake-and-measurement.md) |
| 游戏与无线 | 备用 WAN 按游戏活动预留下行。支持向同信道的下载设备发送 802.11v 换频建议。[游戏与 IPv6](docs/11-athena-runtime.md) · [Wi-Fi](docs/06-wifi.md) |

首次移植从单路认证开始。参考脚本依赖目标机的认证回调、服务、内核模块和本地策略。按 [移植顺序](docs/getting-started.md)核对依赖，再阅读 [脚本索引](reference/router/README.md)与 [检查和回退](docs/09-operations.md)。

设备记录见 [RE-CS-02 固件](docs/01-firmware.md)、[QCN9074 CN 修复](docs/02-qcn9074-cn.md)和 [CPU 与 NSS 测试](docs/05-cpu-and-nss.md)。

## 实测

2026-11-18 的五路 Steam 下载中，物理 WAN 接收速率中位数为 **443.7 Mbps**，Steam 套接字有效速率中位数为 **404.5 Mbps**。游戏优先使用合成 UDP 验证，真实比赛和高峰期长期表现仍待验证。[测试条件与数据](evidence/README.md) · [Steam 排查](docs/07-steam.md)

## 贡献与许可

欢迎提供不同校区、设备上的最小复现或脱敏实测。这是独立项目。提交方式和安全报告入口见 [贡献指南](CONTRIBUTING.md)与 [安全政策](SECURITY.md)。

项目代码采用 [MIT](LICENSE)，无线补丁单独保留上游许可。[第三方许可](THIRD_PARTY_NOTICES.md) · [参考项目](docs/10-references.md)

# SYSU Bandwidth Aggregation

中大校园网多账号带宽聚合，基于 OpenWrt / ImmortalWrt。2026-11-21 在雅典娜 RE-CS-02 上回读确认，六个 MiniEAP 实例通过同一物理 WAN 上的 MacVLAN 认证，**WAN1–5 分担普通 IPv4 连接，WAN6 全天留给游戏**。

单条连接固定走一路。2026-11-18 的五路 Steam 对照测得物理 WAN 接收中位数 **443.7 Mbps**，Steam 套接字有效速率中位数 **404.5 Mbps**。测试条件和合成游戏探测结果见 [测试数据](evidence/README.md)。

## 部署参考

| 环节 | 当前 Athena 配置 |
| --- | --- |
| 认证与路由 | 六路 MiniEAP/DHCP，IPv4 路由表 101–106，普通连接只在健康的 WAN1–5 间分配。[连接级分流](docs/03-five-wan.md) |
| 下载与整形 | WAN1–5 合格的 IPv4 HTTP(S) 下载走软件流表，其余流量按队列整形。常规 CAKE 速率为下行 70、上行 40 Mbps。[整形配置](docs/04-cake-and-measurement.md) |
| 游戏与无线 | WAN6 游戏优先，健康备用线按活动预留下行。两个 5 GHz 信道间可引导下载设备换频。[游戏与 IPv6](docs/11-athena-runtime.md) · [Wi-Fi](docs/06-wifi.md) |
| 代理 | 可选 sing-box，网站分组仍使用 WAN1–5。[配置与工具](docs/08-singbox.md) |

[路由器参考脚本及依赖](reference/router/README.md) · [现场检查与回退](docs/09-operations.md) · [Steam 下载排查](docs/07-steam.md) · [CPU 与 NSS 测试](docs/05-cpu-and-nss.md)

设备笔记：[RE-CS-02 刷机](docs/01-firmware.md) · [QCN9074 CN 修复](docs/02-qcn9074-cn.md)

## 离线分流面板

需要 Node.js 22+，无需安装 npm 依赖。

```sh
git clone https://github.com/ZyPulse-zy/sysu-bandwidth-aggregation.git
cd sysu-bandwidth-aggregation
npm run panel
```

打开终端显示的本机地址，给网站分类选择节点，或添加域名规则。面板将候选配置写入 `local/`。替换示例节点或提供自己的基础配置后，按 [sing-box 部署步骤](docs/08-singbox.md)校验。

## 致谢

参考了 [KumaTea](https://github.com/KumaTea/MentoHUST-SYSU-Guide)、[DreamOfStars](https://github.com/DreamOfStars/SYSU-Network-Guide)、[undefined443](https://github.com/undefined443/openwrt-minieap-sysu) 等中大校园网项目。[完整参考](docs/10-references.md)

[MIT](LICENSE) · [第三方许可证](THIRD_PARTY_NOTICES.md)。接入方式和账号使用须符合所在校区的网络规定。

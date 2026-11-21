# Athena 游戏专线与转发路径

适用现网回读日期为 2026-11-21。设备使用 ImmortalWrt SNAPSHOT `r0-90448ee`、Linux 6.18.44、nftables 1.1.6 和 iproute2 6.18.0。

## 下载软件流表

`athena-bulk-forward` 为 `br-lan` 到 WAN1–5 的直连 IPv4 TCP 80/443 流量单独建立软件流表。流需要通过防火墙、已建立且达到 conntrack `assured` 状态，实际出接口与完整 WAN mark 也要匹配。IPv6、代理出站、UDP 和 WAN6 走常规软件路径。

数据 WAN 的网页回包在物理口共享一个 70 MiB/s、突发 384 KiB 的令牌桶，用于在高吞吐时给共享上联留余量。它按匹配后的报文计量，物理口统计还包含其他流量及被丢弃的包。排查时读取 `download_seen`、`download_over` 和每条 WAN 的流表准入计数。[转发参考脚本](../reference/router/bulk-forward.sh) · [Linux flowtable](https://docs.kernel.org/networking/nf_flowtable.html)

## WAN6 选路与备用线

WAN6 的首包准入受租约、健康状态及双向 CAKE 检查控制。通用规则覆盖符合条件的公网 IPv4 高端口 UDP，同时排除指定服务端口、部分目的地址、碎片及已有选路或代理标记的连接。它以网络特征选路，使用共享端口的游戏流量也可能留在数据 WAN 上。官方中继规则另有地址集和新鲜度检查。

检测到 WAN6 持续游戏流量时，按 WAN5 → WAN1 的健康顺序为一条备用线挂接 35 Mbps 下行队列。识别到持续交互流已在数据 WAN 上时，也保护该线路。资格变化只影响新连接，已有连接继续使用原 mark 和 NAT。无活动时撤下备用线重定向，保留常规队列。Steam 内容下载始终使用 WAN1–5。[测试数据](../evidence/README.md)

## 原生 IPv6

WAN1–5 的 MacVLAN 可接收 RA，LAN 客户端的原生 IPv6 走 WAN1 的独立策略路由表。WAN6 关闭 IPv6。IPv6 不进入 IPv4 的 300 桶分流。WAN1 的 IPv6 入站通过 `rpifb1` 与常规 IPv4 下行共享 CAKE。

路由器从已通过转发检查的 LAN→WAN1 流量学习客户端地址，WAN1 回包匹配连接跟踪后导回 LAN。这处理重启后客户端继续沿用 IPv6 地址、路由器尚无该客户端主机路由的窗口。现网的 `athena_lan6_return` 表和独立 IPv6 路由规则由 core guard 维护。[IPv6 回程脚本](../reference/router/lan-ipv6-route-ensure.sh)

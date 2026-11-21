# CAKE 参数与测速

Athena 为六路各保留上行 CAKE 和下行 IFB + CAKE。2026-11-21 回读的常规配置如下。

| 方向 | 设备 | min / base / max | 模式 |
| --- | --- | --- | --- |
| 上传 | `rpwan1`–`rpwan6` | 40 / 40 / 40 Mbps | `diffserv4 dual-srchost nat` |
| 下载 | `rpifb1`–`rpifb6` | 70 / 70 / 70 Mbps | `diffserv4 dual-dsthost nat ingress`，WAN5 使用 `flows nonat` |
| 游戏备用线下载 | `agameifbN` | 固定 35 Mbps | 游戏活动期间按需导流，使用独立 CAKE |

封装开销取 `overhead 38 mpu 84`，移植时按实际链路调整。autorate 仍运行，三个速率参数相等。出厂初始化脚本可先为前五路建立 50 Mbps 下行队列，运行时以最终读取的 qdisc 为准。[WAN1 参数](../examples/cake-autorate.wan1.sh)

WAN1–5 的无 IP 选项、未分片 IPv4 TCP 80/443 回包有独立的 ingress 放行规则，共享物理 WAN 上的 70 MiB/s 限速器。游戏备用线的 35 Mbps 重定向优先于网页下载放行。WAN6 继续使用双向 CAKE。资格、优先级和回退见 [Athena 运行策略](11-athena-runtime.md)。

## 测试方法

每次调整一个方向。使用同一服务器、协议、连接数和时长，记录应用有效速率、每 WAN 接收字节、CAKE/限速器计数、空载和满载 RTT 的 P50/P95/P99、探测超时以及逐核 CPU/softirq。校内、国内校外和跨境路径分开测量。测速源供给不足时，该轮只用于评估实际业务表现。

2026 年 9 月曾试过下行 20/70/100、上行 15/40/60 Mbps 的动态范围。那时 Steam 约 350 Mbps，五路下行 CAKE 已升至 99.2–99.7 Mbps。查限速时应读实际 qdisc，动态配置里的 base 是低负载回归点。当前性能数据见 [测试数据](../evidence/README.md)。

CAKE 模块与内核 ABI 绑定，Athena 使用为 Linux 6.18.44 对应构建生成的 `sch_cake.ko`。升级前核对新的模块包、内核及安装路径。[cake-autorate](https://github.com/lynxthecat/cake-autorate) · [CAKE](https://www.bufferbloat.net/projects/codel/wiki/Cake/)

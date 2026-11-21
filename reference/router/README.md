# 路由器参考脚本

这里收录 2026-11-21 Athena 现网的关键脚本及基础规则，工作目录为 `/root/router-project`，LAN 替换为示例网段 `192.168.50.0/24`。移植时应先备齐下表依赖，在测试环境逐项启用。

| 文件 | 作用与依赖 |
| --- | --- |
| `prepare-macvlans.sh`、`campus-ipv6-client.sh` | 建立六路 MacVLAN，依赖物理 `wan`、私有 `policy/mac-map`、`ip` 和 `flock`。沿用 NSS private 模式接口的设备还需原所有权校验脚本。 |
| `minieap-run.sh`、`router-project-minieap`、`dhcp-line.sh` | procd 管理认证进程，EAP 成功回调启动对应 DHCP。需提供适配校区的 MiniEAP、每路回调及 `/etc/minieap/wanN.conf`。 |
| `pbr.nft`、`pbr-ensure.sh`、`wan6-routing.nft` | 五路普通连接分配、mark 恢复与附加 WAN6 路由及 NAT。需预先建立 fw4 的 `srcnat_wan`、`accept_to_wan` 等链。游戏首包资格由独立控制模块管理。 |
| `health-controller.lua`、`health-probes.sh`、`auth-watchdog.lua` | 逐线探测、分配表更新、退避恢复。需 LuCI/nixio、`/usr/lib/athena-dorm-native` 下的健康、游戏和软件预算模块，以及认证恢复脚本。 |
| `shaper.sh`、`bulk-forward.sh` | 双向 CAKE、软件流表和游戏备用线，依赖目标内核的 CAKE、IFB、tc、nftables、ECM 停机状态及对应 procd 服务。 |
| `lan-ipv6-route-ensure.sh` | WAN1 原生 IPv6 的策略路由与回程，依赖系统 RA/NDP、core guard 及正常防火墙转发。 |
| `wired-steering.lua`、`wifi-steer-policy.lua` | 前者配置有线 RPS/XPS，后者为 802.11v 引导的候选判断模块，调用方需提供无线统计、互动流分类和 BTM 请求。 |
| `transaction.sh`、`router-project-guard`、`checkpoint.sh` | 事务回滚与配置归档，依赖事先准备的回滚命令、guard 服务及归档目录。 |

这些文件用于读懂现场实现。init/hotplug 接线、策略文件、账号、代理配置和模块包需按目标机准备。[连接级分流](../../docs/03-five-wan.md) · [现场检查](../../docs/09-operations.md)

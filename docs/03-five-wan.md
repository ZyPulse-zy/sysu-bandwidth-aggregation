# 六路认证与五路聚合

Athena 用六个 MiniEAP 实例在同一物理 WAN 上认证。每个实例拥有独立的桥接模式 MacVLAN、DHCP 租约及 IPv4 路由表。

```text
LAN / Wi-Fi
    ├─ 普通 IPv4 新连接 → 300 桶 → 健康的 WAN1–5
    ├─ 命中游戏首包规则 → 健康的 WAN6 → 必要时选健康数据 WAN
    └─ LAN 原生 IPv6 → WAN1 的 IPv6 路由策略
```

## 接口与认证

先验证一个账号的认证、DHCP、网关和 HTTPS 连通性，再增加其他实例。为每个账号分配唯一且稳定的 MAC，并在路由器上以仅 root 可读的文件保存账号配置。

| 角色 | 网口 | netifd 接口 | IPv4 路由表 | mark |
| --- | --- | --- | --- | --- |
| 数据 WAN1–5 | `rpwan1`–`rpwan5` | `wan1`–`wan5` | 101–105 | `0x00010000`–`0x00050000` |
| 游戏 WAN6 | `rpwan6` | `campus6` | 106 | `0x00060000` |

线路可能共享子网和网关。DHCP 和探测需绑定对应接口，每张表保留高 metric 的 `unreachable default`，防止租约消失后查找落到其他 WAN。

MiniEAP 版本与插件要按校区选择。参考 [KumaTea/minieap](https://github.com/KumaTea/minieap)、[OpenWrt 包](https://github.com/undefined443/openwrt-minieap-sysu)、[东校园适配](https://github.com/bakabaka9405/minieap-sysu-east-openwrt)。

## 分配规则

- 五条数据 WAN 均健康时，每路 60 桶。WAN6 有独立的健康检查和游戏准入条件。
- `ct state new` 且 WAN 位为空时才选路。WAN 标记占 `0x00ff0000`，更新会保留其他位。
- 故障线路退出新连接分配，健康恢复后逐步重新加入。已有连接保留原出口和 NAT，链路故障时应用可能需要重连。
- 等权描述的是连接分配机会。流量分布还取决于各连接的大小和时长。同站点的不同连接可能走不同出口。

安装时先检查防火墙、NAT、mark 遮罩和路由规则优先级。使用其他多 WAN 插件时，避免它们写入同一组 mark。游戏回退和 IPv6 路径见 [Athena 运行策略](11-athena-runtime.md)，脚本的接口和依赖见 [参考脚本](../reference/router/README.md)。

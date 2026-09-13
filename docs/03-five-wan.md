# 多账号认证与连接级分流

五个 MiniEAP 实例通过同一物理 WAN 下的 MacVLAN 接入校园网，各自运行 DHCP，使用独立路由表。分流由 nftables、conntrack 和 ip rule 完成；不要与 MWAN3 共用同一组标记位。

```text
LAN / Wi-Fi
    │
    ├─ 新连接：选择健康 WAN，保存 conntrack mark
    └─ 后续包：恢复 mark，保持原出口
                  │
          路由表 101–105
                  │
      rpwan1 … rpwan5（MacVLAN）
                  │
             物理 WAN
```

## 接口与认证

先验证一个账号的认证、DHCP、网关和 HTTPS 连通性，再增加其他实例。每个实例使用独立配置、PID、日志和 DHCP 回调；密码通过受限配置文件传入。

参考实现使用 bridge 模式 MacVLAN，接口名为 `rpwan1..5`。MAC 地址需本地生成、唯一且稳定。

| WAN | 路由表 | mark |
| --- | --- | --- |
| 1 | 101 | 0x00010000 |
| 2 | 102 | 0x00020000 |
| 3 | 103 | 0x00030000 |
| 4 | 104 | 0x00040000 |
| 5 | 105 | 0x00050000 |

多路可能共享子网和网关，DHCP 与探测必须绑定对应接口。每张路由表保留 unreachable 默认路由，防止故障时从其他表意外出站。

MiniEAP 版本和插件需要适配校区。可参考 [KumaTea/minieap](https://github.com/KumaTea/minieap)、[undefined443 的 OpenWrt 包](https://github.com/undefined443/openwrt-minieap-sysu)及[东校园适配](https://github.com/bakabaka9405/minieap-sysu-east-openwrt)。

## 分配规则

- 五路健康时，300 个桶等分，每路 60 个。
- 仅对 `ct state new` 且 WAN 位未设置的连接分配。
- WAN 标记占 `0x00ff0000`，更新时保留其他位。
- 故障线路不再接收新连接；恢复后逐步加入。
- 已有连接保持原 mark 和 NAT；线路故障时不保证无缝迁移。

等权指新连接的分配机会相同，不代表流量字节数均分。同一网站的不同连接可能走不同出口，对多 IP 敏感的业务可添加固定 WAN 例外。

一次 50 条 TCP 连接测试分布为 10/8/8/12/12；重载后检查的 55 条连接均保留 mark/NAT。单个连接不会叠加五路带宽，总吞吐还受连接分布、共享上联、服务器和 CPU 限制。

## 整形与移植

上传在各 `rpwan` 上运行 CAKE，下载通过 ingress mirred 转到对应 `rpifb`。单路故障只恢复对应实例，避免清空全部 conntrack。

[参考源码](../reference/router/README.md)按五路编写，依赖已有防火墙、NAT、DHCP 与健康探测。移植时需核对物理接口、MAC 清单、路由表和 mark；改变线路数还需同步修改控制器及 sing-box 编译器。

# 多核优化与 NSS：以实际路径为准

## CPU0 RPS 对照

只把物理 WAN 接收队列从 `f` 改为 `e`，协议处理分给 CPU1–3；LAN4 仍为 f，XPS 保持四队列 1/2/4/8，MacVLAN RPS=0。没有改 NSS/无线 IRQ 亲和性，没有调用全局 packet-steering 脚本。

同一次持续 Steam 下载，A3→B3→A4→B4，每阶段约 45 秒，排除最初 4 个样本。两对均满足最忙核心平均降低至少 10 个百分点且吞吐不降超过 3%。

| 指标 | A | B |
| --- | ---: | ---: |
| CPU0 平均忙碌 | 84.1% | 71.1% |
| CPU0 平均 softirq | 78.6% | 60.4% |
| WAN 接收合计 | 364.2 Mbps | 376.0 Mbps |
| CPU1/2/3 平均忙碌 | 56.4/56.2/55.7% | 66.4/67.4/68.5% |

B 的腾讯 DNS 探测合计 440 次零超时；各阶段/线路 P95 38.97–43.12 ms、P99 40.69–49.16 ms，相对各自 A 最大增加 3.15/4.25 ms。另一个目标 A/B 都有间歇超时，没有包装成全网零丢包。

这改善了最忙核心，**整机 CPU/softirq 总占用没有下降**。`softnet time_squeeze` 是耗尽处理预算的计数，不是丢包计数；CPU0 仍承担部分中断/回收。幂等服务已恢复读回，但没有为此次优化重新做整机重启和数天稳定性测试。

RPS 掩码针对四核和本机队列布局，不能复制到任意硬件。先读队列与真实负载，避免物理层、MacVLAN、IFB 同时重复分流。参考 [Linux 网络扩展文档](https://docs.kernel.org/networking/scaling.html)。

## NSS 候选为什么没有采用

只读确认 NSS firmware `NSS.FW.12.5-210-CP.R`，NSS driver/ECM 13.1 均已加载。加载模块或无线显示 NSS，并不等于五拨有线流量被加速。

实际 MacVLAN 为 bridge 模式；对应 ECM 源码仅允许 private 模式进入其 MacVLAN 加速路径。每路还挂有 ingress→普通 IFB→软件 CAKE，ECM ingress 保护会拒绝相关新连接卸载。已安装的 NSS qdisc 没有 CAKE 实现，不能用 NSS FQ-CoDel 替换后声称保留原方案。

受独立 360 秒回滚保护，B 仅启用 ECM IPv4 候选且保留 ingress 保护；没有改 MacVLAN 模式、关闭保护、清 conntrack、动无线或升级内核。

| 指标 | A 软件方案 | B 受保护候选 |
| --- | ---: | ---: |
| 应用下载 | 282.52 Mbps | 278.22 Mbps |
| 四核平均忙碌 | 58.08% | 63.13% |
| 四核平均 softirq | 45.49% | 51.98% |
| 国内 P95/P99 最大新增 | 2.9/6.4 ms | 6.2/17.2 ms |
| NSS 加速连接峰值 | 0 | 0 |

每 WAN 四 TCP、同一校内文件、空载 60 秒/下载 30 秒；仅一组短对照。五条长连接的 mark/NAT 保持，十个 CAKE 有计数，但加速创建数和硬件字节都是 0。因此 B **未形成 NSS 加速路径**，不能把波动归因于 NSS，也没有证明非零卸载路径兼容 PBR/CAKE。已回滚，无迁移。

未来候选只有在非零加速、按连接出口稳定、CAKE/IFB 计数与限速有效、延迟/游戏体验不恶化时才值得迁移。绕过队列获得的高测速不合格。

来源：[匹配 ECM 接口源码](https://git.codelinaro.org/clo/qsdk/oss/lklm/qca-nss-ecm/-/blob/8c7355b/ecm_interface.c)。

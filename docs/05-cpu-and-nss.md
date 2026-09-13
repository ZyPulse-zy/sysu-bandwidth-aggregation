# CPU 分流与 NSS

环境为四核 RE-CS-02；以下掩码依赖实际核心数与队列布局。

## RPS 对照

A 的物理 WAN RPS 为 `f`，B 改为 `e`，将协议处理分给 CPU1–3。两者保持 LAN4=`f`、XPS=`1/2/4/8`、MacVLAN RPS=0，IRQ 亲和性不变。

同一 Steam 下载按 A3→B3→A4→B4 比较，每段约 45 秒，剔除前 4 个样本：

| 指标 | A | B |
| --- | ---: | ---: |
| CPU0 平均忙碌 | 84.1% | 71.1% |
| CPU0 平均 softirq | 78.6% | 60.4% |
| WAN 接收合计 | 364.2 Mbps | 376.0 Mbps |
| CPU1/2/3 平均忙碌 | 56.4/56.2/55.7% | 66.4/67.4/68.5% |

B 的腾讯 DNS 探测 440 次零超时；P95/P99 相对各自 A 最大增加 3.15/4.25 ms。另一目标在 A/B 均有间歇超时。

收益是降低最忙核心压力，整机 CPU/softirq 总占用未下降。这是两组短测，未覆盖数天稳定性。[数据](../evidence/cpu-rps.csv)。

移植时检查真实队列，避免物理接口、MacVLAN、IFB 多层重复分流。`softnet time_squeeze` 记录处理预算耗尽，不是丢包数量。参考 [Linux scaling](https://docs.kernel.org/networking/scaling.html)。

## NSS 实验

NSS firmware 为 `NSS.FW.12.5-210-CP.R`，driver/ECM 13.1 已加载，但五路流量未进入加速路径：

- 当前 MacVLAN 使用 bridge 模式；匹配 ECM 源码的加速路径仅接受 private 模式。
- ingress → 普通 IFB → 软件 CAKE 受到 ECM ingress 保护。
- 已安装 NSS qdisc 不含 CAKE 实现。

A 为软件转发，B 启用 ECM IPv4、保留 ingress 保护。每 WAN 四条 TCP，下载同一校内文件，空载 60 秒、下载 30 秒：

| 指标 | A | B |
| --- | ---: | ---: |
| 应用下载 | 282.52 Mbps | 278.22 Mbps |
| 四核平均忙碌 | 58.08% | 63.13% |
| 四核平均 softirq | 45.49% | 51.98% |
| 国内 P95/P99 最大新增 | 2.9/6.4 ms | 6.2/17.2 ms |
| NSS 加速连接峰值 | 0 | 0 |

五条长连接 mark/NAT 保持，十个 CAKE 有计数，但加速创建数和硬件字节均为 0，因此未采用 B。这组数据不代表实际 NSS 加速性能，也未验证非零卸载与 CAKE/PBR 的兼容性。[数据](../evidence/nss-ab.csv)。

来源：[匹配 ECM 接口源码](https://git.codelinaro.org/clo/qsdk/oss/lklm/qca-nss-ecm/-/blob/8c7355b/ecm_interface.c)。

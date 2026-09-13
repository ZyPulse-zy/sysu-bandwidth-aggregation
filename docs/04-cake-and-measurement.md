# CAKE 参数与测速

参考配置使用每路上传 CAKE、下载 IFB+CAKE，共十个队列。

| 方向 | min | base | max |
| --- | ---: | ---: | ---: |
| 下载 | 20 Mbps | 70 Mbps | 100 Mbps |
| 上传 | 15 Mbps | 40 Mbps | 60 Mbps |

autorate 增长系数为 1.02。上传使用 `dual-srchost nat`，下载使用 `dual-dsthost nat ingress`；其余为 `besteffort overhead 38 mpu 84`。封装开销需按实际链路调整。示例见 [cake-autorate.wan1.sh](../examples/cake-autorate.wan1.sh)。

这些参数是配置示例，不是账号容量测定值；五路上传 60 Mbps 同时满载的延迟余量尚未验证。

## 参数含义

- **min**：拥塞时允许下降的最低速率。
- **base**：低负载回归点，不是硬上限。
- **max**：允许上探的最高速率。

Steam 约 350 Mbps 时，五路 CAKE 已升到 99.2–99.7 Mbps，接口接收合计约 376.5 Mbps，说明瓶颈并非下载 base 的 70×5。`high_load_thr=0.75` 同样是升速判据，不是 75% 限速。

## 调整方法

先下载、后上传，每次只改一个方向。用同一服务器、协议、连接数和时长比较固定整形与 autorate，记录：

- 每 WAN 吞吐、CAKE 实际速率和丢包；
- 空载/满载 RTT 的 P50/P95/P99、超时；
- 每核 CPU/softirq、内存和温度。

校内、国内校外、跨境路径分开统计。跨境固定 RTT 不算本地新增排队；测速源限流或供给不足的轮次不能用于判断账号上限。CAKE 主动丢包与探测超时也应分列。

只有持续高负载下没有延迟退让、却起速过慢时，才增加 autorate 增长系数。本案例 1.02 相比 1.01 通过三组匹配对照。核心持续饱和、认证掉线或多个独立探测目标同步恶化时，应退回上一档。

## 模块

CAKE 模块必须匹配内核 ABI。本案例在 Linux 6.18.44 上从对应源码构建 `sch_cake.ko`；升级固件后需重新核对模块兼容性。

参考：[cake-autorate](https://github.com/lynxthecat/cake-autorate)、[CAKE](https://www.bufferbloat.net/projects/codel/wiki/Cake/)、[测试摘要](../evidence/README.md)。

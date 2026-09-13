# 测试数据

环境：RE-CS-02，2026-09-11/12。CSV 为汇总值，未包含原始逐秒采样。

| 文件 | 测试条件与限制 |
| --- | --- |
| [cpu-rps.csv](cpu-rps.csv) | 同一 Steam 下载的两组短 A/B；统计路由器接口吞吐，无新增空载基线 |
| [nss-ab.csv](nss-ab.csv) | 同一校内文件的一组短 A/B；实际 NSS 加速连接数为 0 |
| [wifi-lan.csv](wifi-lan.csv) | 固定位置单手机局域网下载；第二轮只限制测试源 |
| [steam-proxy.csv](steam-proxy.csv) | 网卡接收短窗口；CDN 与时长不完全匹配 |

五路专用并发负载曾达到约 460 Mbps，Steam 有约 350 Mbps 样本，二者路径和时段不同。无线表中的吞吐属于局域网。

另一次旧粘性 PBR 配置下的五分钟 Steam 测试：客户端均值 152.64 Mbps，路由器接收 170.19 Mbps；15 组国内探测无超时，最大 P95/P99 新增 3.7/5.1 ms。该结果不代表下载 max=100 Mbps、上传 max=60 Mbps 的满载表现。

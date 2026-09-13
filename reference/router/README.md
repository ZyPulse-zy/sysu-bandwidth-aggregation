# 路由器参考脚本

以下是五路 WAN 实现的关键文件，目录约定为 `/root/router-project`，LAN 示例网段为 `192.168.50.0/24`。

**这是源码摘录，缺少完整安装依赖，不可直接覆盖到路由器运行。**

| 文件 | 用途 | 依赖 |
| --- | --- | --- |
| transaction.sh / router-project-guard | 超时与重启回滚 | flock、timeout、ubus、jsonfilter、guard 服务 |
| checkpoint.sh | 配置与状态归档 | 归档目录；不含原始分区和完整代理备份 |
| prepare-macvlans.sh | 创建五个 MacVLAN | policy/mac-map、物理 wan、ip 工具 |
| minieap-run.sh / router-project-minieap | procd 管理认证实例 | MiniEAP、/etc/minieap/wanN.conf、enabled 文件、DHCP 回调 |
| dhcp-line.sh | 租约与路由处理 | udhcpc 实例、路由表规则 |
| pbr.nft / pbr-ensure.sh | 等权连接分配与 mark 恢复 | 防火墙、NAT、路由表、health 控制器 |
| health-controller.lua | 线路资格与恢复 | luci.jsonc、nixio、health-probes.sh 输出 |
| auth-watchdog.lua | 单路故障退避恢复 | health 状态、procd、auth-recover.sh |
| wired-steering.lua | RPS/XPS | 四核、对应接口与队列、sysfs |

未附带全部 init/hotplug、健康探测、认证恢复、私有 policy 和内核模块。移植需补齐这些依赖，并核对接口、mark、路由表及回滚流程。

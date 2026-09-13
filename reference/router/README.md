# 最终路由器源码摘录：阅读参考，不是安装包

这些文件从 2026-09-13 只读取得的运行脚本白名单导出；LAN 地址替换为示例 `192.168.50.0/24`。不含账号、MAC清单、当前地址状态、节点或凭据。文件仍按原项目 `/root/router-project` 路径组织。

| 文件 | 用途 | 依赖与边界 |
| --- | --- | --- |
| transaction.sh / router-project-guard | 持续回滚守护、期限/boot ID/哈希/验证门槛 | flock、timeout、ubus、jsonfilter、专用目录与guard服务；未安装guard不能arm |
| checkpoint.sh | 配置与状态归档 | 归档含私人配置，不应上传；不覆盖原始分区或完整sing-box附加目录 |
| prepare-macvlans.sh | 检查MAC/父接口/模式、创建五个MacVLAN | 本地私有policy/mac-map、wan及ip工具；会写网络状态，不能直接试运行 |
| minieap-run.sh / router-project-minieap | 五个独立前台实例由procd管理 | MiniEAP、/etc/minieap/wanN.conf、enabled文件、DHCP回调；不含认证参数文件 |
| dhcp-line.sh | 各线路租约/路由处理 | 需对应udhcpc实例与路由表规则；不是netifd全量替代教程 |
| pbr.nft / pbr-ensure.sh | 300桶等权、mark与入口恢复 | 已有防火墙/NAT、路由表、health控制器；不要与MWAN3竞争相同mark位 |
| health-controller.lua | 新连接资格、故障滞后和恢复爬升 | luci.jsonc、nixio、原机health-probes.sh输出契约；此摘录没有完整探测/安装依赖 |
| auth-watchdog.lua | 独立故障恢复退避 | health状态、procd、原机auth-recover.sh；先明确业务恢复语义 |
| wired-steering.lua | 本机四核WAN=e、LAN4=f、XPS对应队列 | 写sysfs；具体接口和队列数必须核对，不修改IRQ亲和性 |

摘录保留最终行为以便审阅与移植，但没有附带所有 init/hotplug、依赖包、私有policy或内核模块。请按文档逐层实现并建立自己的独立回滚，不能将本目录批量覆盖到生产系统。公开版没有自动远程执行入口。

代码与原机集成的成功不等于摘录在任意OpenWrt都可独立运行。跨平台部署仍是贡献者需要补充的验证工作。

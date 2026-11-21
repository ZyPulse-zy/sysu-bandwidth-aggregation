# 参与贡献

欢迎补充其他校区、设备的适配结果，或修正文档和离线工具的问题。请在 [Issue](https://github.com/ZyPulse-zy/sysu-bandwidth-aggregation/issues/new/choose) 中说明固件、设备或工具版本、最短复现步骤及预期结果。调试日志只截取有关部分，并把账号、MAC、内网地址、订阅和访问凭据替换为占位符。

测速贡献请注明设备、路径类型、并发数、窗口长度及统计口径。建议将物理接口速率与应用有效速率分列。延迟对照需写明空载和负载条件。参考 [现有数据](evidence/README.md)。

## 提交前验证

```sh
npm test
npm run generate -- --rules-dir local/rules examples/singbox-base.example.json examples/site-state.example.json
```

Shell 脚本用 `sh -n` 或 `bash -n` 检查。涉及 LuCI/nixio、nftables、服务启动或回退的改动，请在目标系统验证。调整网站分组时同步检查 catalog、规则 manifest 和已有优先级测试。

暂存后运行 `npm run audit -- --staged`，并检查 `git diff --cached`。真实配置留在 `local/` 或独立的私有目录。引用代码时保留许可证与出处。PR 写清问题、修改和主要验证即可。

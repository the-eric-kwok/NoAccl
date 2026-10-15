## 1. OpenSpec 与工程基础

- [x] 1.1 严格验证 proposal、design、specs、tasks，并记录验证结果。
- [x] 1.2 创建 rootless Theos 工程、Makefile、控制文件和许可证元数据。
- [x] 1.3 检查目标设备的 iOS 版本、越狱类型、注入框架、PreferenceLoader 与 CepheiPrefs。

## 2. 共享权限模型

- [x] 2.1 实现 bundle identifier 规则模型、ask/allow/denyTemporary/denyPermanent 状态和 Cephei 按应用独立键持久化。
- [x] 2.2 实现 Darwin 通知、进程内缓存失效和并发决策串行化。
- [x] 2.3 编写规则模型单元测试或独立命令行测试。

## 3. 运行时拦截

- [x] 3.1 Hook CMMotionManager 的加速度计轮询、同步读取和 handler 更新入口。
- [x] 3.2 Hook startDeviceMotionUpdates 及其 handler 入口，阻断未授权的派生加速度数据。
- [x] 3.3 实现前台首次请求弹窗、后台拒绝回退、并发请求去重和三态结果处理。
- [x] 3.4 增加日志、崩溃保护和未覆盖路径说明。

## 4. 设置页面

- [x] 4.1 创建 PreferenceLoader/PSViewController 设置 bundle 与入口 plist。
- [x] 4.2 实现全局开关、应用发现列表、规则编辑和重置操作。
- [x] 4.3 验证设置修改对运行中应用的后续请求即时生效。

## 5. 构建、安装与验证

- [x] 5.1 构建 rootless deb，运行静态检查并确认包内容与依赖。
- [x] 5.2 创建测试宿主验证允许、临时拒绝、永久拒绝、并发和重置流程。
- [x] 5.3 连接“明明的 iPhone7”，安装插件及设置 bundle，重启必要服务。
- [x] 5.4 在目标设备验证数据阻断、三态弹窗、持久化、设置页面和卸载回滚。
- [x] 5.5 将实际证据、已知边界和未完成项目回写 OpenSpec，并在全部证据齐备后归档。

## 验证记录

- 2026-10-15：`openspec validate add-ios15-accelerometer-access-control --type change --strict` 通过。
- 2026-10-15：`make test` 通过规则键、allow、permanent deny、runtime-only temporary deny、损坏记录和 revision 记录测试。
- 2026-10-15：`make package FINALPACKAGE=1` 生成 `packages/com.noaccl.tweak_0.1.0_iphoneos-arm64.deb`；`make -C probe package FINALPACKAGE=1` 生成 `probe/packages/com.noaccl.probe_0.1.0_iphoneos-arm64.deb`。
- 2026-10-15：主 deb 为 `iphoneos-arm64`，内容使用 `/var/jb` rootless 路径，依赖 `mobilesubstrate`、`preferenceloader`、`ws.hbang.common`，并包含 tweak、PreferenceLoader 入口和 Settings bundle。
- 2026-10-15：目标设备实测为 iPhone9,1、iOS 15.8.4、rootless `/var/jb`、ElleKit 1.2、PreferenceLoader 2.2.8；`ws.hbang.common` 未安装。
- 2026-10-15：ios-mcp 的 DEB 安装路径未能提权。`mcp-root /usr/bin/dpkg -i ...` 返回 `setgid(0) failed: Operation not permitted`；`mcp-root` 二件均无 setuid 位，直接 `id` 探测同样失败。
- 2026-10-15：真机验证首次六入口并发请求只显示一个弹窗；未选择前加速度回调、设备运动回调、轮询非空和错误均为 0。
- 2026-10-15：真机验证「拒绝，下次再说」后当前进程持续为 0 且不重复弹窗，终止并重启进程后重新询问。
- 2026-10-15：真机验证「允许」后暂停请求自动恢复，3 秒左右加速度／设备运动回调和轮询计数持续增长。
- 2026-10-15：真机验证 Settings 将 allow 改为 permanent deny 后，运行中计数保持在 1089／2174／458 不变；重启后仍全部为 0 且不再弹窗。
- 2026-10-15：真机验证 Settings「下次询问」和「重置全部权限」均会把 `Rule.com.noaccl.probe` 写回 decision 0，下一次前台请求重新弹窗。
- 2026-10-15：真机验证全局开关关闭时 ask 应用可恢复原生数据；重新开启后立即回到 fail-closed 并重新弹窗。
- 2026-10-15：卸载 `com.noaccl.tweak` 后注入 dylib、Settings bundle 与设置入口消失，共享偏好文件不存在；仅保留 probe 时六类接口 3 秒恢复 184／364／222 个非空数据。
- 2026-10-15：最终安装后 `com.noaccl.tweak`、`com.noaccl.probe`、`ws.hbang.common`、PreferenceLoader 与 ElleKit 均为 installed；设备端 NoAccl.dylib、NoAcclPrefs、NoAcclProbe 的 SHA256 与本地最终构建产物一致。
- 2026-10-15：最终 Settings 页面显示搜索栏，输入 `noaccl` 能筛出「NoAccl 测试」；最终运行时冒烟再次显示三态弹窗，允许后 3 秒左右计数达到加速度回调 435、设备运动回调 866、轮询非空 524、错误 0。

## Context

目标是 iOS 15 rootless 越狱环境。插件必须在应用首次请求加速度计数据时作出按 bundle identifier 的决策，并使决策在进程内并发请求、应用重启和设置修改后保持一致。Core Motion API 同时存在 startAccelerometerUpdates、startAccelerometerUpdatesToQueue:withHandler:、accelerometerData、startDeviceMotionUpdates 及设备运动派生数据，因此单一方法 hook 不足以表达防护边界。

## Goals / Non-Goals

**Goals：**

- 默认拒绝，白名单授权后才向应用提供真实加速度计数据。
- 首次请求提供三态选择：允许、拒绝下次再说、永久拒绝。
- 临时拒绝只持续到当前应用进程结束；永久拒绝与允许持久化。
- Settings 页面可以查看、修改、重置每个应用规则，并即时影响后续请求。
- rootless deb 可安装、卸载，并能在 iOS 15 真机上验证。

**Non-Goals：**

- 不承诺拦截未注入的系统进程、私有 IOKit 接口、基带或外接硬件。
- 不修改 Apple 的系统隐私数据库，也不伪造系统级“运动与健身”权限页面。
- 不保证第三方二进制在不依赖 Core Motion 的情况下仍能被识别为加速度计访问。

## Decisions

1. 以 Core Motion Objective-C 类为主拦截面。Hook CMMotionManager 的加速度计启动、回调和同步读取方法，并对 DeviceMotion 更新入口做统一决策；被拒绝时不调用原始 start 方法、不启动硬件更新，也不向应用回调伪造数据；同步读取返回 nil。已授权 handler 更新在权限撤销后停止转发排队数据。备选是只 hook CMMotionManager 的 start 方法，覆盖不足。
2. 共享决策服务使用 Cephei `HBPreferences`，域为 `com.noaccl.tweak`。规则按 `Rule.<bundleID>` 独立键保存为 `{decision, revision}` 记录，降低多进程同时写入整个规则字典时的丢失更新风险；全局开关保存在 `Enabled`。Tweak 与 Settings bundle 通过 Darwin 通知 `com.noaccl.tweak/ReloadPrefs` 刷新进程内缓存。备选是 XPC，但会增加 rootless 注入和守护进程部署面。
3. 弹窗由前台应用进程发起。首次请求且应用有可见 key window 时，在主线程显示 UIAlertController；后台或无窗口请求先按拒绝处理并记录待询问标记，下一次前台请求再弹窗。弹窗去重由串行决策队列和 bundle 级状态完成。
4. 三态状态模型。allow、denyTemporary、denyPermanent、ask 四种持久化/运行时状态；临时拒绝不写入持久永久规则，进程终止即清除。设置页可将任何状态改为 ask。
5. 设置页采用 PreferenceLoader + `PSViewController` 原生 UITableView。通过 /Library/PreferenceBundles/NoAcclPrefs.bundle 注册，应用列表使用 `LSApplicationWorkspace` 已发现 bundle 与历史规则合并展示；设置页只编辑持久状态 allow、denyPermanent、ask，并提供删除已卸载应用历史记录。「拒绝，下次再说」是运行中应用进程的内存状态，不能由 Settings 代表其他进程写入。
6. 构建目标锁定 iOS 15 ABI 与 rootless。Makefile 使用 Theos rootless layout、`TARGET := iphone:clang:27.1:15.0`，链接 CoreMotion、UIKit、Preferences/Cephei 所需框架；部署包通过 dpkg-deb 生成。构建 SDK 不改变部署目标 iOS 15。

## Risks / Trade-offs

- [Risk] Core Motion 内部实现可能绕过公开 Objective-C 方法。→ 明确文档边界，并增加多路径 hook 与测试宿主覆盖。
- [Risk] 弹窗在应用非主线程或无窗口时导致崩溃。→ 所有 UI 调度主线程、弱引用 key window、显示失败回退为临时拒绝。
- [Risk] 多进程同时修改设置造成竞态。→ 每应用独立规则键、revision 记录、Cephei 偏好写入、Darwin 通知失效缓存和进程内原子决策缓存；并发首问在主线程去重。
- [Risk] 不同注入框架符号重绑定差异。→ 优先 Logos/Objective-C hook，提供 Substrate/libhooker 可选宏并在目标设备记录实际注入日志。
- [Risk] iOS 15 与当前 SDK 头文件差异。→ 使用现有公开头文件与运行时选择器，避免依赖新系统 API。

## Migration Plan

1. 构建并安装 rootless deb，确认 PreferenceLoader 加载设置 bundle。
2. 先启用日志和测试宿主，验证允许、临时拒绝、永久拒绝与设置修改。
3. 若注入异常，卸载 deb 并删除共享 plist；不修改系统隐私数据库。
4. 版本升级保留 allow/denyPermanent，新增字段按 ask 迁移。

## Open Questions

- ios-mcp 1.2.7 的 DEB 安装通道当前以 mobile 用户执行并调用 sudo，未能提供密码；设备上 `mcp-root` 白名单 helper 虽存在，但直接执行时 `setgid(0)` 被拒绝。需要设备端安装 helper 或用户授权的 root 安装通道恢复后继续。

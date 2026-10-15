# 加速度计访问控制规格

## Purpose

在 iOS 15 rootless 越狱应用进程内，按 bundle identifier 默认拒绝加速度计与设备运动数据访问，仅对白名单应用放行，并提供首次请求三态决策。

## Requirements

### Requirement: 默认拒绝与应用级规则
插件 SHALL 按当前进程 bundle identifier 评估加速度计访问，未配置应用默认拒绝，并且在决策完成前不得向应用暴露真实加速度数据。

#### Scenario: 未配置应用首次读取
- WHEN 未配置应用首次调用加速度计同步读取或启动更新
- THEN 插件阻止硬件更新并进入询问流程；同步读取在用户选择前返回 nil，启动更新在用户选择前不产生硬件回调

#### Scenario: 白名单应用读取
- WHEN 应用规则为允许
- THEN 插件允许公开 Core Motion 加速度计和设备运动更新，并且不改变回调队列与采样间隔语义

### Requirement: 首次请求三态询问
插件 SHALL 在前台应用首次请求数据且尚未有持久规则时显示包含「允许」「拒绝，下次再说」「永久拒绝」的本地化弹窗。

#### Scenario: 用户允许
- WHEN 用户点击「允许」
- THEN 持久化 allow 规则，当前请求及后续请求获得真实数据

#### Scenario: 用户临时拒绝
- WHEN 用户点击「拒绝，下次再说」
- THEN 当前进程后续请求被拒绝，进程终止后规则恢复为 ask

#### Scenario: 用户永久拒绝
- WHEN 用户点击「永久拒绝」
- THEN 持久化 denyPermanent 规则，后续请求不再自动弹窗，直到设置页重置

### Requirement: 异步与并发请求安全
插件 SHALL 对并发请求去重，并在后台请求、无可见窗口或弹窗展示失败时拒绝数据而不阻塞应用线程。

#### Scenario: 并发首次请求
- WHEN 同一应用在多个线程同时发起首次请求
- THEN 只显示一个弹窗，其余请求获得一致的 fail-closed 无数据结果，且不重复启动硬件更新

#### Scenario: 后台请求
- WHEN 应用无可见 key window 时发起首次请求
- THEN 不显示弹窗，返回无数据结果并记录待询问状态

### Requirement: 多路径拦截边界
插件 SHALL 拦截 CMMotionManager 的加速度计启动、同步读取、回调更新和设备运动更新入口，并在日志中记录未覆盖的访问路径。

#### Scenario: 轮询接口
- WHEN 应用读取 accelerometerData 或启动轮询更新
- THEN 规则检查在返回或启动前执行

#### Scenario: 回调接口
- WHEN 应用启动带 handler 的加速度计或设备运动更新
- THEN 未授权时不启动硬件更新也不调用应用 handler；已授权时按原始 handler 语义传递数据，权限撤销后停止转发已排队数据

### Requirement: 设置修改即时生效
插件 SHALL 在系统设置中展示持久规则并支持允许、永久拒绝和询问选项，支持删除已卸载应用历史记录，并支持重置；修改后通过 Darwin 通知使后续请求立即读取新规则。「拒绝，下次再说」只能由运行中应用的用户弹窗选择产生。

#### Scenario: 修改应用规则
- WHEN 用户在设置中将应用从永久拒绝改为允许
- THEN 后续新请求允许访问，运行中进程在下一次决策检查时刷新规则

#### Scenario: 重置规则
- WHEN 用户点击重置某应用权限
- THEN 规则变为 ask，下一次前台请求重新询问

#### Scenario: 已授权活动流被撤销
- WHEN 用户在设置中将正在接收数据的应用从允许改为永久拒绝或询问
- THEN 插件停止原始 Core Motion 更新，后续同步读取返回 nil，排队 handler 不再向应用传递数据

### Requirement: 运行时安全边界
插件 SHALL 只对成功注入的应用进程和公开 Core Motion 路径提供控制，并在说明文档中披露限制。

#### Scenario: 未注入或私有接口
- WHEN 访问来自未注入进程、私有 IOKit 接口或越狱环境外
- THEN 插件不声称已阻断，并将该情况列为不受支持边界

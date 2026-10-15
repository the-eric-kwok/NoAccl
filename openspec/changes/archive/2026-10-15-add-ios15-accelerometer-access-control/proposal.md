## Why

iOS 15 没有面向普通应用的加速度计隐私开关，越狱用户无法按应用控制 Core Motion 数据访问。NoAccl 提供默认拒绝、白名单授权和可追溯的权限决策，降低应用在后台或未明确同意时读取运动数据的风险。

## What Changes

- 新增 rootless Theos 越狱插件，针对 iOS 15 应用进程拦截 Core Motion 加速度计数据请求。
- 默认拒绝未在白名单中的应用，并在首次请求时提供“允许”“拒绝，下次再说”“永久拒绝”三种选择。
- 持久化应用授权、临时拒绝和永久拒绝状态，支持设置中修改和重置。
- 新增 Settings 配置页面，展示已发现应用、当前规则和全局开关。
- 覆盖轮询、回调和设备运动数据中的加速度派生访问路径；文档明确无法覆盖未注入进程、私有硬件接口和越狱环境外的访问。
- 提供测试宿主、构建打包脚本和真机验证记录。

## Capabilities

### New Capabilities

- accelerometer-access-control：应用级加速度计访问决策、弹窗、持久化状态和运行时数据阻断。
- settings-preference-panel：系统设置中的白名单、拒绝规则和权限重置管理。

### Modified Capabilities

无。

## Impact

- 新增 Theos tweak、共享配置库、PreferenceLoader/CepheiPrefs 设置 bundle 和测试宿主。
- 依赖 iOS 15 CoreMotion Objective-C 运行时符号、rootless Theos 打包能力和已越狱设备的注入框架。
- 运行时拦截只对成功注入的应用进程生效；系统守护进程和未支持的私有传感器路径不在本变更承诺范围内。

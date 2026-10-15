# NoAccl

NoAccl 是面向 iOS 15 及以上 rootless 越狱环境的 Core Motion 访问控制插件。插件默认拒绝未授权应用的加速度计和设备运动数据，只允许通过弹窗或系统设置加入白名单的应用访问。

## iOS 版本兼容性

当前代码使用的 Core Motion 入口在 iOS 4.0 及更早版本已经存在，前台窗口查找使用的 `UIWindowScene`／`connectedScenes` 从 iOS 13.0 起可用。结合当前 rootless 打包方式，**无需修改插件源码即可理论支持 iOS 15 及更高版本**。目前只在 iOS 15 上完成过实际测试，iOS 16 及更高版本尚未完成设备验证；能否正常使用还取决于对应版本的 rootless 越狱、注入框架、PreferenceLoader 和 Cephei。

这里的“适配”表示源码/API 和安装包版本约束已经满足，不等同于每个 iOS 版本或越狱方案都完成了设备实测。实际安装还需要对应版本可用的 rootless 越狱、注入框架、PreferenceLoader 和 Cephei；未验证的版本请先用 `probe/` 测试宿主确认拦截行为。

源码仓库：<https://github.com/the-eric-kwok/NoAccl>

## 行为

- 未配置应用首次前台请求时显示「允许」「拒绝，下次再说」「永久拒绝」。
- 「允许」和「永久拒绝」通过 Cephei `HBPreferences` 持久化到 `com.noaccl.tweak` 域。
- 「拒绝，下次再说」只保存在当前应用进程内存中，进程结束后重新询问。
- 后台请求或无可见窗口时不弹窗，保持阻断并记录待询问状态。
- 设置页提供全局开关、应用规则、搜索、重置全部规则和历史规则删除。

## 边界

NoAccl 依赖应用进程注入和 `CMMotionManager` 公开 Objective-C 入口。以下路径不受承诺保护：未注入进程、App extensions、WebKit 子进程、`UIAccelerometer`、`CMSensorRecorder`、私有 IOKit 或其他私有传感器接口。已交付给应用的数据无法从应用侧撤回；权限撤销后只会停止后续更新和同步读取。

## 构建

```sh
make test
make package FINALPACKAGE=1
```

构建需要 Theos rootless 工具链和 iOS 27.0 SDK，deployment target 为 iOS 15.0。当前 Cydia 发布版本为 `0.2.1`。产物分别位于 `packages/` 与 `probe/packages/`。

## 安装

可从 [Releases](https://github.com/the-eric-kwok/NoAccl/releases) 下载主插件 DEB。安装顺序为 `ws.hbang.common`、`com.noaccl.tweak`。主插件安装后按包管理器要求 respring，让 PreferenceLoader 重新加载设置入口。

也可以在 Sileo／Zebra 中添加 Eric 的 Cydia repo：

```text
https://the-eric-kwok.github.io/cydia/
```

## 许可证

MIT License

## 开发验证

`probe/` 是开发阶段专用的 Core Motion 测试宿主，只用于在越狱设备上验证拦截效果；它不会发布到 GitHub Release，也不会进入 Cydia repo。

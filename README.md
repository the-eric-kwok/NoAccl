# NoAccl

NoAccl 是面向 iOS 15 rootless 越狱环境的 Core Motion 访问控制插件。插件默认拒绝未授权应用的加速度计和设备运动数据，只允许通过弹窗或系统设置加入白名单的应用访问。

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

构建需要 Theos rootless 工具链和 iOS 27.1 SDK。产物分别位于 `packages/` 与 `probe/packages/`。

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

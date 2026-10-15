## ADDED Requirements

### Requirement: 设置页面注册与应用列表
设置 bundle SHALL 在系统设置中注册 NoAccl 页面，展示已发现应用和当前规则，并支持按 bundle identifier 稳定保存。

#### Scenario: 打开设置页面
- WHEN 用户从系统设置进入 NoAccl
- THEN 页面显示全局启用状态、规则说明和应用规则列表

#### Scenario: 应用列表合并
- WHEN 已安装应用与历史规则同时存在
- THEN 页面合并显示两者，并为已卸载应用提供删除历史规则的操作

### Requirement: 规则编辑与重置
设置页面 SHALL 提供每个应用的允许、永久拒绝和询问选项，为已卸载应用提供删除历史规则操作，并支持重置全部规则。

#### Scenario: 保存规则
- WHEN 用户选择某应用的新规则并返回
- THEN 规则原子写入共享配置并广播刷新通知

#### Scenario: 重置全部
- WHEN 用户确认重置全部规则
- THEN 所有应用规则变为 ask，页面显示更新后的状态

# P2-42-R5 — App 卸载 / 重装后的关联可用性恢复

## 目标

让 App 安装状态变化只影响关联的当前可用性，不修改插件身份、固定归属、扩展关联拓扑或每个 App 的启用状态。

## 本轮实现

1. `PluginAssociationSnapshot` 增加只读关联可用性投影：
   - `available`：关联 Bundle ID 出现在最新 App Inventory。
   - `unavailable`：关联记录仍存在，但 Bundle ID 当前不在 App Inventory。
   - 未关联的 Bundle ID 返回 `nil`。
   - 可用性不写回 Manifest，也不持久化成第二套关联缓存。
2. `AppsViewModel` 收到 `.filterKitAppInventoryDidRefresh` 后，使用新 App Inventory 与现有 `PluginScanRegistry.shared` 快照重新执行纯关联 join。
3. `PluginsViewModel` 启动单一进程级 LaunchServices 变化观察器，并在收到已完成的 App Inventory 刷新通知时更新显示名称映射。
4. Plugin 扩展关联管理区直接消费同一 App Inventory 刷新通知，更新当前已安装 App 列表；保留原有编辑草稿和每个 App 的启用位。
5. 固定归属详情显示 App 当前已安装/未安装状态；App 未安装时明确提示固定归属记录仍然保留。
6. 新增 Reader 测试覆盖 Fixed Owner 与 Additional App Association 在卸载/重装前后的可用性变化，确认 Bundle ID 和 Plugin ID 不变。

## 不变量

- App 卸载不会删除 dylib、Filter.plist、Manifest 或插件记录。
- App 卸载不会删除 Fixed Owner / Additional App Association。
- App 重装通过相同 Bundle ID 恢复关联可用性，不重新导入、不复制文件、不创建新 Plugin ID。
- 不自动启用注入；每个 App 的既有启用位不因 App Inventory 变化而修改。
- 不执行 Plugin Inventory 扫描；关联刷新只 join App Inventory 与现有 `PluginScanRegistry.shared` 快照。
- App Inventory 刷新失败时，保留上一次成功快照；不得把扫描失败误判为 App 已卸载。
- Helper IPC、卸载事务和生产写入 Gate 不变，仍保持关闭。

## 已知限制

- LaunchServices 变化通知由现有 `LaunchServicesApplicationsChangeObserver` 驱动；如果通知不可用，用户仍可通过 App 页面显式刷新 App Inventory，之后关联可用性随共享快照更新。
- 当前阶段只处理可用性投影和 UI 快照刷新，不执行真实注入、启停、关联写入或卸载。

# P2-42-R2 — APP / Plugin 页面职责与注入术语统一

## 本轮目标

落实 P2-41 冻结的页面职责，不开放生产写入：

- APP 是首次插件注入入口，并负责每个 App 的启用/停用。
- Plugin 负责插件信息、扩展关联、备份恢复、导出和卸载入口。
- Plugin 不提供首次 dylib/plist 注入入口，也不提供启用/停用开关。
- 卸载入口只出现在 Plugin 详情页；当前以禁用状态呈现，直到 Helper 三文件卸载事务和设备验收完成。

## 实际改动

- APP 详情操作文案由「导入插件」改为「注入插件」，英文为 `Inject Plugin`。
- APP 注入文件选择仍是只读预检，不会复制文件、写入 Filter/Manifest 或调用 Helper 执行注入。
- ZIP、DEB、dylib 预检结果中的目标操作术语改为 Injection；默认启用意图仍只是预览，不代表实际启用。
- Plugin 详情页增加「插件管理」区。FilterKit 自有插件显示禁用的「卸载插件」入口和原因；外部/未知来源插件显示只读说明。
- Plugin 页扩展关联管理继续只编辑关联拓扑；新关联默认关闭，已有启用状态保留；启停仍明确引导至 APP 页面。
- 未开放任何卸载、注入、启停或关联写入 Release Gate。
- 更新产品架构审计脚本中的 APP 入口术语。

## 明确未做

- 没有实现 Helper 卸载 IPC 命令或三文件删除事务。
- 没有真实注入、启停、卸载或恢复写入。
- 没有改变 Fixed Owner / Additional App Association 数据语义。
- 没有新增插件扫描路径或缓存。

## 后续工作

下一小阶段应实现 Helper 侧三文件卸载事务：在 Helper 重新验证 FilterKit 所有权、Manifest、dylib/Filter.plist/Manifest 三份 SHA-256、所有 App 启用状态均关闭后，使用可恢复 journal 完成原子隔离/删除；完成恢复规划与故障注入测试后，再接入 IPC。Release Gate 继续关闭，直到 Darwin/Xcode 和 RootHide/ElleKit 真机验收通过。

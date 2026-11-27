# P2-37-R4 — APP 启停操作执行协议与 Helper 事务授权设计

## 本阶段目标

定义 APP 详情页对单个插件、单个目标 App 的启停命令，以及 Helper 生成的单目标计划和提交证明。此阶段只建立可验证协议模型，不开放生产写入、不新增可调用的写入 IPC 路由。

## 新增

- `HelperAppPluginActivationCommand`：命令绑定 requestID、pluginID、唯一目标 Bundle ID、desired/expected 状态、dylib/plist 叶名称、Filter.plist SHA-256、Manifest SHA-256 和 UI snapshotRevision。
- 命令适配器只转换为既有 Helper mutation request；不携带路径、plist 字节或 Manifest 字节。
- `HelperAppPluginActivationPlan`：Helper 计划必须回显同一 request/plugin/target、匹配调用方期望的前态及文件前置哈希，并给出 after 哈希。
- `HelperAppPluginActivationProof`：提交回执必须绑定相同目标和期望状态；实际状态变化必须有 transactionID，无变化则不得伪造事务 ID。
- 5 个 XCTest 用例覆盖单目标绑定、哈希/修订号形状、计划目标与前置条件、回执状态绑定及 no-op 语义。

## 安全边界

- `snapshotRevision` 仅用于 App 侧防止旧 UI 操作；不能替代 Helper 文件哈希检查。
- Helper 仍必须在 prepare/commit 时重新解析 ownership proof、重读 Manifest 与 Filter.plist、核对 expected hash，并调用既有双文件事务。
- 本阶段没有把新协议加入 IPC allowlist/dispatcher，也没有连接 UI 开关；因此这些模型不能触发写入。
- 既有 `pluginAssociationCommitReleased == false` 保持不变；所有生产写入仍关闭。

## 下一阶段前置工作

需要将协议模型接入独立的 Helper IPC request/response 路由，确保同一 requestID 的重放保护、审计、freshness 与 recovery gate 均覆盖，然后在 Apple 平台完成类型检查和 XCTest。只有通过 RootHide/ElleKit 设备验证后才能讨论打开写入门。

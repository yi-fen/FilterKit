# P2-41 — 图标去闪烁（A）+ App/插件扫描剩余提速审计

## 基线

基于上传包 `FilterKit-P2-37-R8-Apple-Readiness.zip`（工作树源码已整体对齐该基线，历史 Build 归档保留）。本轮只做 A 组图标/重绘收敛，不改扫描算法、枚举口径、模型字段与配对归属。

## A 组改动（消除进页图标闪烁）

### A1. 图标解码不再先清空已有图
- `Sources/Features/Apps/ApplicationIconView.swift`
- 去掉 `loadIcon()` 开头的 `image = nil`；解码结果非 nil 才覆盖 `image`，nil 保留旧图。
- 对齐 R16 `ApplicationIconView`：只在 `if let loaded` 成功后赋值，任务重跑不回退占位系统图标。
- 文件/资产/内嵌数据解码仍在 detached `.utility` 后台；bundle-ID 私有 API 兜底缓存逻辑不变。

### A2. 库存身份未变时跳过数组重赋值
- `Sources/Features/Apps/AppsView.swift`（`AppsViewModel.load`）
- 普通读路径（非强制刷新）：新旧库存 bundle-ID 集合相同且当前非空时，不再 `apps = inventory` 重新赋值，避免 List 整批重绘、重置行内图标状态。
- 强制下拉刷新（`forceRefresh: true`）始终替换，以呈现最新元数据；bundle-ID 集合变化或当前为空时正常替换。
- 缓存层已统一去重排序，身份集合相同即视为列表无需重建。

## 静态核对（本机 Linux，无 Xcode/SwiftPM）

- 两文件花括号配平通过；`image = nil` 无残留；测试不直接实例化 `AppsViewModel`、不断言数组替换次数，既有断言不受影响。
- 插件列表无独立图标视图，本轮未涉及。
- 编译与 XCTest 结论以下次 Runner `xcodebuild` 为准。

---

## 扫描链路现状与剩余提速审计

### 一、App 扫描（已具备的提速机制）

- 根 `.task` 双 prewarm 后台预热；provider 单例共享、在飞任务合并、60s TTL 内存缓存、快照先上屏。
- LS 主通路 `allInstalledApplications`，空/不可用才回退 `allApplications`；LS 成功不叠加容器目录扫描。
- 每个 App 的 `Info.plist` 只读一次；图标候选名懒取，解码留到行渲染。
- 去重排序统一在缓存层，扫描侧不二次排序；本轮再加图标不清空 + 身份未变跳过重绘。

### App 剩余可优化点（按风险分级）

| 级别 | 项 | 说明 | 前置条件 |
|---|---|---|---|
| 中风险 · 可立项 | 图标全局缓存 | 文件/资产/内嵌解码结果按 bundleID（或候选路径）入 `NSCache<NSString, UIImage>`，重进页面免重复解码；可选库存就绪后后台批量预解码热点图标 | 评估缓存容量与内存压力；不改变图标解析口径 |
| 待真机剖面 | plist 解析重量 | 每 App 全量 `PropertyListSerialization` 反序列化只为取 DisplayName/Name/Version/Build/Executable/图标等少数键；plist 不支持按键直取，是否值得部分读取需真机占比数据 | 真机剖面确认 plist 读取/解析在枚举耗时中的占比 |
| 低收益 | proxy 多次 `perform` | bundleID/URL/名称三次私有 selector 调用，合并空间小，受私有 API 限制 | 一般不优先 |
| 策略取舍 | TTL 60s 失效 | 超期即重扫；可调长或结合目录 mtime 判定失效，属缓存策略取舍 | 需评估陈旧数据可接受度 |

### 二、插件扫描（已具备的提速机制）

- `PluginScanRegistry` 单例、在飞合并、generation 令牌防旧扫描覆盖新结果、失败保留上次快照、detached `.utility` 后台。
- 预热链接入根 `.task`；关联读取优先复用 App 快照，后台补全；全程只读，不写文件/不调 dpkg。
- 目录枚举 + `resourceValues` 判定符号链接/普通文件。

### 插件剩余可优化点（按风险分级）

| 级别 | 项 | 说明 | 前置条件 |
|---|---|---|---|
| 口径评审 · 最重 | dylib 重操作延后 | 首屏库存只需文件名/配对/路径/清单名；当前对每个 dylib 全量读入 + SHA256 + MachO slice/CDHash 解析。这部分可延后到详情页或按需触发，是插件列表最可能的重量点 | 属首屏填充口径变更，需评审模型字段首屏留空/延后填充的验收口径，不能擅自删除 |
| 待真机剖面 | plist/manifest 哈希延后 | 首屏是否需要每个 plist/`.fk.json` 的 SHA256 与二次 `attributesOfItem` 防变更校验，可评估延后到需要身份核验时 | 真机剖面确认哈希/属性读取占比 |
| 待真机剖面 | 清单 JSON 解码按需 | `.fk.json` 解析主要服务关联与详情展示，纯列表可延后解码 | 同上，需剖面支撑 |
| 待真机剖面 | 目录枚举属性聚合 | 逐文件 `resourceValues` 可评估批量属性获取，减少系统调用次数 | 剖面确认枚举阶段系统调用占比 |

## 未闭环 / 待复验

- 本机无 Xcode，未实编；下一轮 Runner 确认编译、XCTest 通过，进页图标不再回退占位、身份未变时列表不整批重绘。
- 上述"待真机剖面"项均需真机耗时数据支撑，不在离线阶段拍板；"口径评审"项改动首屏数据填充契约，需单独授权。
- DEB 安装/签名放行/jbroot API/真机注入验证仍 pending；0.1 未真机闭环不签署。

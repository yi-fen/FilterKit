# Stage 2.3 C-F5：G8/G9/G10 CI 自动化取证改动清单（评审稿，待授权实施）

- 上游：C-F4 门禁 `Stage-2.3-CF4-Final-Acceptance-Gates.md`；交互清单 `Stage-2.3-CF3-Simulator-Interaction-Acceptance.md`。
- 基线：本地 `fcaa6be`；远端 `main` `2445ef1`。本稿只冻结自动化方案与改动边界，**不在本稿内实现**；授权后按阶段落地。
- 目标：在 macOS Runner 上自动完成 G8（五页面导航）、G9（JSON 导出 + 往返解析）、G10（Share Sheet）取证，产物归档为 CI artifact，替代手动回传 Worker 日志包。
- 本机 Linux 无 Swift/Xcode/模拟器；本方案所有执行步骤均在 `macos-latest` Runner 完成。

## 1. 边界（与冻结契约一致，不得回改）

- 不改 `Core` / `Models` / `Adapters` / 解析器 / 归属实现；不改 `ReportExporting` 协议、`ReportExporter`、`FilterRule` 等冻结契约。
- 不开发 0.1-D 权限探针；不出现插件启停、装卸、删除、修复、规则修改入口；不读写真机与越狱目录。
- 导出只写 App 自身 `FileManager.default.temporaryDirectory`，文件名 `FilterKit-Report-<generatorVersion>.json`；校验步骤只读容器临时目录。
- 合成信封基线不变：3 Total / 2 Paired / 1 Missing / 1 Parse Failed；`loaded` 恒 `.unknown`；`permission.decision` 恒 `undetermined`。
- 实施中若发现必须改动 Core / Models / Adapters / Parser / 冻结契约才能继续，**暂停并单独评审**，不在本批内绕过。

## 2. 现状盘点（已核对源码与工程）

| 项 | 现状 | 对自动化的影响 |
|---|---|---|
| 导航容器 | `RootTabView` 为无绑定 `TabView`（Dashboard / Plugins / Diagnostics / Settings 四 Tab）；Detail 由列表 `NavigationLink` 推入 | 可由 UI 测试按 Tab 标题/标识点击；无需改导航结构 |
| 无障碍标识 | `App/` 下当前**无任何** `accessibilityIdentifier`/`accessibilityLabel` | 自动化只能依赖可见文案；文案改版即脆弱，需补标识（纯视图属性） |
| 导出链路 | Settings `Button("Export JSON Report")` → `SettingsViewModel.exportReport()` → `ReportExporting.export(_:)` → 临时目录；成功后出现 `ShareLink(item: url)` | 测试点：Export 按钮 → 等待 ShareLink 出现且无错误文案；文件在 App 容器 `tmp/` 下由 CI 步骤拉出 |
| 工程定义 | `project.yml` 仅 `FilterKit` application target；无 UI 测试 target | 需在 XcodeGen 定义中新增 UI-testing target |
| SwiftPM | `Package.swift` 含 Models/Adapters/Core/AppPresentation 库与 `Stage2Tests`；无命令行可执行 target | 往返解析校验需新增独立校验入口（见 §5-D） |
| 工作流 | `app-build` job 仅 boot/install/launch/alive/截 Dashboard；无导航、导出、分享步骤；`build` job 日志亦未归档 | 需补 UI 验收 job 与产物上传 |
| 分享组件 | `ShareLink`（SwiftUI 系统分享入口），未实际调起过 | G10 需在测试中点按 ShareLink，等待系统 Share Sheet 渲染后截图 |

## 3. 方案选型

### 3.1 候选路径

- **方案 1：XCUITest UI 测试 target（推荐）**
  新增 `FilterKitUITests`（`bundle.ui-testing`），在 Runner 上 `xcodebuild test` 驱动模拟器：点 Tab、进 Detail、切分段、搜索、点 Export、点 ShareLink；每步截图归档。XCUITest 是 CI 内唯一可注入 UI 点击与等待界面元素的官方路径。
- **方案 2：纯 `simctl` shell 直驱（不可行）**
  `simctl` 只提供 boot/install/launch/io screenshot/spawn 等能力，**没有按坐标或元素注入点击的接口**；无法完成 Tab 切换、Detail 推入、Export/Share 点按。
- **方案 3：启动参数直达 Tab / 确定性深链（辅助）**
  在 App 组合根读取启动参数决定初始 Tab，用于缩短跨页路径与空信封复核；Detail 推入、Export、Share 仍由 XCUITest 完成。

### 3.2 结论

**方案 1 为主，方案 3 为辅**：XCUITest 覆盖导航/导出/分享全链路；启动参数仅用于指定初始 Tab 与注入空信封做禁用态复核，不引入新的业务路由。

## 4. 证据目录与产物命名（对齐 C-F3 §1）

归档目录 `Tests/Stage2/evidence/<run>-acceptance/app-build/`（CI 产物名 `filterkit-ui-acceptance`，retention 14 天）：

| 路径 | 对应门禁 | 内容 |
|---|---|---|
| `simulator/dashboard.png` | G8 | Dashboard 首屏（已有基线，复核不回退） |
| `simulator/plugins.png` | G8 | Plugins 列表（ALL 段 3 行） |
| `simulator/plugin-detail.png` | G8 | Detail 六分区（至少 Paired / Parse Failed / Missing 各一） |
| `simulator/diagnostics.png` | G8 | Diagnostics 七组 |
| `simulator/settings.png` | G8 | Settings 导出前 |
| `simulator/share-sheet.png` | G10 | Share Sheet 调起后 |
| `export/filterkit-report.json` | G9 | 从容器 `tmp/` 拉出的导出样本 |
| `export/export-log.txt` | G9 | 导出步骤日志（按钮点击、文件落盘、容器路径） |
| `export/roundtrip-result.json` | G9 | 往返解析校验结果（解码成功、计数、等义比对结论） |
| `export/SHA256SUMS` | G9 | 导出样本与往返结果哈希 |
| `ui-test/` | G8/G9/G10 | XCUITest 日志、activity、断言记录 |

## 5. 改动清单（按层划分，标注性质）

### 5-A UI 层无障碍标识（纯视图属性，无业务逻辑）

- 范围：`App/Navigation/`、`App/Features/**`。
- 内容：为 Tab、列表行、分段 Picker、搜索框、Detail 分区、Diagnostics 分区、Export 按钮、ShareLink 增加稳定 `accessibilityIdentifier`（命名空间 `<page>.<element>`，如 `settings.exportButton`、`plugins.row.<pluginID>`）。
- 不改动视图布局、状态绑定与数据流；标识不进入生产展示文案。

### 5-B 工程定义 `project.yml`

- 新增 target：

  ```yaml
  FilterKitUITests:
    type: bundle.ui-testing
    platform: iOS
    sources:
      - path: Tests/Stage2/UITests
    dependencies:
      - target: FilterKit
  ```

- 由 XcodeGen 生成对应 scheme；Runner 以 `xcodebuild -scheme FilterKitUITests -destination 'platform=iOS Simulator,...' test` 执行。
- 不改动现有 `FilterKit` application target 的依赖、Bundle ID、Deployment Target 草案。

### 5-C 新增 UITest 源码 `Tests/Stage2/UITests/`

- `NavigationFlowTests.swift`（G8）：
  - 启动 → Dashboard 可见（计数 3/2/1/1、状态文案在位）；
  - 切 Plugins：ALL 段 3 行；PAIRED 段 2 行；ISSUES 段异常项在位；搜索命中/空关键词回全量/无结果空态；
  - 进入 Detail：分别打开 Paired、Parse Failed、Missing 样本，核对六分区（Status / Files / Pairing / Filter / Ownership / Evidence）；`loaded` 显示未确认态，不出现 Not Loaded / 已加载；
  - 进 Diagnostics：DG-1～DG-7 七组在位，空组展示空态；
  - 进 Settings：版本信息在位。
  - 每步截图落 `simulator/`。
- `ExportFlowTests.swift`（G9）：Settings 点 Export → 等待 ShareLink 出现、错误文案为空；记录落盘文件名与容器路径；不校验越狱目录写入。
- `ShareSheetTests.swift`（G10）：点 ShareLink → 等待系统 Share Sheet 元素 → 截 `share-sheet.png`；不实际发送/上传。
- 空信封复核（ST-6）：经启动参数注入空信封，断言 Export 入口禁用且有空态说明；该用例单独归档，不计入合成信封基线截图。

### 5-D 往返解析校验入口（仅 Models 解码与结构比对，不改 Models）

- 候选实现（评审时二选一）：
  - **D1（推荐）**：`Package.swift` 新增可执行 target `ReportRoundtripValidator`，仅依赖 `Models`；输入导出 JSON 路径，`JSONDecoder` 解码为 `ReportEnvelope`，与入库基线夹具 `Tests/Stage2/Fixtures/roundtrip-preview-expected.json` 比对（排除 `generatedAt`），输出 `roundtrip-result.json`：`decodable`、`plugins/unknownItems/warnings` 计数、逐字段等义结论、哈希。
  - **D2**：不加可执行 target；CI 侧用 `plutil`/Python 做合法性、顶层键与计数校验，Model 级等义比对沿用 `ReportExporterTests` 既有结论。G9 门禁口径是「重新解析回等义信封」，D1 证据强度更高。
- 基线夹具由 `SyntheticReportFactory.previewEnvelope()` 一次性生成入库，与源码同源复核；夹具变更需在实现记录中说明。

### 5-E 工作流 `.github/workflows/filterkit-build.yml`

- 新增 `ui-acceptance` job（`needs: [app-build]`，`if: always()` 口径与现有产物 job 一致）：
  1. Checkout；安装 XcodeGen；`xcodegen generate`；
  2. 选取可用 iPhone 模拟器（复用 `app-build` 现有设备选取逻辑与 UDID）；
  3. `xcodebuild test -scheme FilterKitUITests -destination 'platform=iOS Simulator,<device>'`，输出 UI 测试日志；
  4. `xcrun simctl get_app_container <device> com.filterkit.manager tmp` 拉出 `FilterKit-Report-*.json` 到 `build/export/`；
  5. 跑 `ReportRoundtripValidator`（D1）或结构校验（D2），生成 `roundtrip-result.json` 与 `SHA256SUMS`；
  6. `actions/upload-artifact@v7` 上传 `filterkit-ui-acceptance`（`simulator/`、`export/`、`ui-test/`，retention 14 天）。
- 顺带补 G1 自动留证（上一轮已评审的最小改动）：`build` job `tee .build/swift-build.log` + `if: always()` 上传 `filterkit-non-ui-build`；与本 job 解耦，可独立先行。

### 5-F 规格与证据回填

- 实现落地后回填 `Stage-2.3-GUI-Foundation-Implementation-Record.md`：实际用例数、截图清单、往返结果、未决项；
- 全绿后按 C-F4 §4 生成统一 `ACCEPTANCE.md`；本批不预写死通过数量，以真实日志/截图为准。

## 6. 证据 → 门禁映射

| 门禁 | 自动化断言 | 归档证据 |
|---|---|---|
| G8 Navigation | 五面可达无崩溃卡死；PL-1～6、Detail 六分区、DG-1～7 逐项在位；三态/未知项不被裁剪 | `simulator/*.png` + `ui-test/` 断言记录 |
| G9 Export | 经接缝生成合法 JSON；解码回等义信封；计数 3/1/1；Optional nil 保留；仅写临时目录 | `export/filterkit-report.json`、`roundtrip-result.json`、`SHA256SUMS`、`export-log.txt` |
| G10 Share | Share Sheet 正常调起；分享对象为刚生成的 JSON；文件名正确；无空文件/错误 URL | `simulator/share-sheet.png` + `ui-test/` 记录 |

## 7. 分阶段落地建议

- **P1 导航取证**：5-A 标识 + 5-B target 骨架 + 5-C `NavigationFlowTests`；产出 G8 截图与断言记录。
- **P2 导出往返**：5-D 校验入口 + 5-C `ExportFlowTests` + 5-E 拉取/校验/归档；产出 G9 证据。
- **P3 分享与空态**：`ShareSheetTests` + 空信封禁用态复核；产出 G10 证据；回填记录并待最终闭环评审。
- 每阶段独立可回滚；任一阶段失败不回填后续门禁结论。

## 8. 风险与待确认项

1. **CI headless 模拟器 Share Sheet 渲染**：系统分享面板在无窗口 Runner 上的可用性需首轮实测；若无法稳定渲染，兜底口径为断言 ShareLink 可点、分享文件 URL/文件名有效，Share Sheet 截图缺口如实记录，不判通过。
2. **UI 测试 target 构建成本**：新增 scheme 与测试 bundle，Runner 时长与构建矩阵需在首轮实测记录。
3. **空信封注入点**：启动参数在 App 组合根（`FilterKitApp`/`AppDependencies`）读取并选择静态提供者；属组合根装配，不进入 Core。
4. **设备 UDID**：复用现有选取逻辑；多模拟器并存时以清单首个可用 iPhone 为准，日志记录设备名与 UDID。
5. **夹具同源性**：基线 JSON 与 `previewEnvelope()` 的对应关系需在夹具旁附生成说明；信封基线改动时夹具同步更新。

## 9. 不在本批范围

- 真机目录扫描、真实插件加载、entitlement/sandbox/`jbroot()` 放行验证（0.1-D）；
- `OwnershipResolver` 迁移、`loaded` 状态推断、`permission.decision` 判定、pluginID 规则定稿、PARSE-009-B；
- 插件启停/装卸/配置修改/越狱文件写入；
- Rootless 真机兼容结论。

## 10. 评审确认点（已按推荐默认落地，待 Runner 复核）

1. 往返校验：**D1**——`ReportRoundtripValidator` 可执行 target，Model 级解码与合成基线等义比对（忽略 `generatedAt`）。
2. 清单改动：**同意**——`project.yml` 新增 UITest target，`Package.swift` 新增校验可执行 target；仅清单与装配，不动业务源码。
3. 落地节奏：**分阶段 P1→P2→P3**，代码一次落盘、按阶段归档证据；任一阶段 Runner 失败不回填后续门禁。
4. G1 编译日志：**随本批落地**——`build` job 补日志落盘与 `filterkit-non-ui-build` 产物上传。

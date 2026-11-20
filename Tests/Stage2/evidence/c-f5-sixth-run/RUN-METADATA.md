# C-F5 六轮 Runner 复核记录（run `44552220558` / job `build`，新运行于 main `8954cdf`）

- 时间：2026-11-19 15:18:14Z ～ 15:18:53Z；Worker `{d465d53a-a35c-407d-9de6-f2b1264b71a0}`；runner version 2.338.2；macOS 26.7.2（25G332），Image macos-26-arm64 `20261102.0473.1`。
- 检出 SHA：**`8954cdf171ff93cf94dfdc1eae0c7e0df050d756`**；与本地五轮修复树对 `.swift` / yml 无内容差异，五轮两项修复已上 Runner。
- 本附件仅含 `build` job（非 UI `swift build`）日志；test / isolation / app-build / ui-acceptance 各 job 本轮未随附，结论以本日志为准。
- 产物：Artifact `filterkit-non-ui-build`，ID `14542534836`，1055 B；下载页 `https://github.com/yi-fen/FilterKit/actions/runs/44552220558/artifacts/14542534836`。

## 失败结论：`swift build` 编译失败，exit 1

`ReportRoundtripValidator` target 编译 `Tools/ReportRoundtripValidator/main.swift` 时报两处类型错误：

| 行 | 错误 |
|---|---|
| `main.swift:32:66` | `binary operator '<' cannot be applied to two '(String, String, String?)' operands`（plugins 排序元组） |
| `main.swift:36:61` | `binary operator '<' cannot be applied to two '(String?, String, String)' operands`（unknownItems 排序元组） |

- 根因：五轮归一化实现用元组字面量做 `<` 字典序比较；Swift 标准库的元组比较算子对**含 `String?` 元素的元组**不提供（元组未整体满足 `Comparable`），非 Optional 元组可用、混入 Optional 即编译失败。本机 Linux 无 Swift 工具链，该类型错误未在本地暴露，直到 Runner 编译才出现。
- 其余 target 编译进度：Models / Adapters / AppPresentation / Core 已进入编译；错误仅卡在 validator 可执行 target。

## 处置（本地已落地，待七轮最新 main 新建运行复核）

- 移除元组 `<` 比较；新增私有 `compare(_:_:) -> Bool?` 可选字符串比较器（`nil` 排前、相等返回 `nil` 落到下一排序键），与 `Core/ReportExporter/ReportSerialization.swift` 的 `compare` 同口径。
- 三个数组排序改为 `compare(...) ?? compare(...) ?? ... ?? false` 显式回退链：
  - plugins：pluginID → name → plistPath ?? dylibPath；
  - unknownItems：path ?? base → reason → sourceStage；
  - warnings：code → sourceStage → message。
- 未新增 target 依赖；Models / AppPresentation 依赖不变。

## 待复核项（本轮未取证）

- 编译门禁 G1：待 `swift build` 0 error / 0 warning 后复核。
- 五轮遗留：UITest 搜索框先 `tap()` 聚焦再输入的修复，属 ui-acceptance job 的 XCUITest target，本 build 日志不覆盖，待 UI job 复核。
- G9 往返等义、G10 截图本体解包核验仍待后续 Runner 证据。
- 0.1-C 不予闭环；本机 Linux 无 Swift/Xcode，编译与渲染结论以 Runner 日志为准。

## 归档文件 SHA256

| 文件 | SHA256 |
|---|---|
| `job-logs.txt`（257 行） | `d7914ea3230c827fbee9065284360c8be9980abe69fcfd7c7849c5dd62a43566` |

# R3-C 前置基线 — CI 绿灯切片（checkout `d70c131`）

## 基线与环境

- 仓库：`yi-fen/FilterKit`；checkout `origin/main` `d70c131c6ebc0daf0a26ac920f2db5c050960ead`（depth=1，该提交不在本地对象库；本地浅克隆 `origin/main` 停在 `f13989a`）。
- Runner：macos-26-arm64，macOS 26.7.2（25G332），runner 2.338.2，image `20261117.0516.1`；测试目标 `arm64e-apple-macos14.0`。
- 工作流：`.github/workflows/filterkit-build.yml@refs/heads/main`；时间窗 2026-11-21 02:12:11Z → 02:17:40Z。
- 本切片为 **R3-C 桥接代码落地前** 的基线；归档用于复测前后对照，不代表 R3-C 已验收。

## 测试与编译结论

| 门禁 | 结论 | 证据 |
|---|---|---|
| `swift test`（macOS Debug） | **590 tests, 0 failures**（4.638s）；`warning:` / `error:` 计数 0 | `test-log.txt`（SHA256 `08a9fbd3…c99`） |
| S1-05 配对映射独立切片 | **15 tests, 0 failures** | `test-log-s105.txt`（SHA256 `dc2b4b87…1193`） |
| 非界面目标构建（Models/Adapters/Core） | Build complete（30.83s），0 warning/error | `non-ui-swift-build.log`（SHA256 `f490bca0…09`） |
| Adapter 隔离检查 | 7 项全 passed，0 failed | `isolation-summary.json` |
| 设备 App 静态校验 | d1～d6 全 passed | `device-build-summary.json` |
| IPA 结构校验 | p1～p3 全 passed | `ipa-summary.json` |
| DEB 包校验 | e1～e9 全 passed；`signatureState=ldid_signed_embedded` | `deb-summary.json` |
| 模拟器 App 启动 | alive，PID 7609，bundle `com.filterkit.manager`（02:16:49Z）；App `BUILD SUCCEEDED` | `sim-launch.log` |
| UI 导出往返 | `decodable=true`，`equalIgnoringGeneratedAt=true`；counts plugins 3 / unknownItems 1 / warnings 1 | `roundtrip-result.json` |

## 仍未闭环（沿用冻结口径）

- DEB：`installability=device_acceptance_pending`，`installableCandidate=false`；e1～e9 仅静态校验通过，**无真机安装 / 首次启动 / 重启启动证据**。
- UI 往返样本仍是合成 preview：`FilterKit-Report-0-1-0-preview.json` SHA256 `cfbf36262da34aa089fa58afc03863e370b9a3b40f2a7ac58be813a5807c80d7`（`ui-export-SHA256SUMS`），不是真机扫描导出。
- DEB 包 SHA256 `7a65f7393b3ef59a1a621055f287afa6703505d77970f36b30973b36300862ba`。
- CI 绿灯不等于真机验收；C1～C5 根因、G10～G15 / R4-G 待真机 `.ips` 与系统日志，本轮不猜测。

## 与 R3-C 的关系

- 本切片证明 R3-A/B 离线链在 Runner 上编译与既有用例通过；R3-C 新增的导出桥接代码需下一轮 Runner 复测（macOS Debug `swift test` + iOS 两侧编译 + 模拟器 UI 往返）。
- R3-C 不改动本切片已通过的隔离 / 签名 / 打包路径。

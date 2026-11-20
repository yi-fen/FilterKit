# C-F4 门禁状态（run `44552220558` / SHA `8954cdf`，2026-11-19 六轮复核，build job）

> 本轮附件仅含 `build` job（非 UI `swift build`）；test / isolation / app-build / ui-acceptance 各 job 未随附，相关门禁沿用五轮证据，未在本轮重跑。**0.1-C 不予闭环。**

| 门禁 | 本轮判定 | 说明 |
|---|---|---|
| G1 Build（非 UI 目标） | ❌ 编译失败 | `ReportRoundtripValidator/main.swift` 两处元组 `<` 类型错误，`swift build` exit 1；已改 `compare()` 回退链，待七轮复核 |
| G2 Test（全量 XCTest） | ➖ 本轮未取证 | 沿用五轮：405 tests 0 failures |
| G3 S1-05 | ➖ 本轮未取证 | 沿用五轮：15/15 |
| G4 GUI Presentation | ➖ 本轮未取证 | 沿用五轮：GUI-01～08 passed |
| G5 Isolation | ➖ 本轮未取证 | 沿用五轮：7/7，`failed: 0` |
| G6 App Build | ➖ 本轮未取证 | 沿用五轮：BUILD SUCCEEDED |
| G7 Simulator 启动 | ➖ 本轮未取证 | 沿用五轮：PID 4390 alive |
| G8 Navigation | ➖ 本轮未取证 | 五轮：分段计数通过，搜索输入未取证；UITest tap 修复待 UI job 复核 |
| G9 Export | ➖ 本轮未取证 | 五轮：样本落盘可解码，往返不等义；归一化修复随 G1 编译通过后复核 |
| G10 Share | ➖ 本轮未取证 | 五轮：日志口径通过；截图本体待 xcresult 解包核验 |

## 闭环前剩余动作（七轮 Runner）

1. G1：`swift build` 0 error / 0 warning，validator 目标编译通过。
2. G8：搜索框聚焦后命中「Preview」≥1 行并归档 `plugins.png`。
3. G9：校验器归一化后 `equalIgnoringGeneratedAt: true`、exit 0。
4. G10：解包 xcresult blob 目视核验 `share-sheet.png` 等截图本体。
5. 全绿后按 C-F4 §4 归集证据、生成统一 `ACCEPTANCE.md` 签署 0.1-C。

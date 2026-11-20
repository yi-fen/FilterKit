# Stage 2.4 R4 — iOS Device Build & RootHide Deployment Plan（规格冻结）

> 授权依据：用户 R4 建议稿（2026-11-20 上传归档 `Tests/Stage2/evidence/r4-device-build/R4-proposal-device-build-deployment.md`）。
> 定位：在不降低 0.1-D 真机门禁的前提下，补齐当前唯一明确的开发缺口——**只有模拟器构建链，没有 iOS 设备构建与 RootHide 部署链**。R4 让现有 FilterKit 具备上真机测试的条件，而不是重复开发 PermissionProbe。
>
> **本轮边界**：本机 Linux 无 Swift/Xcode、无设备；R4-A～E 本轮落地规格与离线脚手架草案（shell 脚本 / 签名配置草稿），语法本地校验；**不编译设备包、不签名、不产出可安装 IPA/DEB、不连真机、不做权限放行验证**。Runner 离线复验与后续 CI 接线属后续授权批次。

## 1. 两条并行但独立的路线

| 路线 | 内容 | 门禁口径 |
|---|---|---|
| **产品开发路线** | R4：设备构建、签名方案准备、IPA/DEB 打包、静态包校验、部署文档 | 离线 CI/静态检查可先行；不触真机权限判定 |
| **发布验收路线** | 保留 0.1-D 真机门禁（G10～G15）；真机证据不足就不签署、不发布 | R3 真机门禁状态不因 R4 推进而提前转 passed；0.1-E-B 必须等 0.1-C / 0.1-D 闭环 |

两条路线共享同一代码基线与冻结 Models/协议；R4 不得把未完成的真机问题以"打包完成"形式带进 0.1-E。

## 2. 现状审计基线（2026-11-20 本地核对，R4 开工前对照）

### 2.1 已有（离线/模拟器口径已验收）

- Core / Models、Enumeration / Pairing / Parser、Reporting / JSON Export 完成阶段验收；GUI Foundation 模拟器验收通过；PermissionProbe 离线测试通过。
- D5 Entitlement 已实现 signed / runtime / resourceAccess 三类证据分离，真机待验证；D6 `jbroot()` 已实现 raw/normalized/symlink/accessible 四层比较，真实调用待验证。
- CI 工作流 `.github/workflows/filterkit-build.yml`：`environment` → `build`（swift build）→ `test`（458 例 + S1-05 15 例）→ `isolation`（7/7）→ `app-build`（模拟器 `Debug-iphonesimulator`，simctl install/launch/存活/截图）→ `ui-acceptance`（XCUITest 8 例 + 导出往返）→ `artifact`（元数据归档）。
- 工程定义 `project.yml`：Bundle ID 草案 `com.filterkit.manager`，deploymentTarget iOS 17.0（B2/B3 未冻结），Swift 5.0；依赖本地 SwiftPM 产品 Models/Adapters/Core。
- 打包占位：根 `control`（草稿，Version `0.0.1`，Architecture `arm64e` 占位，Depends 空）；根 `Makefile`（Theos 模板草稿，未编译验证）；`reference/0.1.18-src/entitlements.plist` 旧 PoC 四枚 entitlement（仅参考，不作新基线）。
- 既有脚本：`scripts/check-adapter-isolation.sh`（静态文本隔离检查，输出文本 + 机器可读 JSON 摘要）。

### 2.2 缺口（R4 目标）

| 缺口 | 现状 | R4 批次 |
|---|---|---|
| iOS Device Build | 仅 `Debug-iphonesimulator` slice；无 `Release-iphoneos` 设备产物 | R4-A |
| Signing & Entitlements | 无签名配置文件；entitlement 仅参考旧 PoC | R4-B |
| IPA 打包 | 未建立 Payload 结构打包链 | R4-C |
| DEB 打包 | 未建立 `Applications/FilterKit.app` + `DEBIAN/` 包结构链 | R4-D |
| Package Validation | 仅有隔离静态检查；无平台/架构/签名/包结构/control/postinst 校验 | R4-E |
| 部署文档 | 无安装/启动/卸载/回滚说明 | R4-F |
| 真机启动冒烟 | 无设备上 SpringBoard 识别/主屏启动/页面可达性检查 | R4-G（真机门禁，待设备包就位） |

## 3. 批次拆分（R4-A～F + R4-G）

> 顺序：R4 先于 R3-B～E——没有真正可安装的设备包，无法执行真实 GUI 进程探针。R4 各批离线可在 GitHub Actions 完成大部分；真机安装/放行/权限验证不在 R4 范围。

### 3.1 R4-A — iOS Device Build

- **目标**：生成 arm64 真机 App 产物（`Release-iphoneos/FilterKit.app`），区别于模拟器产物。
- **构建口径（示例，最终以 Runner 实测为准）**：`xcodebuild -scheme FilterKit -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build`。
- **离线检查（R4-E 固化为脚本）**：
  - `file FilterKit.app/FilterKit`、`lipo -info FilterKit.app/FilterKit`；
  - `plutil -p FilterKit.app/Info.plist`；
  - 预期：`CFBundleSupportedPlatforms = iPhoneOS`、`DTPlatformName = iphoneos`、架构包含 arm64。
- **架构口径**：arm64 是普通 iPhone 真机主要架构目标；**不把 arm64e 当成所有 iPhone 必须具备的 slice**；不为凑 arm64e 随意修改架构配置。arm64e 仅在目标 RootHide 环境与工具链核实后纳入。
- **未决**：MinimumOSVersion / Deployment Target（B2）取设备/框架/SDK 兼容交集；无 17.x SDK，16.5 SDK 对 iOS 17.0.2 向下兼容待实测。
- **非交付**：可安装签名包；设备启动结论；真机访问结论。

### 3.2 R4-B — Signing & Entitlements

- **目标**：建立独立签名与 entitlement 配置草稿，区分两条签名路线。
- **配置位置（草案）**：`Config/Signing/FilterKit.entitlements`、`FilterKit.Debug.xcconfig`、`FilterKit.Release.xcconfig`。
- **候选 entitlement（参考清单，非已确认可用方案）**：`platform-application`、`com.apple.private.security.no-sandbox`、`com.apple.private.security.storage.AppBundles`、`com.apple.private.security.storage.AppDataContainers`。
- **必须分别验证（四条独立结论，不得互相替代）**：
  1. 签名工具是否允许写入这些 entitlement；
  2. 签名后二进制是否实际包含这些 entitlement；
  3. RootHide 环境是否接受该签名；
  4. iOS 是否实际允许对应资源访问。
- **路线区分**：普通 Apple Developer 签名（证书 + 描述文件）与越狱环境 ldid 签名是不同路线，不能混为一谈；候选方案与路线绑定记录。
- **边界**：entitlement 写进文件 ≠ 权限已获得；签名中存在某键 ≠ 运行时放行；runtime entitlement 读取沿用 R1-B 结论（iOS GUI 进程无公开稳定枚举 API，runtime 保持 unavailable/unknown）。
- **非交付**：已放行的签名；真机 sandbox 结论；真实授权文件下发。

### 3.3 R4-C — IPA Packaging（普通安装对照）

- **目标**：生成普通 IPA 结构对照包；**不要求 IPA 路径通过才完成 R4**。
- **结构**：`FilterKit.ipa` → `Payload/FilterKit.app/`（FilterKit、Info.plist、Frameworks/、内嵌资源）。
- **打包口径（示例）**：`mkdir -p IPA/Payload` → 复制设备 `.app` → `zip -r FilterKit.ipa Payload`。
- **签名状态口径**：无有效设备安装签名时，只能称"未签名 IPA 结构包"，不能称可安装 IPA；正式 IPA 须完成设备签名与授权配置。
- **非交付**：可安装 IPA；设备安装/启动证据。

### 3.4 R4-D — DEB Packaging（RootHide 测试包，优先方向）

- **目标**：生成 RootHide 测试 DEB；命名 `filterkit_0.1.0-1_iphoneos-arm64e.deb`（第三轮后按同机已装包对照定值；版本号随工程 `MARKETING_VERSION` 对齐）。
- **包结构**：`Package/Applications/FilterKit.app/`（rootfs 相对布局，不加 `var/jb/` 前缀）+ `DEBIAN/control`、`DEBIAN/postinst`；打包 `dpkg-deb --build --root-owner-group`，条目属主 root:root。
- **control 字段口径（第三轮修正）**：`Package: com.filterkit.manager`、`Name: FilterKit`、`Version: 0.1.0-1`、`Architecture: iphoneos-arm64e`、`Depends: firmware (>= 15.0)`、`Description`、`Maintainer`、`Section: Utilities`。依据：0.1.18 设备报告同机 366 包对照（二进制档全部 arm64e，arm64 为 0；已装 App 包均带 firmware 基线）。二进制切片与 control 目标架构的一致性仍待 R4-A/R4-G 闭环。
- **postinst 安全边界**：仅在 `configure` 阶段尝试 `uicache -p /Applications/FilterKit.app` 注册；命令与路径以目标 bootstrap 实测为准。**禁止**：改 ElleKit 配置、改插件 plist、删/移 dylib、改 dpkg 数据库、自动授予权限、改系统 sandbox。
- **路径口径**：实际安装路径由目标 RootHide Bootstrap 包管理环境决定；不能未验证假设 `/Applications` 一定映射到预期 JBROOT；不同 bootstrap 对 Architecture、包前缀、uicache 处理可能不同。
- **非交付**：Bootstrap 实际部署；安装成功结论；权限放行结论。

### 3.5 R4-E — Package Validation

- **目标**：独立静态检查脚本，验证安装包本身符合部署要求；**R4-E 通过不代表 RootHide 真机权限通过**，只证明包符合部署要求。
- **脚本（草案位置 `scripts/`）**：`validate-device-build.sh`、`validate-ipa.sh`、`validate-deb.sh`、`validate-entitlements.sh`。
- **检查矩阵**：

| 检查项 | 预期 | 证据类型 |
|---|---|---|
| 平台 | iPhoneOS（非 iPhoneSimulator） | 静态 |
| 架构 | DEB control 目标档 `iphoneos-arm64e`；设备二进制切片以 Runner `lipo -info` 实测为准（第三轮为 Non-fat arm64，一致性待闭环） | 静态 + 待真机 |
| 最低系统版本 | 符合目标设备；SDK 兼容待实测 | 静态 + 待真机 |
| Bundle ID | `com.filterkit.manager`（B3 未冻结前按草案） | 静态 |
| App 文件结构 | 二进制 / Info.plist / Frameworks / 资源完整 | 静态 |
| 签名 | 与部署路线匹配；签名状态如实标注（未签名/Developer/ldid） | 静态 + 待真机 |
| Entitlements | 与批准候选清单一致；逐条列出，不推定放行 | 静态 + 待真机 |
| DEB control | 字段合法、架构/版本一致 | 静态 |
| postinst | 只做必要注册；无越界动作 | 静态文本 |
| SHA256 | 产物可复算一致 | 静态 |

- **输出约定**：沿用隔离脚本惯例——原始文本输出 + 机器可读 JSON 摘要（checks[].id/name/status + failed 计数）；摘要路径由环境变量指定。
- **非交付**：真机权限；真实加载；`jbroot()` 可调用性。

### 3.6 R4-F — Deployment Documentation

- **目标**：安装、启动、卸载及回滚说明（文档口径，不含真机执行结论）。
- **内容**：设备前置条件（RootHide 环境、ElleKit 版本、bootstrap 版本记录项）；IPA / DEB 两条安装路径；主屏启动与存活确认；卸载与残留记录口径；回滚（移除包、恢复上一状态）步骤；证据导出与归档位置。
- **边界**：文档中的命令/路径须标注"待目标 bootstrap 实测"；不记录设备私有数据（UDID/序列号全文）。

### 3.7 R4-G — Device Launch Smoke Test（真机门禁，待设备包就位）

- **性质**：真机门禁，不属于离线 CI 可完成项；在 R4-D/R4-E 产出设备包、真机与 GUI 进程上下文就位后执行。
- **只验证 8 项**：
  1. App 能安装；
  2. App 能被 SpringBoard 识别；
  3. App 能从主屏启动；
  4. Dashboard 能显示；
  5. Diagnostics 能打开；
  6. Settings 能打开；
  7. App 不崩溃；
  8. PermissionProbe 能从 GUI 进程启动。
- **不要求**插件管理功能已经完善。
- **失败口径**：App 启动失败必须如实记录，不能跳过后继续把权限探针结果当作有效证据；启动失败记为 smoke 门禁 `failed`，后续探针证据无效。

## 4. 0.1-E 拆分（验收引擎可提前开发，最终签署不提前）

| 部分 | 可否提前开发 | 功能 | 边界 |
|---|---|---|---|
| **0.1-E-A Release Acceptance Engine** | 可提前（独立证据管理模块，不访问真实 JBROOT） | 门禁注册；证据文件索引；SHA256 校验；Runner ID 校验；Commit SHA 校验；证据环境检查；pending / failed / invalidEvidence 状态传播；发布验收 JSON 生成 | 只做工具与模型，不产生"发布通过"结论；不替 0.1-D 真机门禁判定 |
| **0.1-E-B Final Release Acceptance** | 必须等 0.1-C、0.1-D 真正闭环 | 验证全部正式发布门禁；验证真机证据；验证最终发布 Commit；生成最终验收报告；发布包完整性检查；最终归档 | 未闭环前不执行、不签署 |

两者不能混为一谈：可以提前开发验收工具，不能提前签署发布通过。0.1-E-A 实现属后续授权批次，本轮不落地引擎代码。

## 5. 整体路线（调整后）

```
已完成：0.1-A Engine / 0.1-B Reporting / 0.1-C GUI Foundation / 0.1-D PermissionProbe
   ▼
0.1-D-R4 Device Build & Deployment
   ├── R4-A Device Build ── R4-B Signing ── R4-C IPA ── R4-D DEB
   ├── R4-E Package Validation ── R4-F Documentation ── R4-G Smoke Test(真机)
   ▼
0.1-D-R3 RootHide Device Validation（R3-B JBROOT / R3-C Files / R3-D Entitlement·jbroot() / R3-E Cold Launch）
   ▼
0.1-C G10 独立补证
   ▼
0.1-D Final Acceptance
   ├──────────────────┐
0.1-E-A Release Engine   继续产品完善与测试
   ▼
0.1-E-B Final Release Acceptance
   ▼
0.1.0 Release
```

R4 先于 R3-B～E；R3 真机门禁 G10～G15 与 R4-G 均保持 pending/unknown 直到真机证据取得。

## 6. 本轮（R4-A0 审计与规格冻结）交付与不交付

**交付**：本规格；现状审计基线；R4-A～F 批次与 R4-G 门禁口径；离线脚手架草案（签名配置草稿、打包/校验脚本草案，见 `Config/Signing/`、`scripts/`）；0.1-E-A/B 拆分边界；建议稿归档与记录回填。

**不交付**：设备编译产物；签名包；可安装 IPA/DEB；真机安装/启动/权限证据；0.1-E-A 引擎代码；0.1-E-B 签署结论。

## 7. 既有挂起项与未决依赖（维持不变）

- 既有未决：`OwnershipResolver` 未迁移；`loaded` 恒 unknown；`permission.decision` 恒 undetermined；`pluginID` 稳定标识规则 0.2.0；PARSE-009-B。
- R4 待拍板/待核实：部署形态 A/B/C/B+C（优先 B+C，证据决定）；Bundle ID（B3 草案 `com.filterkit.manager`）；Deployment Target（B2 草案 iOS 17.0）；签名路线（Developer 证书 vs ldid）；DEB 路径前缀/Architecture 命名/uicache 行为；16.5 SDK 对 iOS 17.0.2 兼容；GUI 进程内 libroothide 符号可解析性与 `jbroot()` 返回路径有效性。
- 0.1-C G10（Share Sheet 面板可见性）为既有搁置项，重启复核须明确授权推翻 2026-11-20 搁置决定，R4 不自动重启。
- 本轮脚手架为草案；接入 CI 与 Runner 离线复验前，不得视为已可构建/可打包/可安装。

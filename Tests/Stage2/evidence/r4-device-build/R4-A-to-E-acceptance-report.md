# 0.1-D-R4-A～E 验收报告（CI Device Build & Offline Packaging，待 Runner 离线复验）

> 授权稿：`R4-A-to-E-authorization.md`（2026-11-20）。范围限定 R4-A～E；**不授权 R4-G 真机冒烟、不授权 0.1-E-B 最终发布验收**。
> 报告口径：本轮在本地 Linux（无 Xcode/Swift/plutil/lipo、无 RootHide 真机）完成代码/CI 接线与静态演练；**Runner 实跑日志与产物证据待 workflow_dispatch 调度后回填**。本机结论不构成设备构建、可安装性或真机权限证据。

## 0. 三态判定口径（授权稿 §五 / 规格 §3.5）

| 状态 | 含义 | 本轮状态 |
|---|---|---|
| Build Passed | 成功生成 iPhoneOS 设备构建产物（静态校验 failed=0） | **Build Passed**（第四轮 run `44783839130` 元数据：iphoneos / Non-fat arm64 / MinOS 17.0 / Bundle ID `com.filterkit.manager`） |
| Package Passed | IPA/DEB 结构符合静态检查要求（对应校验摘要 failed=0） | **IPA Package Passed；DEB Package Failed**（第四轮：IPA p1/p2/p3 passed；DEB e1～e4 passed，e5 failed 系校验器 bsdtar 列格式误判，见 §3.4/§4.2；真机 DEB 打开闪退见 §3.4，不构成 Device Install 证据） |
| Device Install Passed | 真机安装、注册及启动成功 | **Device Install Pending**（R4-G 真机门禁，未授权；用户陈述 IPA 可启动、DEB 打开闪退，无 `.ips`/系统日志，待设备侧取证复核） |

## 1. 代码修改清单

### 1.1 新增文件

| 路径 | 批次 | 说明 |
|---|---|---|
| `scripts/collect-package-metadata.sh` | R4-E | 归集设备产物/IPA/DEB 路径、SHA256、平台/架构/Bundle ID/最低系统版本与三态标签，输出机器可读 JSON；缺工具链记 unavailable/Pending，不伪造通过值 |
| `Config/Signing/README.md` | R4-B | Developer 证书与 ldid 两路线区分；四条独立验证结论（工具可写 / 二进制包含 / RootHide 接受 / iOS 放行）；候选四枚 entitlement 清单边界 |
| `Config/DEB/README.md` | R4-D | control 字段草案口径、postinst 禁止事项、待 bootstrap 实测项 |
| `Tests/Stage2/evidence/r4-device-build/R4-A-to-E-authorization.md` | — | 本轮授权稿归档 |

### 1.2 修改文件

| 路径 | 批次 | 改动 |
|---|---|---|
| `.github/workflows/filterkit-build.yml` | R4-A～E | 新增 5 个 R4 job（见 §2）；`artifact` job 依赖补入 R4 链路，元数据归档补 `Config/`、`scripts/` |
| `Config/DEB/control` | R4-D | 去除 dpkg-deb 不接受的 `#` 注释行与空 `Depends:` 字段；保留 Package/Name/Version/Architecture/Maintainer/Section/Description 草案 |
| `scripts/package-deb.sh` | R4-D | 检查 `dpkg-deb --build` 退出码；打包失败清残缺包并 exit 1，不再误报"已生成" |
| `scripts/validate-entitlements.sh` | R4-B/E | 无 plutil 导致键名无法提取时，t2/t3 记 unavailable（不计 failed），与 t1 口径一致 |
| `Spec/Stage-2/Stage-2.4-D2-D7-PermissionProbe-Chain-Implementation-Record.md` | — | §5.14 回填本轮接线与演练记录；§5.15 回填 Runner 首轮失败诊断与修复 |
| `scripts/validate-device-build.sh` | R4-E 复验修复 | d3 去掉无法按标量解析的 `CFBundleSupportedPlatforms` 取值；裸变量 `$min_os` 改 `${min_os}`（Runner unbound variable 修复） |
| `scripts/package-ipa.sh` | R4-C 复验修复 | 告警行裸变量 `$STAGE` 改 `${STAGE}`（同类隐患） |
| `scripts/package-deb.sh` | R4-D 复验修复 | 两处裸变量 `$STAGE` 改 `${STAGE}`（同类隐患） |
| `.github/workflows/filterkit-build.yml` | R4-E 复验修复 | `package-validation` 归集步骤新增 `find_first()`，缺失 artifact 目录返回空路径并记 Pending，不再 find 非零中断归档 |
| `Tests/Stage2/evidence/r4-device-build/run-44758871580-round1-failure-diagnosis.md` | — | Runner 首轮（run 44758871580）两 job 失败根因、修复映射与待复验项归档 |
| `.github/workflows/filterkit-build.yml` | R4-A 复验修复（第二轮） | `device-build` 新增 Stage 步骤：上传前将 `.app` 暂存到 `build/device/FilterKit.app`；上传路径改暂存副本，收窄 artifact LCA，使下游 `find -maxdepth 4` 可在根层定位 `.app` |
| `Tests/Stage2/evidence/r4-device-build/run-44766814111-round2-failure-diagnosis.md` | — | Runner 第二轮（run 44766814111）`package-ipa`/`package-deb` 找不到 `.app` 的归档层级根因、修复映射与 RootHide/Rootless 产物版本口径归档 |
| `Config/DEB/control` | R4-D 第三轮修正 | Architecture `iphoneos-arm64` → `iphoneos-arm64e`；补 `Depends: firmware (>= 15.0)`（同机已装包对照口径，见 round3 诊断 §3） |
| `scripts/package-deb.sh` | R4-D 第三轮修正 | 默认产物名改 arm64e 档；`dpkg-deb --build` 追加 `--root-owner-group`（旧版降级告警）；注释写明 roothide rootfs 相对布局与属主口径 |
| `scripts/validate-deb.sh` | R4-D 第三轮修正 | e2 锁定 arm64e + firmware 依赖；e4 拦截 `var/jb/` rootless 前缀泄漏；新增 e5 数据包 root:root 属主校验 |
| `.github/workflows/filterkit-build.yml` | R4-D 第三轮修正 | `package-deb` 的 OUT_DEB/DEB_PATH/上传产物名三处同步 arm64e 档文件名 |
| `Tests/Stage2/evidence/r4-device-build/run-44772873717-round3-deb-roothide-diagnosis.md` | — | Runner 第三轮（run 44772873717）IPA/DEB 静态出包事实、真机 DEB 失败反馈、同机包对照、H1～H5 根因排序与修复映射归档 |
| `scripts/validate-deb.sh` | R4-D 第四轮修正 | e5 属主解析兼容 GNU tar（`owner/group` 单字段）与 macOS bsdtar（`owner group` 分列）；修复 Runner bsdtar 格式下把链接数 `0` 误判为属主的假 FAIL |
| `Tests/Stage2/evidence/r4-device-build/run-44783839130-round4-deb-crash-ownership-falsepositive.md` | — | Runner 第四轮（run 44783839130）e5 误判定性、IPA/DEB 离线结构对照、闪退 C1～C5 待证假设与真机取证清单归档 |
| `project.yml` | R4-D 第五轮修正 | `info.properties` 增补 `CFBundleShortVersionString: $(MARKETING_VERSION)`、`CFBundleVersion: $(CURRENT_PROJECT_VERSION)`；`MARKETING_VERSION` `0.0.1` → `0.1.0`，`CURRENT_PROJECT_VERSION=1`；修复文件型 Info.plist 缺版本键被 Xcode 回退默认 `1.0` 的漂移 |
| `Config/DEB/control` | R4-D 第五轮修正 | `Version: 0.0.1-1` → `0.1.0-1`，基线 `0.1.0` 与 App 营销版本一致 |
| `Config/DEB/README.md` | R4-D 第五轮修正 | 写明版本单一源口径（project.yml 营销版本/构建号 → App plist；control 基线 = 营销版本，修订号 `-1`）；示例文件名同步 `0.1.0-1` |
| `scripts/package-deb.sh` | R4-D2 快照回填 + 第五轮修正 | 档案/可执行位/Bundle ID/版本基线校验、ditto 暂存、强制 `--root-owner-group` fail-closed、产物名由 control Version 派生；预检打印两侧实际值，版本错误行附带构建号与 control 完整 Version |
| `scripts/validate-deb.sh` | R4-D2 快照回填 + 第五轮修正 | e1～e9 校验链（归档/身份版本/postinst 字节一致/rootfs 布局/root:root/可执行位/parity/Mach-O 切片/签名状态）；e2 OK/FAIL 行带 `AppVersion` 与 `ControlVersion` |
| `scripts/collect-package-metadata.sh` | R4-D2 快照回填 | 摘要归集 profile / packageArchitecture / minimumMachOArchitecture / signatureState；DEB 状态文案 `RootHide Package Layout Passed (Static)` |
| `.github/workflows/filterkit-build.yml` | R4-D2 快照回填 + 第五轮修正 | 权限保真 TAR 往返与解包恢复、BSD 兼容 find、`ARCHS=arm64 ONLY_ACTIVE_ARCH=NO`、e7 同源 parity、`REQUIRE_DEB_VALIDATION_TOOLS=1`；device-build 步骤打印 App 版本/构建号，package-deb 步骤打印 control Version/基线 |
| `Config/DEB/roothide.env` | R4-D2 快照回填 | `roothide-rootfs` 档案元数据单一源：Profile ID / 包架构 / 载荷相对路径 / 最低 Mach-O 切片 / 强制 root:root / 安装注册路径 |
| `scripts/compare-app-bundles.py` | R4-D2 快照回填 | 源 `.app` 与 DEB 解包 `.app` 逐文件 SHA256、Info.plist、符号链接目标与权限位 parity，不跟随符号链接 |
| `Spec/Stage-2/Stage-2.4-R4-D2-Implementation-Record.md` | R4-D2 快照回填 | R4-D2 档案/流水线优化设计记录（profile、打包脚本、e1～e9 校验、TAR 往返、parity 对照） |
| `Tests/Stage2/evidence/r4-device-build/run-44797390321-round5-version-mismatch-diagnosis.md` | — | Runner 第五轮（run 44797390321）App/DEB 版本不一致中止诊断、1.0 默认值成因、版本单一源修复映射与本地演练归档 |

### 1.3 未改动（冻结边界核对）

- 冻结 Models、`ReportEnvelope`、Adapter 七方法协议、Core 业务语义、`loaded`/`installed`/`configured` 语义：**未改**。
- RootHide / Rootless Adapter 独立：**未改**。
- 既有模拟器 CI（`app-build` / `ui-acceptance`）：**未改链路**；模拟器产物不作设备构建证据。
- 根 `control`、根 `Makefile`：**未改**（Stage 2.1 草稿占位）；`project.yml` 仅按第五轮版本单一源口径增补版本键与营销版本 `0.1.0`，B2 Deployment Target / B3 Bundle ID 仍未冻结。

## 2. CI Workflow 修改清单

工作流：`.github/workflows/filterkit-build.yml`（`workflow_dispatch` 手动触发，`macos-latest`）。

| Job | 批次 | 步骤 | 产物/证据 |
|---|---|---|---|
| `device-build` | R4-A | checkout → xcodegen → `xcodebuild -scheme FilterKit -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData-device CODE_SIGNING_ALLOWED=NO build` → 定位 `FilterKit.app` → `validate-device-build.sh` | `filterkit-device-build`：device-xcodebuild.log、device-build-validation.log、device-build-summary.json、设备 `.app` |
| `signing-prep` | R4-B | checkout → `validate-entitlements.sh`（静态格式 + 候选清单一致性） | `filterkit-signing-prep`：entitlements-validation.log、entitlements-summary.json、`Config/Signing/` |
| `package-ipa` | R4-C | 下载设备产物 → `package-ipa.sh`（未签名 Payload 结构包）→ `validate-ipa.sh` | `filterkit-ipa`：package-ipa.log、ipa-validation.log、ipa-summary.json、`FilterKit.ipa` |
| `package-deb` | R4-D | 确保 dpkg-deb → 下载设备产物 → `package-deb.sh` → `validate-deb.sh` | `filterkit-deb`：package-deb.log、deb-validation.log、deb-summary.json、`filterkit_0.1.0-1_iphoneos-arm64e.deb`（第三轮前为 arm64 命名，见 §3.3） |
| `package-validation` | R4-E | 下载四类产物 → `collect-package-metadata.sh` 归集 SHA256 与元数据 → JSON 可解码校验 | `filterkit-package-validation`：metadata-collection.log、package-metadata.json |

依赖关系：`device-build` needs `[build, isolation]`；`signing-prep` needs `[build]`；`package-ipa`/`package-deb` needs `[device-build]`；`package-validation` needs `[device-build, signing-prep, package-ipa, package-deb]`（`if: always()`）。R4 链路与模拟器链路并行独立，互不充当证据。

## 3. R4-A～E 原始 Runner 日志

### 3.1 首轮实跑（run `44758871580`，基线 commit `460a9906`，2026-11-20）

**状态：两个 job 失败，已出本地修复，待二次 Runner 复验。** 详细诊断见 `run-44758871580-round1-failure-diagnosis.md`。

- `device-build`（job run `cf32de97-24c8-5c03-a4c6-6b785983c806`）：macos-26-arm64 / macOS 26.7.2 / Xcode 26.6 / SDK iphoneos26.5；`xcodebuild ... CODE_SIGNING_ALLOWED=NO build` **BUILD SUCCEEDED**，产物 `Release-iphoneos/FilterKit.app`（Mach-O 64-bit arm64，3,294,752B，Info.plist 776B）；静态校验 d1/d2 通过后，d3 于 `validate-device-build.sh` line 86 报 `supported�: unbound variable` exit 1。**编译/链接未失败**，失败在产物静态校验脚本。
- `package-ipa` / `package-deb`：`needs: [device-build]`，上游失败被跳过，未产出 `filterkit-ipa` / `filterkit-deb` artifact。
- `package-validation`（job run `b89a24c6-aaba-5c6d-8146-3a79e908fc40`）：仅下载到 `filterkit-device-build`、`filterkit-signing-prep`、`filterkit-non-ui-build`、`filterkit-isolation` 四个产物；`find build/r4-artifacts/filterkit-ipa: No such file or directory`，`pipefail` 下 step exit 1；`collect-package-metadata.sh` 未执行，无 `package-metadata.json`。
- 首轮下载产物 digest（归档备查）：device-build `sha256:326da8596b95a1f5bc4099238b496bb74a05bd8eeb68dafa96ec7d1d717182e3`；signing-prep `1bacbda2…`；non-ui-build `974b5b12…`；isolation `24f9c4a2…`（完整值见诊断归档 §1）。

### 3.2 第二轮实跑（run `44766814111`，基线 commit `211365cb`，2026-11-20）

**状态：两个打包 job 失败，已出本地修复，待下一轮 Runner 复验。** 详细诊断见 `run-44766814111-round2-failure-diagnosis.md`。

- `package-ipa`（job run `614a21ed-12d8-59f5-9f6e-abe3021a8644`）：下载 `filterkit-device-build`（ID `14645672385`，901,844B，digest `sha256:ae0b5ef2ec442da985fba859bae1f7e955321bd5c4dbc2afb15bffa08ce02fb7`）成功；`find build/device-artifact -name 'FilterKit.app' -maxdepth 4` 返回空，`::error::device app missing from filterkit-device-build artifact` exit 1；`filterkit-ipa` No files found。
- `package-deb`（job run `67d8538d-43e0-5221-9e6e-3fd7812f6e54`）：`brew install dpkg` 1.23.11（gpatch 2.8.1 / libmd 1.3.0），`dpkg-deb` 可用；同一设备产物下载成功；同一 find 落空 exit 1；`filterkit-deb` No files found。
- 根因：`device-build` 上传路径分处 `build/device/`（日志）与 `build/DerivedData-device/.../FilterKit.app`；v7 取 LCA `build/` 归档，下载后 `.app` 在第 5 层，`maxdepth 4` 命不中。修复为上传前暂存 `.app` 到 `build/device/FilterKit.app`，artifact 内位于根层。
- 本轮未提供 `device-build` job 日志；其 d1～d6 校验结果与归档条目清单待下一轮 Runner 证据回填。

### 3.3 第三轮实跑（run `44772873717`，基线 commit `128f4c10d7f821bddafcdb152b14892e2d45c92e`，2026-11-20）

**状态：离线链路出包并通过静态校验；真机 DEB 安装失败，待设备侧报错原文复核。** 详细诊断见 `run-44772873717-round3-deb-roothide-diagnosis.md`。

- 元数据（`package-validation`，2026-11-20T16:34:49Z，runner `GitHub Actions 1000001134`）：设备 `.app` **Build Passed**（iphoneos / Non-fat arm64 / MinOS 17.0 / Bundle ID `com.filterkit.manager`）；IPA **Package Passed**，sha256 `a198e9278c9c044cf195bd20b7f23934f2d9af489c83afeb1cd6a97112e00b5b`；DEB **Package Passed（静态口径）**，路径 `filterkit_0.1.0-1_iphoneos-arm64.deb`，sha256 `2c059442584c76847d1d10367bf5dfe87bbe8cdebba73ba690592123079ae1d0`；entitlements 静态 Passed；`deviceInstall` 仍 Pending。
- 第二轮归档层级修复在本轮生效：`.app` 位于下载根层，两个打包 job 均定位成功出包。
- 真机反馈（用户陈述）：IPA 已在真机安装成功；DEB 经 RootHide 隐根转换后安装失败。日志包内无真机转换/dpkg 报错原文；5 张截图为 `gui-preview` 合成信封，不作扫描/权限证据。
- 同机已装包对照（0.1.18 设备报告，只读归档）：366 包中二进制档 83 个全部 `iphoneos-arm64e`、`iphoneos-arm64` 为 0；五个已装 App 包 control 均为 arm64e + `Depends: firmware (>= 15.0)`，数据归档为 rootfs 相对 `/Applications/*.app` 布局。
- 本轮离线修复（H1 架构档 / H2 firmware 依赖 / H3 属主 root:root）见 §1.2；H4 二进制切片/签名/弱链接、H5 uicache 行为未闭环，仍属 R4-A/R4-G 门禁。

### 3.4 第四轮实跑（run `44783839130`，基线 commit `e02da08362755670470c876beee00f3bb21d5da0`，2026-11-20）

**状态：设备 Build Passed、IPA Package Passed；DEB 仅 e5 校验失败（定性为校验器列格式误判，产物属主实为 root:root）；真机 DEB 打开闪退，待 `.ips` 取证。** 详细诊断见 `run-44783839130-round4-deb-crash-ownership-falsepositive.md`。

- 元数据（`package-validation`，2026-11-20T17:37:30Z，runner `GitHub Actions 1000001146`）：设备 `.app` **Build Passed**（iphoneos / Non-fat arm64 / MinOS 17.0 / Bundle ID `com.filterkit.manager`）；IPA **Package Passed**，内包 sha256 `68b96cf71a5c15076804f8a9a503a71d98d7d210f1728ef84cb4b0ca35f6e8b5`；DEB **Package Failed**，路径 `filterkit_0.1.0-1_iphoneos-arm64e.deb`，内包 sha256 `d1b61b267936abb6d03fa226c2d9f294526bd5a41a277d6a9b551c199083acf2`；entitlements 静态 Passed；`deviceInstall` 仍 Pending。
- DEB 摘要：e1/e2/e3/e4 passed，**e5 failed**。e2 解出 `Architecture=iphoneos-arm64e Depends=firmware (>= 15.0)`（第三轮 H1/H2 修复在 Runner 生效）；e5 列出条目均为 `0 root root`（bsdtar 分列格式），产物属主实为 root:root，失败系原 awk 按 GNU tar 单字段取 `$2`（链接数 `0`）误判，已本地修复双格式解析。
- 工具链：macos-26-arm64 image `20261117.0516.1` / macOS 26.7.2 / Xcode 26.6 / Swift 6.3.3 / dpkg 1.23.12；全量 Swift 测试 0 failures、S1-05 15 tests 0 failures、隔离七项 passed、XCUITest All tests passed。
- 真机反馈（用户陈述）：同一版本 IPA 安装后可正常启动；DEB 安装后打开闪退。日志包内无 `.ips`、无 amfid/SpringBoard/runningboardd/dyld 系统日志；闪退终止原因待设备侧补采。
- 离线结构对照：IPA 与 DEB 包装同一未签名 `.app`；CI 构建 `CODE_SIGNING_ALLOWED=NO`，entitlement 仅静态 plist 校验、未嵌入二进制签名页；DEB data tar 仅 5 条目（二进制 3,294,752B / Info.plist 776B / PkgInfo 8B），未见 Frameworks/PlugIns/`_CodeSignature`。闪退 C1 签名封印 / C2 切片链接 / C3 布局注册 / C4 完整性 / C5 自身异常五类假设待 `.ips` 复核（见诊断 §5）。

### 3.5 第五轮实跑（run `44797390321`，基线 commit `a0cc234f1f8948a901d9b959a01cc705228b10f3`，2026-11-21）

**状态：TAR 权限保真链路生效；DEB 打包在前置版本一致性校验中止（App `1.0` vs control 基线 `0.0.1`），e1～e9 尚未到达。** 详细诊断见 `run-44797390321-round5-version-mismatch-diagnosis.md`。

- 笔记原文事实：Runner macOS 26 ARM64 / dpkg-deb 1.23.12；Artifact 下载通过；TAR 解包通过；主程序执行位保留（`-rwxr-xr-x 755 build/device-restored/FilterKit.app/FilterKit`，`Restored App Bundle: build/device-restored/FilterKit.app`）；失败原文 `App version=1.0 does not match control Version base=0.0.1`，`Process completed with exit code 1`；本轮 `filterkit-deb` artifact 约 209 字节，为失败日志，非可安装包。
- 根因（离线分级）：R1 版本校验 fail-closed 拦截漂移（行为正确，未删除）；R2 文件型 Info.plist 未显式携带版本键，Xcode 缺键回退默认 `1.0`，`MARKETING_VERSION` 未回填；R3 control 基线沿用旧工程占位 `0.0.1`，活跃源码口径已是 `0.1.0`。
- 修复（本地）：`project.yml` 增补 `CFBundleShortVersionString=$(MARKETING_VERSION)` / `CFBundleVersion=$(CURRENT_PROJECT_VERSION)`，营销版本 `0.1.0`、构建号 `1`；control `Version: 0.1.0-1`；预检在 device-build / package-deb / 打包脚本三处打印两侧实际值；e2 摘要带 AppVersion/ControlVersion。
- 原始 `job-logs.txt` 签名链接过期未取回；本轮事实按用户笔记与 R4-D2 快照源码转录，待下一轮 Runner 日志复核。

### 3.6 待下一轮 Runner 复验回填

- `device-build`：确认生成 Info.plist 实测 `CFBundleShortVersionString=0.1.0`、`CFBundleVersion=1`；
- `package-deb`：版本/Bundle ID 校验通过并正常出包；e1～e7 在真实 App 内容上 passed，e8/e9 以 Runner macOS 工具链实测；回填新内包 SHA256；
- `device-build` / `signing-prep` / `package-ipa` / `package-validation`：summary 与元数据 JSON（Runner ID、Commit SHA、工具链版本、四类产物 SHA256）随下一轮证据归档。

## 4. IPA / DEB 结构检查报告

### 4.1 本地占位桩演练（Linux，非设备产物，仅验证脚本链路）

> 演练用 `/tmp` 下占位 `.app`（文本占位二进制 + 占位 Info.plist），不入库、不作证据。

| 校验器 | 检查项 | 本地结果 | 说明 |
|---|---|---|---|
| `validate-ipa.sh` | p1 IPA 为 zip 归档 | passed | 占位包 1015 bytes，zip 可读 |
| `validate-ipa.sh` | p2 `Payload/FilterKit.app/` 结构 | passed | 归档内路径匹配 |
| `validate-ipa.sh` | p3 设备产物静态校验 | **failed（预期内）** | 占位二进制为 ASCII text，非 Mach-O；平台/架构/Bundle ID 因无 plutil/lipo 记 unavailable |
| `validate-deb.sh` | e1 DEB 归档可读 | passed | dpkg-deb 可读 |
| `validate-deb.sh` | e2 control 字段与 RootHide 口径 | passed（正向桩）/ failed（反向旧 control） | Architecture 必须 `iphoneos-arm64e`、Depends 必须含 `firmware`；旧 arm64/无依赖样例两项 FAIL |
| `validate-deb.sh` | e3 postinst 注册-only | passed | 未见越界写/删/移/后台/权限动作 |
| `validate-deb.sh` | e4 `Applications/FilterKit.app` 存在（rootfs 相对布局） | passed（正向桩）/ failed（反向 rootless 前缀） | 拦截 `var/jb/` 前缀泄漏 |
| `validate-deb.sh` | e5 数据包属主 root:root | passed（`--root-owner-group`）/ failed（无属主参数样例） | 兼容 GNU tar `owner/group` 单字段与 bsdtar `owner group` 分列；owner/group 接受 `root` 或 `0` |
| `validate-deb.sh` | e6 `CFBundleExecutable` 存在且可执行 | passed（正向桩） | 占位二进制已置 `755`；执行位缺失反向样例记 failed |
| `validate-deb.sh` | e7 源 `.app` 与 DEB 包 parity | passed（`equal=true`，无 mismatch） | `compare-app-bundles.py`：Info.plist、逐文件 SHA256、符号链接目标、权限位；不跟随符号链接 |
| `validate-deb.sh` | e8 Mach-O 含 arm64 切片 | unavailable（Linux 无 lipo） | 切片一致性独立于 control 架构档；Runner macOS 工具链实测 |
| `validate-deb.sh` | e9 代码签名状态 | unavailable（Linux 无 codesign） | 仅报告状态，签名状态不视同可安装放行 |
| `package-deb.sh` | 打包前置版本/Bundle ID 校验 | 正向 exit 0；反向三种 exit 1 | 正向 App `0.1.0`/build `1` 对 control `0.1.0-1`；反向 App `1.0`、App `0.0.1`、Bundle ID `com.other.manager` 均退出 1，错误行打印两侧实际值 |

### 4.2 Runner 实测（静态口径）与待回填项

- 第三轮 Runner：IPA p1/p2/p3 全 passed；DEB e1～e4 全 passed（旧脚本口径，尚无 e5）；设备 d1～d6 全 passed。
- 第四轮 Runner：IPA p1/p2/p3 全 passed；设备 d1～d6 全 passed；DEB e1～e4 passed，e5 在 bsdtar 格式下误判 failed（产物实为 root:root），本地已修双格式解析，待下一轮复验 e1～e5 全 passed。
- 第五轮 Runner：TAR 权限保真链路生效（解包成功、执行位保留）；DEB 在打包前置版本校验中止（App `1.0` vs control 基线 `0.0.1`），未到达 e1～e9；本地已统一版本源（App `0.1.0`/build `1` ↔ control `0.1.0-1`），待下一轮复验版本校验通过并出包。
- IPA/DEB 离线对照：两者包装同一未签名 `.app`；包内二进制 sha256、Info.plist、Frameworks/PlugIns、资源、`_CodeSignature`、entitlement 封印状态的逐文件对比待真机解包取证（诊断 §7 清单）。
- 真机安装/注册/启动与权限取证属 R4-G，不在本节静态口径内。

## 5. 架构 / 平台 / Deployment Target 检查结果（草案值，待 Runner 实测）

| 项 | 草案/工程值 | 本轮判定 | 待核实 |
|---|---|---|---|
| 平台 | 目标 `iphoneos`（d3 以 `DTPlatformName=iphoneos` 为准；`CFBundleSupportedPlatforms` 系数组，不作标量判定） | 第三轮 Runner 实测 `iphoneos` Passed | 模拟器 `iPhoneSimulator` 产物不得计入 |
| 架构 | 设备二进制第三轮实测 Non-fat `arm64`；DEB control 目标档 `iphoneos-arm64e`（同机对照口径） | 二进制切片与 control 目标架构**一致性待闭环** | arm64e 切片/弱链接 libroothide/roothide rpath 属 R4-A 设备构建与链接门禁；不为凑口径在打包层伪造 arm64e 切片 |
| Bundle ID | `com.filterkit.manager`（B3 草案，未冻结） | 第三轮 Runner 实测 `com.filterkit.manager` | B3 冻结前按草案沿用 |
| Deployment Target | `project.yml` iOS 17.0（B2 草案）；根 Makefile 草案 15.0 | 产物 `MinimumOSVersion=17.0`（第三轮实测） | 设备/框架/SDK 兼容交集；16.5 SDK 对 iOS 17.0.2 向下兼容待实测 |
| 最低系统版本 | 以产物 `MinimumOSVersion` 为准 | 第三轮实测 `17.0` | 与设备 iOS 17.0.2 兼容性待 R4-G 实测 |

## 6. SHA256 与构建元数据

- 元数据脚本：`scripts/collect-package-metadata.sh`；输出字段：`stage` / `generatedAt` / `commitSha` / `runner{os,name,runId}` / `deviceBuild{appPath,platform,architecture,bundleId,minimumOsVersion,status}` / `packages{ipa,deb{path,sha256,status}}` / `entitlements{path,status}` / `deviceInstall{status,note}` / `validation{...摘要}` / `limitations`。
- 本地空输入演练：JSON 可解码，`deviceBuild.status=Build Pending`、`ipa/deb=Package Pending`、`deviceInstall.status=Device Install Pending`；占位演练产物哈希仅在 `/tmp`，不入库、不归档。
- 第三轮 Runner 已回填：IPA sha256 `a198e9278c9c044cf195bd20b7f23934f2d9af489c83afeb1cd6a97112e00b5b`；DEB（旧 arm64 口径）sha256 `2c059442584c76847d1d10367bf5dfe87bbe8cdebba73ba690592123079ae1d0`；runId `44772873717`；runner `GitHub Actions 1000001134`。
- 第四轮 Runner 已回填（runId `44783839130`，runner `GitHub Actions 1000001146`，commit `e02da083`）：IPA 内包 sha256 `68b96cf71a5c15076804f8a9a503a71d98d7d210f1728ef84cb4b0ca35f6e8b5`；DEB 内包 sha256 `d1b61b267936abb6d03fa226c2d9f294526bd5a41a277d6a9b551c199083acf2`（Package Failed，e5 误判）；上传归档 digest：device-build `c9a097c1…`、deb `ca0e6c3e…`、ipa `b4cc5876…`（完整值见诊断 §1）。
- 第五轮 Runner（runId `44797390321`，commit `a0cc234f`）：DEB 未出包，artifact 约 209B 为失败日志，无内包 SHA256；版本基线本轮已统一为 App `0.1.0`/build `1` ↔ control `0.1.0-1`。
- **Runner 待回填**：版本修复复验通过后的新 DEB 包 SHA256、设备 `.app` 产物哈希；元数据 JSON 存 `filterkit-package-validation` artifact。

## 7. 未通过项目与技术限制

### 7.1 本轮未通过 / 未取得

- Runner 首轮（run 44758871580）`device-build` 编译成功但静态校验脚本 d3 中断（裸变量紧邻全角字符，`set -u` unbound variable）；`package-ipa`/`package-deb` 被跳过；`package-validation` 因 find 缺失目录非零退出未产出元数据 JSON。本地修复已落盘，**待二次 Runner 复验**。
- Runner 第二轮（run 44766814111，commit `211365cb`）：设备产物已能上传，但 `package-ipa`/`package-deb` 下载后按 `maxdepth 4` 定位不到 `.app`（归档 LCA 收窄前 `.app` 在第 5 层），两个打包 job 中断、无 IPA/DEB 产物。本地修复为上传前暂存 `.app` 到证据目录根层。
- Runner 第三轮（run `44772873717`，commit `128f4c10`）：归档层级修复生效，设备 Build Passed、IPA/DEB 静态 Package Passed；但真机侧 DEB 经隐根转换后安装失败。离线对照定位 H1 架构档 / H2 firmware 依赖 / H3 属主三项打包口径问题并已本地修复，**待下一轮 Runner 复验 e1～e5**；真机失败报错原文待设备侧补采。
- Runner 第四轮（run `44783839130`，commit `e02da083`）：H1/H2 修复在 Runner 生效（arm64e + firmware）；DEB e5 失败经定性为校验器 bsdtar 列格式误判（产物属主实为 root:root），本地已修双格式解析，**待下一轮 Runner 复验 e1～e5**。真机侧 DEB 打开闪退：无 `.ips`/系统日志，C1 签名封印 / C2 切片链接 / C3 布局注册 / C4 完整性 / C5 自身异常五类假设待设备侧取证复核。
- Runner 第五轮（run `44797390321`，commit `a0cc234f`）：TAR 权限保真链路生效；DEB 打包前置版本校验中止——App `CFBundleShortVersionString=1.0`（文件型 Info.plist 缺版本键，Xcode 回退默认值）vs control 基线 `0.0.1`。本地已统一版本源至 App `0.1.0`/build `1` ↔ control `0.1.0-1`，**待下一轮 Runner 复验 plist 实测版本与出包**；本轮原始 job-logs 票据过期未取回，部分事实按用户笔记转录。
- 设备二进制为 Non-fat `arm64`，与 DEB control 目标档 `iphoneos-arm64e` 的切片一致性未闭环（H4）。
- 未执行任何真机安装、注册、启动的受控取证；Device Install Pending（R4-G 未授权）。用户陈述 IPA 已装上、DEB 转换后失败，属真机反馈，不计入离线门禁证据。
- 未做真实设备签名放行验证；未确认 Developer 证书 / ldid 路线绑定。

### 7.2 技术限制（离线口径）

- 本机 Linux 无 Xcode/Swift/plutil/lipo/ldid；相关检查在本机记 unavailable，结论以 Runner 日志为准。
- entitlement 写入文件 ≠ 权限获得；签名中存在某键 ≠ 运行时放行；runtime entitlement 沿用 R1-B 结论保持 unavailable/unknown。
- DEB Architecture/Depends/属主口径已按同机已装包对照修正（arm64e + `firmware (>= 15.0)` + root:root）；`/Applications` 到 JBROOT 的实际映射、uicache 命令可用性与参数、二进制切片/签名/弱链接仍待目标 RootHide Bootstrap 与 R4-G 真机实测。
- 16.5 SDK 对 iOS 17.0.2 向下兼容待实测。
- R4-E 通过仅证明包符合部署要求，**不代表 RootHide 真机权限通过**；不证明真实加载或 `jbroot()` 可调用。

### 7.3 禁止事项遵守核对

未真机安装；未 Bootstrap 部署；未真实设备签名放行验证；未调用 `jbroot()` 真机 API；未改插件文件或注入配置；未插件启停/删除/移动/安装；未 dpkg 写操作；未进入 R4-G；未进入 0.1-E-B。

## 8. DevDocs 压缩包与完整性

- 打包规则：排除 `.git/`、小写 `research/`、`node_modules/`、`build/`、`.theos/`、`DerivedData/`、`.build/`、`.swiftpm/`、`*.xcodeproj/`、`*.xcworkspace/`、`.tmp/`、`.DS_Store`、`*.zip`、`App/Info.plist`、`*.xcresult/`、`__pycache__/`、`*.pyc`；大写 `Research/` 保留，仅排除 `Research/Validation/evidence/0.1.18-device-report.json`。
- 本轮包（R4 第五轮版本单一源修复 + R4-D2 快照打包实现回填后重打，基线提交 `a868804`）：**2042 个文件**（含包内 `PACKAGE-NOTE.md`）；`unzip -tq` 无错误；包内清单与暂存目录逐文件 `diff` 一致（2042 = 2042）；排除项泄漏扫描无命中（`reference/0.1.18-src/FilterKit-Info.plist` 为上游参考源码，不在 `App/Info.plist` 排除范围）。压缩包大小与 SHA256 以交付附件复算值为准（包内不内嵌自身哈希，避免自引用）。

## 9. 下一步（待授权）

1. 下一轮 Runner 复验版本单一源修复：device-build 日志确认 App `0.1.0`/build `1`，DEB 正常出包且 e1～e7 passed（e8/e9 按 macOS 工具链实测），回填新包 SHA256 与 control 实测字段；同时复验 e5 双格式解析。设备侧补采闪退 `.ips`（Exception Type / Termination Reason / Crashed Thread / Code Signing / Library not loaded / Namespace DYLD）与 IPA/DEB 解包对比、落盘权限、系统日志，复核 C1～C5 假设排序。
2. Runner 调度 R4-A～E 离线链路，回填 §3/§4.2/§5/§6 证据，按摘要 failed 计数重算 Build/Package 状态。
3. R4-F 部署文档（安装/启动/卸载/回滚/证据导出，命令路径标注待 bootstrap 实测）——本轮未在授权范围。
4. R4-G 真机启动冒烟 8 项：**须单独授权**，在离线包校验通过、真机与 GUI 上下文就位后执行。
5. R3-B～E 真机权限取证、0.1-C G10 补证、0.1-D Final、0.1-E-A/B 维持既有顺序与门禁。

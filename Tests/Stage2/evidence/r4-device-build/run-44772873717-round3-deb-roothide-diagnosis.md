# R4-A～E Runner 第三轮实跑诊断 + DEB RootHide 隐根口径修复（run 44772873717，2026-11-20）

> 范围：0.1-D-R4-A～E 离线设备构建/打包/静态校验；不涉及 R4-G 真机冒烟、不涉及 0.1-E-B 发布验收。
> 证据来源：用户上传日志包 `logs_121188178789.zip`（Runner CI 日志，非真机安装日志）+ 5 张真机 GUI 截图 + 本地归档只读证据 `Research/Validation/evidence/0.1.18-device-report.json` + 参考源码 `reference/0.1.18-src/`。
> Runner 检出基线 commit `128f4c10d7f821bddafcdb152b14892e2d45c92e`（该对象不在本地仓库与 `origin/main` 中；本轮事实按日志原文转录，不据本地树反推 Runner 内容）。

## 1. 第三轮 Runner 实跑结果（日志原文）

元数据（`package-validation` 步骤，2026-11-20T16:34:49Z，runner `GitHub Actions 1000001134`，runId `44772873717`）：

| 产物 | 路径 | SHA256 | 状态（静态口径） |
|---|---|---|---|
| 设备 `.app` | `build/r4-artifacts/filterkit-device-build/FilterKit.app` | — | **Build Passed**；platform `iphoneos`；二进制 Non-fat `arm64`；Bundle ID `com.filterkit.manager`；MinimumOSVersion `17.0` |
| IPA | `build/r4-artifacts/filterkit-ipa/FilterKit.ipa` | `a198e9278c9c044cf195bd20b7f23934f2d9af489c83afeb1cd6a97112e00b5b` | **Package Passed**（p1/p2/p3 全 passed） |
| DEB | `build/r4-artifacts/filterkit-deb/filterkit_0.1.0-1_iphoneos-arm64.deb` | `2c059442584c76847d1d10367bf5dfe87bbe8cdebba73ba690592123079ae1d0` | **Package Passed**（e1～e4 全 passed，仅静态结构口径） |
| entitlements | `Config/Signing/FilterKit.entitlements` | — | Entitlements Static Passed |
| 真机安装 | — | — | **Device Install Pending**（R4-G 未授权） |

- 第二轮归档层级修复在本轮 Runner 生效：`.app` 位于下载根层，`package-ipa` / `package-deb` 均定位成功并出包。
- `package-deb` 打包步骤原文告警：`dpkg-deb: warning: root directory .../Package has unusual owner or group 501:20`，并提示 `you might need to pass --root-owner-group`（打包机宿主 uid/gid 进入数据包）。
- `package-deb` 步骤使用 `brew install dpkg` 1.23.11（gpatch 2.8.1 / libmd 1.3.0）。

## 2. 真机侧反馈（用户陈述 + 截图）

- 用户陈述：**IPA 产物已在真机安装成功**；**DEB 产物 `filterkit_0.1.0-1_iphoneos-arm64.deb` 在 RootHide 环境经隐根（shadow-root）转换后安装失败**。
- 5 张截图为 GUI 合成预览信封（WARNING `PREVIEW-001`：Synthetic preview report; not a device scan · `gui-preview`）：界面环境卡片显示 RootHide / iOS 17.0.2 / arm64e / JBROOT `/private/var/jb`，Permission 仍 Undetermined、Probes No probe evidence。**截图内容属预览数据，不作为真机扫描或权限证据**；其中 ellekit 版本显示 `1.0.0` 与设备报告 `1.2-3` 不一致，同样以预览信封口径看待。
- 日志包内**没有真机安装/转换失败的报错原文**（无 dpkg 输出、无转换器日志、无 exit code）。失败的确切阶段与报错串待真机侧补采；本轮根因按"离线可得证据 + 同机已装包对照"排序，不把假设写成已证实结论。

## 3. 同机已装包对照（0.1.18 设备报告，只读归档）

设备：iOS 17.0.2 / iPhone16,2 / RootHide / ellekit 1.2-3，JBROOT `/private/var/containers/Bundle/Application/.jbroot-9C414BB7D5DCECC4`。

### 3.1 控制字段 Architecture 分布（366 包）

| Architecture | 包数 |
|---|---|
| `iphoneos-arm64e` | 83 |
| `all` | 283 |
| `iphoneos-arm64` | **0** |

本机 RootHide dpkg 库中**不存在** `iphoneos-arm64` 二进制包；二进制档统一声明 `iphoneos-arm64e`。

### 3.2 已安装 App 包 control 对照

| 包 | Architecture | Depends | 数据归档路径（.list 口径） |
|---|---|---|---|
| `cn.zqbb.jailfools` 5.2.3 | `iphoneos-arm64e` | `firmware (>= 15.0)` | `/Applications/*.app` |
| `com.filterkit.manager` 0.1.18（旧版，同 Bundle ID，安装成功） | `iphoneos-arm64e` | `firmware (>= 15.0)` | `/Applications/FilterKit.app/...` |
| `com.roothide.manager` 1.4.1 | `iphoneos-arm64e` | `firmware (>= 15.0)` | `/Applications/RootHide.app/...` |
| `com.tigisoftware.filza64bit` 5.0.1-3 | `iphoneos-arm64e` | `firmware (>= 15.0)` | `/Applications/Filza.app/...` |
| `org.coolstar.sileo` 2.5.1-15 | `iphoneos-arm64e` | `firmware (>= 11.0), firmware (>= 12.2), …` | `/Applications/Sileo.app/...` |

### 3.3 路径布局结论

- 已装 App 包在 dpkg `.list` 中均为 **rootfs 相对路径**（`/Applications/<App>.app/...`），安装时由 roothide 安装层映射进隐藏 JBROOT 容器；**不**使用普通 rootless 档的 `var/jb/` 前缀。
- 本轮修复保持 `Applications/FilterKit.app` 根层布局，**不加** `var/jb/` 前缀（那是 rootless 布局，套到 roothide 会错位）。

## 4. 失败根因排序（假设，待真机报错原文复核）

| # | 假设 | 证据 | 本轮处置 |
|---|---|---|---|
| H1 | **Architecture 档不匹配**：control 声明 `iphoneos-arm64`，而本机 RootHide 二进制档为 `iphoneos-arm64e`，库中 `iphoneos-arm64` 包数为 0；隐根转换/安装层按架构过滤时拒绝 | §3.1/§3.2；旧版同 Bundle ID 成功包为 arm64e | control Architecture 改 `iphoneos-arm64e`；校验器 e2 锁定该口径 |
| H2 | **缺 firmware 基线依赖**：已装 App 包均声明 `Depends: firmware (>= 15.0)`；原 control 无 Depends 字段 | §3.2；参考源码 `reference/0.1.18-src/control` 同口径 | control 补 `Depends: firmware (>= 15.0)`；e2 校验 firmware 声明 |
| H3 | **数据包属主非 root**：打包机宿主 `501:20` 进入 data tar；Theos/root 构建的包条目为 root:root；roothide 安装/转换层可能在属主修正或校验环节失败 | 本轮 `package-deb` 日志 owner/group 501:20 告警与 dpkg-deb 官方 hint | `dpkg-deb --build --root-owner-group` 强制 root:root；新增 e5 属主校验 |
| H4 | 二进制切片/签名/弱链接不满足 roothide 运行要求：Runner 产物为 Non-fat `arm64`（非 arm64e）、未签名、未弱链接 libroothide、无 roothide rpath | 元数据 architecture 字段；参考 Makefile roothide `ARCHS=arm64e`、`-weak-lroothide`、rpath `@loader_path/.jbroot/usr/lib` | **本轮不动**：属 R4-A 设备构建/链接与 R4-G 签名放行门禁，DEB 打包层不伪造 arm64e 切片或签名；列为待闭环缺口 |
| H5 | postinst uicache 路径/行为在目标 bootstrap 不符 | 规格 §5 既有待实测项 | 本轮不改脚本动作；`/Applications/FilterKit.app` 与 §3.3 rootfs 相对布局一致，uicache 实际行为待 R4-G 真机取证 |

> 注意：H1～H3 为离线证据支持的打包口径修正；H4/H5 未在本轮闭环。真机转换失败的确切报错串仍须从设备侧（Sileo/Zebra/dpkg 输出或转换器日志）补采后复核根因排序。

## 5. 本轮修复（本地，待下一轮 Runner 复验）

| 文件 | 改动 | 对应假设 |
|---|---|---|
| `Config/DEB/control` | `Architecture: iphoneos-arm64` → `iphoneos-arm64e`；新增 `Depends: firmware (>= 15.0)`；Package/Name/Version/Maintainer/Section/Description 不变 | H1、H2 |
| `scripts/package-deb.sh` | 默认产物名改 `filterkit_0.1.0-1_iphoneos-arm64e.deb`；`dpkg-deb --build` 追加 `--root-owner-group`（先探测 `dpkg-deb --help` 支持，旧版降级告警）；头注释写明 roothide rootfs 相对布局、arm64e 口径与属主口径 | H1、H3 |
| `scripts/validate-deb.sh` | e2 升级为"字段齐全 + RootHide 口径"：Architecture 必须 `iphoneos-arm64e`、Depends 必须含 `firmware`；e4 增加 rootless `var/jb/` 前缀泄漏检查；新增 e5 数据包条目属主/属组必须 root:root（`0/0` 或 `root/root`） | H1、H2、H3 |
| `.github/workflows/filterkit-build.yml` | `package-deb` 的 `OUT_DEB` / `DEB_PATH` / 上传产物名三处同步为 `filterkit_0.1.0-1_iphoneos-arm64e.deb`；`package-validation` 按 `*.deb` glob 归集，无需改 | H1 |

## 6. 本地静态演练（Linux dpkg-deb 1.21.1，非设备证据）

- `bash -n`：`package-deb.sh` / `validate-deb.sh` 通过；workflow YAML 解析良构（12 jobs）。
- 正向（`/tmp` 占位 `.app`）：e1～e5 全 passed，`failed=0`；control 解出 `Architecture=iphoneos-arm64e`、`Depends=firmware (>= 15.0)`；data tar 条目全部 `root/root`；路径 `Applications/FilterKit.app`，无 `var/jb/` 前缀；打包步骤无 owner/group 告警。
- 反向模拟：
  - 旧 control（arm64、无 Depends）→ e2 两项 FAIL（架构不符、缺 firmware）；
  - rootless 布局（`var/jb/Applications/FilterKit.app`）→ e4 FAIL（前缀泄漏）；
  - 不带 `--root-owner-group` 打包 → e5 FAIL（非 root:root 条目）。
- 本机无 xcodebuild/swift/plutil/lipo/ldid；arm64e 切片、签名、entitlement 放行、uicache 行为均以 Runner/真机证据为准。

## 7. 修复后仍 Pending / 未闭环项

- 下一轮 Runner 复验：`package-deb` 产出 arm64e 命名 DEB、e1～e5 全 passed；元数据 JSON 回填新 SHA256 / Commit SHA / Runner ID。
- 真机侧补采：隐根转换器与 dpkg 的失败报错原文、exit code、失败阶段（解包/属主/架构校验/脚本执行/注册）。
- H4 缺口：设备二进制 Non-fat `arm64` 与 control 目标 `arm64e` 的切片一致性；是否需要 arm64e 切片、弱链接 libroothide、roothide rpath；未签名二进制在 roothide 安装层的接受度；entitlement 四枚候选的签名链放行。
- H5 缺口：postinst `uicache -p /Applications/FilterKit.app` 在目标 bootstrap 的可用性与参数；`/Applications` 到 JBROOT 的实际映射。
- 既有未决项不变：部署形态 A/B/C/B+C、Bundle ID（B3）、Deployment Target（B2）、签名路线、16.5 SDK 对 iOS 17.0.2 兼容、GUI 进程内 `jbroot()` 符号可解析性；`OwnershipResolver` 未迁移、`loaded` 恒 unknown、`permission.decision` 恒 undetermined、pluginID 0.2.0、PARSE-009-B。

## 8. 冻结边界核对

未改冻结 Models、`ReportEnvelope`、Adapter 七方法协议、Core 业务语义、Plist Parser 语义、Stage1 fixtures；未改 `loaded`/`installed`/`configured` 语义；未触真机写操作、插件启停、dylib 删移、dpkg 写、注入规则、entitlement/签名放行、常驻 daemon；未新增 jbroot() C 桥接声明/弱链接/dlsym/伪造符号；未进 R4-G、未进 0.1-E-B。

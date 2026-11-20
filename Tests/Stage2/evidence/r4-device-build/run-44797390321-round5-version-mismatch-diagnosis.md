# R4-A～E Runner 第五轮实跑诊断：App/DEB 版本不一致导致打包中止（run 44797390321，2026-11-21）

> 范围：0.1-D-R4-A～E 离线设备构建/打包/静态校验；不涉及 R4-G 真机冒烟、不涉及 0.1-E-B 发布验收。
> 证据来源：用户上传现象分析笔记（`这轮 Runner 有明显进展…md`）+ 用户上传 R4-D2 DevDocs 快照（`FilterKit-DevDocs-0.1-R4-D2.zip`，对应 Runner 检出基线）。原始 `job-logs.txt` 签名链接已过期，`web.fetch` 未取回；本轮事实按笔记原文与快照源码转录，不据本地树反推 Runner 未记录环节。
> Runner 检出基线 commit `a0cc234f1f8948a901d9b959a01cc705228b10f3`（该对象不在本地仓库与 `origin/main` 中）。

## 1. 第五轮 Runner 实跑结果（笔记原文）

| 项目 | 结果 |
|---|---|
| Runner | macOS 26 ARM64 |
| dpkg-deb | 1.23.12 |
| Run ID | `44797390321` |
| Checkout SHA | `a0cc234f1f8948a901d9b959a01cc705228b10f3` |
| Artifact 下载 | 通过 |
| TAR 解包 | 通过（权限保真 TAR 往返） |
| 主程序执行权限 | 通过（`-rwxr-xr-x 755 build/device-restored/FilterKit.app/FilterKit`；`Restored App Bundle: build/device-restored/FilterKit.app`） |
| DEB 打包 | **失败** |
| e1～e9 | 尚未到达（打包前置版本校验即中止） |
| 真机安装 | Pending（R4-G 未授权） |

- **进展确认**：第四轮引入的权限保真 TAR 链路本轮生效——TAR 上传/下载/解包成功，主程序执行位保留，第四轮的 `CFBundleExecutable is not executable` 问题不再复现。
- **失败原文**：`App version=1.0 does not match control Version base=0.0.1`；`Process completed with exit code 1`。
- 失败位置：`package-deb` job 打包前置一致性校验（App `CFBundleShortVersionString` 与 control Version 基线比对）。该检查为**主动 fail-closed**，本轮不删除、不放宽。
- 本轮 `filterkit-deb` artifact 约 209 字节，为失败日志，**不是可安装包**。

## 2. 版本两侧实际值

| 位置 | 第五轮 Runner 实测/声明 | 说明 |
|---|---|---|
| `FilterKit.app` `CFBundleShortVersionString` | `1.0` | Xcode 缺键默认值，非工程主动设定 |
| `Config/DEB/control` Version 基线（`-<revision>` 前） | `0.0.1` | 第五轮快照 control 为 `0.0.1-1` |
| 校验要求 | 两者必须一致 | `package-deb.sh` / `validate-deb.sh` e2 同口径 |

## 3. 根因分析（假设分级，待下一轮 Runner 实测复核）

### R1（直接原因，离线证据支持）：版本一致性校验拦截到漂移

打包脚本读取 App 版本 `1.0`、control 基线 `0.0.1`，两者不等即退出 1。校验行为正确，问题在两侧版本来源本身未对齐。

### R2（App 侧 `1.0` 成因）：文件型 Info.plist 未注入版本键，Xcode 回退默认 1.0

- 快照 `project.yml` 的 `info.properties` 只声明 `UILaunchScreen`，**没有** `CFBundleShortVersionString` / `CFBundleVersion`；`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` 是构建设置，对**文件型 Info.plist** 不会自动回填——只有 plist 内显式引用 `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)` 时，Xcode 构建期才会替换。
- 生成的 Info.plist 缺版本键时，Xcode/agvtool 处理流程回退默认 `1.0` / `1`，于是 App 侧表现为 `1.0`，与工程设置 `0.0.1` 脱节。
- 对照：模拟器/ SwiftPM 测试不读取该 Info.plist 版本键，因此前述轮次未暴露此漂移。

### R3（control 侧 `0.0.1` 成因）：R4-D2 把 control 基线对齐到旧的工程占位 `MARKETING_VERSION=0.0.1`

- R4-D2 记录明确写过“DEB Version 对齐当前 `project.yml MARKETING_VERSION=0.0.1` → `0.0.1-1`”。
- 但活跃源码的版本口径已是 `0.1.0`：`Models/ReportEnvelope.swift` 默认 `schemaVersion/generatorVersion 0.1.0`、`SyntheticReportFactory` `0.1.0` / `0.1.0-preview`、GUI 测试断言 `0.1.0`；旧 `0.0.1` 是 Stage 2.1 占位遗留。营销版本目标应为 `0.1.0`，不应把 App 降级回 `0.0.1`。

### R4（排除项）：本轮与架构档/属主/签名无关

- 架构档（arm64e）、firmware 依赖、root:root 属主在第四轮已修复并进入快照；本轮失败发生在版本校验阶段，尚未到达 e1～e9，不能据此判定架构/属主/签名回归。
- 第四轮归档的真机闪退 C1～C5 待证假设本轮无新设备证据，状态不变。

## 4. 修复映射（本轮本地落地）

### 4.1 版本单一源（App ↔ DEB）

| 文件 | 改动 |
|---|---|
| `project.yml` | `info.properties` 增补 `CFBundleShortVersionString: $(MARKETING_VERSION)`、`CFBundleVersion: $(CURRENT_PROJECT_VERSION)`，使生成 Info.plist 显式携带版本键并由构建设置替换；`MARKETING_VERSION` 改 `0.1.0`，`CURRENT_PROJECT_VERSION` 保持 `1` |
| `Config/DEB/control` | `Version: 0.1.0-1`（营销基线 `0.1.0` + 打包修订号 `-1`） |
| `Config/DEB/README.md` | 写明版本单一源：`project.yml MARKETING_VERSION` → App 短版本；`CURRENT_PROJECT_VERSION` → 构建号；control 基线必须等于营销版本，不再维护第三份独立版本串；示例文件名同步 `0.1.0-1` |

版本口径最终态：App `CFBundleShortVersionString=0.1.0`、`CFBundleVersion=1`；DEB `Version=0.1.0-1`，基线 `0.1.0` 与 App 短版本一致。

### 4.2 预检可见性（笔记建议 1～3）

- `device-build` 的 Locate 步骤：构建后打印 App `CFBundleShortVersionString` / `CFBundleVersion`，不必等到 DEB 打包阶段才发现版本漂移。
- `package-deb` workflow 步骤：打包前打印 control 完整 Version 与基线。
- `scripts/package-deb.sh`：一致性校验前先打印两侧实际值（Bundle ID、App 版本/构建号、control Package/Version/基线）；版本不一致错误行附带构建号与 control 完整 Version。
- `scripts/validate-deb.sh` e2：OK/FAIL 行均带 `AppVersion` 与 `ControlVersion`，失败日志可直接对照两侧值。

### 4.3 快照对齐（本地仓库回填 Runner R4-D2 实现）

本轮同时把 R4-D2 快照中已在 Runner 运行、本地尚未回填的打包实现同步回本地：

- `Config/DEB/roothide.env`：`roothide-rootfs` 档案元数据单一源（Profile ID / 包架构 / 载荷相对路径 / 最低 Mach-O 切片 / 强制 root:root / 安装注册路径）。
- `scripts/package-deb.sh`：档案校验、`CFBundleExecutable` 存在与执行位校验、Bundle ID 与版本基线校验、`ditto` 暂存（Linux 回退 `cp -R`）、强制 `--root-owner-group` 不支持即 fail-closed、产物文件名由 control Version 派生、出包后立即归档可读校验。
- `scripts/validate-deb.sh`：e1～e9（归档可读 / control 档案身份与版本一致 / postinst 字节一致与语法 / rootfs 相对布局无 `var/jb/` 泄漏 / root:root 属主双格式解析 / 可执行位 / 源包与 DEB 包逐文件 parity / Mach-O arm64 切片独立于 control 架构 / 签名状态仅报告不视同可安装）。
- `scripts/compare-app-bundles.py`：Info.plist、逐文件 SHA256、符号链接目标与权限位 parity，不跟随符号链接。
- `scripts/collect-package-metadata.sh`：摘要归集 profile / packageArchitecture / minimumMachOArchitecture / signatureState 字段；DEB 状态文案 `RootHide Package Layout Passed (Static)`。
- `.github/workflows/filterkit-build.yml`：权限保真 TAR 往返（device-build 暂存→校验执行位→打包 TAR→解包复测；ipa/deb 从 TAR 恢复）、BSD/macOS 兼容 `find -print -quit`、`ARCHS=arm64 ONLY_ACTIVE_ARCH=NO`、e7 对照同源 `.app`、CI 置 `REQUIRE_DEB_VALIDATION_TOOLS=1`。
- `Spec/Stage-2/Stage-2.4-R4-D2-Implementation-Record.md`：R4-D2 档案/流水线设计记录（快照原样归档）。

## 5. 本地静态演练（Linux dpkg-deb 1.21.1 amd64；桩包，不入库）

- 正向桩包（Info.plist `0.1.0` / build `1`，Bundle ID `com.filterkit.manager`）：
  - `package-deb.sh` exit 0；预检行打印 `App version=0.1.0 build=1; control … Version=0.1.0-1 (base=0.1.0)`；
  - `validate-deb.sh`：e1/e2/e3/e4/e5/e6/e7 **passed**；e8（lipo）/ e9（codesign）在 Linux 记 **unavailable**（本机无 Apple 工具链）；摘要 `failed=0`；e7 parity `equal=true`、无 mismatch。
- 反向桩包（均在打包前置校验退出 1，不产出 DEB）：
  - App `1.0` vs control 基线 `0.1.0` → 错误行 `App version=1.0 (build=1) does not match control Version base=0.1.0 (control Version=0.1.0-1)`；
  - App `0.0.1` vs control 基线 `0.1.0` → 同类版本不一致退出 1；
  - Bundle ID `com.other.manager` vs control `com.filterkit.manager` → Bundle ID 不一致退出 1。
- 静态检查：八脚本 `bash -n` 全过；`compare-app-bundles.py` `py_compile` 过；`project.yml` 与 workflow YAML 良构；元数据脚本空输入 JSON 可解码。

## 6. 待下一轮 Runner 复验 / 未闭环项

1. Runner 在真实 `Release-iphoneos` 产物上确认生成 Info.plist 实测 `CFBundleShortVersionString=0.1.0`、`CFBundleVersion=1`（R2 修复是否在文件型 plist 生效，须以 Runner 构建产物为准）。
2. `package-deb` 版本/Bundle ID 校验通过，DEB 正常出包；`validate-deb.sh` e1～e7 在真实 App 内容上 passed；e8/e9 以 Runner macOS 工具链实测。
3. 第四轮遗留真机闪退假设 C1 签名封印 / C2 切片链接 / C3 布局注册 / C4 完整性 / C5 自身异常，仍待 `.ips` 与系统日志取证；本轮无新设备证据。
4. H4（Non-fat arm64 与 arm64e 标签一致性、弱链接 libroothide、roothide rpath、签名/entitlement 嵌入）、H5（postinst uicache 行为与 `/Applications`→JBROOT 映射）仍归 R4-A/R4-B/R4-G 门禁，打包层不伪造。
5. 版本号冻结（B2/B3 之外的营销版本基线）仍属待拍板项；本轮按活跃源码既有 `0.1.0` 口径统一，不视为版本冻结签署。

## 7. 边界核对

未改 Adapter 七方法协议；RootHide/Rootless Adapter 独立；冻结公共 Models、`ReportEnvelope`、Core 业务语义、Plist Parser 语义、Stage1 fixtures 未改；未链接 libroothide、未写 C 桥接声明、未弱链接、未 dlsym、未调用未验证私有 API；未做插件启停、plist 写入、dylib 删除/移动、dpkg 写操作、注入规则修改、自动修复、常驻 daemon；未触真机、未签名放行、未进 R4-G 与 0.1-E-B。

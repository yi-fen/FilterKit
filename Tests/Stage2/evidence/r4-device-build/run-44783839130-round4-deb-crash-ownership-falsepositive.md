# R4-A～E Runner 第四轮实跑诊断：DEB e5 属主校验误判 + DEB 真机闪退待证（run 44783839130，2026-11-20）

> 范围：0.1-D-R4-A～E 离线设备构建/打包/静态校验；不涉及 R4-G 真机冒烟、不涉及 0.1-E-B 发布验收。
> 证据来源：用户上传日志包 `logs_121217686412.zip`（Runner CI 日志，非真机安装/崩溃日志）+ 用户现象分析笔记（IPA 可启动、DEB 打开闪退）+ 参考源码 `reference/0.1.18-src/`。
> Runner 检出基线 commit `e02da08362755670470c876beee00f3bb21d5da0`（该对象不在本地仓库与 `origin/main` 中；本轮事实按日志原文转录，不据本地树反推 Runner 内容）。

## 1. 第四轮 Runner 实跑结果（日志原文）

元数据（`package-validation` 步骤，2026-11-20T17:37:30Z，runner `GitHub Actions 1000001146`，runId `44783839130`）：

| 产物 | 路径 | SHA256（元数据内包） | 状态（静态口径） |
|---|---|---|---|
| 设备 `.app` | `build/r4-artifacts/filterkit-device-build/FilterKit.app` | — | **Build Passed**；platform `iphoneos`；二进制 Non-fat `arm64`；Bundle ID `com.filterkit.manager`；MinimumOSVersion `17.0` |
| IPA | `build/r4-artifacts/filterkit-ipa/FilterKit.ipa` | `68b96cf71a5c15076804f8a9a503a71d98d7d210f1728ef84cb4b0ca35f6e8b5` | **Package Passed**（p1/p2/p3 全 passed） |
| DEB | `build/r4-artifacts/filterkit-deb/filterkit_0.1.0-1_iphoneos-arm64e.deb` | `d1b61b267936abb6d03fa226c2d9f294526bd5a41a277d6a9b551c199083acf2` | **Package Failed**（e1～e4 passed，**e5 failed**） |
| entitlements | `Config/Signing/FilterKit.entitlements` | — | Entitlements Static Passed（t1/t2/t3） |
| 真机安装 | — | — | **Device Install Pending**（R4-G 未授权） |

- 第三轮打包口径修复在本轮 Runner 生效：DEB 命名 `iphoneos-arm64e`，e2 解出 `Architecture=iphoneos-arm64e Depends=firmware (>= 15.0)`；e1/e3/e4 均 passed。
- 唯一失败项为 `package-deb` job 的 e5（属主校验），`##[error]Process completed with exit code 1`；其余 job（build / test / isolation / device-build / signing-prep / package-ipa / app-build / ui-acceptance / artifact）均通过。
- 工具链：macos-26-arm64，image `20261117.0516.1`，macOS 26.7.2（25G332），runner 2.338.2，Xcode 26.6，Swift 6.3.3（swiftlang-6.3.3.1.3 clang-2100.1.1.101），dpkg **1.23.12**（第三轮为 1.23.11）。
- 上传产物归档 digest（artifact 压缩包口径，与元数据内包 SHA256 不同）：

| Artifact | ID | Size(B) | 归档 digest |
|---|---|---|---|
| filterkit-device-build | 14654276039 | 901,520 | `c9a097c1d718002c390cd566af0aa63dcf98f1f2d14f75c88ccb7b35eba6199a` |
| filterkit-signing-prep | 14654220028 | 5,078 | `80a6a4e537a6061d001c988bbdd9911f7d8df7ac0afe19dd6b13408a7440c7b2` |
| filterkit-non-ui-build | 14654015152 | 1,669 | `81047e5228834aac15ee230013fc2c719602567507a75edf90f118d5ad97ada7` |
| filterkit-isolation | 14653721092 | 891 | `28bd3fe6f852a6c68f82bcd284409f1d7f311e528523ac8dca1ca7219b240dc6` |
| filterkit-deb | 14653237769 | 552,827 | `ca0e6c3e28646ffc38663ddc4554dc188d75bd29e757630a90cbcab269570e7c` |
| filterkit-ipa | 14653163079 | 858,800 | `b4cc5876ca3dfebf94c8b38b80e1d30914873d68a7c15bd04c04d24bb4c1bf2f` |
| filterkit-test-log | 14653118048 | 12,655 | `39e40b4bcbd53a0f8ef89b3447dd1a1f67c6b249361f058e259ab43e7954e9cd` |

- 测试口径：全量 Swift 测试 `All tests passed`、0 failures；S1-05 配对映射独立过滤 15 tests 0 failures；隔离检查七项 passed；XCUITest `All tests passed`（NavigationFlow / ShareSheet 套件）。

## 2. 真机侧反馈（用户陈述 + 分析笔记）

- 用户陈述：**同一版本 FilterKit，IPA 安装后可正常启动；DEB 安装后打开闪退**。
- 日志包内**没有**真机 `.ips` 崩溃日志、没有 amfid/SpringBoard/runningboardd/dyld 系统日志、没有 dpkg/转换器报错原文；闪退的确切终止原因、崩溃线程、动态库加载情况均无设备侧证据。
- 用户分析笔记给出的排查顺序（本轮采纳为取证纪律）：① 静态对比 IPA 与 DEB 解包后的 App（二进制 / Info.plist / Frameworks / PlugIns / CodeSignature / embedded.mobileprovision / entitlements / 权限）；② 检查 DEB 实际安装路径、权限与 uicache 注册；③ 对比两种安装方式的签名与 entitlement；④ 凭 `.ips` 终止原因定位；⑤ 只修被证据确认的环节。**不直接给 DEB 碰运气追加 `platform-application` / `no-sandbox` 等 entitlement**——entitlement 写进文件 ≠ 设备放行。

## 3. e5 失败定性：校验器列格式误判（非真实属主问题）

### 3.1 Runner 日志原文（e5 列出条目）

```
== e5. 数据包属主 root:root ==
FAIL: 数据包存在非 root:root 属主条目：
drwxr-xr-x  0 root   root        0 Nov 20 17:37 ./
drwxr-xr-x  0 root   root        0 Nov 20 17:37 ./Applications/
drwxr-xr-x  0 root   root        0 Nov 20 17:37 ./Applications/FilterKit.app/
-rw-r--r--  0 root   root  3294752 Nov 20 17:37 ./Applications/FilterKit.app/FilterKit
-rw-r--r--  0 root   root      776 Nov 20 17:37 ./Applications/FilterKit.app/Info.plist
-rw-r--r--  0 root   root        8 Nov 20 17:37 ./Applications/FilterKit.app/PkgInfo
```

全部条目属主 `root`、属组 `root`；`--root-owner-group` 在 Runner dpkg 1.23.12 上生效，**H3 属主口径本轮在产物侧已满足**。

### 3.2 误判根因

- 原 e5 awk 按 GNU tar 列格式解析：`perms owner/group size date name`，属主/属组合并在 `$2`（如 `root/root`、`1000/1000`）。
- Runner macOS 自带 bsdtar 输出为分列格式：`perms links owner group size date name`（`$2`=硬链接数 `0`，`$3`=owner，`$4`=group）。原脚本取 `$2` 比较 `root/root`，拿到的是链接数 `0`，于是把全部 root:root 条目误判为非 root:root。
- 本地 Linux 演练环境为 GNU tar 1.34，此前正向桩只验证了 GNU 格式，未覆盖 bsdtar 分列格式，故误判在 Runner 才暴露。

### 3.3 修复（本地）

`scripts/validate-deb.sh` e5 解析改为双格式兼容：`$2` 含 `/` 按 GNU `owner/group` 拆分；否则按 bsdtar 取 `$3`/`$4`；owner/group 归一化接受 `root` 或 `0`。详见 §6 本地演练。

## 4. IPA / DEB 离线结构对照（同一未签名 `.app`）

- 两个打包脚本输入为同一 `filterkit-device-build` 产物；IPA p1/p2/p3 与 DEB e1/e2/e3/e4 静态结构检查均通过。
- DEB data tar 仅含 5 个条目（目录 + `FilterKit` 3,294,752B + `Info.plist` 776B + `PkgInfo` 8B）；日志列表中**未见** `Frameworks/`、`PlugIns/`、`_CodeSignature/` 条目。
- 设备构建步骤为 `xcodebuild ... CODE_SIGNING_ALLOWED=NO build`：二进制**未签名**，entitlements plist 仅经 `validate-entitlements.sh` 静态解析（t1 可解析 / t2 候选齐全 / t3 无未批准键），**未嵌入二进制签名页**；CI 链路无 codesign / ldid 步骤。
- 参考可正常安装的 0.1.18（`reference/0.1.18-src/Makefile`，Theos roothide 路线）口径对照：

| 项 | 参考 0.1.18（Theos roothide） | 当前 Runner 产物（xcodebuild 离线） |
|---|---|---|
| 架构 | `ARCHS=arm64e` | Non-fat `arm64`（d4 仅要求包含 arm64） |
| 弱链接 / rpath | `-weak-lroothide -Xlinker -rpath -Xlinker @loader_path/.jbroot/usr/lib` | 无弱链接、无 roothide rpath |
| 签名 / entitlement | `FilterKit_CODESIGN_FLAGS = -Sentitlements.plist`（entitlement 随签名写入二进制） | `CODE_SIGNING_ALLOWED=NO`；entitlement 仅静态 plist 校验，未签名嵌入 |
| 安装路径 | `FilterKit_INSTALL_PATH = /Applications` | `Applications/FilterKit.app` rootfs 相对布局（e4 一致） |

## 5. DEB 闪退待证假设排序（假设，须 `.ips` / 系统日志复核，不写成已证实结论）

| # | 假设 | 离线证据 | 本轮处置 |
|---|---|---|---|
| C1 | **签名 / entitlement 封印缺失**：DEB 安装路径不经过设备端重签，未签名二进制且无 `platform-application` / `no-sandbox` 签名封印，启动时被 amfid / 沙盒拒绝；IPA 安装链路上可能由安装工具完成了重签或 ldid 注入（待核实 IPA 实际安装方式与包内签名状态） | §4：CI 未签名、entitlement 未嵌入；参考包由 Theos `-Sentitlements.plist` 签名写入 | 本轮不动签名路线；列入 R4-B/R4-G 门禁，先取 `.ips` Code Signing / Termination Reason 证据 |
| C2 | **切片 / 动态库链接不符**：Non-fat `arm64` 在 arm64e RootHide 环境的兼容性；缺 `weak-lroothide` 与 roothide rpath，进程内库加载 / 符号解析失败（dyld `Library not loaded` / `Namespace DYLD`） | §4 对照表；元数据 architecture 字段 | 属 R4-A 设备构建/链接门禁；打包层不伪造 arm64e 切片或弱链接 |
| C3 | **安装布局 / 注册 / 权限**：DEB 实际落盘路径、`uicache -p` 注册目标、目录与可执行位在目标 bootstrap 不符 | e4 仅验包内路径存在；H5 既有待实测项 | 待设备侧落盘核对（路径 / `ls -laR` / 可执行位 / uicache 输出） |
| C4 | **Bundle 内容完整性**：打包复制中 Info.plist / 资源 / Seal 缺失或损坏；静态 p2/e4 只验存在，不做逐文件哈希与签名 Seal 比对 | §4：包内仅 5 条目，无 `_CodeSignature` | 待 IPA/DEB 解包逐文件对比（二进制 sha256、Info.plist、Frameworks/PlugIns、资源） |
| C5 | **应用自身启动异常**：main / 初始装配在 DEB 上下文抛错 | 无设备崩溃线程证据 | 以 `.ips` Exception Type / Crashed Thread 区分是否应用自身崩溃 |

> 关键空白：当前无法区分"签名拒绝 / 动态库加载失败 / 应用自身崩溃"三类闪退；在拿到 `.ips` 前不调整 GUI 或 Core 代码，也不为 DEB 追加 entitlement 碰运气。

## 6. 本轮离线修复与静态演练（Linux dpkg-deb 1.21.1，非设备证据）

- 修复：`scripts/validate-deb.sh` e5 双格式属主解析（GNU `owner/group` 单字段 / bsdtar `owner group` 分列）；OK 文案标注兼容两种列格式。
- `bash -n`：`validate-deb.sh` 通过。
- awk 单测（合成行）：
  - 正向混合格式（GNU `root/root` + bsdtar `0 root root`）→ 无坏条目，exit 0；
  - 反向三种非 root：GNU `1000/1000`、bsdtar `runner staff`、bsdtar 数值 `501 20` → 三行全部列出，exit 1。
- 本地 `/tmp` 桩包正向演练：e1～e5 全 passed，`failed=0`；不带 `--root-owner-group` 打包的反向桩包 e5 仍 FAIL（非 root:root 条目被拦截）。演练产物已清理，不入库。
- 本机无 xcodebuild/swift/plutil/lipo/ldid；arm64e 切片、签名、entitlement 放行、uicache 行为均以 Runner / 真机证据为准。

## 7. 待真机侧补采清单（R4-G 门禁前取证）

1. **`.ips` 崩溃日志**（设置 → 隐私与安全性 → 分析与改进 → 分析数据，按 FilterKit 时间定位）：`Exception Type`、`Termination Reason`、`Crashed Thread`、Code Signing 相关记录、`Library not loaded`、`Namespace DYLD`。
2. **IPA / DEB 解包对比**：二进制 sha256、Info.plist、Frameworks / PlugIns、资源文件、`_CodeSignature`、`embedded.mobileprovision`、`codesign -d --entitlements :-` 输出、文件权限位。
3. **安装后落盘核对**：FilterKit.app 实际路径（jbroot 内 `/Applications` 还是其他位置）、`ls -laR`、可执行位、属主/属组；uicache 注册输出与结果。
4. **系统日志**：启动 FilterKit 时段 amfid、SpringBoard、runningboardd、dyld 记录（有 SSH 时可取）。
5. **IPA 安装方式取证**：通过何种工具安装 IPA（TrollStore / TrollFools / Sileo / 其他），安装时是否重签或 ldid 注入；IPA 包内签名状态。

## 8. 修复后仍 Pending / 未闭环项

- 下一轮 Runner 复验：e5 在 bsdtar 格式下判 root:root 通过，DEB e1～e5 全 passed；元数据 JSON 回填新内包 SHA256 / Commit SHA / Runner ID。
- C1 签名路线（Developer 证书 + 描述文件 / 越狱 ldid）与 entitlement 嵌入二进制的闭环；C2 arm64e 切片、弱链接 libroothide、roothide rpath；C3 uicache / JBROOT 映射；C4 逐文件完整性比对——均待 R4-A/R4-B/R4-G 授权与真机证据。
- 既有未决项不变：部署形态 A/B/C/B+C、Bundle ID（B3）、Deployment Target（B2）、16.5 SDK 对 iOS 17.0.2 兼容、GUI 进程内 `jbroot()` 符号可解析性；`OwnershipResolver` 未迁移、`loaded` 恒 unknown、`permission.decision` 恒 undetermined、pluginID 0.2.0、PARSE-009-B；0.1-C G10 搁置不豁免。

## 9. 冻结边界核对

未改冻结 Models、`ReportEnvelope`、Adapter 七方法协议、Core 业务语义、Plist Parser 语义、Stage1 fixtures；未改 `loaded`/`installed`/`configured` 语义；未触真机写操作、插件启停、dylib 删移、dpkg 写、注入规则、entitlement/签名放行、常驻 daemon；未新增 jbroot() C 桥接声明/弱链接/dlsym/伪造符号；未进 R4-G、未进 0.1-E-B。

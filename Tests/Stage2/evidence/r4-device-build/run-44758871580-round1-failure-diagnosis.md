# R4-A～E Runner 首轮实跑失败诊断（run 44758871580，2026-11-20）

> 范围：0.1-D-R4-A～E 离线设备构建/打包/静态校验；不涉及 R4-G 真机冒烟、不涉及 0.1-E-B 发布验收。
> 证据来源：两份 Runner job 日志 SAS 链接（下载票已过期，原文不再复取；以下事实按日志原文记录）。Runner 检出基线 commit `460a9906ffa51d4b317169e285c3c846290d1baf`。

## 1. 实跑概况

| Job | job run | 结果 | 关键事实 |
|---|---|---|---|
| `device-build` | `cf32de97-24c8-5c03-a4c6-6b785983c806` | **失败** | macos-26-arm64 / macOS 26.7.2 / Xcode 26.6 / SDK iphoneos26.5；`xcodebuild ... CODE_SIGNING_ALLOWED=NO build` **`** BUILD SUCCEEDED **`**；产物 `Release-iphoneos/FilterKit.app`，主二进制 3,294,752B，Mach-O 64-bit executable arm64；静态校验脚本 d1/d2 通过后 d3 中断 |
| `package-validation` | `b89a24c6-aaba-5c6d-8146-3a79e908fc40` | **失败** | download-artifact 仅 4 个产物：`filterkit-device-build`、`filterkit-signing-prep`、`filterkit-non-ui-build`、`filterkit-isolation`；缺 `filterkit-ipa`、`filterkit-deb`；元数据归集步骤中断，未产出 `package-metadata.json` |
| `package-ipa` / `package-deb` | 同 run | **被跳过（skipped）** | `needs: [device-build]`，上游 `device-build` 失败，未调度；因此无 IPA/DEB 产物 |

### 1.1 首轮下载产物 digest（package-validation 视角，日志原文）

| Artifact | ID | 大小 | Expected SHA256 |
|---|---|---|---|
| `filterkit-device-build` | 14641182449 | 901,193B | `326da8596b95a1f5bc4099238b496bb74a05bd8eeb68dafa96ec7d1d717182e3` |
| `filterkit-signing-prep` | 14640836497 | 5,078B | `1bacbda2bddb1facf5c53ea073a354e27af9f4f73a7b89845fd23cbe1c554605` |
| `filterkit-non-ui-build` | 14639647827 | 1,588B | `974b5b1278a2fdbd1ad7fb5afdb739a5aac1e3cebb6a4855a11e08c802121cc9` |
| `filterkit-isolation` | 14638949252 | 891B | `24f9c4a21172f7cd45264c44fe01c0270182b7aa21e80a7940cdae3902e5fbfe` |

缺失：`filterkit-ipa`、`filterkit-deb`（上游 job 被跳过，无产物可下载）。

## 2. 失败根因

### 2.1 device-build：d3 校验脚本裸变量紧邻全角字符，`set -u` 下 unbound variable

- 中断行：`scripts/validate-device-build.sh: line 86: supported�: unbound variable`，`##[error]Process completed with exit code 1`。
- 机理：d3 分支中原写法 `echo "OK: DTPlatformName=iphoneos（$supported）"`——裸变量 `$supported` 后直接紧跟全角右括号 `）`（UTF-8 `EF BC 89`）。Runner 宿主 shell/区域设置下，变量名解析把紧随的多字节字符并入变量名，形成不存在的 `supported）`；脚本 `set -u`，引用未绑定变量即非零退出。`BUILD SUCCEEDED` 的设备产物本身已生成，失败发生在产物静态校验阶段，不是编译/链接失败。
- 附带缺陷：`CFBundleSupportedPlatforms` 是 plist 数组，`read_plist` 按标量单行取值，无法正确解析数组；该变量本就不应作为 d3 判定依据（d3 以 `DTPlatformName=iphoneos` 为准）。

### 2.2 package-validation：`find` 对缺失目录非零退出，`pipefail` 下中断归档

- 中断行：`find: build/r4-artifacts/filterkit-ipa: No such file or directory`，步骤 `/bin/bash -e {0}` + `set -o pipefail`，find 非零 → 整条流水线非零 → step exit 1；`collect-package-metadata.sh` 未执行，`build/validation/` 无日志/JSON，artifact 上传告警 "No files were found"。
- 链路关系：IPA/DEB 缺失是 §2.1 的下游结果（上游 job 被跳过）；但归集步骤本身缺少容错——缺 artifact 应记 `Package Pending` 并继续归档元数据，而不是整体中断。

## 3. 本轮修复（本地，待 Runner 复验）

| 文件 | 改动 | 对应根因 |
|---|---|---|
| `scripts/validate-device-build.sh` | d3 删除无法按标量解析的 `CFBundleSupportedPlatforms` 取值；OK 行改为 `echo "OK: DTPlatformName=iphoneos"`；d6 裸变量 `$min_os` 改为 `${min_os}` 包裹 | §2.1 |
| `scripts/package-ipa.sh` | 告警行裸变量 `$STAGE` 改为 `${STAGE}`（同类隐患，未在本轮触发） | §2.1 同类 |
| `scripts/package-deb.sh` | 两处裸变量 `$STAGE` 改为 `${STAGE}`（同类隐患，未在本轮触发） | §2.1 同类 |
| `.github/workflows/filterkit-build.yml` | `package-validation` 元数据归集步骤新增 `find_first()` 辅助函数：目录不存在时返回空路径，`find` 错误重定向到 `/dev/null`；七个产物路径定位全部改走该函数；缺产物由 `collect-package-metadata.sh` 记 Pending，不再中断归档 | §2.2 |

## 4. 本地静态演练（Linux，非设备证据）

- `bash -n scripts/*.sh`：8 个脚本全部通过。
- 裸变量紧邻非 ASCII 字节扫描：`scripts/*.sh` 与 workflow YAML 无命中。
- workflow YAML 解析：12 个 job，结构良构。
- `collect-package-metadata.sh` 空输入演练：JSON 可解码；`deviceBuild.status=Build Pending`、`ipa/deb=Package Pending`、`deviceInstall.status=Device Install Pending`，退出码 0。
- `find_first` 模拟：缺失目录返回空、存在目录定位到文件，`pipefail` 下退出码 0。
- 本机无 xcodebuild/swift/plutil/lipo/ldid；设备产物、Mach-O 平台/架构/Bundle ID/最低系统版本实测值仍以 Runner 日志为准。

## 5. 修复后仍 Pending / 未闭环项

- Runner 复验 `device-build` 静态校验 d1～d6 全部 passed、`device-build-summary.json` `failed=0`。
- `package-ipa` / `package-deb` 实跑产出结构包并通过 `validate-ipa.sh` / `validate-deb.sh`。
- `package-validation` 在缺产物时也能归档 `Package Pending` 元数据 JSON；有产物时回填 SHA256、Commit SHA、Runner ID、工具链版本。
- Build Passed / Package Passed 须以上述 Runner 证据重算；Device Install Passed 属 R4-G 真机门禁，未授权、不取证。
- 既有未决项不变：部署形态 A/B/C/B+C、Bundle ID（B3）、Deployment Target（B2）、签名路线（Developer vs ldid）、DEB 路径前缀/架构命名/uicache、SDK 向下兼容、GUI 进程内 `jbroot()` 符号可解析性；`OwnershipResolver` 未迁移、`loaded` 恒 unknown、`permission.decision` 恒 undetermined、pluginID 0.2.0、PARSE-009-B。

## 6. 冻结边界核对

未改冻结 Models、`ReportEnvelope`、Adapter 七方法协议、Core 业务语义、Plist Parser 语义、Stage1 fixtures；未改 `loaded`/`installed`/`configured` 语义；未触真机写操作、插件启停、dylib 删移、dpkg 写、注入规则、entitlement/签名放行、常驻 daemon；未进 R4-G、未进 0.1-E-B。

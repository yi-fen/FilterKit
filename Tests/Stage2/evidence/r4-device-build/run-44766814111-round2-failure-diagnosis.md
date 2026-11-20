# R4-A～E Runner 第二轮实跑失败诊断（run 44766814111，2026-11-20）

> 范围：0.1-D-R4-A～E 离线设备构建/打包/静态校验；不涉及 R4-G 真机冒烟、不涉及 0.1-E-B 发布验收。
> 证据来源：两份 Runner job 日志 SAS 链接（下载票已过期，原文不再复取；以下事实按日志原文记录）。Runner 检出基线 commit `211365cbf039f525a0bbc4f8608f44ca3c5e84e3`。

## 1. 实跑概况

| Job | job run | 结果 | 关键事实 |
|---|---|---|---|
| `package-ipa` | `614a21ed-12d8-59f5-9f6e-abe3021a8644` | **失败** | macos-26-arm64 / macOS 26.7.2 / runner 2.338.2 / image 20261117.0516.1；下载 `filterkit-device-build`（ID `14645672385`，901,844B，digest `sha256:ae0b5ef2ec442da985fba859bae1f7e955321bd5c4dbc2afb15bffa08ce02fb7`）成功；定位 `.app` 步骤为空路径，`::error::device app missing from filterkit-device-build artifact` exit 1；`filterkit-ipa` 上传告警 No files found |
| `package-deb` | `67d8538d-43e0-5221-9e6e-3fd7812f6e54` | **失败** | macos-26-arm64 / macOS 26.7.2 / image 20261102.0473.1；`brew install dpkg` 1.23.11（依赖 gpatch 2.8.1、libmd 1.3.0），`dpkg-deb` 可用；同一 `filterkit-device-build` 产物（同 ID/大小/digest）下载成功；定位 `.app` 同样为空路径 exit 1；`filterkit-deb` 上传告警 No files found |
| `device-build` | 同 run（本轮未提供该 job 日志） | 待回填 | 产物 artifact 存在且体积与首轮相近（901,844B），推断设备 `.app` 已随产物上传；其静态校验 d1～d6 结果以该 job 日志为准，待下一轮 Runner 证据回填 |

### 1.1 本轮下载产物 digest（下游 job 视角，日志原文）

| Artifact | ID | 大小 | Expected SHA256 |
|---|---|---|---|
| `filterkit-device-build` | 14645672385 | 901,844B | `ae0b5ef2ec442da985fba859bae1f7e955321bd5c4dbc2afb15bffa08ce02fb7` |

缺失：`filterkit-ipa`、`filterkit-deb`（两个打包 job 在定位步骤即中断，未产出结构包）。

## 2. 失败根因

### 2.1 设备 `.app` 在 artifact 内层级深于下游 `find -maxdepth 4` 的定位深度

- 两个打包 job 的定位步骤完全相同：
  ```bash
  APP_PATH=$(find build/device-artifact -name 'FilterKit.app' -maxdepth 4 | head -1)
  if [ -z "$APP_PATH" ]; then
    echo "::error::device app missing from filterkit-device-build artifact"
    exit 1
  fi
  ```
  本轮该命令返回空 → 步骤 exit 1。

- `device-build` 上传步骤的输入路径分处两个目录：
  - 日志/摘要：`build/device/device-xcodebuild.log`、`build/device/device-build-validation.log`、`build/device/device-build-summary.json`；
  - 设备产物：`${{ steps.app.outputs.app_path }}`，即 `build/DerivedData-device/Build/Products/Release-iphoneos/FilterKit.app`。

- `actions/upload-artifact@v7` 对多路径取**最小公共祖先（LCA）**作为 artifact 根目录（本轮 `package-ipa` 上传日志原文："Multiple search paths detected. Calculating the least common ancestor of all paths … The least common ancestor is …/build/ipa. This will be the root directory of the artifact"）。上述两组路径的 LCA 是 `build/`，因此 `.app` 在归档内保留为：
  ```
  DerivedData-device/Build/Products/Release-iphoneos/FilterKit.app/
  ```
  下载到 `build/device-artifact/` 后，相对深度为：`DerivedData-device`(1) / `Build`(2) / `Products`(3) / `Release-iphoneos`(4) / `FilterKit.app`(5)。`find -maxdepth 4` 只下探到第 4 层（`Release-iphoneos`），第 5 层的 `FilterKit.app` 标记目录不会被命中。

- 链路关系：首轮（run 44758871580）修复的是校验脚本变量引用与归集容错；本轮 device-build 已能产出并上传产物，失败点后移到**产物归档层级与下游定位深度不匹配**。这是 CI 打包链路问题，不是编译/链接失败，也不是 `.app` 结构本身损坏。

### 2.2 待 Runner 证据确认的点

- 本轮未提供 `device-build` job 日志，归档内实际条目清单未能直接列出；上述层级推断依据 workflow 路径、v7 LCA 语义（同轮日志原文佐证）与 `/tmp` 目录层级模拟。下一轮 Runner 日志/artifact 清单用于复核 `.app` 确实在归档内、且位于根层。
- 若下一轮仍定位失败，需先拉取 `filterkit-device-build` 归档清单核对条目前缀，再判断是上传路径缺失还是层级问题。

## 3. 本轮修复（本地，待 Runner 复验）

| 文件 | 改动 | 对应根因 |
|---|---|---|
| `.github/workflows/filterkit-build.yml`（`device-build` job） | 新增 "Stage app bundle into evidence directory" 步骤：定位 `.app` 后、静态校验前，将 `cp -R` 复制到 `build/device/FilterKit.app`；上传路径由 `${{ steps.app.outputs.app_path }}` 改为 `build/device/FilterKit.app`。四条上传路径同处 `build/device/`，LCA 收窄到 `build/device/`，artifact 内 `.app` 位于根层，下游 `find -maxdepth 4` 第 1 层即可命中 | §2.1 |

- 下游 `package-ipa` / `package-deb` 定位步骤与 `package-validation` 的 `find_first()` 不改： staged 布局下 `.app` 深度为 1，现有 `maxdepth 4` 余量充足；打包 job 对缺 `.app` 保持硬失败（上游产物缺失应显式报错），缺产物容错仍由 `package-validation` 归集层记 Pending。
- 静态校验步骤仍读取 DerivedData 原始路径（env `APP_PATH` 不变）；暂存副本仅用于归档与下游打包，字节内容一致。

## 4. 本地静态演练（Linux，非设备证据）

- `bash -n scripts/*.sh`：8 个脚本全部通过。
- workflow YAML 解析：12 个 job 良构；`device-build` 步骤序为 Checkout → Install XcodeGen → Generate → Build → Locate → **Stage app bundle** → Validate → Upload。
- `/tmp` 层级模拟：旧嵌套布局（`DerivedData-device/Build/Products/Release-iphoneos/FilterKit.app`）下 `find -maxdepth 4` 返回空；新 staged 布局（`FilterKit.app` 位于下载根）下同一命令第 1 层命中。
- `validate-deb.sh` e3 扫描 `Config/DEB/postinst`：无越界写/删/移/后台/权限动作命中。
- 本机无 xcodebuild/swift/plutil/lipo/ldid；设备产物、IPA/DEB 结构校验实测值仍以 Runner 日志为准。

## 5. 产物版本口径（RootHide / Rootless）

- **当前 CI 不区分 RootHide / Rootless 产物版本**：`device-build` 只产出单份未签名 iphoneos `.app`；`package-ipa.sh` 出单份 `Payload/FilterKit.app` 的 IPA；`package-deb.sh` 出单份 `Package/Applications/FilterKit.app` 的 DEB（control `Architecture: iphoneos-arm64`，命名 `filterkit_0.1.0-1_iphoneos-arm64.deb`）。包名、control、打包脚本中均无路线（scheme/route）维度，也没有 Theos roothide/rootless scheme 矩阵。
- 双路线只体现在源码层：`Adapters/RootHide/RootHideAdapter.swift` 与 `Adapters/Rootless/RootlessAdapter.swift` 两套适配器独立存在；产物打包层尚未按路线分叉。
- **前期默认只对 RootHide 路线负责**：R4 规格标题即 "iOS Device Build & RootHide Deployment Plan"，R4-D DEB 定位为 "RootHide 测试包，优先方向"；基线规格记录唯一真机为 RootHide，Rootless 无设备，仅离线/合成夹具验证，且不得以 RootHide 验收结果覆盖 Rootless（原则 C）。
- Rootless 版本包的产出前提：Theos `rootless` scheme 接线、arm64 架构口径、Rootless 真机或固定样本到位；当前均属未决/待验证项，不在 R4-A～E 范围。
- 未决口径不变：部署形态 A/B/C/B+C、DEB 路径前缀/Architecture 命名/uicache 行为、SDK 向下兼容、签名路线，均须目标 RootHide Bootstrap 实测定值。

## 6. 修复后仍 Pending / 未闭环项

- Runner 复验 `device-build` 静态校验 d1～d6 全 passed、`device-build-summary.json` `failed=0`；artifact 内 `FilterKit.app` 位于根层。
- `package-ipa` / `package-deb` 实跑定位到 `.app`、产出结构包并通过 `validate-ipa.sh` / `validate-deb.sh`。
- `package-validation` 归档元数据 JSON，有产物时回填 SHA256、Commit SHA、Runner ID、工具链版本。
- Build Passed / Package Passed 须以上述 Runner 证据重算；Device Install Passed 属 R4-G 真机门禁，未授权、不取证。
- 既有未决项不变：部署形态、Bundle ID（B3）、Deployment Target（B2）、签名路线、DEB 前缀/架构/uicache、SDK 兼容、GUI 进程内 `jbroot()` 符号可解析性；`OwnershipResolver` 未迁移、`loaded` 恒 unknown、`permission.decision` 恒 undetermined、pluginID 0.2.0、PARSE-009-B。

## 7. 冻结边界核对

未改冻结 Models、`ReportEnvelope`、Adapter 七方法协议、Core 业务语义、Plist Parser 语义、Stage1 fixtures；未改 `loaded`/`installed`/`configured` 语义；未触真机写操作、插件启停、dylib 删移、dpkg 写、注入规则、entitlement/签名放行、常驻 daemon；未进 R4-G、未进 0.1-E-B。

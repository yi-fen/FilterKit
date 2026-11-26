# P2-09 — Helper Provisioning & Real Device Integration

## 本阶段交付边界

P2-09 增加**签名后信任配置生成工具**和设备联调准备说明。它不会代替 Apple `codesign`、不会安装/启动 Helper、不会写入 JBROOT，也不会开放插件关联提交。没有真实签名产物与 RootHide 测试设备时，不可能诚实地产生有效 CDHash 或宣称真实 IPC/注入验证通过。

## 两阶段签名顺序

1. 编译并最终签名独立 `FilterKitHelper` 可执行文件。
2. 执行 `p209_provision_helper_trust.py prepare`，从该 Helper 的签名读取 CDHash，生成 `FilterKit-Helper-AppTrust.json`。
3. 将 JSON 放入 App 的 `Resources`（确保 XcodeGen 将它复制进 App bundle），然后最终签名 FilterKit App。
4. 在完成签名的 `.app` 上执行 `finalize`。脚本重新读取 Helper 和 App 的 CDHash，生成 installer provisioning bundle、root manifest disabled 模板和 launchd disabled 模板。
5. 将生成物交给受信任的 root 安装器/打包流程；**本脚本本身不安装、不启动、不改权限、不启用服务**。

示例（路径与 UID 必须替换成设备实测值）：

```sh
python3 Build/scripts/p209_provision_helper_trust.py prepare \
  --helper build/FilterKitHelper --bundle-id cn.yfen.filterkit \
  --generation 1 --output Resources/FilterKit-Helper-AppTrust.json

# 将上一步 JSON 纳入 App bundle 后，再完成 App 最终签名。
python3 Build/scripts/p209_provision_helper_trust.py finalize \
  --helper build/FilterKitHelper --app build/FilterKit.app \
  --bundle-id cn.yfen.filterkit --generation 1 \
  --jbroot /实际设备探测到的/.jbroot-XXXXXXXX \
  --client-uid 501 --staging-uid 501 \
  --route-id roothide-ellekit --release-id p209-device-test \
  --helper-version 1.0.0 --output-dir build/p209-provisioning
```

## 输出文件

- `FilterKit-Helper-AppTrust.json`：App 端 pin Helper CDHash。
- `FilterKit-Helper-InstallerProvisioning.json`：签名流水线输入摘要，字段与 `HelperInstallerProvisioningBundle` 对齐。
- `FilterKit-Helper-RootManifest.DISABLED.json`：root manifest 模板，`executionEnabled=false`。
- `cn.yfen.filterkit.helper.plist`：launchd 模板，`Disabled=true`、`RunAtLoad=false`、`KeepAlive=false`。

这些 JSON 是配置，不是签名证明；安装器仍必须验证来源、文件签名、所有权、哈希、JBROOT 身份与事务状态。不要把示例 UID、JBROOT 或 CDHash 当成设备事实。

## 设备联调验收（尚未执行）

- [ ] 从目标 RootHide 设备只读获取真实 JBROOT、UID/GID、ElleKit 注入目录和 Helper socket 路径。
- [ ] 确认 socket 路径长度小于 `sockaddr_un.sun_path` 容量；确认目录 root-owned、不可被普通用户替换。
- [ ] 检查 socket 文件 owner/mode。当前 server 默认 `0666`，安全边界依赖 `getpeereid`/PID、内核 CDHash 与 UID/CDHash pin；设备联调必须验证实际权限和 peer credential 行为。未验证前不得将其视为安全通过。
- [ ] 验证 App 对 Helper 的 peer PID/CDHash 校验，Helper 对 App UID/PID/CDHash 校验，错误 pin 必须拒绝。
- [ ] 验证 `FilterKit-Helper-AppTrust.json` 在最终 App bundle 中存在且内容与 Helper 最终 CDHash 一致。
- [ ] 验证 root manifest 与最终 App/Helper CDHash 一致，`executionEnabled=false`。
- [ ] 验证 launchd job 安装后仍 Disabled，不自动启动；先做只读启动/停止与 socket 观测。
- [ ] 在隔离测试插件上验证 Prepare/Commit/Recovery；记录操作前后 plist/manifest 哈希及 dylib 哈希。
- [ ] 只有全部设备证据审核并获得明确发布批准后，才可另行规划打开执行开关的变更。

## 当前执行门

以下开关保持关闭：

- `HelperRequestDispatcher.pluginAssociationCommitReleased = false`
- `HelperDeploymentCoordinator.pluginAssociationCommitReleased = false`
- `HelperRequestDispatcher.executionReleased = false`
- `HelperDeploymentCoordinator.executionReleased = false`
- `HelperProductionDeploymentBackend.executionReleased = false`

## 本阶段验证边界

本地只运行脚本语法/单元测试、Swift 源码 parse、项目 YAML 解析和归档完整性检查。没有 Xcode/iOS SDK、最终签名产物或 RootHide 真机，因此没有生成真实 CDHash，没有完成真实安装、launchd、AF_UNIX、peer credential 或 ElleKit 注入验证。

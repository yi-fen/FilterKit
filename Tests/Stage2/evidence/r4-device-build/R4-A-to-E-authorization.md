建议授权开发。 这个推进方向合理，而且没有越过当前阶段边界：利用 macOS Runner 建立真实的 iOS 设备构建与打包链路，不依赖 Linux 本地工具链，也不提前进行真机安装。

建议授权范围限定为 0.1-D-R4-A～R4-E：CI Device Build & Offline Packaging。

一、建议授权内容

授权执行 FilterKit 0.1-D-R4-A～R4-E。

阶段目标：
在 GitHub Actions macOS Runner 上建立 iOS Device Build、IPA/DEB 打包和静态校验链路，完成离线构建与证据归档。

一、R4-A：iOS Device Build

1. 核对现有 Xcode 工程、Scheme、Deployment Target。
2. 接入 iphoneos SDK 设备构建。
3. 首轮使用 CODE_SIGNING_ALLOWED=NO。
4. 检查平台标识、最低系统版本和实际架构。
5. 不强制要求 arm64e，按目标设备和工程配置确定架构。

二、R4-B：Signing & Entitlements 准备

1. 整理签名配置与 entitlement 文件。
2. 区分普通开发者签名和越狱环境签名。
3. 验证 entitlement 文件格式与静态配置。
4. 不使用虚构证书或假定权限已经放行。
5. 不执行真实设备签名安装验证。

三、R4-C：IPA Packaging

1. 生成 IPA 结构包。
2. 验证 Payload/FilterKit.app 结构。
3. 明确区分未签名 IPA 与可安装 IPA。
4. 未获得有效设备签名时，不得标记为可安装包。

四、R4-D：DEB Packaging

1. 生成 FilterKit DEB 测试包。
2. 验证 control、安装目录和包结构。
3. 检查 postinst，仅允许必要的 App 注册操作。
4. 不修改插件、ElleKit 配置、dpkg 数据库或系统注入规则。
5. JBROOT 安装路径和 Bootstrap 兼容性保持待真机验证。

五、R4-E：静态校验与 Runner 验收

1. 验证 iPhoneOS 平台和设备架构。
2. 验证 Bundle ID、Deployment Target。
3. 验证 IPA 和 DEB 包结构。
4. 验证 entitlement 文件格式。
5. 生成 SHA256 和构建元数据。
6. 将原始日志、测试结果和构建产物归档。
7. 明确区分 Build Passed、Package Passed 和 Device Install Pending。

六、工程约束

1. 保持 RootHide 与 Rootless Adapter 独立。
2. 不修改冻结 Models、ReportEnvelope、Adapter 七方法协议。
3. 不改变 installed/configured/loaded 语义。
4. 不将模拟器构建结果作为设备构建证据。
5. 优先复用现有 CI Workflow 和脚本，避免重复创建构建链。
6. 修改前核对当前真实仓库结构和最新提交基线。

七、禁止事项

* 不执行真机安装。
* 不执行 Bootstrap 实际部署。
* 不执行真实设备签名放行验证。
* 不调用 RootHide jbroot() 真机 API。
* 不修改插件文件或注入配置。
* 不执行插件启停、删除、移动或安装。
* 不执行 dpkg 写操作。
* 不进入 R4-G。
* 不进入 0.1-E Final Release Acceptance。

交付要求：

1. 代码修改清单。
2. CI Workflow 修改清单。
3. R4-A～E 原始 Runner 日志。
4. IPA/DEB 结构检查报告。
5. 架构、平台、Deployment Target 检查结果。
6. SHA256 与构建元数据。
7. 未通过项目及技术限制。
8. 更新后的 DevDocs 压缩包及完整性校验结果。

完成后先提交验收报告，等待下一阶段授权。

二、开发顺序

建议严格按照：

R4-A → R4-B → R4-C → R4-D → R4-E

不要先写 DEB 打包脚本，再回头发现设备构建产物不符合预期。

特别注意三个验收边界：

结果	可以证明什么
Device Build Passed	成功生成 iPhoneOS 设备构建产物
Package Passed	IPA/DEB 结构符合静态检查要求
Device Install Passed	真机安装、注册及启动成功

前两项可以由 Runner 验证，第三项必须留给 R4-G 真机验证。

三、R4 完成后的下一步

R4-A～E 通过后，再单独授权 R4-G：

RootHide 真机安装、App 启动和部署验证。

之后才进入 R3-B～R3-E 真机权限取证。

最终决定：可以授权 R4-A～E，但不授权 R4-G，也不授权 0.1-E 正式发布验收。
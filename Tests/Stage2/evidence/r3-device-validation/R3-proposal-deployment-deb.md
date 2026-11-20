建议准备 .deb 安装包，但不代表真机测试必须只能通过 .deb 安装。对于 FilterKit 当前的 RootHide 部署目标，我更推荐采用 .deb 作为正式真机测试安装载体。

原因是：我们不仅要验证 App 能否启动，还要验证它在 RootHide 环境中的安装位置、签名、entitlement、sandbox 和文件访问权限。

一、IPA 和 DEB 两种方式有什么区别？

对比项	IPA 安装	DEB 安装
安装方式	普通 iOS 安装流程	Bootstrap / dpkg
安装位置	通常进入 App 容器体系	可安装到 JBROOT 内指定位置
uicache 注册	取决于安装方式	可通过安装脚本注册
特殊 entitlement	取决于签名及部署环境	同样需要有效签名和权限放行
JBROOT 访问	不能默认具备	不能默认具备
RootHide 集成	需要额外部署适配	更适合越狱环境部署
真机权限验证	可以	可以

这里有一个非常重要的区别：

DEB 安装成功，不等于 App 获得了 JBROOT 访问权限。

安装位置、代码签名、entitlement 和 sandbox 是四个需要分别验证的问题。

二、FilterKit 推荐采用什么部署方式？

结合之前冻结的部署研究，我建议优先验证：

B+C：特殊权限 App + Bootstrap DEB 安装通道。

建议安装结构：

FilterKit.deb
    |
    +-- Applications/
    |      |
    |      +-- FilterKit.app/
    |             |
    |             +-- FilterKit
    |             +-- Info.plist
    |             +-- Frameworks/
    |             +-- embedded resources
    |
    +-- DEBIAN/
           |
           +-- control
           +-- postinst

安装流程：

GitHub Actions
      |
      v
编译 FilterKit.app
      |
      v
签名与 entitlement 配置
      |
      v
打包 FilterKit.deb
      |
      v
传输到 RootHide 设备
      |
      v
Bootstrap / dpkg 安装
      |
      v
uicache 注册
      |
      v
从 iOS 主屏幕启动 FilterKit
      |
      v
执行 GUI 进程 PermissionProbe

这里的目录只是建议结构，最终安装路径、签名方式和安装脚本必须结合实际 RootHide 环境确定。

三、DEB 需要特别注意的五件事

1. 安装路径

建议优先评估：

<JBROOT>/Applications/FilterKit.app

不能未经验证就硬编码某个 JBROOT 路径。

2. Entitlements

需要验证实际签名中包含的 entitlement，例如此前研究的：

* platform-application
* no-sandbox
* storage.AppBundles
* storage.AppDataContainers

但不能因为 entitlement 出现在签名中，就认定系统一定放行。

3. 安装脚本

postinst 可以负责安装后的 App 注册，但不要在脚本中擅自修改插件、注入规则或系统配置。

4. App 启动

必须从 iOS 主屏幕真正启动 FilterKit，确认进程运行正常。

SSH 启动 CLI 不算 GUI 进程验证。

5. 权限验证

安装后分别测试：

* JBROOT 访问；
* TweakInject 枚举；
* dylib 读取；
* plist 读取和解析；
* dpkg 只读；
* jbroot() 调用。

这些才是 R3 真正要验证的内容。

⸻

四、建议增加一个 DEB 打包批次

我建议在 R3-B 前增加：

R3-A2 — RootHide Test Deployment Package

工作范围：

1. 确定 FilterKit .deb 包结构。
2. 确定 Bundle ID 和安装路径。
3. 确定签名与 entitlement 方案。
4. 编写最小化 DEBIAN/control。
5. 设计安全的 postinst 注册流程。
6. 验证 DEB 文件结构和完整性。
7. 生成 SHA256 和构建元数据。
8. 准备设备安装与卸载说明。

注意：这一步可以先在 CI 中完成 DEB 的构建和静态检查，不需要连接真机。

但真正的安装、uicache 注册、App 启动及权限验证，必须在 RootHide 真机上进行。

五、我的最终建议

FilterKit 不应该只准备一个 IPA 就直接开始 R3。

建议准备两个交付物：

文件	用途
FilterKit.ipa	普通安装方式的对照测试，可选
FilterKit.deb	RootHide 正式真机测试载体，优先

其中 DEB 是主要测试对象，IPA 是辅助对照对象，不要求两种方式都通过才能完成 R3。

下一步建议先冻结 R3-A2 的 DEB 部署规格，不要立即编写安装脚本或执行真机安装。 重点先确定特殊 entitlement 的签名方式、DEB 安装位置和 Bootstrap 安装通道是否能够配合工作。
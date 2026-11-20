我的建议是：不要让开发工作一直停在真机验收上，但也不要把 0.1-D 未完成的问题带进 0.1-E。应该把开发工作分成两条并行但相互独立的路线。

1. 产品开发路线：继续完成真机测试所需的设备构建、DEB 打包和安装准备。
2. 发布验收路线：保留 0.1-D 真机门禁，真机证据不足就不签署、不发布。

这样不会因为暂时没有 RootHide 真机，就让整个项目停止开发。

一、当前真正缺少的是什么？

根据你最新提供的七份产物核对结果，当前状态是：

模块	状态
Core / Models	已完成阶段验收
Enumeration / Pairing / Parser	已完成阶段验收
Reporting / JSON Export	已完成阶段验收
GUI Foundation	Simulator 验收通过
PermissionProbe	离线测试通过
D5 Entitlement	已实现证据分离，真机待验证
D6 jbroot()	已实现路径比较，真实调用待验证
iOS Device Build	尚未建立
IPA 打包	尚未建立
DEB 打包	尚未建立
RootHide 真机权限	未验证
0.1-E	尚未开始

我认为现在最大的开发缺口已经非常明确：

FilterKit 目前只有模拟器构建交付链，没有真正的 iOS 设备构建与 RootHide 部署链。

这应该成为下一阶段的主要开发目标。

⸻

二、建议增加 0.1-D-R4：Device Build & Deployment

我建议将下一阶段命名为：

0.1-D-R4 — iOS Device Build & RootHide Deployment

目标不是重复开发 PermissionProbe，而是让现有 FilterKit 真正具备上真机测试的条件。

建议分为六批。

批次	开发内容	主要目标
R4-A	iOS Device Build	生成 arm64 真机 App
R4-B	Signing & Entitlements	建立签名与 entitlement 配置
R4-C	IPA Packaging	生成普通 IPA 对照包
R4-D	DEB Packaging	生成 RootHide 测试 DEB
R4-E	Package Validation	验证架构、签名、路径、包结构
R4-F	Deployment Documentation	安装、启动、卸载及回滚说明

R4 可以先在 GitHub Actions 完成大部分工作。

不需要立即连接越狱手机。

R4-A：iOS Device Build

当前模拟器构建路径：

Debug-iphonesimulator/FilterKit.app

目标设备构建应该是：

Release-iphoneos/FilterKit.app

建议增加独立构建配置：

- name: Build iOS Device App
  run: |
    xcodebuild \
      -scheme FilterKit \
      -configuration Release \
      -sdk iphoneos \
      -destination 'generic/platform=iOS' \
      -derivedDataPath DerivedData \
      CODE_SIGNING_ALLOWED=NO \
      build

注意：

* 这段是 Xcode 构建方案示例，不是当前仓库已存在的 Workflow。
* CODE_SIGNING_ALLOWED=NO 只适用于先验证未签名设备产物的阶段。
* 它不会生成可以直接安装到 iPhone 的正式签名包。
* arm64 是普通 iPhone 真机的主要架构目标；不能把 arm64e 当成所有 iPhone 必须具备的 slice。
* 不应仅为了得到 arm64e 而随意修改架构配置。
* iOS 17.0.2 的最低系统版本兼容性还需要单独验证。

构建成功后，必须检查：

file FilterKit.app/FilterKit
lipo -info FilterKit.app/FilterKit
plutil -p FilterKit.app/Info.plist

重点是确认：

CFBundleSupportedPlatforms = iPhoneOS
DTPlatformName = iphoneos
Architectures include arm64

这才是真机设备构建，而不是模拟器构建。

R4-B：签名与 Entitlements

建议建立独立文件：

Config/
    Signing/
        FilterKit.entitlements
        FilterKit.Debug.xcconfig
        FilterKit.Release.xcconfig

entitlements 示例：

<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>platform-application</key>
    <true/>
    <key>no-sandbox</key>
    <true/>
    <key>storage.AppBundles</key>
    <true/>
    <key>storage.AppDataContainers</key>
    <true/>
</dict>
</plist>

这里必须强调：

以上只是此前部署研究中考虑过的 entitlement 配置示意，不是已经确认可用的签名方案。

需要分别验证：

1. 签名工具是否允许写入这些 entitlement。
2. 签名后的二进制是否包含这些 entitlement。
3. RootHide 环境是否接受该签名。
4. iOS 是否实际允许对应资源访问。

不能将 entitlement 写进文件就当作权限已经获得。

另外，普通 Apple Developer 签名与越狱环境的 ldid 签名是不同路线，不能混为一谈。

R4-C：IPA Packaging

IPA 主要用于普通安装对照。

建议结构：

FilterKit.ipa
    Payload/
        FilterKit.app/
            FilterKit
            Info.plist
            Frameworks/

构建命令示意：

mkdir -p IPA/Payload
cp -R FilterKit.app IPA/Payload/
cd IPA
zip -r FilterKit.ipa Payload

正式 IPA 还需要完成设备签名和对应的授权配置。

如果没有有效的设备安装签名，就只能称为未签名 IPA 结构包，不能称为可安装 IPA。

R4-D：DEB Packaging

这是我建议优先完成的部分。

目标包：

filterkit_0.1.0-1_iphoneos-arm64.deb

建议目录：

Package/
    Applications/
        FilterKit.app/
    DEBIAN/
        control
        postinst

control 示例：

Package: com.filterkit.manager
Name: FilterKit
Version: 0.1.0-1
Architecture: iphoneos-arm64
Description: RootHide & ElleKit Plugin Manager
Maintainer: FilterKit Development
Section: Utilities

postinst 示例：

#!/bin/sh
set -e
if [ "$1" = "configure" ]; then
    if command -v uicache >/dev/null 2>&1; then
        uicache -p /Applications/FilterKit.app
    fi
fi
exit 0

注意：这只是安装脚本示意。

实际 DEB 的安装路径必须由目标 RootHide Bootstrap 的包管理环境决定。不能未经验证就假设 /Applications 一定映射到预期的 JBROOT 位置。

也不能假设不同 Bootstrap 对 Architecture、包前缀和 uicache 的处理完全相同。

此外，DEB 安装脚本不应该：

* 修改 ElleKit 配置；
* 修改插件 plist；
* 删除或移动 dylib；
* 修改 dpkg 数据库；
* 自动授予权限；
* 修改系统 sandbox。

R4 只负责 App 部署。

R4-E：Package Validation

建议建立独立检查脚本：

Scripts/
    validate-device-build.sh
    validate-ipa.sh
    validate-deb.sh
    validate-entitlements.sh

检查内容：

检查	预期
平台	iPhoneOS
架构	arm64
最低系统版本	符合目标设备
Bundle ID	com.filterkit.manager
App 文件结构	完整
签名	与部署路线匹配
Entitlements	与批准配置一致
DEB 控制文件	合法
postinst	只做必要注册
SHA256	可复算一致

R4-E 通过不代表 RootHide 真机权限通过。

它只证明安装包本身符合部署要求。

⸻

三、0.1-E 是否可以提前开发？

我的建议是：可以，但要限定范围。

我认为没有必要让 Release Acceptance Engine 完全等到真机完成后才开始开发。

因为它是一个独立的证据管理模块，不需要访问真实 JBROOT。

建议将 0.1-E 分为两部分：

0.1-E-A：Release Acceptance Engine

可以提前开发。

功能：

* 门禁注册；
* 证据文件索引；
* SHA256 校验；
* Runner ID 校验；
* Commit SHA 校验；
* 证据环境检查；
* pending / failed / invalidEvidence 状态传播；
* 生成发布验收 JSON。

0.1-E-B：Final Release Acceptance

必须等 0.1-C 和 0.1-D 真正闭环后再执行。

功能：

* 验证所有正式发布门禁；
* 验证真机证据；
* 验证最终发布 Commit；
* 生成最终验收报告；
* 发布包完整性检查；
* 最终归档。

两者不能混为一谈。

可以提前开发验收工具，但不能提前签署发布通过。

⸻

四、建议的整体路线调整

我建议把开发计划调整成下面这样：

已完成
│
├── 0.1-A Engine
├── 0.1-B Reporting
├── 0.1-C GUI Foundation
└── 0.1-D PermissionProbe
      │
      ▼
0.1-D-R4 Device Build & Deployment
      │
      ├── R4-A Device Build
      ├── R4-B Signing
      ├── R4-C IPA
      ├── R4-D DEB
      ├── R4-E Validation
      └── R4-F Documentation
      │
      ▼
0.1-D-R3 RootHide Device Validation
      │
      ├── R3-B JBROOT
      ├── R3-C Plugin Files
      ├── R3-D Entitlements / jbroot()
      └── R3-E Cold Launch
      │
      ▼
0.1-C G10 独立补证
      │
      ▼
0.1-D Final Acceptance
      │
      ├─────────────────┐
      ▼                 ▼
0.1-E-A             继续产品完善
Release Engine       与测试
      │
      ▼
0.1-E-B
Final Release Acceptance
      │
      ▼
0.1.0 Release

这里有一个调整：R4 应先于 R3-B～E，因为没有真正可安装的设备包，就无法执行真实 GUI 进程探针。

⸻

五、还有一个比打包更重要的问题：UI 完成度

你提到软件还没有完善，UI 也不保证能开启。

我建议 R4 同时增加一个最小真机启动门禁：

R4-G：Device Launch Smoke Test。

只验证：

1. App 能安装。
2. App 能被 SpringBoard 识别。
3. App 能从主屏启动。
4. Dashboard 能显示。
5. Diagnostics 能打开。
6. Settings 能打开。
7. App 不崩溃。
8. PermissionProbe 能从 GUI 进程启动。

不要求插件管理功能已经完善。

但如果 App 启动失败，必须如实记录，不能跳过后继续把权限探针结果当作有效证据。

⸻

六、我的最终建议

我不建议你继续在没有设备包的情况下反复进行 R3 真机验收准备。

现在应该真正开始建立设备构建和部署能力。

我建议下一步授权：

0.1-D-R4-A～R4-E：iOS Device Build、签名方案准备、IPA/DEB 打包与静态验证。

暂时不包含：

* 真机安装；
* 真机签名放行验证；
* Bootstrap 实际部署；
* entitlement 真机权限验证；
* jbroot() 真机调用；
* 插件启停及任何插件写操作；
* 0.1-E Final Release Acceptance。

还有一点：当前我没有实际读取你的 DevDocs ZIP 和最新仓库源码，所以这些代码都是设计示例。真正实施前，应该先核对现有 Xcode 工程、Bundle ID、签名配置、CI Workflow 和 R2 的真实接口，避免重复创建文件或破坏已冻结的工程结构。

我的判断是：项目不应该停滞，但 0.1-D 的真机门禁也不能降低。先完成 R4，让 FilterKit 真正成为可部署到 RootHide iPhone 的 App，再回来完成 R3。
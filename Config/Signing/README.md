# FilterKit 签名与 Entitlement 配置（R4-B，静态准备，未验证放行）

> R4-B2 更新：设备构建仍先以 `CODE_SIGNING_ALLOWED=NO` 生成可复现 App，再由独立
> `scripts/sign-app-ldid.sh` 对 RootHide DEB 路线执行 ldid 签名。签名 blob 与嵌入 entitlement
> 可在 Runner 静态核对；这不证明 Bootstrap/amfid 接受、安装成功或运行时资源访问放行。

## 1. 文件

| 文件 | 用途 | 状态 |
|---|---|---|
| `FilterKit.entitlements` | 候选 entitlement 清单（四枚，见 §3） | 草稿，未绑定签名路线 |
| `FilterKit.Debug.xcconfig` | Debug 设备构建签名口径占位 | 离线 `CODE_SIGNING_ALLOWED=NO` |
| `FilterKit.Release.xcconfig` | Release 设备构建签名口径占位 | 离线 `CODE_SIGNING_ALLOWED=NO` |

## 2. 两条签名路线（必须分开记录，不得混用）

| 路线 | 工具/材料 | 适用 | 本轮状态 |
|---|---|---|---|
| **普通 Apple Developer 签名** | 开发证书 + 描述文件（Provisioning Profile）+ `CODE_SIGN_STYLE` | 普通沙盒 App 对照安装 | 未配置；`DEVELOPMENT_TEAM` / `PROVISIONING_PROFILE_SPECIFIER` 留空，待 Runner/真机前核实 |
| **越狱环境签名（ldid）** | ldid 签名 + 候选 entitlement 注入 | RootHide/Rootless 越狱文件访问 App | 未配置；ldid 写入参数、二进制包含性、bootstrap 接受度均待实测 |

两条路线的证书/描述文件/授权参数互不通用；候选 entitlement 与路线的绑定关系须在
R4-B 核实后逐条记录，不能把 Developer 路线的签名结论套到 ldid 路线，反之亦然。

## 3. 候选 entitlement（参考清单，非已确认可用方案）

- `platform-application`
- `com.apple.private.security.no-sandbox`
- `com.apple.private.security.storage.AppBundles`
- `com.apple.private.security.storage.AppDataContainers`

候选键来源：官方 RootHide Manager 解包与旧 0.1.18 PoC 参考
（`reference/0.1.18-src/entitlements.plist`，仅参考，不作新基线）。新增候选键须先过规格冻结。

## 4. 四条独立验证结论（不得互相替代）

1. 签名工具是否**允许写入**这些 entitlement；
2. 签名后二进制是否**实际包含**这些 entitlement；
3. RootHide 环境是否**接受**该签名；
4. iOS 是否**实际放行**对应资源访问。

任一条未取证，对应权限结论保持 unknown；静态格式校验（`validate-entitlements.sh`）
只覆盖第 1 条之前的文件可解析性与清单一致性。

## 5. 禁止事项（R4-A～E 范围）

- 不写入虚构证书、描述文件或团队标识；
- 不把"entitlement 已写入文件"记为"权限已获得"；
- 不执行真机签名安装、不验证签名被 bootstrap 接受；
- 不修改系统 sandbox 例外、不自动授予权限。

## 6. R4-B2 ldid 签名候选流程

```bash
APP_PATH=build/device/FilterKit.app \
ENTITLEMENTS_PATH=Config/Signing/FilterKit.entitlements \
  bash scripts/sign-app-ldid.sh sign build/device/FilterKit.app

APP_PATH=build/device/FilterKit.app \
ENTITLEMENTS_PATH=Config/Signing/FilterKit.entitlements \
  bash scripts/sign-app-ldid.sh verify build/device/FilterKit.app
```

脚本流程（0.1-D Diagnostics-Port 对齐 LDID-Signing-Fix 基线）：

1. App 内嵌套 Mach-O 一律 `ldid -S` 临时签名，**不携带主 App entitlement**；
2. 仅主 `CFBundleExecutable` 使用 `Config/Signing/FilterKit.entitlements` 签名；
3. 签完立即调用独立校验脚本 `scripts/validate-ldid-signature.sh`：逐个 Mach-O 检查
   `LC_CODE_SIGNATURE` 与 `ldid -h` CodeDirectory hash 可提取；主程序 `ldid -e` 提取嵌入
   entitlement 与候选 plist **精确比较**；输出静态摘要（`ldid_signed_static_valid` /
   `deviceAcceptance=unknown` / `deviceInstallable=false`）。

`verify` 模式委托同一独立校验脚本。静态签名/entitlement 一致不等于 amfid/Bootstrap 接受、
安装或启动；安装性仍是 `unknown`，不将此状态称为 `signed_valid` 或 `installable`。

普通 Apple Developer 签名仍是独立对照路线，不与 ldid 混用。候选私有 entitlement 的系统接受度、Bootstrap 安装路径、uicache 注册及 GUI 进程权限仍须 RootHide 真机证据。

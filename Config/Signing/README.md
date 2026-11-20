# FilterKit 签名与 Entitlement 配置（R4-B，静态准备，未验证放行）

> 边界：本目录承载签名声明配置；R4 设备构建阶段仍保持 `CODE_SIGNING_ALLOWED=NO`，随后在 CI 工作副本上通过 ldid 形成签名候选。此流程不使用虚构 Apple Developer 证书、不假定权限已放行、不执行真机安装验证。
> entitlement 出现在签名中 ≠ 系统授予对应权限；runtime entitlement 读取沿用 R1-B 结论
> （iOS GUI 进程无公开稳定枚举 API，runtime 证据保持 unavailable/unknown）。

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
| **越狱环境签名（ldid）** | ldid 签名 + 候选 entitlement 注入 | RootHide/Rootless 越狱文件访问 App | CI 签名链已接入；Runner 实跑与 bootstrap 接受度待验证 |

两条路线的证书/描述文件/授权参数互不通用；当前 DEB 仅使用 ldid 候选路线，不能把 Developer 路线的签名结论套到 ldid 路线，反之亦然。

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
覆盖源文件解析/候选清单/reference parity；签名后另由 `validate-ldid-signature.sh` 检查实际嵌入内容。

## 5. 禁止事项（本轮 CI 候选签名范围）

- 不写入虚构证书、描述文件或团队标识；
- 不把"entitlement 已写入文件"记为"权限已获得"；
- 不执行真机安装、不宣称签名已被 bootstrap 接受；
- 不修改系统 sandbox 例外、不自动授予权限。

## 6. R4 ldid 签名候选链（本轮实现）

`sign-app-ldid.sh` 在 CI 工作目录中对设备构建 App 副本执行签名：先签 App 内嵌套 Mach-O，再签主程序；主程序使用 `FilterKit.entitlements`。签名后 `validate-ldid-signature.sh` 对每个 Mach-O 检查 `LC_CODE_SIGNATURE` 与 `ldid -h`，并用 `ldid -e` 提取主程序实际嵌入的 entitlement，和源 plist 结构化比较，要求完全一致。

- `ldid_signed_static_valid` 只代表静态签名/嵌入内容校验通过。
- 不代表 RootHide / amfid 接受签名，也不代表 sandbox 访问已放行。
- IPA 路线仍为 unsigned structure 对照，不与 ldid DEB 路线混用。
- DEB 文件名固定带 `.ldid-signed-candidate.deb`，不得简称正式安装包。
- 候选包 `deviceInstallable=false`、`deviceInstallStatus=not-tested`，真机安装/启动仍须独立授权和取证。

脚本：`scripts/sign-app-ldid.sh`、`scripts/validate-ldid-signature.sh`。CI 日志及摘要随 `filterkit-deb` artifact 归档。完整门禁见 `Spec/FilterKit-0.1-E-Preflight.md`。

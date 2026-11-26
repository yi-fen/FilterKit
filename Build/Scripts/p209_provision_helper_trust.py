#!/usr/bin/env python3
"""Two-pass, fail-closed signing/provisioning helper for FilterKit P2-09.

Pass 1 runs after Helper signing and before App signing. Pass 2 runs after App signing.
This tool never signs binaries, installs files, starts launchd jobs, or enables execution.
"""
import argparse, json, os, plistlib, re, subprocess, sys
from pathlib import Path

CDHASH_RE = re.compile(r"(?im)^\s*CDHash\s+([0-9a-f]{40})\s*$")
BUNDLE_RE = re.compile(r"^[A-Za-z][A-Za-z0-9-]*(?:\.[A-Za-z][A-Za-z0-9-]*)+$")
IDENT_RE = re.compile(r"^[A-Za-z0-9._+-]{1,128}$")


def cdhash(path: str) -> str:
    p = Path(path)
    if not p.exists():
        raise ValueError(f"签名产物不存在: {path}")
    result = subprocess.run(["/usr/bin/codesign", "-d", "--verbose=4", str(p)],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    output = result.stdout + "\n" + result.stderr
    match = CDHASH_RE.search(output)
    if result.returncode != 0 or not match:
        raise ValueError(f"无法从 codesign 读取 CDHash: {path}; 请确认产物已完成签名")
    return match.group(1).lower()


def validate_common(bundle_id, generation, helper_hash):
    if not BUNDLE_RE.fullmatch(bundle_id): raise ValueError("Bundle ID 格式无效")
    if generation <= 0: raise ValueError("generation 必须大于 0")
    if not re.fullmatch(r"[0-9a-f]{40}", helper_hash): raise ValueError("Helper CDHash 无效")


def write_json(path, value):
    target = Path(path); target.parent.mkdir(parents=True, exist_ok=True)
    data = json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    tmp = target.with_suffix(target.suffix + ".tmp")
    tmp.write_text(data, encoding="utf-8")
    os.replace(tmp, target)


def prepare(args):
    helper_hash = cdhash(args.helper)
    validate_common(args.bundle_id, args.generation, helper_hash)
    trust = {"schemaVersion": 1, "bundleIdentifier": args.bundle_id,
             "allowedHelperCDHashes": [helper_hash], "generation": args.generation,
             "allowedHelperUIDs": [0], "allowedHelperGIDs": [0]}
    write_json(args.output, trust)
    print(f"Helper CDHash: {helper_hash}\nApp Trust 配置已生成: {args.output}")
    print("下一步：将该 JSON 作为 FilterKit-Helper-AppTrust.json 嵌入 App，再完成 App 最终签名。")


def finalize(args):
    helper_hash = cdhash(args.helper); app_hash = cdhash(args.app)
    validate_common(args.bundle_id, args.generation, helper_hash)
    if app_hash == helper_hash: raise ValueError("App 与 Helper CDHash 不应相同；检查签名产物")
    if args.jbroot == "/" or not args.jbroot.startswith("/") or "/../" in args.jbroot + "/":
        raise ValueError("JBROOT 必须是干净的绝对路径且不能是 /")
    root = args.jbroot.rstrip("/")
    tweak = root + "/usr/lib/TweakInject"
    staging = root + "/var/FilterKit/Staging"
    socket = root + "/Library/FilterKit/Helper/helper.sock"
    if len(socket.encode()) >= 100: raise ValueError("Unix socket 路径超过 sockaddr_un 安全长度")
    if args.client_uid == 0 or args.socket_gid == 0 or args.staging_uid == 0: raise ValueError("UID 必须为非 root 用户")
    if not IDENT_RE.fullmatch(args.release_id) or not IDENT_RE.fullmatch(args.route_id):
        raise ValueError("release-id 或 route-id 格式无效")
    bundle = {
      "schemaVersion": 2, "generation": args.generation, "releaseIdentifier": args.release_id,
      "bundleIdentifier": args.bundle_id, "jbRootPath": root, "appCDHash": app_hash,
      "helperCDHash": helper_hash, "allowedClientUID": args.client_uid,
      "socketGroupID": args.socket_gid, "stagingOwnerUID": args.staging_uid, "routeIdentifier": args.route_id,
      "tweakInjectPath": tweak, "stagingRootPath": staging, "socketPath": socket,
      "helperVersion": args.helper_version
    }
    app_trust = {"schemaVersion": 1, "bundleIdentifier": args.bundle_id,
                 "allowedHelperCDHashes": [helper_hash], "generation": args.generation,
             "allowedHelperUIDs": [0], "allowedHelperGIDs": [0]}
    root_manifest = {
      "schemaVersion": 2, "routeIdentifier": args.route_id, "jbRootPath": root,
      "tweakInjectPath": tweak, "stagingRootPath": staging, "socketPath": socket,
      "allowedAppCDHashes": [app_hash], "allowedHelperCDHashes": [helper_hash],
      "allowedClientUIDs": [args.client_uid], "socketGroupID": args.socket_gid, "stagingOwnerUID": args.staging_uid,
      "executionEnabled": False
    }
    launchd = {"Label": "cn.yfen.filterkit.helper", "ProgramArguments": [root + "/usr/libexec/filterkit-helper"],
               "Disabled": True, "RunAtLoad": False, "KeepAlive": False,
               "ProcessType": "Background", "StandardOutPath": "/dev/null", "StandardErrorPath": "/dev/null"}
    out = Path(args.output_dir); out.mkdir(parents=True, exist_ok=True)
    write_json(out / "FilterKit-Helper-AppTrust.json", app_trust)
    write_json(out / "FilterKit-Helper-InstallerProvisioning.json", bundle)
    write_json(out / "FilterKit-Helper-RootManifest.DISABLED.json", root_manifest)
    with open(out / "cn.yfen.filterkit.helper.plist", "wb") as f:
        plistlib.dump(launchd, f, fmt=plistlib.FMT_XML, sort_keys=True)
    print(f"App CDHash: {app_hash}\nHelper CDHash: {helper_hash}")
    print(f"只生成已关闭的配置模板: {out}")
    print("未安装、未启动 Helper，未修改 JBROOT，executionEnabled=false / Disabled=true。")


def main():
    p = argparse.ArgumentParser(description=__doc__); sub = p.add_subparsers(required=True)
    a = sub.add_parser("prepare", help="Helper 签名后、App 签名前生成 App Trust JSON")
    a.add_argument("--helper", required=True); a.add_argument("--bundle-id", required=True)
    a.add_argument("--generation", type=int, required=True); a.add_argument("--output", required=True)
    a.set_defaults(func=prepare)
    b = sub.add_parser("finalize", help="App 最终签名后生成 installer provisioning 和关闭状态模板")
    b.add_argument("--helper", required=True); b.add_argument("--app", required=True)
    b.add_argument("--bundle-id", required=True); b.add_argument("--generation", type=int, required=True)
    b.add_argument("--jbroot", required=True); b.add_argument("--client-uid", type=int, required=True)
    b.add_argument("--staging-uid", type=int, required=True); b.add_argument("--socket-gid", type=int, required=True, help="Installed App primary GID measured on the target device"); b.add_argument("--route-id", required=True)
    b.add_argument("--release-id", required=True); b.add_argument("--helper-version", required=True)
    b.add_argument("--output-dir", required=True); b.set_defaults(func=finalize)
    args = p.parse_args()
    try: args.func(args)
    except (ValueError, OSError, subprocess.SubprocessError) as e:
        print(f"ERROR: {e}", file=sys.stderr); return 2
    return 0

if __name__ == "__main__": sys.exit(main())

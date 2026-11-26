#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENVIRONMENT="${ENVIRONMENT:?ENVIRONMENT is required}"
PROFILE="${PROFILE:-Auto}"
CONFIGURATION="${CONFIGURATION:-Release}"
ARCHITECTURE="${ARCHITECTURE:-arm64}"
# iOS application bundles must carry the arm64 app ABI. arm64e is a device /
# jailbreak runtime label, not an app-bundle build target for this project.
APP_ARCHITECTURE="arm64"
PACKAGE="${PACKAGE:-None}"
CLEAN_BUILD="${CLEAN_BUILD:-true}"
RUN_TESTS="${RUN_TESTS:-false}"
SIMULATOR_DESTINATION="${SIMULATOR_DESTINATION:-platform=iOS Simulator,name=iPhone 16,OS=latest}"
OUT="$ROOT/Build/Output/$ENVIRONMENT"
mkdir -p "$OUT"

python3 "$ROOT/Build/Scripts/resolve-profile.py" --environment "$ENVIRONMENT" --profile "$PROFILE" --output "$OUT/profile.json"
if [[ "$PACKAGE" == "DEB" || "$PACKAGE" == "Both" ]]; then
  if [[ "$ENVIRONMENT" != "RootHide" ]]; then
    echo "ERROR: DEB/Both packaging is enabled only for RootHide; the Rootless DEB layout remains unverified. Use IPA or None for Rootless." >&2
    exit 30
  fi
  if ! command -v dpkg-deb >/dev/null 2>&1; then
    echo "ERROR: dpkg-deb is required. Install it with: brew install dpkg" >&2
    exit 31
  fi
fi

if [[ "$CLEAN_BUILD" == "true" ]]; then rm -rf "$ROOT/.build/DerivedData"; fi
if ! command -v xcodegen >/dev/null 2>&1 || ! command -v xcodebuild >/dev/null 2>&1; then
  echo "ERROR: run on macOS with Xcode and XcodeGen installed." >&2; exit 31
fi
cd "$ROOT"
xcodegen generate --spec Project.yml
DERIVED="$ROOT/.build/DerivedData/$ENVIRONMENT-$ARCHITECTURE"
mkdir -p "$DERIVED"
case "$ARCHITECTURE" in
  arm64|arm64e|Both)
    ARCHS_VALUE="$APP_ARCHITECTURE"
    ;;
  *)
    echo "ERROR: unsupported architecture selection '$ARCHITECTURE'. Select arm64 or arm64e device profile; the iOS app payload is built as arm64." >&2
    exit 33
    ;;
esac
printf 'Requested device architecture: %s; actual iOS app architecture: %s\n' "$ARCHITECTURE" "$APP_ARCHITECTURE"
if [[ "$RUN_TESTS" == "true" ]]; then
  xcodebuild -project FilterKit.xcodeproj -scheme FilterKit -configuration "$CONFIGURATION" -destination "$SIMULATOR_DESTINATION" -derivedDataPath "$DERIVED" ARCHS=arm64 CODE_SIGNING_ALLOWED=NO test
fi
xcodebuild -project FilterKit.xcodeproj -scheme FilterKit -configuration "$CONFIGURATION" -destination 'generic/platform=iOS' -derivedDataPath "$DERIVED" ARCHS="$ARCHS_VALUE" ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build | tee "$OUT/xcodebuild.log"
APP="$DERIVED/Build/Products/$CONFIGURATION-iphoneos/FilterKit.app"
if [[ ! -d "$APP" ]]; then echo "ERROR: expected app product not found: $APP" >&2; exit 32; fi
cp -R "$APP" "$OUT/FilterKit.app"
# Keep the raw Xcode product untouched here. The RootHide DEB pipeline signs
# the staged payload with ldid (R16.1 route) and verifies every Mach-O after
# packaging; Apple ad-hoc codesign is not substituted for the jailbreak signer.
if [[ "$PACKAGE" == "IPA" || "$PACKAGE" == "Both" ]]; then
  mkdir -p "$OUT/ipa/Payload"
  cp -R "$APP" "$OUT/ipa/Payload/FilterKit.app"
  (cd "$OUT/ipa" && /usr/bin/zip -qry "$OUT/FilterKit-unsigned.ipa" Payload)
fi
if [[ "$PACKAGE" == "DEB" || "$PACKAGE" == "Both" ]]; then
  bash "$ROOT/Build/Scripts/package-deb.sh" "$ENVIRONMENT" "$OUT/FilterKit.app" "$OUT"
fi
python3 - "$ROOT" "$OUT" "$ENVIRONMENT" "$CONFIGURATION" "$ARCHITECTURE" "$PACKAGE" "$APP_ARCHITECTURE" <<'PY2'
import sys,json,hashlib,subprocess,platform,datetime
from pathlib import Path
root,out,env,config,arch,pkg,app_arch=map(str,sys.argv[1:])
out=Path(out)
def sha(p):
 h=hashlib.sha256()
 with open(p,'rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''): h.update(b)
 return h.hexdigest()
files=[]
for p in sorted(out.rglob('*')):
 if p.is_file() and p.name not in ('build-report.json','SHA256SUMS.txt'):
  files.append({'path':str(p.relative_to(out)),'sha256':sha(p),'size':p.stat().st_size})
try: commit=subprocess.check_output(['git','-C',root,'rev-parse','HEAD'],text=True).strip()
except Exception: commit='unknown-or-uncommitted'
report={'project':'FilterKit','environment':env,'profile':json.loads((out/'profile.json').read_text()),'configuration':config,'requestedDeviceArchitecture':arch,'appBinaryArchitecture':app_arch,'package':pkg,'timestampUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'macOS':platform.platform(),'xcode':subprocess.getoutput('xcodebuild -version'),'swift':subprocess.getoutput('swift --version').splitlines()[0] if subprocess.call(['bash','-lc','command -v swift >/dev/null 2>&1'],stdout=subprocess.DEVNULL)==0 else 'unknown','gitCommit':commit,'artifacts':files}
(out/'build-report.json').write_text(json.dumps(report,indent=2)+'\n')
(out/'SHA256SUMS.txt').write_text(''.join(f"{x['sha256']}  {x['path']}\n" for x in files))
PY2

#!/usr/bin/env python3
from pathlib import Path
import sys
root = Path(__file__).resolve().parents[2]
checks = []
def check(name, condition):
    checks.append((name, bool(condition)))

macho = (root / 'Sources/Environment/MachOMetadataReader.swift').read_text()
scanner = (root / 'Sources/Environment/ReadOnlyPluginScanner.swift').read_text()
filter_model = (root / 'Sources/Core/Models/PluginFilterConfiguration.swift').read_text()
settings = (root / 'Sources/Features/Settings/SettingsView.swift').read_text()
app_identity = (root / 'Sources/Environment/AppBinaryIdentityInspector.swift').read_text()
ui = (root / 'Sources/Features/Plugins/PluginsView.swift').read_text()
check('Mach-O CodeDirectory CDHash extraction', 'cdhash_extracted' in macho and 'SHA256Digest.hex(cd)' in macho)
check('CodeDirectory identifier/team/flags/platform', all(x in macho for x in ['codeSignatureIdentifier', 'codeSignatureTeamIdentifier', 'codeSignatureFlags', 'codeSignaturePlatform']))
check('Fat/thin Mach-O slice enumeration', 'readSlices(data: Data)' in macho and 'CAFEBABE' in macho)
check('Bounded read-only dylib hashing and parsing', 'maximumDylibBytes' in scanner and 'MachOMetadataReader().readSlices' in scanner and 'SHA256Digest.hex(data)' in scanner)
check('Filter fields parsed and surfaced', all(x in filter_model for x in ['Bundles', 'Executables', 'Classes', 'Mode']))
check('Mode boolean/value projection', 'CFGetTypeID(value) == CFBooleanGetTypeID()' in filter_model)
check('Plugin detail displays signature metadata', 'machOSliceDetails' in ui and 'plugins.macho.signature_state' in ui)
check('FilterKit own main executable identity inspector', 'Bundle = .main' in app_identity and 'MachOMetadataReader().readSlices' in app_identity)
home = (root / 'Sources/Features/Home/HomeView.swift').read_text()
check('Home exposes plugin Filter inventory and ElleKit profile summary', all(x in home for x in ['home.filter_health', 'home.filter.parsed', 'home.filter.invalid', 'home.environment.status']))
check('Settings retains low-level Filter diagnostics and App identity', all(x in settings for x in ['settings.filter.ellekit_profile', 'settings.filter.refresh', 'settings.identity.cdhash']))
for file, key in [
    ('Sources/Environment/Deployment/PluginToggleReleaseGate.swift','productionMutationReleased = false'),
    ('Sources/Environment/Helper/HelperDeploymentCoordinator.swift','executionReleased = false'),
    ('Sources/Environment/Helper/HelperDeploymentCoordinator.swift','pluginAssociationCommitReleased = false'),
    ('Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift','executionReleased = false'),
    ('Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift','pluginAssociationCommitReleased = false'),
    ('Sources/Environment/Helper/Execution/HelperProductionDeploymentBackend.swift','executionReleased = false'),
]:
    check(f'Production gate remains closed: {Path(file).name}:{key}', key in (root/file).read_text())
failed = [name for name, ok in checks if not ok]
for name, ok in checks:
    print(('PASS' if ok else 'FAIL') + ' ' + name)
print(f'P2-33 static audit: {len(checks)-len(failed)}/{len(checks)} passed')
if failed: sys.exit(1)

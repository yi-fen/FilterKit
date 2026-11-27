#!/usr/bin/env python3
from pathlib import Path
root = Path(__file__).resolve().parents[2]
checks = {
    'full-set action exists': 'case replaceSoftAssociations' in (root/'Sources/Core/Models/Helper/HelperPluginFilterMutationModels.swift').read_text(),
    'intent carries desired set': 'desiredSoftAssociations' in (root/'Sources/Core/Models/Helper/HelperPluginFilterMutationModels.swift').read_text(),
    'new associations default disabled': '?? !item.isEnabled' in (root/'Sources/Environment/Helper/Execution/HelperPluginFilterMutationAuthorizer.swift').read_text(),
    'existing activation bits immutable': 'oldByID[item.bundleIdentifier].map { $0 == item.isEnabled }' in (root/'Sources/Environment/Helper/Execution/HelperPluginFilterMutationAuthorizer.swift').read_text(),
    'enabled association removal blocked': 'desiredByID[$0.bundleIdentifier] != nil || !$0.isEnabled' in (root/'Sources/Environment/Helper/Execution/HelperPluginFilterMutationAuthorizer.swift').read_text(),
    'association-only plist preserved': 'replacementPlistData: plistData' in (root/'Sources/Environment/Helper/Execution/HelperPluginFilterMutationAuthorizer.swift').read_text(),
    'two-file journal transaction exists': 'replacingManifest' in (root/'Sources/Environment/Helper/Execution/HelperPluginFilterConfigurationTransaction.swift').read_text(),
    'plugin detail save entry exists': 'plugins.association_manager.save' in (root/'Sources/Features/Plugins/PluginsView.swift').read_text(),
    'English save resources': '"plugins.association_manager.save"' in (root/'Resources/en.lproj/Localizable.strings').read_text(),
    'Chinese save resources': '"plugins.association_manager.save"' in (root/'Resources/zh-Hans.lproj/Localizable.strings').read_text(),
    'App release gate closed': 'static let pluginAssociationCommitReleased = false' in (root/'Sources/Environment/Helper/HelperDeploymentCoordinator.swift').read_text(),
    'Helper release gate closed': 'static let pluginAssociationCommitReleased = false' in (root/'Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift').read_text(),
}
for name, ok in checks.items(): print(('PASS' if ok else 'FAIL') + ' ' + name)
print(f'{sum(checks.values())}/{len(checks)} checks passed')
raise SystemExit(0 if all(checks.values()) else 1)

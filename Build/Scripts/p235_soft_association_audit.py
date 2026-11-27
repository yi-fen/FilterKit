#!/usr/bin/env python3
from pathlib import Path
import sys
root = Path(__file__).resolve().parents[2]
plugins = (root / 'Sources/Features/Plugins/PluginsView.swift').read_text()
apps = (root / 'Sources/Features/Apps/AppsView.swift').read_text()
plan = (root / 'Sources/Core/Models/PluginAssociationPlan.swift').read_text()
tests = (root / 'Tests/UnitTests/PluginAssociationPlanTests.swift').read_text()
zh = (root / 'Resources/zh-Hans.lproj/Localizable.strings').read_text()
en = (root / 'Resources/en.lproj/Localizable.strings').read_text()
checks = []
def check(name, ok): checks.append((name, bool(ok)))
check('Plugin detail embeds soft association manager', 'PluginSoftAssociationManagerSection(plugin: plugin)' in plugins)
check('Manager lists installed Apps excluding immutable hard-bound App', 'apps.filter { $0.bundleIdentifier != hardBoundID }' in plugins)
check('Hard-bound identity is shown as locked', 'plugins.association_manager.hard_bound' in plugins and 'lock.shield' in plugins)
check('Only FilterKit-owned, authorized, paired, conflict-free plugins are editable', all(x in plugins for x in ['plugin.ownership == .filterKit', 'plugin.managementPermission?.canModify == true', 'plugin.pairingState == .paired', 'plugin.ownershipConflict == .none', 'plugin.identityConflictIDs.isEmpty']))
check('Association selection adds/removes soft relationships only', all(x in plugins for x in ['.addSoft(bundleIdentifier:', '.restoreSoft(association: prior)', '.removeSoft(bundleIdentifier:', 'toggleAssociation(for app: InstalledApp)']))
check('Missing installed Apps remain visible and removable', all(x in plugins for x in ['missingAssociatedIDs', 'plugins.association_manager.missing_app']))
check('New association defaults disabled, never auto-enables injection', 'PluginSoftAssociation(bundleIdentifier: bundleID, isEnabled: false)' in plan)
check('Existing per-App activation bits are preserved in draft', 'plugin.softAssociationStates' in plugins and 'isEnabled: $0.isEnabled' in plugins and '.restoreSoft(association: prior)' in plugins)
check('Plugin page has no enable/disable or Helper commit operation', all(x not in plugins for x in ['preview_enable', 'preview_disable', 'commitAssociation(action:', 'HelperPluginAssociationCommitService.production()']))
check('Association editing is explicitly local draft only', all(x in plugins for x in ['plugins.association_manager.not_saved', 'plugins.association_manager.review_only', 'showingReview = true']))
check('No association write path was opened', 'pluginAssociationCommitReleased = false' in (root/'Sources/Environment/Helper/HelperDeploymentCoordinator.swift').read_text() and 'pluginAssociationCommitReleased = false' in (root/'Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift').read_text())
check('APP page remains the only first-time dylib/plist importer', 'fileImporter(isPresented: $isImportingPlugin' in apps and 'apps.detail.import_plugin' in apps and 'fileImporter(isPresented: $isImportingPlugin' not in plugins)
check('Plugins page still only imports FilterKit backup data', 'fileImporter(isPresented: $isImportingBackup' in plugins and 'filterkitbackup' in plugins)
check('Tests cover new associations remaining inactive', 'testAddingSoftAssociationDoesNotEnableInjection' in tests and 'isEnabled: false' in tests)
keys = [line.split('=', 1)[0].strip() for line in zh.splitlines() if '=' in line and line.strip().startswith('"')]
en_keys = [line.split('=', 1)[0].strip() for line in en.splitlines() if '=' in line and line.strip().startswith('"')]
check('Chinese and English association-manager localization keys match', set(keys) == set(en_keys) and len(keys) == len(set(keys)) and len(en_keys) == len(set(en_keys)))
for name, ok in checks: print(('PASS ' if ok else 'FAIL ') + name)
failed = [name for name, ok in checks if not ok]
print(f'P2-35 soft-association audit: {len(checks)-len(failed)}/{len(checks)} passed')
if failed: sys.exit(1)

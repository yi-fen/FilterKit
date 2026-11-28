from pathlib import Path

root = Path(__file__).resolve().parents[2]
ui = (root / 'Sources/Features/Plugins/PluginsView.swift').read_text()
association_model = (root / 'Sources/Core/Models/PluginAssociationPlan.swift').read_text()
zh = (root / 'Resources/zh-Hans.lproj/Localizable.strings').read_text()
en = (root / 'Resources/en.lproj/Localizable.strings').read_text()
checks = {
    'Plugin page contains no per-App activation Toggle control': 'Toggle(' not in ui,
    'Plugin page contains no activation-edit operation': 'setSoftEnabled' not in ui and 'setSoftEnabled' not in association_model,
    'Plugin page uses checkmark buttons for association membership': 'toggleAssociation(for: app)' in ui,
    'Association page explicitly directs activation control to Apps page': 'plugins.association_manager.activation_from_app' in ui,
    'Chinese responsibility copy is explicit': '本页只管理扩展关联，不控制注入启停' in zh,
    'English responsibility copy is explicit': 'does not control injection' in en,
    'Plugin list observes shared registry': '@ObservedObject private var registry = PluginScanRegistry.shared' in ui,
    'Detail page resolves current plugin from shared snapshot': 'registry.result?.plugins.first(where: { $0.id == plugin.id }) ?? plugin' in ui,
    'Pull-to-refresh forces shared registry refresh': '.refreshable { model.refresh() }' in ui and 'registry.refresh()' in ui,
    'Initial load reuses snapshot without forcing duplicate scan': 'registry.loadIfNeeded()' in ui,
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(('PASS' if ok else 'FAIL') + ' ' + name)
if failed:
    raise SystemExit(1)
print(f'All {len(checks)} checks passed.')

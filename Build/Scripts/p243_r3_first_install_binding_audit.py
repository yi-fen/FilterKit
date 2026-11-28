#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[2]
policy = (root / 'Sources/Core/Models/PluginFirstInstallBindingPolicy.swift').read_text()
backend = (root / 'Sources/Environment/Helper/Execution/HelperProductionDeploymentBackend.swift').read_text()
bootstrap = (root / 'Sources/Environment/Helper/Execution/HelperFirstInstallManifestBootstrap.swift').read_text()
reader = (root / 'Sources/Core/Models/Helper/HelperAppPluginActivationStateReader.swift').read_text()
transaction = (root / 'Sources/Environment/Helper/Execution/HelperPluginFilterConfigurationTransaction.swift').read_text()
checks = {
    'first-install policy emits schema 4': 'FilterKitPluginManifest(schemaVersion: 4' in policy,
    'fixed owner defaults enabled': 'fixedOwnerIsEnabled: true' in policy,
    'filter targets equal enabled binding projection': 'filterKeys == expectedEnabled' in policy,
    'case-insensitive association duplicate detection': 'seen.insert(key).inserted' in policy,
    'owner cannot repeat as association': 'ownerRepeatedAsAssociation' in policy and 'key != HelperBundleIdentifierKey.make(owner)' in policy,
    'production first-install backend uses shared policy': 'PluginFirstInstallBindingPolicy.makeManifest' in backend,
    'production first-install proof declares schema 4': 'manifestSchemaVersion: 4' in backend,
    'root bootstrap uses shared policy': 'PluginFirstInstallBindingPolicy.makeManifest' in bootstrap,
    'root bootstrap proof declares schema 4': 'manifestSchemaVersion: 4' in bootstrap,
    'activation reader supports schema 4': 'case 4:' in reader,
    'configuration transaction supports schema 4': 'manifest.schemaVersion == 4' in transaction,
    'legacy schema 3 update path remains': 'updatedManifest = FilterKitPluginManifest(schemaVersion: 3' in backend,
    'schema 4 update preserves owner enabled bit': 'fixedOwnerIsEnabled: oldTopology.fixedOwnerIsEnabled' in backend,
    'schema 4 update preserves association states': 'additionalAssociations: normalized' in backend,
}
for name, passed in checks.items():
    print(('PASS' if passed else 'FAIL') + ': ' + name)
if not all(checks.values()):
    raise SystemExit(1)
print(f'P2-43-R3 first-install binding audit: {len(checks)} assertions passed')

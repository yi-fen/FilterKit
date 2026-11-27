import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}


@main
struct P235Smoke {
    static func main() {
        let pluginID = UUID()
        let hardBound = "com.example.source"
        let existing = PluginSoftAssociation(bundleIdentifier: "com.example.existing", isEnabled: false)
        let plan = PluginAssociationPlan(pluginID: pluginID, hardBoundBundleIdentifier: hardBound,
                                         softAssociations: [existing])
        let installed: Set<String> = [hardBound, "com.example.existing", "com.example.new"]
        let editor = PluginAssociationPlanEditor()

        let addResult = editor.applying(.addSoft(bundleIdentifier: "com.example.new"), to: plan,
                                        installedBundleIdentifiers: installed, pluginIsManageable: true)
        guard case .success(let added) = addResult else { fatalError("new soft association should be accepted") }
        expect(added.softAssociations.first(where: { $0.bundleIdentifier == "com.example.new" })?.isEnabled == false,
               "new association must remain inactive")
        expect(added.softAssociations.first(where: { $0.bundleIdentifier == "com.example.existing" })?.isEnabled == false,
               "existing activation state must be preserved")

        let hardBoundResult = editor.applying(.addSoft(bundleIdentifier: hardBound), to: plan,
                                              installedBundleIdentifiers: installed, pluginIsManageable: true)
        if case .failure(let error) = hardBoundResult {
            expect(error == .hardBoundIsImmutable, "hard-bound App must be immutable")
        } else { fatalError("hard-bound App was incorrectly accepted as a soft association") }

        let unauthorized = editor.applying(.addSoft(bundleIdentifier: "com.example.new"), to: plan,
                                           installedBundleIdentifiers: installed, pluginIsManageable: false)
        if case .failure(let error) = unauthorized {
            expect(error == .pluginNotManageable, "unauthorized plugin must remain read-only")
        } else { fatalError("unauthorized plugin association edit was accepted") }

        let removeResult = editor.applying(.removeSoft(bundleIdentifier: "com.example.existing"), to: added,
                                           installedBundleIdentifiers: installed, pluginIsManageable: true)
        guard case .success(let removed) = removeResult else { fatalError("soft association removal should be accepted") }
        expect(removed.softAssociations.map(\.bundleIdentifier) == ["com.example.new"], "only selected soft association should be removed")
        expect(removed.hardBoundBundleIdentifier == hardBound, "hard-bound identity must remain unchanged")

        let activeOriginal = PluginSoftAssociation(bundleIdentifier: "com.example.active", isEnabled: true)
        let activePlan = PluginAssociationPlan(pluginID: pluginID, hardBoundBundleIdentifier: hardBound,
                                               softAssociations: [activeOriginal])
        let activeRemoved = try! editor.applying(.removeSoft(bundleIdentifier: activeOriginal.bundleIdentifier), to: activePlan,
            installedBundleIdentifiers: installed.union([activeOriginal.bundleIdentifier]), pluginIsManageable: true).get()
        let activeRestored = try! editor.applying(.restoreSoft(association: activeOriginal), to: activeRemoved,
            installedBundleIdentifiers: installed.union([activeOriginal.bundleIdentifier]), pluginIsManageable: true).get()
        expect(activeRestored.softAssociations == [activeOriginal], "remove/re-add must preserve the original activation bit")

        let resolution = PluginAssociationPlanResolver().resolve(added, installedBundleIdentifiers: installed)
        expect(resolution.enabledSoftBundleIdentifiers.isEmpty, "association draft must not activate any App")
        expect(resolution.disabledSoftBundleIdentifiers == ["com.example.existing", "com.example.new"], "draft associations should remain disabled")
        print("P2-35 soft-association smoke: PASS (add inactive, preserve states, restore state, hard-bound immutable, unauthorized denied, remove soft only)")
    }
}

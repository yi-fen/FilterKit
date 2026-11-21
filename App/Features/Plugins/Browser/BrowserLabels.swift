//
//  BrowserLabels.swift
//  FilterKit 0.1-E2 Plugin List & Discovery
//
//  E1 只读状态 → 展示文案与分级的唯一落点。unknown / unverified 不等于失败；
//  loaded unknown 显示「加载状态未知」，不得显示「未加载」。
//

import Foundation
import Core

enum BrowserLabels {

    static func installed(_ state: FKPluginState) -> DisplayStatus {
        switch state {
        case .confirmed: DisplayStatus(kind: .success, text: "Installed")
        case .absent: DisplayStatus(kind: .warning, text: "Missing")
        case .unverified: DisplayStatus(kind: .failure, text: "Unverified")
        case .unknown: DisplayStatus(kind: .unknown, text: "Unknown")
        }
    }

    static func configured(_ state: FKPluginState) -> DisplayStatus {
        switch state {
        case .confirmed: DisplayStatus(kind: .success, text: "Configured")
        case .absent: DisplayStatus(kind: .warning, text: "Not Configured")
        case .unverified: DisplayStatus(kind: .failure, text: "Unverified")
        case .unknown: DisplayStatus(kind: .unknown, text: "Unknown")
        }
    }

    static func loaded(_ state: FKPluginState) -> DisplayStatus {
        switch state {
        case .confirmed: DisplayStatus(kind: .success, text: "Loaded")
        case .absent: DisplayStatus(kind: .warning, text: "Not Loaded")
        case .unverified: DisplayStatus(kind: .failure, text: "Unverified")
        case .unknown:
            DisplayStatus(kind: .unknown, text: "Unknown",
                          detail: "Runtime state not verified")
        }
    }

    static func associationSummary(_ entry: PluginListEntry) -> String {
        if entry.exactMatchCount > 0 {
            return "\(entry.exactMatchCount) Associated App\(entry.exactMatchCount == 1 ? "" : "s")"
        }
        guard let category = entry.associationCategories.first else {
            return "No Association"
        }
        switch category {
        case .globalRule: return "Global Rule"
        case .unmatchedTarget: return "Unmatched Target"
        case .invalidConfiguration: return "Invalid Configuration"
        case .unresolved: return "Unresolved"
        case .exactMatch: return "No Association"
        }
    }
}

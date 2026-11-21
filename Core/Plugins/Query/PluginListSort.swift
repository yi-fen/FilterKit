//
//  PluginListSort.swift
//  FilterKit 0.1-E2 Plugin List & Discovery
//
//  E2 第一版开放名称升序/降序；`.evidence` 为内部扩展项，证据等级排序优先级
//  待 E3/E4 确认前不在 UI 暴露。
//

import Foundation

public enum PluginListSort: Equatable {
    case nameAscending
    case nameDescending
    case evidence
}

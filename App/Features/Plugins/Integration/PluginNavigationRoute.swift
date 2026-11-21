//
//  PluginNavigationRoute.swift
//  FilterKit 0.1-E4 Plugin Feature Integration & Dependency
//
//  插件功能统一路由。String 为稳定模型 ID（插件 id / App bundleID），
//  禁用显示名作导航 ID；根视图单一 NavigationStack 按路由解析目的地。
//

import Foundation

enum PluginNavigationRoute: Hashable {
    /// 插件详情（插件稳定 ID）。
    case plugin(String)
    /// App 详情（App bundleID）。
    case application(String)
    /// App 库存列表（根栈内入口；规格 §4.2 D5 偏差记录）。
    case applicationList
}

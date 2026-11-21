//
//  PluginFileInformationSection.swift
//  FilterKit 0.1-E3 Plugin Detail & App Association Explorer
//
//  文件信息分区：路径/大小/Hash/所属包全部来自 E1 投影；无证据字段留空，
//  不虚构 Hash 或归属关系。
//

import SwiftUI
import Core

struct PluginFileInformationSection: View {
    let detail: PluginDetailEntry

    var body: some View {
        Section("File Information") {
            if !detail.filePath.isEmpty {
                Text(detail.filePath)
                    .textSelection(.enabled)
            }
            if let size = detail.fileSize {
                LabeledContent(
                    "Size",
                    value: ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
                )
            }
            if let hash = detail.fileHash {
                LabeledContent("Hash", value: hash)
            }
            if let package = detail.packageIdentifier {
                LabeledContent("Package", value: package)
            }
            if !detail.packageOwners.isEmpty {
                LabeledContent("Owners", value: detail.packageOwners.joined(separator: ", "))
            }
        }
    }
}

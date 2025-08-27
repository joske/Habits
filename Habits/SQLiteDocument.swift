//
//  SQLiteDocument.swift
//  Habits
//
//  Created by Jos Dehaes on 27/08/2025.
//

import SwiftUI
import UniformTypeIdentifiers

struct SQLiteDocument: FileDocument {
    static var readableContentTypes: [UTType] = [
        UTType(filenameExtension: "db") ?? .data,
        UTType(filenameExtension: "sqlite") ?? .data,
        .data
    ]

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

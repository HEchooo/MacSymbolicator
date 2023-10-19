//
//  ReportFile.swift
//  MacSymbolicator
//

import Foundation
import KSCrash

public class ReportFile {
    enum InitializationError: Error {
        case readingFile(Error)
        case emptyFile
        case translation(Translator.Error)
        case other(Error)
    }

    let path: URL
    let filename: String
    let processes: [ReportProcess]

    lazy var uuidsForSymbolication: [BinaryUUID] = processes.flatMap { $0.uuidsForSymbolication }

    let content: String
    var symbolicatedContent: String?

    var symbolicatedContentSaveURL: URL {
        let originalPathExtension = path.pathExtension
        let extensionLessPath = path.deletingPathExtension()
        let newFilename = extensionLessPath.lastPathComponent.appending("_symbolicated")
        return extensionLessPath
            .deletingLastPathComponent()
            .appendingPathComponent(newFilename)
            .appendingPathExtension(originalPathExtension)
    }

    public init(path: URL) throws {
        let originalContent: String
        do {
            originalContent = try convertKSCrashJsonToCrashFormatContent(path: path)
//            originalContent = try String(contentsOf: path, encoding: .utf8)
        } catch {
            throw InitializationError.readingFile(error)
        }

        guard !originalContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw InitializationError.emptyFile
        }

        var processes = ReportProcess.find(in: originalContent)

        if processes.isEmpty, originalContent.hasPrefix("{") {
            // Could not find any processes defined in the report file -> Probably not the usual crash report format
            // However, the contents might be JSON -> It might be the new .ips format
            // Attempt translation to the old crash format

            do {
                self.content = try Translator.translatedCrash(forIPSAt: path)
            } catch {
                if let translationError = error as? Translator.Error {
                    throw InitializationError.translation(translationError)
                } else {
                    throw InitializationError.other(error)
                }
            }

            processes = ReportProcess.find(in: content)
        } else {
            self.content = originalContent
        }

        self.path = path
        self.filename = path.lastPathComponent
        self.processes = processes
    }
}

func convertKSCrashJsonToCrashFormatContent(path: URL) throws -> String {
    guard path.pathExtension == "json" else {
        return try String(contentsOf: path, encoding: .utf8)
    }
    let jsonData = try Data(contentsOf: path)
    let json = try JSONSerialization.jsonObject(with: jsonData)
    let filter = KSCrashReportFilterAppleFmt(reportStyle: .symbolicatedSideBySide)
    let group = DispatchGroup()
    group.enter()
    var content: String?
    filter?.filterReports([json], onCompletion: { reports, completed, error in
        if completed, error == nil {
            content = reports?.first as? String
        } else {
            content = try? String(contentsOf: path, encoding: .utf8)
        }
        group.leave()
    })
    group.wait()
    guard let content = content else { throw ReportFile.InitializationError.emptyFile }
    return content
}

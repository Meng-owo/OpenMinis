import Foundation
import SwiftUI
import UIKit

/// Saved theme history. Current pack stays in AppearanceStudio;
/// this drawer only keeps names. Full packs live as JSON files so
/// wallpaper / category pictures never land in UserDefaults.
struct AppearanceSavedTheme: Equatable, Codable, Identifiable {
    var id: String
    var name: String
    var savedAt: Date
    var userStyle: String
    var assistantStyle: String

    static let libraryKey = "appearanceStudio.themeLibrary.v1"
    static let limit = 40

    var userStyleTitle: String { AppearanceBubbleStyle.parse(userStyle).title }
    var assistantStyleTitle: String { AppearanceBubbleStyle.parse(assistantStyle).title }
}

extension AppearanceStudio {
    private static let libraryKey = AppearanceSavedTheme.libraryKey

    private struct LegacyLibraryMeta: Codable {
        var id: String
        var name: String
        var savedAt: Date
        var userStyle: String?
        var assistantStyle: String?
    }

    private func libraryDirectory() -> URL {
        let dir = appearanceDirectory.appendingPathComponent("library", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func libraryPackURL(_ id: String) -> URL {
        libraryDirectory().appendingPathComponent("\(id).json")
    }

    func savedThemes() -> [AppearanceSavedTheme] {
        guard let data = UserDefaults.standard.data(forKey: Self.libraryKey) else { return [] }
        if let list = try? JSONDecoder().decode([AppearanceSavedTheme].self, from: data) {
            return list.sorted { $0.savedAt > $1.savedAt }
        }
        return migrateLegacyLibrary(data)
    }

    /// v1 stuffed the whole pack (including JPEG) into UserDefaults.
    /// Pull pictures out into files and keep only names in the list.
    private func migrateLegacyLibrary(_ data: Data) -> [AppearanceSavedTheme] {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        let decoder = JSONDecoder()
        var list: [AppearanceSavedTheme] = []
        for obj in raw {
            guard let itemData = try? JSONSerialization.data(withJSONObject: obj),
                  let meta = try? decoder.decode(LegacyLibraryMeta.self, from: itemData) else {
                continue
            }
            var userStyle = meta.userStyle ?? ""
            var assistantStyle = meta.assistantStyle ?? ""
            if let packObj = obj["pack"] as? [String: Any],
               let pack = try? AppearanceThemePack.decode(packObj) {
                writeLibraryPack(pack, id: meta.id)
                if userStyle.isEmpty { userStyle = pack.userStyle.rawValue }
                if assistantStyle.isEmpty { assistantStyle = pack.assistantStyle.rawValue }
            }
            list.append(AppearanceSavedTheme(
                id: meta.id,
                name: meta.name,
                savedAt: meta.savedAt,
                userStyle: userStyle,
                assistantStyle: assistantStyle
            ))
        }
        persistLibrary(list)
        return list.sorted { $0.savedAt > $1.savedAt }
    }

    func saveCurrentTheme(name: String? = nil) -> AppearanceSavedTheme {
        var pack = exportThemePack(includeWallpaper: true)
        let trimmed = (name ?? pack.name).trimmingCharacters(in: .whitespacesAndNewlines)
        let label = trimmed.isEmpty ? pack.name : trimmed
        pack.name = label
        let item = AppearanceSavedTheme(
            id: UUID().uuidString.lowercased(),
            name: label,
            savedAt: Date(),
            userStyle: pack.userStyle.rawValue,
            assistantStyle: pack.assistantStyle.rawValue
        )
        writeLibraryPack(pack, id: item.id)
        var list = savedThemes()
        list.insert(item, at: 0)
        if list.count > AppearanceSavedTheme.limit {
            for extra in list.suffix(from: AppearanceSavedTheme.limit) {
                try? FileManager.default.removeItem(at: libraryPackURL(extra.id))
            }
            list = Array(list.prefix(AppearanceSavedTheme.limit))
        }
        persistLibrary(list)
        return item
    }

    func applySavedTheme(id: String) -> Bool {
        guard savedThemes().contains(where: { $0.id == id }),
              let pack = readLibraryPack(id: id) else { return false }
        applyThemePack(pack)
        return true
    }

    func renameSavedTheme(id: String, name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        var list = savedThemes()
        guard let idx = list.firstIndex(where: { $0.id == id }) else { return false }
        list[idx].name = trimmed
        if var pack = readLibraryPack(id: id) {
            pack.name = trimmed
            writeLibraryPack(pack, id: id)
        }
        persistLibrary(list)
        return true
    }

    /// [B28 B-2] 删掉一套。pack 文件不真删，挪进 `trash/` 留着撤销。
    ///
    /// 原来直接 `removeItem` —— 点错一下这套就没了，没有二次确认、没有
    /// 撤销、也没有提示。
    func deleteSavedTheme(id: String) -> Bool {
        var list = savedThemes()
        let before = list.count
        list.removeAll { $0.id == id }
        guard list.count != before else { return false }
        let src = libraryPackURL(id)
        let dst = trashedPackURL(id)
        if FileManager.default.fileExists(atPath: src.path) {
            try? FileManager.default.createDirectory(at: trashDirectory(),
                                                     withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: dst)
            try? FileManager.default.moveItem(at: src, to: dst)
        }
        pruneTrash()
        persistLibrary(list)
        return true
    }

    /// [B28 B-2] 撤销删除：文件搬回 library/，元数据插回列表最前面。
    func restoreSavedTheme(_ item: AppearanceSavedTheme) -> Bool {
        let src = trashedPackURL(item.id)
        guard FileManager.default.fileExists(atPath: src.path) else { return false }
        try? FileManager.default.removeItem(at: libraryPackURL(item.id))
        try? FileManager.default.moveItem(at: src, to: libraryPackURL(item.id))
        var list = savedThemes()
        if !list.contains(where: { $0.id == item.id }) {
            list.insert(item, at: 0)
        }
        persistLibrary(Array(list.prefix(AppearanceSavedTheme.limit)))
        return true
    }

    private func trashDirectory() -> URL {
        libraryDirectory().appendingPathComponent("trash", isDirectory: true)
    }

    private func trashedPackURL(_ id: String) -> URL {
        trashDirectory().appendingPathComponent("\(id).json")
    }

    /// 回收站只留最近 5 套，免得删过的主题永远堆在磁盘上。
    private func pruneTrash() {
        let dir = trashDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return }
        let sorted = files.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            return da > db
        }
        for extra in sorted.dropFirst(5) {
            try? FileManager.default.removeItem(at: extra)
        }
    }

    private func readLibraryPack(id: String) -> AppearanceThemePack? {
        guard let data = try? Data(contentsOf: libraryPackURL(id)),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pack = try? AppearanceThemePack.decode(obj) else {
            return nil
        }
        return pack
    }

    private func writeLibraryPack(_ pack: AppearanceThemePack, id: String) {
        guard let data = try? JSONSerialization.data(
            withJSONObject: pack.asJSONObject(),
            options: [.sortedKeys]
        ) else { return }
        try? data.write(to: libraryPackURL(id), options: .atomic)
    }

    private func persistLibrary(_ list: [AppearanceSavedTheme]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: Self.libraryKey)
        }
        themePackRevision += 1
        objectWillChange.send()
    }

    /// [P3-16] Delete saved-theme pack files in `library/` whose id is not
    /// in the theme-library list, returning how many were removed.
    ///
    /// Restore merges the appearance file tree (package files overwrite;
    /// unmentioned files are left alone), but the theme-library LIST in
    /// UserDefaults is replaced wholesale by the backup's. A pack created
    /// after the backup — or whose list entry was deleted while the file
    /// lingered — therefore survives a restore as an orphan: not in the
    /// list, but still on disk. The list is the registry the theme drawer
    /// reads, so a pack with no list entry can never be opened, applied,
    /// or deleted from the UI — unreachable clutter, and deleting it
    /// loses nothing the user could touch.
    ///
    /// Only `library/*.json` pack files are touched. Wallpapers, icons
    /// and category images have no registry to compare against, so they
    /// keep merge semantics: deleting an unreferenced wallpaper could
    /// destroy the live look.
    @discardableResult
    func removeOrphanedLibraryPacks() -> Int {
        let validIds = Set(savedThemes().map(\.id))
        let dir = libraryDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return 0 }
        var removed = 0
        for url in files where url.pathExtension.lowercased() == "json" {
            let id = url.deletingPathExtension().lastPathComponent
            guard !validIds.contains(id) else { continue }
            do {
                try FileManager.default.removeItem(at: url)
                removed += 1
            } catch {
                // Leave it; the next restore or delete pass retries.
            }
        }
        return removed
    }
}

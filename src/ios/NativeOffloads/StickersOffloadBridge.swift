//
//  StickersOffloadBridge.swift
//  MinisApp
//
//  Swift bridge for `minis-stickers` offload.
//

import Foundation
import UIKit

@objc public class StickersOffloadBridge: NSObject {

    @objc public static func listStickers(category: String?, limit: Int) -> NSDictionary {
        let sem = DispatchSemaphore(value: 0)
        var out: [String: Any] = [:]

        Task.detached { @MainActor in
            let store = StickerStore.shared
            var items = store.stickers
            if let cat = category?.trimmingCharacters(in: .whitespacesAndNewlines), !cat.isEmpty {
                items = items.filter { $0.category == cat }
            }
            let maxCount = limit > 0 ? min(limit, items.count) : items.count
            let slice = items.prefix(maxCount)

            let mapped: [[String: Any]] = slice.map { item in
                [
                    "id": item.id,
                    "title": item.title,
                    "short_desc": item.shortDesc,
                    "category": item.category,
                    "scenario": item.scenario,
                    "content": item.content,
                    "use_count": item.useCount,
                    "image_file": item.imageFilename,
                    // [sticker-fix] Was "minis://stickers/…" — a scheme nothing
                    // handles (the app's is "minis-clone://"), so the URL the
                    // CLI handed back could not be opened or rendered anywhere.
                    // Same construction as the other bridges (voice composer):
                    // minis-clone:// + percent-encoded filename.
                    "minis_url": "minis-clone://stickers/\(item.imageFilename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? item.imageFilename)"
                ]
            }

            out = [
                "ok": true,
                "count": mapped.count,
                "total": items.count,
                "stickers": mapped
            ]
            sem.signal()
        }
        if sem.wait(timeout: .now() + 5) == .timedOut {
            // [batch7 / W3C-01] Never hang the caller forever.
            NSLog("[CLIBridge] semaphore wait timed out - returning default value")
        }
        return out as NSDictionary
    }

    @objc public static func getSticker(id: String) -> NSDictionary {
        let sem = DispatchSemaphore(value: 0)
        var out: [String: Any] = [:]

        Task.detached { @MainActor in
            let store = StickerStore.shared
            if let item = store.sticker(for: id) {
                out = [
                    "ok": true,
                    "sticker": [
                        "id": item.id,
                        "title": item.title,
                        "short_desc": item.shortDesc,
                        "category": item.category,
                        "scenario": item.scenario,
                        "content": item.content,
                        "use_count": item.useCount,
                        "image_file": item.imageFilename,
                        // [sticker-fix] Was "minis://stickers/…" — a scheme nothing
                        // handles (the app's is "minis-clone://"), so the URL the
                        // CLI handed back could not be opened or rendered anywhere.
                        // Same construction as the other bridges (voice composer):
                        // minis-clone:// + percent-encoded filename.
                        "minis_url": "minis-clone://stickers/\(item.imageFilename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? item.imageFilename)"
                    ]
                ]
            } else {
                out = [
                    "ok": false,
                    "error": "Sticker not found: \(id)"
                ]
            }
            sem.signal()
        }
        if sem.wait(timeout: .now() + 5) == .timedOut {
            // [batch7 / W3C-01] Never hang the caller forever.
            NSLog("[CLIBridge] semaphore wait timed out - returning default value")
        }
        return out as NSDictionary
    }

    @objc public static func editSticker(
        id: String,
        title: String?,
        desc: String?,
        category: String?,
        content: String?
    ) -> NSDictionary {
        let sem = DispatchSemaphore(value: 0)
        var out: [String: Any] = [:]

        Task.detached { @MainActor in
            let store = StickerStore.shared
            guard let item = store.sticker(for: id) else {
                out = ["ok": false, "error": "Sticker not found: \(id)"]
                sem.signal()
                return
            }

            let newTitle = (title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? item.title
            let newDesc = (desc?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? item.shortDesc
            let newCategory = (category?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? item.category
            let newContent = content ?? item.content

            store.updateSticker(
                id: id,
                title: newTitle,
                content: newContent,
                scenario: item.scenario,
                shortDesc: newDesc,
                category: newCategory
            )

            out = [
                "ok": true,
                "sticker": [
                    "id": id,
                    "title": newTitle,
                    "short_desc": newDesc,
                    "category": newCategory
                ]
            ]
            sem.signal()
        }
        if sem.wait(timeout: .now() + 5) == .timedOut {
            // [batch7 / W3C-01] Never hang the caller forever.
            NSLog("[CLIBridge] semaphore wait timed out - returning default value")
        }
        return out as NSDictionary
    }

    @objc public static func deleteSticker(id: String) -> NSDictionary {
        let sem = DispatchSemaphore(value: 0)
        var out: [String: Any] = [:]

        Task.detached { @MainActor in
            let store = StickerStore.shared
            guard store.sticker(for: id) != nil else {
                out = ["ok": false, "error": "Sticker not found: \(id)"]
                sem.signal()
                return
            }
            store.deleteSticker(id: id)
            out = ["ok": true, "id": id, "deleted": true]
            sem.signal()
        }
        if sem.wait(timeout: .now() + 5) == .timedOut {
            // [batch7 / W3C-01] Never hang the caller forever.
            NSLog("[CLIBridge] semaphore wait timed out - returning default value")
        }
        return out as NSDictionary
    }

    @objc public static func batchMove(ids: [String], category: String) -> NSDictionary {
        let sem = DispatchSemaphore(value: 0)
        var out: [String: Any] = [:]

        Task.detached { @MainActor in
            let store = StickerStore.shared
            let setIds = Set(ids)
            let trimmedCat = category.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedCat.isEmpty else {
                out = ["ok": false, "error": "Category cannot be empty"]
                sem.signal()
                return
            }
            store.batchMoveCategory(ids: setIds, newCategory: trimmedCat)
            out = [
                "ok": true,
                "moved_count": setIds.count,
                "category": trimmedCat
            ]
            sem.signal()
        }
        if sem.wait(timeout: .now() + 5) == .timedOut {
            // [batch7 / W3C-01] Never hang the caller forever.
            NSLog("[CLIBridge] semaphore wait timed out - returning default value")
        }
        return out as NSDictionary
    }

    @objc public static func listCategories() -> NSDictionary {
        let sem = DispatchSemaphore(value: 0)
        var out: [String: Any] = [:]

        Task.detached { @MainActor in
            let store = StickerStore.shared
            out = [
                "ok": true,
                "categories": store.categories
            ]
            sem.signal()
        }
        if sem.wait(timeout: .now() + 5) == .timedOut {
            // [batch7 / W3C-01] Never hang the caller forever.
            NSLog("[CLIBridge] semaphore wait timed out - returning default value")
        }
        return out as NSDictionary
    }
}

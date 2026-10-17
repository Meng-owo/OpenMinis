//
//  ThemeOffloadExtras.swift
//  MinisApp
//
//  `minis-theme` coverage for the parts of the appearance system the pack
//  JSON never carried: avatars, replaceable row icons, per-page wallpapers,
//  and single colour overrides.
//
//  The pack is a fixed 26-field document. Everything below lives outside it,
//  so before this file an AI could restyle bubbles, radii and the 16 category
//  tiles and nothing else — asking it to change a settings-row icon or the
//  chat page's wallpaper was impossible, not merely undocumented.
//
//  Every setter takes an image path or hex value, never raw bytes on the
//  command line: `--file` points at a guest path the shell already has.
//

import Foundation
import SwiftUI
import UIKit

@objc public class ThemeOffloadExtras: NSObject {

    // MARK: - Shared plumbing

    /// Runs `work` on the main actor and waits, with the same 5s ceiling the
    /// rest of the theme bridge uses.
    private static func onMain(_ work: @escaping @MainActor () -> [String: Any]) -> NSDictionary {
        let sem = DispatchSemaphore(value: 0)
        var result: [String: Any] = [:]
        Task { @MainActor in
            result = work()
            sem.signal()
        }
        if sem.wait(timeout: .now() + 5) == .timedOut {
            NSLog("[CLIBridge] semaphore wait timed out - returning default value")
            return ["ok": false, "error": "timeout",
                    "message": "The appearance system did not answer in 5s."] as NSDictionary
        }
        return result as NSDictionary
    }

    private static func fail(_ code: String, _ message: String) -> [String: Any] {
        ["ok": false, "error": code, "message": message]
    }

    /// Reads an image from a path the caller already resolved.
    ///
    /// The ObjC handler maps guest paths with `noff_resolve_host_path` before
    /// calling in — the same function `minis-theme apply --file` uses — so
    /// one resolver serves both entry points.
    private static func loadImage(_ hostPath: String) -> UIImage? {
        guard !hostPath.isEmpty else { return nil }
        return UIImage(contentsOfFile: hostPath)
    }

    // MARK: - Avatars

    @objc public static func setAvatar(_ role: String, hostPath: String) -> NSDictionary {
        guard let image = loadImage(hostPath) else {
            return fail("no_image", "Cannot read an image at \(hostPath).") as NSDictionary
        }
        return onMain {
            switch role {
            case "user":
                AppearanceStudio.shared.setUserAvatar(image)
                return ["ok": true, "avatar": "user"]
            case "assistant":
                do {
                    try AppearanceStudio.shared.setAssistantAvatar(image)
                    return ["ok": true, "avatar": "assistant"]
                } catch {
                    return fail("save_failed", error.localizedDescription)
                }
            default:
                return fail("bad_role", "role must be user or assistant.")
            }
        }
    }

    @objc public static func removeAvatar(_ role: String) -> NSDictionary {
        onMain {
            switch role {
            case "user":
                AppearanceStudio.shared.removeUserAvatar()
                return ["ok": true, "avatar": "user", "removed": true]
            case "assistant":
                do {
                    try AppearanceStudio.shared.removeAssistantAvatar()
                    return ["ok": true, "avatar": "assistant", "removed": true]
                } catch {
                    return fail("save_failed", error.localizedDescription)
                }
            default:
                return fail("bad_role", "role must be user or assistant.")
            }
        }
    }

    // MARK: - Replaceable row icons

    @objc public static func setIcon(_ slot: String, hostPath: String) -> NSDictionary {
        guard let image = loadImage(hostPath) else {
            return fail("no_image", "Cannot read an image at \(hostPath).") as NSDictionary
        }
        return onMain {
            AppearanceStudio.shared.setIcon(image, for: slot)
            return ["ok": true, "slot": slot]
        }
    }

    @objc public static func removeIcon(_ slot: String) -> NSDictionary {
        onMain {
            AppearanceStudio.shared.removeIcon(for: slot)
            return ["ok": true, "slot": slot, "removed": true]
        }
    }

    @objc public static func listIconSlots() -> NSDictionary {
        onMain {
            let slots = QuietIconSlot.allCases.map { slot -> [String: Any] in
                [
                    "slot": slot.rawValue,
                    "title": slot.title,
                    "custom": AppearanceStudio.shared.customIcon(for: slot.rawValue) != nil,
                ]
            }
            return ["ok": true, "count": slots.count, "slots": slots]
        }
    }

    // MARK: - Per-page wallpapers

    @objc public static func setWallpaper(_ scope: String, hostPath: String) -> NSDictionary {
        guard let image = loadImage(hostPath) else {
            return fail("no_image", "Cannot read an image at \(hostPath).") as NSDictionary
        }
        guard let parsed = AppearanceScope(rawValue: scope) else {
            return fail("bad_scope", "scope must be one of: \(AppearanceScope.allCases.map(\.rawValue).joined(separator: ", ")).") as NSDictionary
        }
        return onMain {
            AppearanceStudio.shared.setWallpaper(image, for: parsed)
            return ["ok": true, "scope": parsed.rawValue]
        }
    }

    @objc public static func removeWallpaper(_ scope: String) -> NSDictionary {
        guard let parsed = AppearanceScope(rawValue: scope) else {
            return fail("bad_scope", "scope must be one of: \(AppearanceScope.allCases.map(\.rawValue).joined(separator: ", ")).") as NSDictionary
        }
        return onMain {
            AppearanceStudio.shared.removeWallpaper(parsed)
            return ["ok": true, "scope": parsed.rawValue, "removed": true]
        }
    }

    // MARK: - Single colour override

    @objc public static func setColor(_ role: String, hex: String,
                                      scope: String, variant: String) -> NSDictionary {
        guard let parsedRole = AppearanceColorRole(rawValue: role) else {
            return fail("bad_role",
                        "role must be one of: \(AppearanceColorRole.allCases.map(\.rawValue).joined(separator: ", ")).") as NSDictionary
        }
        guard let parsedScope = AppearanceScope(rawValue: scope) else {
            return fail("bad_scope",
                        "scope must be one of: \(AppearanceScope.allCases.map(\.rawValue).joined(separator: ", ")).") as NSDictionary
        }
        guard let parsedVariant = AppearanceVariant(rawValue: variant) else {
            return fail("bad_variant", "variant must be light or dark.") as NSDictionary
        }
        // Reject junk before it reaches the store: an unparseable hex used to
        // land as pure black with no complaint.
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted).uppercased()
        guard (cleaned.count == 6 || cleaned.count == 8),
              cleaned.allSatisfy({ $0.isHexDigit }) else {
            return fail("bad_hex", "hex must be 6 or 8 hex digits, e.g. D4778B.") as NSDictionary
        }
        return onMain {
            AppearanceStudio.shared.setColor(Color(hex: cleaned), role: parsedRole,
                                             scope: parsedScope, variant: parsedVariant)
            return [
                "ok": true, "role": parsedRole.rawValue, "hex": cleaned,
                "scope": parsedScope.rawValue, "variant": parsedVariant.rawValue,
            ]
        }
    }

    @objc public static func clearColor(_ role: String,
                                        scope: String, variant: String) -> NSDictionary {
        guard let parsedRole = AppearanceColorRole(rawValue: role),
              let parsedScope = AppearanceScope(rawValue: scope),
              let parsedVariant = AppearanceVariant(rawValue: variant) else {
            return fail("bad_args", "Unknown role, scope or variant.") as NSDictionary
        }
        return onMain {
            AppearanceStudio.shared.clearOverride(parsedRole, scope: parsedScope, variant: parsedVariant)
            return ["ok": true, "role": parsedRole.rawValue,
                    "scope": parsedScope.rawValue, "variant": parsedVariant.rawValue,
                    "cleared": true]
        }
    }
}

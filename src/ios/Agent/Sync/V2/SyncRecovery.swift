import Foundation
import CloudKit

private let logger = AppLogger(category: "SyncRecovery")

/// Recovery actions that used to exist only on the v1 settings page.
///
/// v1's page was replaced by `CloudSyncSettingsV2View`, which took the enable
/// switch, the device name, the category toggles and the size cap — but not
/// the two escape hatches: "force a full resync" and "delete everything this
/// account has in iCloud". Those are exactly the buttons a user reaches for
/// when sync has gone wrong, so losing them meant the only fix was to
/// reinstall. This file re-implements them against the v2 engine.
///
/// Both are deliberately explicit: nothing here runs on its own.
enum SyncRecovery {

    /// Push everything local again and pull everything remote again.
    ///
    /// Re-marks every local row dirty (the dirty queue may have been dropped
    /// after a failure) and resets the provider anchor so the next fetch
    /// re-queries full history instead of the incremental window. Nothing is
    /// deleted on either side; this is the "my other device doesn't show what
    /// I have" button.
    @available(iOS 17.0, *)
    @MainActor
    static func forceFullResync() async {
        logger.warning("[SyncRecovery] force full resync START")
        // Force=true: this is the recovery path, explicitly the case the
        // once-per-install guard on the initial backlog is meant to exempt.
        await ChatStore.shared.markAllLocalForReupload(force: true)
        _ = await ForceSyncHelper.markMemoryDirty()
        _ = await ForceSyncHelper.markProvidersDirty()
        _ = await ForceSyncHelper.markSoulDirty()
        await SyncCore.shared.sendNow(trigger: .manual)
        await SyncCore.shared.fullFetchAndReconcile(trigger: .manual)
        logger.warning("[SyncRecovery] force full resync DONE")
    }

    /// Delete every record this account has in the app's private iCloud
    /// database, then re-upload this device's local content.
    ///
    /// Local data is never touched — that is the whole point: it repairs a
    /// cloud zone that has diverged or filled with junk without asking the
    /// user to lose their chat history. Every zone in the user's own private
    /// database is deleted; `allRecordZones()` only returns zones owned by the
    /// signed-in account, so another account's data is unreachable from here.
    @available(iOS 17.0, *)
    @MainActor
    static func deleteAllCloudData() async throws -> (deletedZones: Int, failedZones: Int) {
        logger.warning("[SyncRecovery] delete all cloud data START")
        // Stop the engine first: a live send racing the wipe would recreate
        // the zones we are about to remove.
        await SyncCore.shared.stop()

        let db = ICloudSharedZoneTransport.cloneContainer().privateCloudDatabase
        var deleted = 0
        var failed = 0
        do {
            let zones = try await db.allRecordZones()
            logger.warning("[SyncRecovery] deleting \(zones.count) zone(s)")
            for zone in zones {
                do {
                    _ = try await db.deleteRecordZone(withID: zone.zoneID)
                    deleted += 1
                    logger.warning("[SyncRecovery] deleted zone \(zone.zoneID.zoneName)")
                } catch {
                    failed += 1
                    logger.error("[SyncRecovery] failed to delete zone \(zone.zoneID.zoneName): \(error.localizedDescription)")
                }
            }
        } catch {
            // The engine is already stopped; bring it back so sync isn't dead
            // for the rest of the launch while the switch still reads "on".
            logger.error("[SyncRecovery] could not list zones: \(error.localizedDescription)")
            await SyncV2Bootstrap.restartAfterRecovery()
            throw error
        }

        // Clear the local sync bookkeeping (tokens, caches, remote mirrors) so
        // the next run starts from scratch. Local sessions/messages/files are
        // untouched; `markAllLocalForReupload` is what repopulates the cloud.
        await ChatStore.shared.clearAllRemoteTables()
        await ChatStore.shared.markAllLocalForReupload(force: true)
        _ = await ForceSyncHelper.markMemoryDirty()
        _ = await ForceSyncHelper.markProvidersDirty()
        _ = await ForceSyncHelper.markSoulDirty()

        await SyncV2Bootstrap.restartAfterRecovery()
        logger.warning("[SyncRecovery] delete all cloud data DONE deleted=\(deleted) failed=\(failed)")
        return (deleted, failed)
    }
}

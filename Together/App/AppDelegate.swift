import CloudKit
import UIKit

/// Handles UIApplicationDelegate callbacks that are not available in the SwiftUI lifecycle.
/// Primarily used for CKShare acceptance via `userDidAcceptCloudKitShareWith`.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {

    weak var bootstrapper: AppBootstrapper?

    /// Stored when share acceptance arrives before the app is fully bootstrapped.
    /// AppContext consumes this via `consumePendingShareMetadata()` once ready.
    private(set) var pendingShareMetadata: CKShare.Metadata?

    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        // CKShare is no longer used for pairing (replaced by SyncRelay architecture).
        // This callback is kept as a no-op for system compatibility.
        print("[AppDelegate] Received CKShare metadata but CKShare pairing is disabled")
    }

    func consumePendingShareMetadata() -> CKShare.Metadata? {
        let m = pendingShareMetadata
        pendingShareMetadata = nil
        return m
    }
}

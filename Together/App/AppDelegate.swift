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
        Task { @MainActor in
            if let appContext = bootstrapper?.appContext {
                await appContext.handleAcceptedCloudKitShare(metadata: cloudKitShareMetadata)
            } else {
                // App is still launching — store for later consumption
                pendingShareMetadata = cloudKitShareMetadata
            }
        }
    }

    func consumePendingShareMetadata() -> CKShare.Metadata? {
        let m = pendingShareMetadata
        pendingShareMetadata = nil
        return m
    }
}

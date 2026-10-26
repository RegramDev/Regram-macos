import Foundation
import TelegramCore
import PasscodeCore
import BuildConfig
#if !SHARE
import WalletContext
#endif

let unscopedWalletPasscodeCredentialManagedKey = "wallet.passcodeCredentialManaged"

var walletPasscodeCredentialManagedKey: String {
    if let scope = PasscodeEnvironment.shared.keychainScope {
        return unscopedWalletPasscodeCredentialManagedKey + "." + scope
    }
    return unscopedWalletPasscodeCredentialManagedKey
}

func makeAccountManagerAccessChallenge(basePath: String, isTemporary: Bool, isReadOnly: Bool) -> AccountManagerAccessChallenge {
    let isMainProcess = PasscodeEnvironment.shared.isMainApp
    return AccountManagerAccessChallenge(prepare: { isFreshInstallation in
        guard #available(macOS 10.15, *) else {
            return
        }
        _ = try PasscodeEnvironment.shared.sharedAccessGroup()
        PasscodeCredentialStore.shared.configureLock(directory: basePath)
        #if !SHARE
        if isMainProcess && !isTemporary && !isReadOnly && isFreshInstallation {
            try resetWalletLocalSecrets()
        }
        if isMainProcess, UserDefaults.standard.bool(forKey: walletPasscodeCredentialManagedKey) {
            if try PasscodeCredentialStore.shared.hasStoredCredential() {
                PasscodeCredentialStore.shared.requireExistingCredential()
            } else if !isTemporary && !isReadOnly {
                try resetWalletLocalSecrets()
            }
        }
        #endif
    }, resolve: { current, _ in
        guard current == nil else {
            return nil
        }
        let encryption = AppEncryptionParameters(path: (basePath as NSString).deletingLastPathComponent)
        let challenge: PostboxAccessChallengeData = encryption.hasPasscode() ? .plaintextPassword(value: "") : .none
        return challenge
    }, finishInitialization: {
        guard #available(macOS 10.15, *), isMainProcess else {
            return
        }
        try PasscodeCredentialStore.shared.resumeCleanup()
    })
}

# Source attribution

The RG-prefixed models and policies are adapted from Regram iOS commit `f61df19a1d19e9821f7adcf5c74cbb23601d1683`, under the repository license. Their original sources are in `Regram/RGSimpleSettings/Sources/`. Persistence uses the macOS application’s local defaults and account identifiers. No iOS application container is accessed.

Category names and descriptions in the shared localization resources follow the same
checkout's `Regram/RGStrings/Strings`. Message-menu identities, canonical order and
conditional-action ordering follow `ContextMenuItemId.swift` and `SimpleSettings.swift`.

Network modes, IP policy raw values, deterministic search matching and navigation behavior follow `RGNetworkPolicy.swift`, `RGSettingsCatalog.swift` and `TabBarLayoutPolicy.swift`. `RegramRegistrationDate.swift` adapts the local monotone registration-date anchors and interpolation from `Regram/RGRegDate/Sources/RGRegDateLocal.swift`, whose merged public datasets are credited to jobians/telegram-id-age, SantiiRepair/tdage and lastochkin-group/telegram-account-age-estimator in the original source. These values are estimates with bounded precision. Transfer/DC statistics adapt `TransferStatistics.swift` and `RGDatacenterStatistics.swift`.

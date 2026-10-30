import RegramCore

enum GeneralViewType: Equatable {
    case firstItem, innerItem, lastItem, textBottomItem
}

enum GeneralInteractedType: Equatable {
    case switchable(Bool), next
}

struct InputDataGeneralData {
    let name: String
    let color: Int
    let type: GeneralInteractedType
    let viewType: GeneralViewType
    let enabled: Bool
    let action: (() -> Void)?

    init(name: String, color: Int, type: GeneralInteractedType, viewType: GeneralViewType, enabled: Bool = true, description: String? = nil, descTextColor: Int? = nil, action: (() -> Void)? = nil) {
        self.name = name
        self.color = color
        self.type = type
        self.viewType = viewType
        self.enabled = enabled
        self.action = action
    }
}

struct InputDataIdentifier: Equatable {
    let value: String
    init(_ value: String) { self.value = value }
}

enum InputDataValue { case none }
enum SectionType { case normal }
enum DescriptionText { case plain(String) }
struct DescriptionData {
    let color: Int
    let viewType: GeneralViewType
}

enum InputDataEntry {
    case sectionId(Int32, type: SectionType)
    case general(sectionId: Int32, index: Int32, value: InputDataValue, error: String?, identifier: InputDataIdentifier, data: InputDataGeneralData)
    case desc(sectionId: Int32, index: Int32, text: DescriptionText, data: DescriptionData)
}

struct InputDataSignalValue { let entries: [InputDataEntry] }
struct FixtureColors {
    let text = 1
    let grayText = 2
    let listGrayText = 3
}
struct FixtureTheme { let colors = FixtureColors() }
let theme = FixtureTheme()
func regramString(_ key: String) -> String { key }
struct FixtureNavigation { func push(_ controller: Int) {} }
struct FixtureBindings { func rootNavigation() -> FixtureNavigation { FixtureNavigation() } }
struct FixtureContext {
    let peerId = PeerId(value: 1)
    let bindings = FixtureBindings()
}
func RegramRevokedMarkerController(context: FixtureContext) -> Int { 0 }

func privacyRows(ghostMode: Bool = false) -> InputDataSignalValue {
    let context = FixtureContext()
__PRIVACY_GROUPS__
    let settings = fixturePreferences.settings(accountId: accountId)
__PRIVACY_ROWS__
}

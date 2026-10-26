import AppKit
import CoreText
import RegramCore

public enum RegramFonts {
    public enum Area { case messages, interface, preview }
    private static let cache = NSCache<NSString, NSFont>()
    private static let chineseCharacters: CharacterSet = {
        var result = CharacterSet()
        for range in [0x2e80...0x303f, 0x3100...0x312f, 0x31a0...0x31ef, 0x3400...0x4dbf, 0x4e00...0x9fff, 0xf900...0xfaff, 0xff01...0xff60, 0xffe0...0xffe6, 0x20000...0x323af] {
            result.insert(charactersIn: UnicodeScalar(range.lowerBound)!...UnicodeScalar(range.upperBound)!)
        }
        return result
    }()
    public static let latinFamilies: [(id: String, title: String, prefix: String?)] = [
        ("system", "Fonts.System", nil),
        ("jetBrainsMono", "JetBrains Mono", "JetBrainsMono"), ("jetBrainsMonoNL", "JetBrains Mono NL", "JetBrainsMonoNL"),
        ("inter", "Inter", "Inter"), ("poppins", "Poppins", "Poppins"), ("lora", "Lora", "Lora"),
        ("ibmPlexSans", "IBM Plex Sans", "IBMPlexSans"), ("ibmPlexSerif", "IBM Plex Serif", "IBMPlexSerif"),
        ("ibmPlexMono", "IBM Plex Mono", "IBMPlexMono"), ("sourceSans3", "Source Sans 3", "SourceSans3"), ("sourceSerif4", "Source Serif 4", "SourceSerif4"), ("rounded", "Fonts.Rounded", nil), ("serif", "Fonts.Serif", nil)
    ]
    public static let chineseFamilies: [(id: String, title: String, prefix: String?)] = [
        ("system", "Fonts.Chinese.System", nil), ("ibmPlexSansSC", "IBM Plex Sans SC", "IBMPlexSansSC"), ("notoSerifSC", "Noto Serif SC", "NotoSerifSC")
    ]

    public static func messageFont(base: NSFont, accountId: Int64) -> NSFont {
        return font(base: base, settings: RegramPreferences.shared.settings(accountId: accountId), area: .messages) ?? base
    }

    public static func interfaceFont(size: CGFloat, weight: NSFont.Weight, italic: Bool, accountId: Int64) -> NSFont? {
        var base = NSFont.systemFont(ofSize: size, weight: weight)
        if italic {
            let descriptor = CTFontCopyFontDescriptor(base as CTFont)
            let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
            if let converted = CTFontCreateCopyWithSymbolicTraits(font, size, nil, .italicTrait, .italicTrait) { base = converted as NSFont }
        }
        return font(base: base, settings: RegramPreferences.shared.settings(accountId: accountId), area: .interface)
    }

    public static func font(base: NSFont, settings: RegramAccountSettings, area: Area, store: RegramFontStore = .shared) -> NSFont? {
        if area == .messages && !settings["fontApplyToMessages"].bool { return nil }
        if area == .interface && !settings["fontApplyToInterface"].bool { return nil }
        let latin = settings["fontFamily"].string
        let chinese = settings["fontChineseFamily"].string
        let latinId = settings["fontImportedLatin"].string
        let chineseId = settings["fontImportedChinese"].string
        guard latin != "system" && !latin.isEmpty || chinese != "system" && !chinese.isEmpty || !latinId.isEmpty || !chineseId.isEmpty else { return nil }
        let traits = CTFontCopyTraits(base as CTFont) as NSDictionary
        let weight = NSFont.Weight(rawValue: CGFloat((traits[kCTFontWeightTrait] as? NSNumber)?.doubleValue ?? 0))
        let italic = CTFontGetSymbolicTraits(base as CTFont).contains(.italicTrait)
        let key = "\(ObjectIdentifier(store))|\(store.revision)|\(base.fontName)|\(base.pointSize)|\(weight.rawValue)|\(italic)|\(latin)|\(chinese)|\(latinId)|\(chineseId)" as NSString
        if let font = cache.object(forKey: key) { return font }
        var primary: NSFont? = latinId.isEmpty ? nil : store.font(importedId: latinId, size: base.pointSize, italic: italic)
        if primary == nil, let choice = latinFamilies.first(where: { $0.id == latin }) {
            if let prefix = choice.prefix { primary = store.font(prefix: prefix, size: base.pointSize, weight: weight, italic: italic) }
            else if #available(macOS 10.15, *), choice.id != "system", let descriptor = base.fontDescriptor.withDesign(choice.id == "serif" ? .serif : .rounded) { primary = NSFont(descriptor: descriptor, size: base.pointSize) }
        }
        var cjk = chineseId.isEmpty ? nil : store.font(importedId: chineseId, size: base.pointSize, italic: italic)
        if cjk == nil, let prefix = chineseFamilies.first(where: { $0.id == chinese })?.prefix { cjk = store.font(prefix: prefix, size: base.pointSize, weight: weight, italic: italic) }
        guard primary != nil || cjk != nil else { return nil }
        let chosen = styledFont(primary ?? base, weight: weight, italic: italic)
        let nativeChinese = CTFontCreateForString(base as CTFont, "中文漢字" as CFString, CFRange(location: 0, length: 4)) as NSFont
        let chineseFont = styledFont(cjk ?? nativeChinese, weight: weight, italic: italic)
        let latinCharacters = (CTFontCopyCharacterSet(chosen as CTFont) as CharacterSet).subtracting(chineseCharacters)
        let selectedChineseCharacters = (CTFontCopyCharacterSet(chineseFont as CTFont) as CharacterSet).intersection(chineseCharacters)
        let chineseDescriptor = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(chineseFont as CTFont), [kCTFontCharacterSetAttribute: selectedChineseCharacters as CFCharacterSet] as CFDictionary)
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(chosen as CTFont), [kCTFontCharacterSetAttribute: latinCharacters as CFCharacterSet, kCTFontCascadeListAttribute: [chineseDescriptor]] as CFDictionary)
        let font = CTFontCreateCopyWithAttributes(chosen as CTFont, 0, nil, descriptor) as NSFont
        cache.countLimit = 512
        cache.setObject(font, forKey: key)
        return font
    }

    private static func styledFont(_ font: NSFont, weight: NSFont.Weight, italic: Bool) -> NSFont {
        var result = font as CTFont
        var hasWeightAxis = false
        var hasItalicAxis = false
        var variations: [NSNumber: NSNumber] = [:]
        if let axes = CTFontCopyVariationAxes(result) as? [[String: Any]] {
            for axis in axes {
                guard let id = axis[kCTFontVariationAxisIdentifierKey as String] as? NSNumber else { continue }
                let desired: Double
                switch id.uint32Value {
                case 0x77676874:
                    hasWeightAxis = true
                    desired = weight >= .bold ? 700 : weight >= .semibold ? 600 : weight >= .medium ? 500 : weight <= .thin ? 200 : weight <= .light ? 300 : 400
                case 0x6f70737a: desired = Double(font.pointSize)
                case 0x736c6e74:
                    hasItalicAxis = true
                    desired = italic ? -10 : 0
                case 0x6974616c:
                    hasItalicAxis = true
                    desired = italic ? 1 : 0
                default: continue
                }
                let minimum = (axis[kCTFontVariationAxisMinimumValueKey as String] as? NSNumber)?.doubleValue ?? desired
                let maximum = (axis[kCTFontVariationAxisMaximumValueKey as String] as? NSNumber)?.doubleValue ?? desired
                variations[id] = NSNumber(value: max(minimum, min(maximum, desired)))
            }
        }
        if !variations.isEmpty {
            let descriptor = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(result), [kCTFontVariationAttribute: variations] as CFDictionary)
            result = CTFontCreateCopyWithAttributes(result, 0, nil, descriptor)
        }
        if !hasWeightAxis, weight >= .semibold, let bold = CTFontCreateCopyWithSymbolicTraits(result, 0, nil, .boldTrait, .boldTrait) { result = bold }
        if italic && !hasItalicAxis {
            if let converted = CTFontCreateCopyWithSymbolicTraits(result, 0, nil, .italicTrait, .italicTrait) { result = converted }
            else {
                var matrix = CGAffineTransform(a: 1, b: 0, c: 0.2, d: 1, tx: 0, ty: 0)
                result = CTFontCreateCopyWithAttributes(result, 0, &matrix, nil)
            }
        }
        return result as NSFont
    }
}

import XCTest

@testable import RegramCore

@available(macOS 10.15, *)
final class AdFilterTests: XCTestCase {
    private func entity(_ text: String, _ token: String, kind: RGAdEntity.Kind = .mention, value: String? = nil) -> RGAdEntity {
        let range = (text as NSString).range(of: token)
        return RGAdEntity(range: RGAdRange(range.location, NSMaxRange(range)), kind: kind, value: value ?? token)
    }
    private func store() throws -> RGAdSampleStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return RGAdSampleStore(accountDirectory: directory)
    }
    private let ad = "0充值，免费体验，中奖可提现 → @promotion_user"

    func testAdvertisingMajorityRemovesOrphanLinksAndURLActions() throws {
        let body = "精选套餐限时优惠，现在购买即可享受专属折扣和额外权益。\n"
        let text = body + "\nhttps://example.org/offer\n@offer_contact\n立即访问\n"
        let input = RGAdInput(
            text: text,
            entities: [
                entity(text, "https://example.org/offer", kind: .link),
                entity(text, "@offer_contact"), entity(text, "立即访问", kind: .link, value: "https://example.org/join"),
            ],
            buttons: [[RGAdButton(id: "other", title: "入口", target: "https://example.org/join")]], hasMedia: true)
        let semantic = RGAdSemanticResult(
            predictions: [RGAdPrediction(range: RGAdRange(0, body.utf16.count), confidence: 1)], threshold: 0.98)
        let result = try RGAdPolicy.project(input, semantic: semantic)
        XCTAssertEqual(result.disposition, .hide)
        XCTAssertTrue(result.buttons.isEmpty)
        XCTAssertTrue(result.entities.isEmpty)
        XCTAssertEqual(
            try RGAdFilter.project(input, confirmedRanges: [RGAdRange(0, body.utf16.count)], inferButtons: false).buttons, input.buttons)
        XCTAssertTrue(
            try RGAdFilter.project(input, confirmedRanges: [RGAdRange(0, body.utf16.count)], inferButtons: false).text.contains(
                "https://example.org/offer"))
    }

    func testLongAdKeepsNormalBodyAndItsResources() throws {
        let normal = "剧集更新与播放说明。\nhttps://example.org/play\n\n"
        let ad = "本店全新套餐优惠上线，现在订购可以享受长期折扣，还可以联系客服定制服务，欢迎访问并了解全部价格。\n"
        let text = normal + ad + "https://example.org/offer\n"
        let input = RGAdInput(
            text: text,
            entities: [entity(text, "https://example.org/play", kind: .link), entity(text, "https://example.org/offer", kind: .link)],
            hasMedia: true)
        let result = try RGAdFilter.project(input, confirmedRanges: [RGAdRange(normal.utf16.count, (normal + ad).utf16.count)])
        XCTAssertEqual(result.text, normal)
        XCTAssertEqual(result.disposition, .trim)
        XCTAssertEqual(result.entities.count, 1)
        XCTAssertEqual(result.entities[0].value, "https://example.org/play")
    }

    func testAdvertisingRatioDoesNotCountURLLengthAndPreservesAmbiguousReferences() throws {
        let ad = "本店的精选套餐现在开始订购享受折扣。\n"
        let normal = "这是一段详细的正常使用说明，介绍安装、配置以及遇到问题时的解决方法。\n"
        let hugeURL = "https://example.org/" + String(repeating: "a", count: 600)
        let text = normal + ad + hugeURL
        let input = RGAdInput(text: text, entities: [entity(text, hugeURL, kind: .link)])
        let projected = try RGAdFilter.project(input, confirmedRanges: [RGAdRange(normal.utf16.count, (normal + ad).utf16.count)])
        XCTAssertEqual(projected.text, normal + hugeURL)
        let dominant = String(repeating: ad, count: 5)
        for kind in [RGAdEntity.Kind.quote, .code] {
            let protected = RGAdInput(
                text: dominant + hugeURL,
                entities: [entity(dominant + hugeURL, hugeURL, kind: .link), entity(dominant + hugeURL, hugeURL, kind: kind)])
            XCTAssertTrue(try RGAdFilter.project(protected, confirmedRanges: [RGAdRange(0, dominant.utf16.count)]).text.contains(hugeURL))
        }
        let adjacent = dominant + "https://example.org/docs\n" + normal
        let guarded = RGAdInput(text: adjacent, entities: [entity(adjacent, "https://example.org/docs", kind: .link)])
        XCTAssertEqual(
            try RGAdFilter.project(guarded, confirmedRanges: [RGAdRange(0, dominant.utf16.count)]).text,
            "https://example.org/docs\n" + normal)
    }

    func testReviewedNormalActionsAndOpaqueActionsSurviveMajorityCleanup() throws {
        let body = "现在订购本店精选套餐，超值优惠限时开放，欢迎了解具体服务。\n"
        let text = body + "https://example.org/docs"
        let input = RGAdInput(
            text: text, entities: [entity(text, "https://example.org/docs", kind: .link)],
            buttons: [
                [
                    RGAdButton(id: "keep", title: "官方说明", target: "https://example.org/docs"), RGAdButton(id: "opaque", title: "验证"),
                ]
            ])
        let result = try RGAdFilter.project(input, confirmedRanges: [RGAdRange(0, body.utf16.count)], preservedButtonIds: ["keep"])
        XCTAssertEqual(result.text, "https://example.org/docs")
        XCTAssertEqual(result.buttons, input.buttons)
    }

    func testPaddedCouponCodeDoesNotProtectWholeCommercialCard() throws {
        let text = "购买套餐限时优惠\n优惠码：9999\n\n \n"
        let entities = [entity(text, "9999\n\n", kind: .code), entity(text, " \n", kind: .code)]
        let result = try RGAdFilter.project(
            RGAdInput(text: text, entities: entities, hasMedia: true),
            predictions: [RGAdPrediction(range: RGAdRange(0, text.utf16.count), confidence: 1)], entireMessageIsAd: true)
        XCTAssertEqual(result.disposition, .hide)
        let code = "let price = 20\nprint(price)"
        let guarded = text + code
        XCTAssertNotEqual(
            try RGAdFilter.project(
                RGAdInput(text: guarded, entities: [entity(guarded, code, kind: .code)]),
                predictions: [RGAdPrediction(range: RGAdRange(0, guarded.utf16.count), confidence: 1)], entireMessageIsAd: true
            ).disposition, .hide)
    }

    func testAuthorDisclosureHidesCompleteCardAndMediaWithoutModel() throws {
        for tag in RGAdDisclosure.tags.map({ "#" + $0 }) + ["#AD", "#Ads", "#Sponsored", "＃广告"] {
            for text in [tag + "\n\n产品服务介绍\n\n多个功能和价格说明", "产品服务介绍\n\n多个功能和价格说明\n\n🥰 #产品 " + tag] {
                let input = RGAdInput(
                    text: text,
                    buttons: [
                        [
                            RGAdButton(id: "contact", title: "咨询", target: "https://example.org/contact"),
                            RGAdButton(id: "opaque", title: "领取"),
                        ]
                    ], hasMedia: true)
                let result = try RGAdPolicy.project(input)
                XCTAssertEqual(result.disposition, .hide)
                XCTAssertTrue(result.text.isEmpty)
                XCTAssertTrue(result.buttons.isEmpty)
            }
        }
        let long = Array(repeating: "服务说明与功能列表\n", count: 160).joined() + "\n#推广"
        XCTAssertEqual(try RGAdPolicy.project(RGAdInput(text: long, hasMedia: true)).disposition, .hide)
        XCTAssertEqual(try RGAdPolicy.project(RGAdInput(text: "套餐说明\n\n#AD 10-21", hasMedia: true)).disposition, .hide)
    }

    func testDisclosureRespectsMixedMessageSectionsAndButtons() throws {
        let prefix = "正常软件介绍与安装教程\nhttps://example.org/docs\n"
        let promotion = "服务套餐说明\nhttps://example.org/buy\n\n#推广\n"
        let suffix = "下一段正常更新说明\n"
        let text = prefix + "======\n" + promotion + "======\n" + suffix
        let input = RGAdInput(
            text: text,
            entities: [entity(text, "https://example.org/docs", kind: .link), entity(text, "https://example.org/buy", kind: .link)],
            buttons: [
                [
                    RGAdButton(id: "docs", title: "使用文档", target: "https://example.org/docs"),
                    RGAdButton(id: "buy", title: "立即购买", target: "https://example.org/buy"),
                ]
            ], hasMedia: true)
        let result = try RGAdPolicy.project(input)
        XCTAssertEqual(result.disposition, .trim)
        XCTAssertTrue(result.text.contains(prefix))
        XCTAssertTrue(result.text.contains(suffix))
        XCTAssertFalse(result.text.contains("套餐"))
        XCTAssertFalse(result.text.contains("#推广"))
        XCTAssertEqual(result.buttons.flatMap { $0 }.map(\.id), ["docs"])
        XCTAssertTrue(result.entities.allSatisfy { $0.range.upper <= result.text.utf16.count })
    }

    func testInlineDisclosureOnlyRemovesItsOwnSentenceOrParagraph() throws {
        for text in ["正常内容。#广告 套餐介绍。正常结尾。", "正常内容。套餐介绍 #广告。正常结尾。", "正常内容。\n\n#推广 套餐介绍\n更多套餐说明\n\n正常结尾。"] {
            let result = try RGAdPolicy.project(RGAdInput(text: text, hasMedia: true))
            XCTAssertEqual(result.disposition, .trim)
            XCTAssertTrue(result.text.contains("正常内容。"))
            XCTAssertTrue(result.text.contains("正常结尾。"))
            XCTAssertFalse(result.text.contains("套餐"))
            XCTAssertFalse(result.text.contains("#广告"))
            XCTAssertFalse(result.text.contains("#推广"))
        }
        let text = "正常影片介绍\n#影视 #更新\n\n产品与价格说明\n\n#推广"
        let result = try RGAdPolicy.project(RGAdInput(text: text, hasMedia: true))
        XCTAssertTrue(result.text.contains("正常影片介绍\n#影视 #更新"))
        XCTAssertFalse(result.text.contains("产品"))
    }

    func testDisclosureDoesNotMatchTagSubstringsDiscussionOrURLs() throws {
        for text in [
            "#广告设计", "#推广教程", "#广告_案例", "#广告123", "标签说明：\"#广告\"", "讨论 #推广 标签的用法", "`#广告`", "https://example.org/#广告",
            "https://example.org?q=#推广", "abc#广告", "#admin", "#ADvice", "#adblock", "#adapter", "#address", "#sponsorshipGuide", "#福利",
            "#推荐", "#合作", "#sponsor",
        ] {
            XCTAssertTrue(RGAdDisclosure.ranges(RGAdInput(text: text)).isEmpty, text)
            XCTAssertEqual(try RGAdPolicy.project(RGAdInput(text: text)).text, text)
        }
        for kind in [RGAdEntity.Kind.quote, .code, .link] {
            let text = "#广告\n套餐介绍"
            XCTAssertEqual(try RGAdPolicy.project(RGAdInput(text: text, entities: [entity(text, "#广告", kind: kind)])).text, text)
        }
    }

    func testDisclosureCanHideQuotedPriceCardButProtectsRealCode() throws {
        let text = "套餐价格与服务说明\n优惠码 EXAMPLE\n\n#广告"
        let quoted = RGAdInput(
            text: text, entities: [entity(text, "套餐价格与服务说明", kind: .quote), entity(text, "EXAMPLE", kind: .code)], hasMedia: true)
        XCTAssertEqual(try RGAdPolicy.project(quoted).disposition, .hide)
        let label = "复制 123456 到活动页面搜索，领取邀请红包"
        let redemption = "红包推广\n" + label + "\n\n#推广"
        XCTAssertEqual(
            try RGAdPolicy.project(RGAdInput(text: redemption, entities: [entity(redemption, label, kind: .code)], hasMedia: true))
                .disposition, .hide)
        let code = "func show() { print(1) }\n#广告"
        XCTAssertEqual(
            try RGAdPolicy.project(RGAdInput(text: code, entities: [entity(code, "func show() { print(1) }", kind: .code)])).text, code)
    }

    func testReviewedKeepOverridesAuthorDisclosure() throws {
        let storage = try store()
        let input = RGAdInput(text: "保留这一条示例内容\n\n#AD", peerId: 99)
        XCTAssertEqual(try RGAdPolicy.project(input).disposition, .hide)
        let sample = try storage.draft(input: input, messageKey: "99:disclosure", mediaKinds: [], mediaIdentity: "")
        try storage.save(sample)
        XCTAssertEqual(try RGAdPolicy.project(input, samples: storage.load(), sourceGroup: sample.sourceGroup).disposition, .keep)
        XCTAssertEqual(try RGAdPolicy.project(input, samples: storage.load(), sourceGroup: "another-conversation").disposition, .hide)
    }

    func testEmbeddedTopicTagsInNormalSoftwareDescriptionArePreserved() throws {
        let text = "开源拦截工具\n⏺ #短信 #电话 #广告 #拦截\n使用方法见官方文档。"
        XCTAssertTrue(RGAdDisclosure.ranges(RGAdInput(text: text)).isEmpty)
        XCTAssertEqual(try RGAdPolicy.project(RGAdInput(text: text)).text, text)
    }

    func testStandaloneDisclosureBetweenNormalParagraphs() throws {
        for gap in ["\n", "\n\n"] {
            let text = "正常教程介绍。\n\n#AD" + gap + "商业服务套餐说明\n更多价格说明\n\n正常教程结尾。"
            let result = try RGAdPolicy.project(RGAdInput(text: text, hasMedia: true))
            XCTAssertEqual(result.disposition, .trim)
            XCTAssertTrue(result.text.contains("正常教程介绍。"))
            XCTAssertTrue(result.text.contains("正常教程结尾。"))
            XCTAssertFalse(result.text.contains("#AD"))
            XCTAssertFalse(result.text.contains("套餐"))
            XCTAssertFalse(result.text.contains("价格"))
        }
    }

    func testPromotionalSentenceWithQueryLinkIsRemovedCompletely() throws {
        let link = "https://example.org/buy?plan=small!limited;ref=sample"
        let promotion = "购买付费套餐，访问 " + link + " 获取优惠。\n"
        let text = promotion + "正常软件使用说明。"
        let entities = [entity(text, link, kind: .link)]
        let segments = RGAdFilter.semanticRanges(text, entities: entities)
        let adRange = RGAdRange(0, promotion.utf16.count - 1)
        XCTAssertTrue(segments.contains(adRange))
        let result = try RGAdFilter.project(
            RGAdInput(text: text, entities: entities), predictions: [RGAdPrediction(range: adRange, confidence: 1)])
        XCTAssertEqual(result.text.trimmingCharacters(in: .whitespacesAndNewlines), "正常软件使用说明。")
        XCTAssertTrue(result.entities.isEmpty)
    }

    func testDisclosedQuotedSectionPreservesOutsideQuotation() throws {
        let text = "正常引用说明\n======\n套餐广告\n月付价格与购买入口\n#广告\n======\n正常教程结尾"
        let result = try RGAdPolicy.project(
            RGAdInput(
                text: text, entities: [entity(text, "正常引用说明", kind: .quote), entity(text, "月付价格与购买入口", kind: .quote)], hasMedia: true))
        XCTAssertEqual(result.disposition, .trim)
        XCTAssertTrue(result.text.contains("正常引用说明"))
        XCTAssertTrue(result.text.contains("正常教程结尾"))
        XCTAssertFalse(result.text.contains("套餐"))
        XCTAssertFalse(result.text.contains("月付"))
    }

    func testMixedCaptionAndButtons() throws {
        let text = "剧名：春日旅程\n简介：两人一起寻找答案。\n@search_helper\n================\n" + ad
        let input = RGAdInput(
            text: text, entities: [entity(text, "@search_helper"), entity(text, "@promotion_user")],
            buttons: [
                [
                    RGAdButton(id: "0:0", title: "电影搜索", target: "https://t.me/search_helper"),
                    RGAdButton(id: "0:1", title: "一元云购", target: "https://t.me/promotion_user"),
                ]
            ], hasMedia: true)
        let result = try RGAdPolicy.project(input)
        XCTAssertEqual(result.disposition, .trim)
        XCTAssertTrue(result.text.contains("剧名：春日旅程"))
        XCTAssertTrue(result.text.contains("@search_helper"))
        XCTAssertFalse(result.text.contains("中奖"))
        XCTAssertFalse(result.text.contains("===="))
        XCTAssertEqual(result.buttons.flatMap { $0 }.map(\.id), ["0:0"])
    }

    func testInlineNavigationKeepsIndependentNormalLinks() throws {
        let text = "软件介绍保留。\n🧐 合集 💬 群组 😄 恰饭 🥰联系推广\n#软件"
        let names = ["合集", "群组", "恰饭", "联系推广"]
        let input = RGAdInput(
            text: text,
            entities: names.enumerated().map {
                entity(text, $0.element, kind: .link, value: "https://example.org/\($0.offset)")
            }, hasMedia: true)
        let rows = RGAdFilter.navigationRows(input)
        XCTAssertEqual(rows.count, 1)
        let units = try XCTUnwrap(rows.values.first)
        XCTAssertEqual(units.count, 4)
        let predictions = units.suffix(2).map { RGAdPrediction(range: $0, confidence: 1) }
        let result = try RGAdFilter.project(input, predictions: predictions)
        XCTAssertEqual(result.disposition, .trim)
        XCTAssertTrue(result.text.contains("软件介绍保留。"))
        XCTAssertTrue(result.text.contains("合集 💬 群组"))
        XCTAssertTrue(result.text.contains("群组\n#软件"))
        XCTAssertTrue(result.text.contains("#软件"))
        XCTAssertFalse(result.text.contains("恰饭"))
        XCTAssertFalse(result.text.contains("推广"))
        XCTAssertEqual(result.entities.count, 2)
        for kind in [RGAdEntity.Kind.quote, .code] {
            let guarded = RGAdInput(text: text, entities: input.entities + [entity(text, "🧐 合集 💬 群组 😄 恰饭 🥰联系推广", kind: kind)])
            XCTAssertTrue(RGAdFilter.navigationRows(guarded).isEmpty)
            XCTAssertEqual(try RGAdFilter.project(guarded, predictions: predictions).text, text)
        }
        let prose = "请阅读项目文档，然后在社区讨论问题。"
        let linkedProse = RGAdInput(text: prose, entities: [entity(prose, "项目文档", kind: .link), entity(prose, "社区讨论", kind: .link)])
        XCTAssertTrue(RGAdFilter.navigationRows(linkedProse).isEmpty)
    }

    func testAdjacentFragmentsOfOneHyperlinkStayAtomic() throws {
        let title = "银行开户奖励：DD入金查询指南"
        let fragments = ["银行开户奖励：", "DD", "入金查询指南"]
        let input = RGAdInput(
            text: title,
            entities: fragments.map {
                entity(title, $0, kind: .link, value: "https://example.org/guide")
            })
        XCTAssertTrue(RGAdFilter.navigationRows(input).isEmpty)
        let isolated = entity(title, fragments[2]).range
        XCTAssertEqual(try RGAdFilter.project(input, predictions: [RGAdPrediction(range: isolated, confidence: 1)]).text, title)

        let menu = "官网 社区 联系推广"
        let mixed = RGAdInput(
            text: menu,
            entities: [
                entity(menu, "官网", kind: .link, value: "https://example.org"),
                entity(menu, "社区", kind: .link, value: "https://example.org/community"),
                entity(menu, "联系", kind: .link, value: "https://example.org/ads"),
                entity(menu, "推广", kind: .link, value: "https://example.org/ads"),
            ])
        let units = try XCTUnwrap(RGAdFilter.navigationRows(mixed).values.first)
        XCTAssertEqual(units.count, 3)
        let projection = try RGAdFilter.project(mixed, predictions: [RGAdPrediction(range: units[2], confidence: 1)])
        XCTAssertEqual(projection.text, "官网 社区")
        XCTAssertEqual(projection.entities.count, 2)
    }

    func testBareDestinationOnlyFollowsSameAdjacentRemovedLink() throws {
        let ad = "订阅套餐现在购买"
        for (gap, url, shouldRemove) in [
            ("\n\n", "https://example.org", true), ("\n正常来源说明\n", "https://example.org", false), ("\n", "https://example.org/docs", false),
        ] {
            let text = "正常正文\n" + ad + gap + url
            let input = RGAdInput(
                text: text,
                entities: [entity(text, ad, kind: .link, value: "https://example.org/"), entity(text, url, kind: .link, value: url)])
            let range = (text as NSString).range(of: ad)
            let result = try RGAdFilter.project(input, confirmedRanges: [RGAdRange(range.location, NSMaxRange(range))])
            XCTAssertTrue(result.text.contains("正常正文"))
            XCTAssertEqual(result.text.contains(url), !shouldRemove)
            XCTAssertTrue(
                try RGAdFilter.project(input, confirmedRanges: [RGAdRange(range.location, NSMaxRange(range))], inferButtons: false).text
                    .contains(url))
        }
        let text = ad + "\nhttps://example.org"
        for kind in [RGAdEntity.Kind.quote, .code] {
            let input = RGAdInput(
                text: text,
                entities: [entity(text, ad, kind: .link, value: "https://example.org"), entity(text, "https://example.org", kind: kind)])
            XCTAssertTrue(
                try RGAdFilter.project(input, confirmedRanges: [RGAdRange(0, ad.utf16.count)]).text.contains("https://example.org"))
        }
    }

    func testEntireAdvertisingCaptionHidesItsAttachment() throws {
        let input = RGAdInput(text: ad, entities: [entity(ad, "@promotion_user")], hasMedia: true)
        XCTAssertEqual(try RGAdPolicy.project(input).disposition, .hide)
        let normalButton = RGAdInput(
            text: ad, entities: input.entities, buttons: [[RGAdButton(id: "search", title: "电影搜索", target: "https://t.me/search_helper")]],
            hasMedia: true)
        XCTAssertEqual(try RGAdPolicy.project(normalButton).disposition, .trim)
        XCTAssertEqual(try RGAdPolicy.project(RGAdInput(text: "", hasMedia: true)).disposition, .keep)
        let mixed = "正常影片介绍\n" + ad
        XCTAssertEqual(
            try RGAdPolicy.project(RGAdInput(text: mixed, entities: [entity(mixed, "@promotion_user")], hasMedia: true)).disposition, .trim)
        let semantic = RGAdSemanticResult(
            predictions: [RGAdPrediction(range: RGAdRange(0, ad.utf16.count), confidence: 1)], threshold: 0.996)
        XCTAssertEqual(try RGAdPolicy.project(RGAdInput(text: ad, hasMedia: true), semantic: semantic).disposition, .hide)
    }

    func testWarningAndQuotedPromotionArePreserved() throws {
        for text in ["警惕骗局：" + ad, "新闻报道：" + ad] {
            XCTAssertEqual(try RGAdPolicy.project(RGAdInput(text: text, entities: [entity(text, "@promotion_user")])).disposition, .keep)
        }
        for kind in [RGAdEntity.Kind.code, .quote] {
            let input = RGAdInput(
                text: ad, entities: [entity(ad, "@promotion_user"), RGAdEntity(range: RGAdRange(0, ad.utf16.count), kind: kind)])
            XCTAssertEqual(try RGAdPolicy.project(input).disposition, .keep)
        }
    }

    func testDecorativeGapOnlyDisappearsBetweenAds() throws {
        for gap in ["\n🤩🤩\n", "\n正常说明\n", "\n@resource\n"] {
            let text = "推广内容甲\n" + gap + "推广内容乙\n正常正文"
            let first = (text as NSString).range(of: "推广内容甲\n")
            let second = (text as NSString).range(of: "推广内容乙\n")
            let cuts = [first, second].map { RGAdRange($0.location, NSMaxRange($0)) }
            let result = try RGAdFilter.project(RGAdInput(text: text), confirmedRanges: cuts)
            XCTAssertEqual(result.text, gap.contains("🤩") ? "正常正文" : gap + "正常正文")
        }
        let text = "推广内容甲\n🤩🤩\n推广内容乙"
        let emoji = entity(text, "🤩🤩", kind: .link, value: "https://example.org/resource")
        let cuts = [RGAdRange(0, 6), RGAdRange(text.utf16.count - 5, text.utf16.count)]
        XCTAssertTrue(try RGAdFilter.project(RGAdInput(text: text, entities: [emoji]), confirmedRanges: cuts).text.contains("🤩"))
    }

    func testInlineDividerKeepsNormalPrefixAndCouponCodeNeedsWholeAd() throws {
        let text = "正常搜索入口 @resource================\n\n" + ad
        let input = RGAdInput(text: text, entities: [entity(text, "@resource"), entity(text, "@promotion_user")])
        XCTAssertEqual(try RGAdPolicy.project(input).text, "正常搜索入口 @resource")
        for code in ["SAVE20", "print(20)", "let value = 20"] {
            let card = "注册优惠，立即下单\n优惠码：" + code
            let input = RGAdInput(text: card, entities: [entity(card, code, kind: .code)])
            let prediction = RGAdPrediction(range: RGAdRange(0, card.utf16.count), confidence: 1)
            XCTAssertEqual(
                try RGAdFilter.project(input, predictions: [prediction], entireMessageIsAd: true).disposition,
                code == "SAVE20" ? .hide : .keep)
            XCTAssertEqual(try RGAdFilter.project(input, predictions: [prediction]).disposition, .keep)
        }
    }

    func testRepeatedPromotionDoesNotEraseWarningInSameMessage() throws {
        let text = "警惕骗局：" + ad + "\n" + ad
        let last = (text as NSString).range(of: "@promotion_user", options: .backwards)
        let input = RGAdInput(
            text: text,
            entities: [
                entity(text, "@promotion_user"),
                RGAdEntity(range: RGAdRange(last.location, NSMaxRange(last)), kind: .mention, value: "@promotion_user"),
            ])
        XCTAssertEqual(try RGAdPolicy.project(input).text, "警惕骗局：" + ad + "\n")
    }

    func testRepeatedNormalOccurrencePreventsLearning() throws {
        let storage = try store()
        let snippet = "欢迎参与我们的优惠活动并领取专属奖励"
        var sample = try storage.draft(
            input: RGAdInput(text: snippet + "\n" + snippet, peerId: 9), messageKey: "9:1", mediaKinds: [], mediaIdentity: "")
        try sample.mark(NSRange(location: 0, length: snippet.utf16.count), as: .ad)
        try storage.save(sample)
        XCTAssertEqual(
            try RGAdPolicy.project(RGAdInput(text: "新内容\n" + snippet, peerId: 9), samples: storage.load(), sourceGroup: sample.sourceGroup)
                .disposition, .keep)
    }

    func testNoDestinationAndNormalResourceLinksArePreserved() throws {
        for text in ["中奖可提现", "本片包含广告行业与赌场相关情节。", "免费体验新功能 @search_helper", ad] {
            XCTAssertEqual(try RGAdPolicy.project(RGAdInput(text: text)).disposition, .keep)
        }
        let input = RGAdInput(text: "影视介绍与资源", buttons: [[RGAdButton(id: "a", title: "电报资源", target: "https://t.me/search_helper")]])
        XCTAssertEqual(try RGAdPolicy.project(input).buttons, input.buttons)
    }

    func testPublicButtonRuleDoesNotRemoveBody() throws {
        let input = RGAdInput(
            text: "新闻：今天讨论广告合作招商。", buttons: [[RGAdButton(id: "a", title: "广告合作招商", target: "https://example.org/sponsor")]])
        let output = try RGAdPolicy.project(input)
        XCTAssertEqual(output.text, input.text)
        XCTAssertTrue(output.buttons.isEmpty)
        let buttons = [
            RGAdButton(id: "ad", title: "8G.COM 新人注册送38U", target: "https://example.org/invite"),
            RGAdButton(id: "normal", title: "警惕8G.COM 新人注册送38U骗局", target: "https://example.org/news"),
        ]
        XCTAssertEqual(try RGAdPolicy.project(RGAdInput(text: "正常文章", buttons: [buttons])).buttons, [[buttons[1]]])
    }

    func testEmojiBannerAndIndependentInviteButton() throws {
        let banner = "🩷🩷🩷🩷 新人注册送38U"
        let text = "剧名：春日旅程\n简介：正常剧情。\n@search_helper\n================\n\n实力飞投｜超高限红｜大额无忧 ➜ @first_promo\n\n" + ad + "\n\n" + banner
        var entities = [
            entity(text, "@search_helper"), entity(text, "@first_promo"), entity(text, "@promotion_user"),
            entity(text, banner, kind: .link, value: "https://example.org/signup"),
            entity(text, "================", kind: .format, value: "bold"),
        ]
        let start = (text as NSString).range(of: "🩷🩷🩷🩷").location
        for i in 0..<4 {
            entities.append(RGAdEntity(range: RGAdRange(start + i * 2, start + i * 2 + 2), kind: .customEmoji, value: "synthetic-\(i)"))
        }
        let input = RGAdInput(
            text: text, entities: entities,
            buttons: [
                [RGAdButton(id: "cooperate", title: "广 告 合 作 招 商", target: "https://example.org/sponsor")],
                [
                    RGAdButton(id: "search", title: "电影搜索", target: "https://t.me/search_helper"),
                    RGAdButton(id: "resources", title: "电报资源", target: "https://t.me/resource_helper"),
                ],
                [
                    RGAdButton(id: "invite", title: "白马庄园大额无忧", target: "https://t.me/+syntheticInvite"),
                    RGAdButton(id: "lottery", title: "一元云购 0充值，免费体验，中奖可提现", target: "https://example.org/different-destination"),
                ],
            ], hasMedia: true)
        let result = try RGAdPolicy.project(input)
        XCTAssertEqual(result.text, "剧名：春日旅程\n简介：正常剧情。\n@search_helper\n")
        XCTAssertEqual(result.buttons.flatMap { $0 }.map(\.id), ["search", "resources"])
        XCTAssertEqual(result.disposition, .trim)
        XCTAssertEqual(result.entities.map(\.kind), [.mention])
    }

    func testLinkedHiddenBrandAndObfuscatedPromotion() throws {
        let text = "正常正文👨‍👩‍👧‍👦\n🩷🩷🩷🩷 新人注册送38U"
        for target in ["https://8g.com/?campaign=synthetic", "https://8gtg.vip/synthetic"] {
            let link = entity(text, "🩷🩷🩷🩷 新人注册送38U", kind: .link, value: target)
            XCTAssertEqual(try RGAdPolicy.project(RGAdInput(text: text, entities: [link])).text, "正常正文👨‍👩‍👧‍👦\n")
        }
        let spaced = "正常正文\n０ 充 值，免\u{200b}费 体 验，中 奖 可 提 现 → @promotion_user"
        XCTAssertEqual(try RGAdPolicy.project(RGAdInput(text: spaced, entities: [entity(spaced, "@promotion_user")])).text, "正常正文\n")
        let traditional = "正常正文\n實 力 飛 投｜超 高 限 紅｜大 額 無 憂 @promotion_user"
        XCTAssertEqual(
            try RGAdPolicy.project(RGAdInput(text: traditional, entities: [entity(traditional, "@promotion_user")])).text, "正常正文\n")
    }

    func testBannerEvidenceDoesNotConsumeNormalOrReportedContent() throws {
        let banner = "🩷🩷🩷🩷 新人注册送38U"
        for prefix in ["", "警惕骗局：" + ad + "\n", ad + "\n正常剧情介绍\n"] {
            let text = prefix + banner
            var entities = [entity(text, banner, kind: .link, value: "https://example.org/signup")]
            if prefix.contains("@promotion_user") { entities.append(entity(text, "@promotion_user")) }
            let start = (text as NSString).range(of: "🩷🩷🩷🩷").location
            for i in 0..<4 {
                entities.append(RGAdEntity(range: RGAdRange(start + i * 2, start + i * 2 + 2), kind: .customEmoji, value: "synthetic-\(i)"))
            }
            XCTAssertTrue(try RGAdPolicy.project(RGAdInput(text: text, entities: entities)).text.contains(banner))
        }
        for target in ["https://8g.com.example.org", "https://example.org/8g.com"] {
            XCTAssertEqual(
                try RGAdPolicy.project(RGAdInput(text: banner, entities: [entity(banner, banner, kind: .link, value: target)])).disposition,
                .keep)
        }
        let warning = "警 惕\u{200b}诈 骗：" + ad
        XCTAssertEqual(try RGAdPolicy.project(RGAdInput(text: warning, entities: [entity(warning, "@promotion_user")])).disposition, .keep)
        let normal = RGAdInput(
            text: "影视正文",
            buttons: [
                [
                    RGAdButton(id: "normal", title: "白马庄园取景地介绍", target: "https://example.org/film"),
                    RGAdButton(id: "warning", title: "警惕白马庄园大额无忧骗局", target: "https://example.org/report"),
                ]
            ])
        XCTAssertEqual(try RGAdPolicy.project(normal).disposition, .keep)
    }

    func testDestinationIsExactAndNormalLinkVetoesInferredRemoval() throws {
        let text = "联系 @promotion_user\n" + ad
        let ranges = (text as NSString).range(of: "@promotion_user", options: .backwards)
        let input = RGAdInput(
            text: text,
            entities: [
                entity(text, "@promotion_user"),
                RGAdEntity(range: RGAdRange(ranges.location, NSMaxRange(ranges)), kind: .mention, value: "@promotion_user"),
            ],
            buttons: [
                [
                    RGAdButton(id: "a", title: "联系", target: "https://t.me/promotion_user"),
                    RGAdButton(id: "b", title: "别的频道", target: "https://t.me/search_helper"),
                ]
            ])
        XCTAssertEqual(try RGAdPolicy.project(input).buttons, input.buttons)
        XCTAssertNotEqual(RGAdFilter.normalizedTarget("https://t.me/promotion_user/123"), RGAdFilter.normalizedTarget("@promotion_user"))
        XCTAssertEqual(RGAdFilter.normalizedTarget("@abcd"), RGAdFilter.normalizedTarget("https://t.me/abcd"))
    }

    func testUnicodeMarkSplitAndClear() throws {
        let storage = try store()
        var sample = try storage.draft(input: RGAdInput(text: "正常👨‍👩‍👧‍👦广告é尾部", peerId: 1), messageKey: "1", mediaKinds: [], mediaIdentity: "")
        try sample.mark(NSRange(location: 3, length: 1), as: .ad)
        XCTAssertEqual((sample.input.text as NSString).substring(with: sample.spans[0].range.nsRange), "👨‍👩‍👧‍👦")
        try sample.mark(NSRange(location: 0, length: sample.input.text.utf16.count), as: .ad)
        try sample.mark(NSRange(location: 0, length: 2), as: .normal)
        XCTAssertEqual(sample.previewText, "正常")
        try sample.validate()
        XCTAssertThrowsError(try sample.mark(NSRange(location: Int.max, length: 3), as: .ad))
    }

    func testHumanSelectionExpandsAtomicLink() throws {
        let storage = try store()
        let text = "内容 链接文字 保留"
        var sample = try storage.draft(
            input: RGAdInput(text: text, peerId: 1, entities: [entity(text, "链接文字", kind: .link, value: "https://example.org")]),
            messageKey: "1", mediaKinds: [], mediaIdentity: "")
        try sample.mark(NSRange(location: 4, length: 1), as: .ad)
        XCTAssertEqual((text as NSString).substring(with: sample.spans[0].range.nsRange), "链接文字")
        XCTAssertEqual(sample.previewText, "内容  保留")
    }

    func testFormattingRemapAfterRemovedParagraph() throws {
        let text = "广告片段\n正常👋文字"
        let output = try RGAdFilter.project(
            RGAdInput(text: text, entities: [RGAdEntity(range: RGAdRange(0, text.utf16.count), kind: .format, value: "bold")]),
            rules: [RGAdRule("广告片段")])
        XCTAssertEqual(output.text, "正常👋文字")
        XCTAssertEqual(output.entities.first?.range, RGAdRange(0, output.text.utf16.count))
    }

    func testReviewedNormalOverridesAutomaticAndSurvivesRestart() throws {
        let storage = try store()
        let input = RGAdInput(text: ad, peerId: 99, entities: [entity(ad, "@promotion_user")])
        let sample = try storage.draft(input: input, messageKey: "99:1", mediaKinds: [], mediaIdentity: "")
        XCTAssertTrue(try storage.load().isEmpty)
        try storage.save(sample)
        let reopened = RGAdSampleStore(accountDirectory: storage.directory.deletingLastPathComponent())
        let loaded = try reopened.load()
        XCTAssertEqual(try RGAdPolicy.project(input, samples: loaded, sourceGroup: sample.sourceGroup).disposition, .keep)
        XCTAssertEqual(try reopened.draft(input: input, messageKey: "99:1", mediaKinds: [], mediaIdentity: "").id, sample.id)
    }

    func testEditedMessageGetsNewUnreviewedSnapshot() throws {
        let storage = try store()
        let sample = try storage.draft(input: RGAdInput(text: "原文", peerId: 2), messageKey: "2:1", mediaKinds: [], mediaIdentity: "a")
        try storage.save(sample)
        let edited = try storage.draft(input: RGAdInput(text: "新原文", peerId: 2), messageKey: "2:1", mediaKinds: [], mediaIdentity: "a")
        let replaced = try storage.draft(input: RGAdInput(text: "原文", peerId: 2), messageKey: "2:1", mediaKinds: [], mediaIdentity: "b")
        XCTAssertNotEqual(edited.id, sample.id)
        XCTAssertNil(edited.reviewedAt)
        XCTAssertNotEqual(replaced.id, sample.id)
    }

    func testSameChannelLearnsExactAdSnippetButOtherChannelsDoNot() throws {
        let storage = try store()
        let snippet = "欢迎参与我们的优惠活动并领取专属奖励"
        var sample = try storage.draft(
            input: RGAdInput(text: "正常介绍\n" + snippet, peerId: 9), messageKey: "9:1", mediaKinds: [], mediaIdentity: "")
        try sample.mark((sample.input.text as NSString).range(of: snippet), as: .ad)
        try storage.save(sample)
        let later = RGAdInput(text: "另一个正常介绍\n" + snippet, peerId: 9)
        XCTAssertFalse(try RGAdPolicy.project(later, samples: storage.load(), sourceGroup: sample.sourceGroup).text.contains(snippet))
        XCTAssertEqual(try RGAdPolicy.project(later, samples: storage.load(), sourceGroup: "other").disposition, .keep)
        try storage.remove(sample)
        XCTAssertEqual(try RGAdPolicy.project(later, samples: storage.load(), sourceGroup: sample.sourceGroup).disposition, .keep)
    }

    func testButtonCorrectionDoesNotRemoveNormalTextLink() throws {
        let storage = try store()
        let text = "正常链接 @search_helper"
        let button = RGAdButton(id: "0:0", title: "推广入口", target: "https://t.me/search_helper")
        let input = RGAdInput(text: text, peerId: 9, entities: [entity(text, "@search_helper")], buttons: [[button]])
        var sample = try storage.draft(input: input, messageKey: "9:1", mediaKinds: [], mediaIdentity: "")
        sample.buttonLabels[button.id] = .ad
        try storage.save(sample)
        let later = RGAdInput(text: text + " 更多内容", peerId: 9, entities: input.entities, buttons: input.buttons)
        let projected = try RGAdPolicy.project(later, samples: storage.load(), sourceGroup: sample.sourceGroup)
        XCTAssertEqual(projected.text, later.text)
        XCTAssertTrue(projected.buttons.isEmpty)
    }

    func testNormalButtonLabelVetoesAdTextInference() throws {
        let storage = try store()
        let input = RGAdInput(
            text: ad, peerId: 9, entities: [entity(ad, "@promotion_user")],
            buttons: [[RGAdButton(id: "a", title: "保留", target: "https://t.me/promotion_user")]])
        var sample = try storage.draft(input: input, messageKey: "9:1", mediaKinds: [], mediaIdentity: "")
        try sample.mark(NSRange(location: 0, length: ad.utf16.count), as: .ad)
        sample.buttonLabels["a"] = .normal
        try storage.save(sample)
        XCTAssertEqual(try RGAdPolicy.project(input, samples: storage.load(), sourceGroup: sample.sourceGroup).buttons, input.buttons)
    }

    func testRetainedButtonCorrectionAppliesToLaterMessagesInSameChannel() throws {
        for label in [RGAdLabel.normal, .uncertain] {
            let storage = try store()
            let button = RGAdButton(id: "a", title: "保留入口", target: "https://t.me/promotion_user")
            let input = RGAdInput(text: ad, peerId: 9, entities: [entity(ad, "@promotion_user")], buttons: [[button]])
            var sample = try storage.draft(input: input, messageKey: "9:1", mediaKinds: [], mediaIdentity: "")
            try sample.mark(NSRange(location: 0, length: ad.utf16.count), as: .ad)
            sample.buttonLabels[button.id] = label
            try storage.save(sample)
            let text = "新的正常介绍\n" + ad
            let later = RGAdInput(
                text: text, peerId: 9, entities: [entity(text, "@promotion_user")],
                buttons: [[RGAdButton(id: "1:1", title: button.title, target: button.target)]])
            let knowledge = try RGAdPolicy.Knowledge(samples: storage.load())
            let projected = try knowledge.project(later, sourceGroup: sample.sourceGroup)
            XCTAssertEqual(projected.text, "新的正常介绍\n")
            XCTAssertEqual(projected.buttons, later.buttons)
            XCTAssertTrue(projected.removedButtonIds.isEmpty)
            XCTAssertTrue(try knowledge.project(later, sourceGroup: "other").buttons.isEmpty)
        }
    }

    func testAccountIsolationExportAndCorruptionFailClosed() throws {
        let first = try store()
        let second = try store()
        let input = RGAdInput(text: "正常消息", peerId: 123_456_789)
        let a = try first.draft(input: input, messageKey: "m", mediaKinds: [], mediaIdentity: "")
        let b = try second.draft(input: input, messageKey: "m", mediaKinds: [], mediaIdentity: "")
        XCTAssertNotEqual(a.sourceGroup, b.sourceGroup)
        XCTAssertNotEqual(a.id, b.id)
        try first.save(a)
        let export = try first.export()
        let text = String(decoding: export, as: UTF8.self)
        XCTAssertFalse(text.contains("123456789"))
        XCTAssertTrue(text.contains("utf16"))
        XCTAssertTrue(try second.load().isEmpty)
        try Data("broken".utf8).write(to: first.directory.appendingPathComponent(a.id + ".json"))
        XCTAssertThrowsError(try first.load())
        XCTAssertThrowsError(try first.export())
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.directory.appendingPathComponent(a.id + ".json").path))
    }

    func testAutomaticRecordsDoNotTeachUntilReviewedAndKeepOriginalDecision() throws {
        let storage = try store()
        let text = "正常内容\n欢迎购买本店的精选商品享受专属优惠"
        let input = RGAdInput(text: text, peerId: 42)
        let cut = RGAdRange(5, text.utf16.count)
        let projection = try RGAdFilter.project(input, confirmedRanges: [cut])
        for _ in 0..<3 {
            try storage.recordDetection(input: input, messageKey: "42:1", mediaKinds: [], mediaIdentity: "", projection: projection)
        }
        let reopened = RGAdSampleStore(accountDirectory: storage.directory.deletingLastPathComponent())
        var records = try reopened.load()
        XCTAssertEqual(records.count, 1)
        XCTAssertTrue(try reopened.load(reviewedOnly: true).isEmpty, "Inference must not retain the pending sample library")
        XCTAssertNil(records[0].reviewedAt)
        XCTAssertNotNil(records[0].detection)
        XCTAssertEqual(records[0].input.text, text)
        XCTAssertNil(records[0].input.peerId)
        XCTAssertTrue(try reopened.export(trainingOnly: true).isEmpty)
        XCTAssertFalse(try reopened.export().isEmpty)
        XCTAssertEqual(try RGAdPolicy.project(input, samples: records, sourceGroup: records[0].sourceGroup).disposition, .keep)
        let originalDecision = records[0].detection
        records[0].spans = []
        try reopened.save(records[0])
        try reopened.recordDetection(input: input, messageKey: "42:1", mediaKinds: [], mediaIdentity: "", projection: projection)
        records = try reopened.load()
        XCTAssertTrue(records[0].spans.isEmpty)
        XCTAssertNotNil(records[0].reviewedAt)
        XCTAssertEqual(records[0].detection, originalDecision)
        XCTAssertFalse(try reopened.export(trainingOnly: true).isEmpty)
        let edited = RGAdInput(text: text + "！", peerId: 42)
        try reopened.recordDetection(
            input: edited, messageKey: "42:1", mediaKinds: [], mediaIdentity: "",
            projection: RGAdFilter.project(edited, confirmedRanges: [cut]))
        XCTAssertEqual(try reopened.load().count, 2)
        XCTAssertEqual(try reopened.load(reviewedOnly: true).count, 1)
        try reopened.recordDetection(
            input: edited, messageKey: "42:1", mediaKinds: [], mediaIdentity: "",
            projection: RGAdFilter.project(edited, confirmedRanges: [cut]))
        XCTAssertEqual(try reopened.load().count, 2, "Reviewed-only loading must keep the full idempotency index")
        XCTAssertEqual(String(decoding: try reopened.export(trainingOnly: true), as: UTF8.self).split(separator: "\n").count, 1)
    }

    func testConcurrentReviewKeepsTheAutomaticDetection() throws {
        let store = try store()
        let input = RGAdInput(text: "广告示例", peerId: 42)
        let draft = try store.draft(input: input, messageKey: "42:1", mediaKinds: [], mediaIdentity: "")
        let projection = try RGAdFilter.project(input, confirmedRanges: [RGAdRange(0, input.text.utf16.count)])
        try store.recordDetection(input: input, messageKey: "42:1", mediaKinds: [], mediaIdentity: "", projection: projection)
        let detection = try XCTUnwrap(store.load().first?.detection)
        try store.save(draft)
        XCTAssertEqual(try store.load().first?.detection, detection)
        XCTAssertThrowsError(try store.save(draft)) { XCTAssertEqual($0 as? RGAdSampleError, .changed) }
    }

    func testReviewedWholeAdHidesMediaButUncertainReviewDoesNot() throws {
        let storage = try store()
        let input = RGAdInput(text: "推广正文", peerId: 42, hasMedia: true)
        var sample = try storage.draft(input: input, messageKey: "42:1", mediaKinds: ["image"], mediaIdentity: "image-1")
        try sample.mark(NSRange(location: 0, length: input.text.utf16.count), as: .ad)
        try storage.save(sample)
        XCTAssertFalse(try storage.load()[0].isTrainingReady)
        XCTAssertNotEqual(
            try RGAdPolicy.project(input, samples: storage.load(), sourceGroup: sample.sourceGroup, sampleId: sample.id).disposition, .hide)
        sample = try XCTUnwrap(storage.load().first)
        sample.mediaLabel = .ad
        try storage.save(sample)
        XCTAssertEqual(
            try RGAdPolicy.project(input, samples: storage.load(), sourceGroup: sample.sourceGroup, sampleId: sample.id).disposition, .hide)
        XCTAssertTrue(try storage.load()[0].isTrainingReady)
    }
    func testMediaOnlyReviewIsBoundToOneSnapshot() throws {
        let storage = try store()
        let input = RGAdInput(text: "", peerId: 42, hasMedia: true)
        var sample = try storage.draft(input: input, messageKey: "42:1", mediaKinds: ["image"], mediaIdentity: "ad-image")
        sample.mediaLabel = .ad
        try storage.save(sample)
        let other = try storage.draft(input: input, messageKey: "42:2", mediaKinds: ["image"], mediaIdentity: "normal-image")
        let knowledge = RGAdPolicy.Knowledge(samples: try storage.load())
        XCTAssertEqual(try knowledge.project(input, sourceGroup: sample.sourceGroup, sampleId: sample.id).disposition, .hide)
        XCTAssertEqual(try knowledge.project(input, sourceGroup: sample.sourceGroup, sampleId: other.id).disposition, .keep)
        XCTAssertEqual(try knowledge.project(input, sourceGroup: sample.sourceGroup).disposition, .keep)
        XCTAssertEqual(
            sample.id, try RGAdSampleStore.sampleId(input: input, salt: storage.salt(), messageKey: "42:1", mediaIdentity: "ad-image"))
    }

}

import Foundation

public enum RegramWebTranslationScript {
    public static let collect = #"""
    (() => {
        if (!document.body) return [];
        const previous = window.__regramTranslation;
        if (previous) previous.restore();
        const items = [];
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        let node;
        while ((node = walker.nextNode())) {
            const parent = node.parentElement;
            if (!parent || parent.closest('script,style,noscript,pre,code,form,textarea,input,select,option,svg,canvas,[contenteditable],[translate="no"],[hidden],[aria-hidden="true"]')) continue;
            if (!parent.getClientRects().length) continue;
            const style = getComputedStyle(parent);
            if (style.display === 'none' || style.visibility === 'hidden') continue;
            const text = node.nodeValue;
            if (!text || !text.trim() || !/[^\s\d\p{P}\p{S}]/u.test(text)) continue;
            items.push({node, original: text, translated: null});
        }
        window.__regramTranslation = {
            items,
            restore() {
                for (const item of this.items) {
                    if (item.node.isConnected && item.translated !== null && item.node.nodeValue === item.translated) item.node.nodeValue = item.original;
                }
                this.items = [];
            },
            apply(index, text) {
                const item = this.items[index];
                if (!item || !item.node.isConnected || item.node.nodeValue !== item.original) return;
                item.node.nodeValue = text;
                item.translated = text;
            }
        };
        return items.map(item => item.original);
    })()
    """#

    public static let restore = "window.__regramTranslation && window.__regramTranslation.restore()"

    public static func apply(index: Int, translation: String) -> String? {
        guard index >= 0, let data = try? JSONSerialization.data(withJSONObject: [translation]), let json = String(data: data, encoding: .utf8) else { return nil }
        return "window.__regramTranslation && window.__regramTranslation.apply(\(index), \(json)[0])"
    }
}

import Foundation

/// Small, source-grounded excerpts. No script, embedded player or media URL is
/// executed or downloaded; social imports can use the public recipe caption.
struct RecipeSourceContent: Equatable {
    enum Kind: String { case structuredRecipe, pageText, publicCaption }
    let text: String
    let kind: Kind
}

/// A nutrition estimate may use a typical food profile, but an ingredient
/// amount/yield must come from a declared source measure, never a typical one.
enum RecipeSourceQuantity {
    enum CookingFat: Equatable { case butter, oil }
    private static let number = "(?:[0-9]+\\s+[0-9]+\\s*/\\s*[0-9]+|[0-9]+\\s*/\\s*[0-9]+|[0-9]+(?:[.,][0-9]+)?|half|quarter|نصف|نص|ربع|ثلث|اثنان|اثنتان|اثنين|اثنتين|واحده?|ثلاثه?|اربعه?|خمسه)"
    private static let grams = "(?:kilograms?|kg|كيلو(?:غرام|جرام)?|كجم|كغ|grams?|g|جرامات?|غرامات?|جرام|غرام|جم|غم)"
    private static let liquid = "(?:milliliters?|millilitres?|ml|liters?|litres?|l|مليلتر|مليليتر|لتر|مل)"
    private static let end = "(?=\\s|[.,;:،()\\-]|$)"

    static func quantity(_ proposed: Double, unit: FoodUnit, unitLabel: String, quote: String?, source: String?) -> Double? {
        guard let phrase = verified(quote, source: source), proposed.isFinite, proposed > 0 else { return nil }
        let values: [Double]
        switch unit {
        case .g:
            values = measures(in: phrase, units: grams).map { pair in
                pair.0 * (["kg", "kilogram", "kilograms", "كجم", "كغ"].contains(pair.1) || pair.1.hasPrefix("كيلو") ? 1000 : 1)
            }
        case .ml:
            values = measures(in: phrase, units: liquid).map { pair in
                pair.0 * (["l", "liter", "liters", "litre", "litres", "لتر"].contains(pair.1) ? 1000 : 1)
            }
        case .serving:
            guard let family = householdFamily(unitLabel) else { return nil }
            var declared = measures(in: phrase, units: family.aliases).map { $0.0 }
            for (text, amount) in family.implied where containsPhrase(phrase, text) { declared.append(amount) }
            values = declared
        }
        return values.contains(where: { abs($0 - proposed) <= max(0.0001, $0 * 0.001) }) ? proposed : nil
    }

    static func servings(_ proposed: Double, quote: String?, source: String?) -> Double? {
        guard let phrase = verified(quote, source: source), proposed.isFinite, proposed > 0 else { return nil }
        let before = captures("(" + number + ")\\s*(?:servings?|portions?|people|حصص|حصه|اشخاص|افراد)" + end, in: phrase, group: 1)
        let after = captures("(?:servings?|serves|makes|portions?|عدد\\s*الحصص|تكفي)\\s*[:=]?\\s*(" + number + ")" + end, in: phrase, group: 1)
        let values = (before + after).compactMap(numeric)
        return values.contains { abs($0 - proposed) <= 0.0001 } ? proposed : nil
    }

    /// Preserve explicitly used cooking fat when extraction omits its row.
    /// A source mentioning fat-free/without/optional fat adds nothing.
    static func omittedCookingFats(in source: String, ingredientNames: [String]) -> [CookingFat] {
        let text = normalized(source)
        let names = ingredientNames.map(normalized)
        let actions = "(?:fry|saute|heat|cook|نشوحه?|نشوحها|شوحه?|شوحها|نقلي|اقلي|نحمر|حمر|نسخن|سخن)"
        let denied = ["without", "don't", "do not", "never", "optional", "if desired", "بدون", "بلا", "من غير", "اختياري", "حسب الرغبه"]
        let candidates: [(CookingFat, String, [String])] = [(.butter, "(?:\\bbutter\\b|بالزبده|بزبده|الزبده|زبده)", ["butter", "زبده"]),
                                                            (.oil, "(?:\\boil\\b|بالزيت|بزيت|الزيت|زيت)", ["oil", "زيت"])]
        return candidates.compactMap { candidate -> CookingFat? in
            let (kind, target, aliases) = candidate
            guard !names.contains(where: { name in aliases.contains(where: name.contains) }),
                  let regex = try? NSRegularExpression(pattern: actions + "[^\\n.;:،]{0,35}" + target) else { return nil }
            let ns = text as NSString
            let used = regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).contains { match in
                let context = ns.substring(with: NSRange(location: max(0, match.range.location - 16),
                    length: match.range.length + min(16, match.range.location)))
                let after = match.range.location + match.range.length
                let tail = ns.substring(with: NSRange(location: after, length: min(24, ns.length - after)))
                return !denied.contains(where: context.contains) &&
                    !["optional", "if desired", "اختياري", "حسب الرغبه"].contains(where: tail.contains)
            }
            return used ? kind : nil
        }
    }

    private static func verified(_ quote: String?, source: String?) -> String? {
        guard let quote, !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, quote.count <= 240,
              quote.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) || $0 == "\n" }) else { return nil }
        let phrase = normalized(quote)
        guard phrase.count >= 3, phrase.contains(where: \.isLetter) else { return nil }
        if let source, !normalized(source).contains(phrase) { return nil }
        return phrase
    }
    private struct Family { let aliases: String; let implied: [(String, Double)] }
    private static func householdFamily(_ label: String) -> Family? {
        let name = normalized(label)
        if name.contains("tablespoon") || name.contains("tbsp") || name.contains("كبير") && name.contains("ملعق") {
            return Family(aliases: "(?:tablespoons?|tbsp|tbs|ملعقه\\s+كبيره|ملاعق\\s+كبيره)",
                          implied: [("ملعقتان كبيرتان", 2), ("ملعقتين كبيرتين", 2), ("ملعقه كبيره", 1)])
        }
        if name.contains("teaspoon") || name.contains("tsp") || name.contains("صغير") && name.contains("ملعق") {
            return Family(aliases: "(?:teaspoons?|tsp|ملعقه\\s+صغيره|ملاعق\\s+صغيره)",
                          implied: [("ملعقتان صغيرتان", 2), ("ملعقتين صغيرتين", 2), ("ملعقه صغيره", 1)])
        }
        if name.contains("cup") || name.contains("كوب") || name.contains("اكواب") {
            return Family(aliases: "(?:cups?|كوب|اكواب)", implied: [("كوبان", 2), ("كوبين", 2), ("كوب", 1)])
        }
        if name.contains("spoon") || name.contains("ملعق") || name.contains("ملاعق") {
            return Family(aliases: "(?:spoons?|ملعقه|ملاعق)", implied: [("ملعقتان", 2), ("ملعقتين", 2), ("ملعقه", 1)])
        }
        if ["piece", "egg", "banana", "onion", "clove", "slice", "whole", "حبه", "حبات", "بيض", "بصله", "بصل", "قطعه", "شريحه", "فص"].contains(where: name.contains) {
            return Family(aliases: "(?:(?:(?:large|small|medium|كبيره?|صغيره?|متوسطه?)\\s+)?(?:eggs?|bananas?|onions?|tomatoes?|potatoes?|cloves?|pieces?|slices?|حبه|حبات|بيضه?|بصله?|قطعه|قطع|شريحه|شرائح|فص|فصوص))",
                          implied: [("حبه", 1), ("فص", 1), ("شريحه", 1), ("قطعه", 1)])
        }
        if name.contains("serving") || name.contains("portion") || name.contains("حصه") || name.contains("حصص") {
            return Family(aliases: "(?:servings?|portions?|حصه|حصص)", implied: [])
        }
        return nil
    }
    private static func measures(in phrase: String, units: String) -> [(Double, String)] {
        let pattern = "(?<![0-9/+-])(" + number + ")\\s*(" + units + ")" + end
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let text = phrase as NSString
        return regex.matches(in: phrase, range: NSRange(location: 0, length: text.length)).compactMap { match in
            guard let amount = numeric(text.substring(with: match.range(at: 1))) else { return nil }
            return (amount, text.substring(with: match.range(at: 2)))
        }
    }
    private static func containsPhrase(_ phrase: String, _ value: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: value) + "(?=$|[^\\p{L}\\p{N}])"),
              let match = regex.firstMatch(in: phrase, range: NSRange(location: 0, length: (phrase as NSString).length)),
              let range = Range(match.range, in: phrase) else { return false }
        // Singular measures imply one only without an adjacent numeric/fraction
        // modifier. E.g. '2 tablespoons' must not also become one tablespoon.
        let preceding = String(phrase[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        guard let last = preceding.last else { return true }
        if let token = preceding.split(separator: " ").last, numeric(String(token)) != nil { return false }
        return !last.isNumber && !["نصف", "نص", "ربع", "ثلث", "half", "quarter"].contains(where: preceding.hasSuffix)
    }
    private static func numeric(_ raw: String) -> Double? {
        let value = raw.trimmingCharacters(in: .whitespaces)
        if let number = Double(value.replacingOccurrences(of: ",", with: ".")) { return number }
        let words: [String: Double] = ["half": 0.5, "quarter": 0.25, "نصف": 0.5, "نص": 0.5, "ربع": 0.25, "ثلث": 1/3,
                                      "اثنان": 2, "اثنتان": 2, "اثنين": 2, "اثنتين": 2, "واحد": 1, "واحده": 1,
                                      "ثلاث": 3, "ثلاثه": 3, "اربع": 4, "اربعه": 4, "خمسه": 5]
        if let result = words[value] { return result }
        if let space = value.firstIndex(of: " "), let whole = Double(value[..<space]),
           value[value.index(after: space)...].contains("/"), let fraction = numeric(String(value[value.index(after: space)...])) { return whole + fraction }
        let fraction = value.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        if fraction.count == 2, let top = Double(fraction[0]), let bottom = Double(fraction[1]), bottom > 0 { return top / bottom }
        return nil
    }
    private static func normalized(_ raw: String) -> String {
        var text = DisplayFormat.westernDigits(raw).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        for (old, new) in ["½": " 1/2", "¼": " 1/4", "¾": " 3/4", "ة": "ه", "أ": "ا", "إ": "ا", "آ": "ا"] { text = text.replacingOccurrences(of: old, with: new) }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    private static func captures(_ pattern: String, in phrase: String, group: Int) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let text = phrase as NSString
        return regex.matches(in: phrase, range: NSRange(location: 0, length: text.length)).map { text.substring(with: $0.range(at: group)) }
    }
}

enum RecipeSource {
    static let maximumPageBytes = 1024 * 1024
    static let maximumExcerptCharacters = 14000

    static func content(_ data: Data, mimeType: String?, socialCaption: Bool = false) -> RecipeSourceContent? {
        guard !data.isEmpty, data.count <= maximumPageBytes else { return nil }
        let mime = (mimeType ?? "").lowercased()
        guard mime.isEmpty || mime.contains("html") || mime.contains("json") || mime.contains("text/plain") else { return nil }
        guard let document = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
        if mime.contains("json"), let object = try? JSONSerialization.jsonObject(with: data) {
            if let recipe = firstRecipe(object), let result = recipeExcerpt(recipe) { return result }
            // The official TikTok oEmbed endpoint supplies a public caption,
            // not a transcript. Ignore author, thumbnail and player fields.
            if socialCaption, let embed = object as? [String: Any] {
                let title = cleanText(embed["title"] as? String ?? "")
                let html = embed["html"] as? String ?? ""
                let captions = captures("(?is)<p\\b[^>]*>(.*?)</p\\s*>", in: html).map(cleanText)
                let caption = (captions.isEmpty ? [title] : captions).joined(separator: "\n")
                if looksLikeRecipe(caption) { return excerpt(caption, kind: .publicCaption) }
                return nil
            }
        }
        for script in captures("(?is)<script\\b[^>]*type\\s*=\\s*[\"']application/ld\\+json[\"'][^>]*>(.*?)</script\\s*>", in: document) {
            guard let bytes = script.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: bytes),
                  let recipe = firstRecipe(object), let result = recipeExcerpt(recipe) else { continue }
            return result
        }
        if socialCaption {
            for script in captures("(?is)<script\\b[^>]*id\\s*=\\s*[\"']__UNIVERSAL_DATA_FOR_REHYDRATION__[\"'][^>]*>(.*?)</script\\s*>", in: document) {
                guard let data=script.data(using:.utf8),let object=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],
                      let scope=object["__DEFAULT_SCOPE__"] as? [String:Any],let detail=scope["webapp.video-detail"] as? [String:Any],
                      let info=detail["itemInfo"] as? [String:Any],let item=info["itemStruct"] as? [String:Any],
                      let description=item["desc"] as? String else {continue}
                let caption=cleanText(description)
                if looksLikeRecipe(caption) {return excerpt(caption,kind:.publicCaption)}
            }
        }
        var descriptions: [String] = []
        for tag in matches("(?is)<meta\\b[^>]*>", in: document) {
            let attributes = attributeValues(tag)
            let name = (attributes["property"] ?? attributes["name"] ?? "").lowercased()
            if ["og:description", "twitter:description", "description"].contains(name), let value = attributes["content"] {
                let caption = cleanText(value)
                if looksLikeRecipe(caption), !descriptions.contains(caption) { descriptions.append(caption) }
            }
        }
        if socialCaption {
            // A social login shell may have a title and thumbnail only. Those
            // cannot prove quantities or instructions inside a video.
            return descriptions.first.flatMap { excerpt($0, kind: .publicCaption) }
        }
        let body = captures("(?is)<body\\b[^>]*>(.*?)</body\\s*>", in: document).first ?? document
        let visible = cleanText(body)
        let candidate = descriptions.isEmpty ? visible : descriptions.joined(separator: "\n") + "\n" + visible
        guard looksLikeRecipe(candidate) else { return nil }
        return excerpt(candidate, kind: .pageText)
    }

    static func isTikTok(_ url: URL) -> Bool { domain(url, is: "tiktok.com") || domain(url,is:"tt.site") }
    static func isInstagram(_ url: URL) -> Bool { domain(url, is: "instagram.com") }
    private static func domain(_ url: URL, is name: String) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host == name || host.hasSuffix("." + name)
    }
    static func tikTokEmbedURL(_ source: URL) -> URL? {
        guard isTikTok(source), source.path.contains("/video/") else { return nil }
        var parts = URLComponents(string: "https://www.tiktok.com/oembed")!
        parts.queryItems = [URLQueryItem(name: "url", value: source.absoluteString)]
        return parts.url
    }

    /// Reject private/reserved addresses after DNS resolution as well as the
    /// lexical host restrictions in RecipeImport.canonicalURL.
    static func isPublicAddress(_ raw: String) -> Bool {
        let address = raw.lowercased()
        if address.contains(":") {
            guard !address.contains("%"), !address.contains("."), let first = address.split(separator: ":").first,
                  let leading = UInt16(first, radix: 16), (0x2000...0x3fff).contains(leading) else { return false }
            return !["2001:db8:", "2001:0:", "2001:10:", "2001:20:", "2002:"].contains(where: address.hasPrefix)
        }
        let groups = address.split(separator: ".", omittingEmptySubsequences: false)
        guard groups.count == 4 else { return false }
        let octets = groups.compactMap { part -> UInt8? in
            guard !part.isEmpty, part.allSatisfy(\.isNumber) else { return nil }
            return UInt8(part)
        }
        guard octets.count == 4 else { return false }
        let a = octets[0], b = octets[1], c = octets[2]
        if a == 0 || a == 10 || a == 127 || a >= 224 { return false }
        if a == 100 && (64...127).contains(b) { return false }
        if a == 169 && b == 254 || a == 172 && (16...31).contains(b) { return false }
        if a == 192 && (b == 168 || b == 0 || b == 88 && c == 99 || b == 0 && c == 2) { return false }
        if a == 198 && (b == 18 || b == 19 || b == 51 && c == 100) { return false }
        if a == 203 && b == 0 && c == 113 { return false }
        return true
    }

    private static func firstRecipe(_ value: Any, depth: Int = 0) -> [String: Any]? {
        guard depth < 12 else { return nil }
        if let list = value as? [Any] {
            for item in list.prefix(100) { if let result = firstRecipe(item, depth: depth + 1) { return result } }
        } else if let object = value as? [String: Any] {
            let types = (object["@type"] as? [String]) ?? (object["@type"] as? String).map { [$0] } ?? []
            if types.contains(where: { $0 == "Recipe" || $0.hasSuffix("/Recipe") }) { return object }
            for name in ["mainEntity", "@graph", "itemListElement", "item"] {
                if let child = object[name], let recipe = firstRecipe(child, depth: depth + 1) { return recipe }
            }
        }
        return nil
    }
    private static func recipeExcerpt(_ recipe: [String: Any]) -> RecipeSourceContent? {
        let ingredients = sourceStrings(recipe["recipeIngredient"] ?? recipe["ingredients"]).prefix(80)
        guard !ingredients.isEmpty else { return nil }
        let title = sourceStrings(recipe["name"]).joined(separator: " ")
        let yield = sourceStrings(recipe["recipeYield"]).joined(separator: " ")
        let steps = sourceStrings(recipe["recipeInstructions"]).prefix(40)
        // Exact original units/yield are retained for the AI to translate;
        // no density, serving count or nutrients are inferred here.
        let value = "Recipe title: \(title)\nDeclared yield: \(yield.isEmpty ? "not stated" : yield)\nIngredients:\n" +
            ingredients.map { "- " + $0 }.joined(separator: "\n") + "\nPreparation:\n" +
            steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        return excerpt(value, kind: .structuredRecipe)
    }
    private static func sourceStrings(_ value: Any?, depth: Int = 0) -> [String] {
        guard depth < 12 else { return [] }
        if let text = value as? String { let result = cleanText(text); return result.isEmpty ? [] : [result] }
        if let number = value as? NSNumber { return [number.stringValue] }
        if let list = value as? [Any] { return list.prefix(100).flatMap { sourceStrings($0, depth: depth + 1) } }
        if let item = value as? [String: Any] {
            if let children = item["itemListElement"] { return sourceStrings(children, depth: depth + 1) }
            if let child = item["item"] { return sourceStrings(child, depth: depth + 1) }
            if let amount = item["value"] {
                let fields = sourceStrings(amount, depth: depth + 1) +
                    sourceStrings(item["unitText"], depth: depth + 1) + sourceStrings(item["name"], depth: depth + 1)
                if !fields.isEmpty { return [fields.joined(separator: " ")] }
            }
            if let text = item["text"] { return sourceStrings(text, depth: depth + 1) }
            if let name = item["name"] { return sourceStrings(name, depth: depth + 1) }
        }
        return []
    }
    static func cleanText(_ source: String) -> String {
        var result = replacing("(?is)<(script|style|noscript|svg|nav|header|footer|form)\\b[^>]*>.*?</\\1\\s*>", in: source, with: " ")
        result = replacing("(?i)<(?:br|/?p|/?li|/?h[1-6]|/?div|/?section|/?article)\\b[^>]*>", in: result, with: "\n")
        result = replacing("(?s)<[^>]*>", in: result, with: " ")
        for (entity, value) in ["&amp;": "&", "&quot;": "\"", "&apos;": "'", "&#39;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " ", "&frac12;": "½", "&frac14;": "¼", "&frac34;": "¾"] {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        for match in matches("&#(?:[xX][0-9a-fA-F]+|[0-9]+);", in: result).reversed() {
            let digits = String(match.dropFirst(2).dropLast())
            let hex = digits.lowercased().hasPrefix("x")
            if let number = UInt32(hex ? String(digits.dropFirst()) : digits, radix: hex ? 16 : 10), let scalar = UnicodeScalar(number) {
                result = result.replacingOccurrences(of: match, with: String(scalar))
            }
        }
        result = String(result.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) && $0 != "\n" ? " " : String($0) }.joined())
        return result.split(separator: "\n").map { line in
            line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }.filter { !$0.isEmpty }.joined(separator: "\n")
    }
    private static func looksLikeRecipe(_ text: String) -> Bool {
        guard text.count >= 35 else { return false }
        let value = DisplayFormat.westernDigits(text).lowercased()
        let quantities = matches("[0-9]+(?:[.,/][0-9]+)?\\s*(?:g\\b|grams?\\b|kg\\b|ml\\b|cups?\\b|tbsp\\b|tsp\\b|tablespoons?\\b|teaspoons?\\b|eggs?\\b|جم|جرام|غرام|كوب|أكواب|اكواب|ملعق|ملاعق|حبة|حبات|بيض|مل\\b)", in: value)
        let actions = ["ingredients", "preparation", "instructions", "mix", "cook", "bake", "whisk", "blend", "fry", "boil", "المقادير", "المكونات", "اخلط", "نخلط", "اطه", "اسلق", "اخبز", "نضيف", "نقلي", "نحمص", "طريقة"]
        return !quantities.isEmpty && actions.contains(where: value.contains)
    }
    private static func excerpt(_ value: String, kind: RecipeSourceContent.Kind) -> RecipeSourceContent? {
        let result = String(value.prefix(maximumExcerptCharacters))
        return result.count >= 20 ? RecipeSourceContent(text: result, kind: kind) : nil
    }
    private static func attributeValues(_ tag: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(pattern: "(?is)([a-z_:][-a-z0-9_:]*)\\s*=\\s*([\"'])(.*?)\\2") else { return [:] }
        let value = tag as NSString
        return regex.matches(in: tag, range: NSRange(location: 0, length: value.length)).reduce(into: [:]) { result, match in
            result[value.substring(with: match.range(at: 1)).lowercased()] = value.substring(with: match.range(at: 3))
        }
    }
    private static func captures(_ pattern: String, in value: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let string = value as NSString
        return regex.matches(in: value, range: NSRange(location: 0, length: string.length)).prefix(100).map { string.substring(with: $0.range(at: 1)) }
    }
    private static func matches(_ pattern: String, in value: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let string = value as NSString
        return regex.matches(in: value, range: NSRange(location: 0, length: string.length)).prefix(100).map { string.substring(with: $0.range) }
    }
    private static func replacing(_ pattern: String, in value: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
        return regex.stringByReplacingMatches(in: value, range: NSRange(location: 0, length: (value as NSString).length), withTemplate: replacement)
    }
}

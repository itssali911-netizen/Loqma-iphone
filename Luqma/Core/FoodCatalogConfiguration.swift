import Foundation

/// A deployment hook for the complete, separately hosted OFF catalogue. No URL
/// is shipped until a real server has been imported, licensed and validated.
/// Absence keeps the existing OFF live search and barcode flow unchanged.
enum FoodCatalogConfiguration {
    static func baseURL(_ value: Any?) -> URL? {
        guard let value = value as? String, !value.isEmpty,
              var parts = URLComponents(string: value), parts.scheme?.lowercased() == "https",
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil else { return nil }
        parts.path = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !parts.path.isEmpty { parts.path = "/" + parts.path }
        return parts.url
    }

    static func searchURL(base: URL, query: String, page: Int, pageSize: Int) -> URL? {
        guard page > 0, page < Int.max, (1...100).contains(pageSize), !query.isEmpty, query.count <= 180,
              var parts = URLComponents(url: base.appendingPathComponent("v1/products"), resolvingAgainstBaseURL: false) else { return nil }
        parts.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "page", value: String(page)),
                            URLQueryItem(name: "page_size", value: String(pageSize))]
        return parts.url
    }

    static func productURL(base: URL, code: String) -> URL? {
        guard !code.isEmpty, code.count <= 180,
              code.allSatisfy({ "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-_".contains($0) }) else { return nil }
        return base.appendingPathComponent("v1/products").appendingPathComponent(code)
    }

    struct SearchResponse: Decodable {
        let format: String
        let version: Int
        let page: Int
        let pageSize: Int
        let foods: [Food]
        let nextPage: Int?
        let sourceTotal: Int?
        enum CodingKeys: String, CodingKey { case format, version, page, foods; case pageSize = "page_size", nextPage = "next_page", sourceTotal = "source_total" }

        func validated(requestedPage: Int, size: Int) -> FoodSearchPage? {
            guard format == "luqma-off-catalog", version == 1, page > 0, page < Int.max,
                  page == requestedPage, pageSize == size, foods.count <= size,
                  nextPage == nil || nextPage == page + 1, nextPage == nil || !foods.isEmpty,
                  sourceTotal.map({ $0 >= 0 }) ?? true,
                  foods.allSatisfy(FoodCatalogConfiguration.validFood), Set(foods.map(\.id)).count == foods.count else { return nil }
            return FoodSearchPage(foods: foods, nextPage: nextPage, sourceTotal: sourceTotal)
        }

    }

    private static func validFood(_ food: Food) -> Bool {
        guard FoodSearch.isOpenFoodFacts(food), let code = food.sourceId, !code.isEmpty, code.count <= 180,
              code.allSatisfy({ "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-_".contains($0) }),
              !food.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, food.name.count <= 180,
              [food.kcal, food.protein, food.carbs, food.fat].allSatisfy({ $0.map { $0.isFinite && $0 >= 0 && $0 <= 100000 } ?? true }),
              food.servingNutrition == nil || food.servingNutrition?.valid == true else { return false }
        if let barcode = food.barcode {
            guard barcode == code, (8...14).contains(barcode.count),
                  barcode.allSatisfy({ "0123456789".contains($0) }) else { return false }
        }
        return true
    }

    struct ProductResponse: Decodable {
        let format: String
        let version: Int
        let food: Food?
        func validated(code: String) throws -> Food? {
            guard format == "luqma-off-catalog", version == 1,
                  food == nil || (food?.sourceId == code && food.map(FoodCatalogConfiguration.validFood) == true) else {
                throw AppError.invalid("لم تكتمل بيانات المنتج. أعد المحاولة.", "The product response was incomplete. Retry.")
            }
            return food
        }
    }
}

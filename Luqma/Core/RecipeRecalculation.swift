import Foundation

extension RecipeImportDraft {
    var canRecalculate:Bool {
        guard let servings,RecipeImport.positive(servings,maximum:1000),
              (1...80).contains(ingredients.count),(1...40).contains(steps.count) else {return false}
        return ingredients.allSatisfy {
            RecipeImport.text($0.name,maximum:180) && RecipeImport.text($0.unitLabel,maximum:100) &&
            $0.quantity.map {RecipeImport.positive($0,maximum:10000)} == true
        }
    }

    /// Quantities confirmed by the user become the explicit calculation input;
    /// no guessed source weight or previous calorie value is carried forward.
    func recalculationInput() throws -> RecipeImport.Input {
        guard canRecalculate,let servings else {
            throw AppError.invalid("حدّد عدد الحصص ومقادير المكونات أولًا.","Set servings and ingredient quantities first.")
        }
        let rows=ingredients.map {item in
            let unit=item.unit == .g ? "g":item.unit == .ml ? "ml":item.unitLabel
            return "- "+DisplayFormat.decimal(item.quantity!,digits:6)+" "+unit+" "+item.name
        }
        let text="Recipe title: "+title+"\nMakes "+DisplayFormat.decimal(servings,digits:6)+" servings.\nIngredients:\n"+
            rows.joined(separator:"\n")+"\nPreparation:\n"+steps.joined(separator:"\n")
        return try RecipeImport.input(url:sourceURL ?? "",pastedText:text)
    }

    func retainingSource(of original:RecipeImportDraft,language:AppLanguage) -> RecipeImportDraft {
        var value=self
        value.title=original.title;value.sourceURL=original.sourceURL;value.sourceKind=original.sourceKind;value.steps=original.steps
        let note=language.text("أُعيد حساب التغذية من المقادير التي راجعتها.","Nutrition was recalculated from your reviewed quantities.")
        value.assumptions=Array((value.assumptions+[note]).prefix(16))
        return value
    }
}

import SwiftUI

@MainActor struct RecipeImportView: View {
    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var pastedText = ""
    @State private var showPaste = false
    @State private var draft: RecipeImportDraft?
    @State private var busy = false
    @State private var error: String?
    @State private var extraction: Task<Void, Never>?
    @State private var generation = UUID()
    @State private var pendingIngredientEdits = Set<UUID>()
    @State private var previewFixtureLoaded = false
    @State private var saved = false
    @State private var stage: RecipeImportStage = .readingSource
    private enum InputFocus: Hashable { case link, paste }
    @FocusState private var inputFocus: InputFocus?

    private var hasInput: Bool {
        !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    LuqmaPageHeader(title: diary.t("وصفة من رابط", "Recipe from a link"),
                        subtitle: diary.t("مكونات وخطوات، في مكان واحد", "Ingredients and steps, in one place"), symbol: "link")
                    if draft == nil || busy { sourceInput }
                    else {
                        Button {
                            draft = nil; error = nil; pendingIngredientEdits.removeAll()
                        } label: {
                            Label(diary.t("تغيير الرابط أو النص", "Change link or text"), systemImage: "link")
                        }.font(.subheadline).foregroundStyle(Theme.accent)
                    }
                    if busy {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(stage == .readingSource ? diary.t("نقرأ المقادير من الرابط…", "Reading ingredients from the link…") :
                                diary.t("نحسب السعرات ونرتب الوصفة…", "Calculating nutrition and organizing the recipe…")).font(.subheadline)
                            Spacer(minLength: 8)
                            Button(diary.t("إيقاف", "Stop")) { cancel() }
                        }.luqmaCard()
                    }
                    if let error {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(error).font(.footnote).foregroundStyle(.orange).accessibilityLabel(error)
                            if let url = try? RecipeImport.canonicalURL(link) {
                                Link(destination: url) { Label(diary.t("فتح المصدر ونسخ الوصفة", "Open source and copy recipe"), systemImage: "arrow.up.right.square") }
                                    .font(.subheadline).foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    if let draft { review(draft) }
                }.padding(20)
            }.scrollDismissesKeyboard(.interactively).appBackground()
                .navigationTitle(diary.t("استيراد وصفة", "Import recipe"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(diary.t("إغلاق", "Close")) { cancel(); dismiss() }
                    }
                }
        }.onAppear { loadPreviewFixture() }.onDisappear { cancel() }
    }

    private var sourceInput: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(diary.t("رابط الوصفة", "Recipe link")).font(.headline)
            TextField(diary.t("الصق رابط الموقع أو المنشور", "Paste the page or post link"), text: $link)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($inputFocus, equals: .link)
                .submitLabel(.go).onSubmit { if hasInput && !busy { extract() } }
                .padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityLabel(diary.t("رابط الوصفة", "Recipe link"))
                .onChange(of: link) { _, _ in if !busy { draft = nil; error = nil } }
            DisclosureGroup(diary.t("الصق نص الوصفة بدلًا من الرابط", "Paste recipe text instead"), isExpanded: $showPaste) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(diary.t("المنشورات الخاصة أو المحجوبة تحتاج نص الوصفة. انسخ الوصف والمقادير والخطوات والصقها هنا.",
                        "Private or blocked posts need the recipe text. Copy the description, quantities and steps and paste them here."))
                        .font(.caption).foregroundStyle(Theme.muted)
                    TextEditor(text: $pastedText).frame(minHeight: 150)
                        .focused($inputFocus, equals: .paste)
                        .scrollContentBackground(.hidden).padding(10)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityLabel(diary.t("نص الوصفة", "Recipe text"))
                        .onChange(of: pastedText) { _, _ in if !busy { draft = nil; error = nil } }
                }.padding(.top, 12)
            }.font(.subheadline)
            Text(diary.t("مواقع الوصفات، يوتيوب، تيك توك وإنستقرام. يجب أن تكون المقادير متاحة للعامة في الصفحة أو وصف المنشور.",
                "Recipe websites, YouTube, TikTok and Instagram. Ingredients must be publicly available in the page or post description."))
                .font(.caption).foregroundStyle(Theme.muted)
            Text(diary.t("يُرسل محتوى الوصفة العام أو النص الذي تلصقه إلى خدمة التحليل. راجع المقادير والتقديرات قبل الحفظ.",
                "Public recipe content or your pasted text is sent to the analysis service. Review quantities and estimates before saving."))
                .font(.caption).foregroundStyle(Theme.muted)
            Button(action: extract) {
                Label(diary.t("استخراج الوصفة", "Extract recipe"), systemImage: "sparkles")
            }.buttonStyle(LuqmaPrimaryButtonStyle()).disabled(!hasInput)
        }.luqmaCard().disabled(busy)
    }

    private func review(_ result: RecipeImportDraft) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(diary.t("راجع وصفتك", "Review your recipe")).font(.title3.bold())
                    Spacer()
                    Text(result.sourceKind.isPastedText ? diary.t("من نصك", "From your text") : diary.t("من الرابط", "From the link"))
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                TextField(diary.t("اسم الوصفة", "Recipe name"), text: Binding(
                    get: { draft?.title ?? "" }, set: { draft?.title = $0 }))
                    .font(.headline).accessibilityLabel(diary.t("اسم الوصفة", "Recipe name"))
                NumericInput(title: diary.t("عدد الحصص", "Number of servings"), value: Binding(
                    get: { draft?.servings ?? 0 }, set: { draft?.servings = $0 }))
                if result.servings == nil || !(result.servings.map { $0.isFinite && $0 > 0 && $0 <= 1000 } ?? false) {
                    Text(diary.t("أدخل عدد الحصص لإكمال الوصفة.", "Enter the serving count to complete the recipe."))
                        .font(.caption).foregroundStyle(.orange)
                }
            }.luqmaCard()

            VStack(alignment: .leading, spacing: 18) {
                Text(diary.t("تقدير الوصفة كاملة", "Estimated whole recipe")).font(.headline)
                if let total = result.total { NutritionView(value: total, large: true) }
                else { Text(diary.t("بعض المقادير أو القيم ناقصة؛ أكملها في المكونات لعرض الإجمالي.",
                    "Some quantities or values are missing. Complete the ingredients to see the total."))
                    .font(.subheadline).foregroundStyle(Theme.muted) }
                if let perServing = result.perServing {
                    Divider().overlay(Theme.stroke)
                    Text(diary.t("لكل حصة", "Per serving")).font(.headline)
                    NutritionView(value: perServing)
                }
            }.luqmaCard()

            Button(action: recalculate) {
                Label(diary.t("حساب السعرات بعد تعديل المقادير", "Calculate nutrition after editing amounts"),systemImage:"sparkles")
            }.buttonStyle(LuqmaPrimaryButtonStyle()).disabled(!result.canRecalculate || busy || saved || !pendingIngredientEdits.isEmpty)
            if !result.canRecalculate {
                Text(diary.t("حدّد الحصص ومقادير المكونات، ثم اضغط حساب السعرات.", "Set servings and ingredient amounts, then calculate nutrition."))
                    .font(.caption).foregroundStyle(Theme.muted)
            }

            VStack(alignment: .leading, spacing: 14) {
                LuqmaSectionHeader(title: diary.t("المكونات", "Ingredients"), detail: "\(result.ingredients.count)")
                ForEach(result.ingredients) { ingredient in
                    RecipeImportIngredientRow(ingredient: binding(for: ingredient), onPendingEdit: { id, pending in
                        if pending { pendingIngredientEdits.insert(id) } else { pendingIngredientEdits.remove(id) }
                    }, onRemove: { id in
                        draft?.ingredients.removeAll { $0.id == id }; pendingIngredientEdits.remove(id)
                    })
                }
            }

            VStack(alignment: .leading, spacing: 16) {
                LuqmaSectionHeader(title: diary.t("خطوات التحضير", "Preparation steps"))
                if result.steps.isEmpty {
                    Text(diary.t("الخطوات غير متاحة. الصق نص الوصفة الكامل وأعد استخراجها.",
                        "The steps are unavailable. Paste the full recipe text and extract it again."))
                        .font(.subheadline).foregroundStyle(Theme.muted)
                }
                ForEach(Array(result.steps.enumerated()), id: \.offset) { number, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text(String(number + 1)).font(.caption.bold()).foregroundStyle(Theme.accent)
                            .frame(width: 30, height: 30).background(Theme.surface, in: Circle()).accessibilityHidden(true)
                        Text(DisplayFormat.westernDigits(step)).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                    }.accessibilityElement(children: .combine)
                }
            }.luqmaCard()

            if !result.assumptions.isEmpty || result.sourceURL != nil {
                VStack(alignment: .leading, spacing: 12) {
                    if let source = result.sourceURL, let url = URL(string: source) {
                        Link(destination: url) { Label(diary.t("فتح المصدر", "Open source"), systemImage: "arrow.up.right.square") }
                    }
                    if !result.assumptions.isEmpty {
                        DisclosureGroup(diary.t("ملاحظات التقدير", "Estimate notes")) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(result.assumptions.enumerated()), id: \.offset) { _, note in
                                    Text(DisplayFormat.westernDigits(note)).font(.caption).foregroundStyle(Theme.muted)
                                }
                            }.padding(.top, 10)
                        }
                    }
                }.luqmaCard()
            }
            Button(action: save) {
                Label(diary.t("حفظ في مطبخي", "Save to my kitchen"), systemImage: "book.closed")
            }.buttonStyle(LuqmaPrimaryButtonStyle()).disabled(!result.readyToSave || busy || saved || !pendingIngredientEdits.isEmpty)
            if !pendingIngredientEdits.isEmpty {
                Text(diary.t("طبّق تعديلات القيم في المكونات قبل حفظ الوصفة.", "Apply your ingredient value edits before saving the recipe."))
                    .font(.caption).foregroundStyle(Theme.muted)
            }
        }
    }

    private func binding(for original: RecipeImportIngredient) -> Binding<RecipeImportIngredient> {
        Binding(get: { draft?.ingredients.first { $0.id == original.id } ?? original }, set: { updated in
            guard let index = draft?.ingredients.firstIndex(where: { $0.id == original.id }) else { return }
            draft?.ingredients[index] = updated
        })
    }

    private func extract() {
        guard hasInput && !busy else { return }
        let source = link, text = pastedText, language = diary.language
        let token = UUID(); generation = token
        inputFocus = nil
        stage = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .readingSource : .calculating
        busy = true; error = nil; draft = nil; saved = false; pendingIngredientEdits.removeAll()
        extraction = Task {
            do {
                let result = try await RecipeImportService.shared.extract(url: source, pastedText: text, language: language) { value in
                    Task { @MainActor in guard generation == token else { return }; stage = value }
                }
                try Task.checkCancellation()
                guard generation == token else { return }
                draft = result
            } catch is CancellationError {
                // Cancellation has no save or partial-result side effect.
            } catch {
                guard generation == token && !Task.isCancelled else { return }
                self.error = (error as? AppError)?.message(language) ?? diary.t("تعذّر قراءة الوصفة. الصق نصها كاملًا وأعد المحاولة.",
                    "The recipe could not be read. Paste its full text and try again.")
                showPaste = true
            }
            if generation == token { busy = false; extraction = nil }
        }
    }

    private func recalculate() {
        guard let original=draft,original.canRecalculate,!busy,!saved,pendingIngredientEdits.isEmpty else{return}
        let input:RecipeImport.Input
        do {input=try original.recalculationInput()}catch {self.error=(error as? AppError)?.message(diary.language);return}
        let token=UUID();generation=token;let language=diary.language
        inputFocus=nil;busy=true;stage = .calculating;error=nil
        extraction=Task {
            do {
                let value=try await RecipeImportService.shared.extract(url:input.sourceURL?.absoluteString ?? "",pastedText:input.pastedText,language:language)
                try Task.checkCancellation();guard generation==token else{return}
                draft=value.retainingSource(of:original,language:language)
            }catch is CancellationError {}catch {
                guard generation==token,!Task.isCancelled else{return}
                self.error=(error as? AppError)?.message(language) ?? diary.t("تعذّر الحساب. مقاديرك محفوظة؛ حاول مجددًا.","Calculation failed. Your amounts remain; retry.")
            }
            if generation==token {busy=false;extraction=nil}
        }
    }

    private func cancel() {
        generation = UUID(); extraction?.cancel(); extraction = nil; busy = false
    }

    private func save() {
        guard let draft, draft.readyToSave, !busy, !saved, pendingIngredientEdits.isEmpty else { return }
        do {
            let recipe = try draft.recipe(language: diary.language)
            if diary.saveRecipe(recipe) { saved = true; dismiss() }
            else { error = diary.error ?? diary.t("تعذّر حفظ الوصفة. حاول مجددًا.", "The recipe could not be saved. Try again.") }
        } catch { self.error = (error as? AppError)?.message(diary.language) ?? diary.t("راجع المقادير والحصص قبل الحفظ.", "Review quantities and servings before saving.") }
    }

    private func loadPreviewFixture() {
        #if DEBUG
        guard !previewFixtureLoaded, CommandLine.arguments.contains("-loqma-preview-recipe") else { return }
        previewFixtureLoaded = true
        draft = RecipeImportDraft(
            title: diary.t("أرز ودجاج", "Rice and chicken"), servings: 2,
            ingredients: [
                RecipeImportIngredient(name: diary.t("أرز مطبوخ", "Cooked rice"), quantity: 200, unit: .g,
                    unitLabel: diary.t("جم", "g"), nutrition: Nutrition(kcal: 260, protein: 5.4, carbs: 56, fat: 0.6), assumption: ""),
                RecipeImportIngredient(name: diary.t("دجاج مشوي", "Grilled chicken"), quantity: 150, unit: .g,
                    unitLabel: diary.t("جم", "g"), nutrition: Nutrition(kcal: 250, protein: 46, carbs: 0, fat: 5.5), assumption: "")
            ],
            steps: [diary.t("اطهُ الأرز حتى ينضج.", "Cook the rice until ready."),
                    diary.t("اشوِ الدجاج حتى يكتمل نضجه.", "Grill the chicken until fully cooked."),
                    diary.t("قسّم الوجبة إلى حصتين.", "Divide the meal into two servings.")],
            sourceURL: "https://example.com/recipe",
            assumptions: [diary.t("مثال لعرض الواجهة؛ الأرقام تقديرية ولم تُستخرج من الموقع.",
                "A UI preview example; values are illustrative and were not extracted from the website.")],
            sourceKind: .pastedText)
        #endif
    }
}

@MainActor private struct RecipeImportIngredientRow: View {
    @Binding var ingredient: RecipeImportIngredient
    var onPendingEdit: (UUID, Bool) -> Void
    var onRemove: (UUID) -> Void
    @EnvironmentObject private var diary: DiaryStore
    @State private var editing = false
    @State private var kcal = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var error: String?
    @State private var nutritionPending = false
    private var unitLabel: String { DisplayFormat.westernDigits(ingredient.unitLabel.isEmpty ? ingredient.unit.label(diary.language) : ingredient.unitLabel) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(DisplayFormat.westernDigits(ingredient.name)).font(.headline)
                Spacer()
                Button(role: .destructive) { onRemove(ingredient.id) } label: { Image(systemName: "minus.circle") }
                    .accessibilityLabel(diary.t("إزالة ", "Remove ") + ingredient.name)
            }
            if let quantity = ingredient.quantity {
                Text("\(decimal(quantity)) \(unitLabel)").font(.subheadline).foregroundStyle(Theme.muted)
            } else { Text(diary.t("المقدار غير محدد", "Quantity unspecified")).font(.caption).foregroundStyle(.orange) }
            if let nutrition = ingredient.nutrition {
                HStack {
                    Text("\(decimal(nutrition.kcal, 0)) " + diary.t("سعرة", "kcal")).foregroundStyle(Theme.accent)
                    Spacer()
                    Text(diary.t("بروتين ", "P ")+decimal(nutrition.protein)+diary.t(" · كارب ", " · C ")+decimal(nutrition.carbs)+diary.t(" · دهون ", " · F ")+decimal(nutrition.fat)).foregroundStyle(Theme.muted)
                }.font(.caption)
            } else { Text(diary.t("القيم الغذائية غير مكتملة", "Nutrition is incomplete")).font(.caption).foregroundStyle(.orange) }
            if !ingredient.assumption.isEmpty { Text(DisplayFormat.westernDigits(ingredient.assumption)).font(.caption).foregroundStyle(Theme.muted) }
            DisclosureGroup(diary.t("تعديل المكوّن", "Edit ingredient"), isExpanded: $editing) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField(diary.t("اسم المكوّن", "Ingredient name"), text: $ingredient.name)
                    if ingredient.nutrition == nil {
                        Picker(diary.t("وحدة المقدار", "Quantity unit"),selection:Binding(get:{ingredient.unit},set:{unit in
                            ingredient.unit=unit;ingredient.unitLabel=unit.label(diary.language);ingredient.nutrition=nil
                            nutritionPending=false;onPendingEdit(ingredient.id,false);loadNutrition()
                        })) {ForEach(FoodUnit.allCases,id:\.self){unit in Text(unit.label(diary.language)).tag(unit)}}
                    }
                    NumericInput(title: diary.t("المقدار", "Quantity"), value: Binding(
                        get: { ingredient.quantity ?? 0 }, set: changeQuantity), suffix: unitLabel)
                    Text(diary.t("القيم لهذه الكمية كاملة، وليست لكل ١٠٠ جم.", "These values describe this whole quantity, not 100 g."))
                        .font(.caption).foregroundStyle(Theme.muted)
                    nutrientInput(diary.t("السعرات", "Calories (kcal)"), value: $kcal)
                    nutrientInput(diary.t("البروتين (جم)", "Protein (g)"), value: $protein)
                    nutrientInput(diary.t("الكارب (جم)", "Carbs (g)"), value: $carbs)
                    nutrientInput(diary.t("الدهون (جم)", "Fat (g)"), value: $fat)
                    if let error { Text(error).font(.caption).foregroundStyle(.orange) }
                    Button(diary.t("تطبيق القيم", "Apply values"), action: applyNutrition).buttonStyle(.bordered)
                    if nutritionPending {
                        Button(diary.t("إلغاء تعديلات القيم", "Discard value edits")) {
                            loadNutrition(); nutritionPending = false; error = nil; onPendingEdit(ingredient.id, false)
                        }.font(.caption)
                    }
                }.padding(.top, 12)
            }.font(.subheadline)
        }.luqmaCard().onAppear(perform: loadNutrition)
            .onChange(of: ingredient.nutrition) { _, _ in loadNutrition() }
    }

    private func nutrientInput(_ title: String, value: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, text: Binding(get: { value.wrappedValue }, set: {
                value.wrappedValue = $0; nutritionPending = true; onPendingEdit(ingredient.id, true)
            }))
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .frame(maxWidth: 110).accessibilityLabel(title)
        }
    }

    private func loadNutrition() {
        kcal = ingredient.nutrition.map { decimal($0.kcal, 2) } ?? ""
        protein = ingredient.nutrition.map { decimal($0.protein, 3) } ?? ""
        carbs = ingredient.nutrition.map { decimal($0.carbs, 3) } ?? ""
        fat = ingredient.nutrition.map { decimal($0.fat, 3) } ?? ""
    }

    private func changeQuantity(_ value: Double) {
        guard !nutritionPending else {
            error = diary.t("طبّق تعديلات القيم أو ألغها قبل تغيير المقدار.", "Apply or discard the value edits before changing the quantity.")
            return
        }
        guard value.isFinite && value > 0 else { ingredient.quantity = nil; ingredient.nutrition = nil; onPendingEdit(ingredient.id, false); return }
        do { ingredient = try ingredient.changingQuantity(value); error = nil; onPendingEdit(ingredient.id, false) }
        catch { self.error = (error as? AppError)?.message(diary.language) ?? diary.t("راجع المقدار.", "Check the quantity.") }
    }

    private func applyNutrition() {
        guard let quantity = ingredient.quantity, quantity.isFinite, quantity > 0,
              let k = TextSearch.number(kcal), let p = TextSearch.number(protein),
              let c = TextSearch.number(carbs), let f = TextSearch.number(fat) else {
            error = diary.t("أدخل المقدار والقيم الأربع كاملة؛ لا تُفترض القيم الناقصة صفرًا.",
                "Enter the quantity and all four values; missing values are not assumed to be zero.")
            return
        }
        let nutrition = Nutrition(kcal: k, protein: p, carbs: c, fat: f)
        guard nutrition.valid else { error = diary.t("أدخل قيمًا غذائية صحيحة.", "Enter valid nutrition values."); return }
        var candidate = ingredient
        if candidate.nutrition != nutrition {
            let note = diary.t("القيم عُدّلت يدويًا. ", "Values adjusted by you. ")
            if !candidate.assumption.hasPrefix(note) { candidate.assumption = String((note + candidate.assumption).prefix(240)) }
        }
        candidate.nutrition = nutrition
        guard candidate.ready else {
            error = diary.t("راجع اسم المكوّن والمقدار والقيم لهذه الكمية.", "Check the ingredient name, quantity and values for that amount.")
            return
        }
        ingredient = candidate; error = nil; nutritionPending = false; onPendingEdit(ingredient.id, false)
    }
}

# Recipe details refinement — visual approval pending

The current calmer implementation and evidence are documented in [RecipeDetailComfort.md](RecipeDetailComfort.md) and [RecipeDetailNativeEvidence.json](RecipeDetailNativeEvidence.json). This follow-up is limited to RecipeDetailView; the editor and other seven reviewed screens retain their existing layouts.

The initial refinement replaced the oversized identity/edit button and introduced compact ingredient disclosures. The subsequent comfort pass removes the redundant provenance row, quiets labels, removes nested disclosure cards, and places serving/gram actions side by side. Exact source tokens and Changa-Bold are retained.

The earlier gram-action correction remains: an optional FoodPortionView.initialUnit is supplied only by RecipeDetailView, so gram-based addition opens in grams. Other callers keep their existing default. Stored quantities, nutrient calculations, database schemas, APIs and services are unchanged.

Historical screenshot/test revisions are retained in git history. Earlier eight-screen and recipe captures are historical and do not prove the current follow-up appearance. No merge, release or final visual approval is implied.

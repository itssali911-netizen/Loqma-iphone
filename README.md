# Luqma iPhone — version 1.7

Native compilation, test execution and six real Simulator screenshots are pending for this source. Final evidence belongs in VALIDATION.md.

Meal analysis estimates portion calories and macros, shows a complete editable total, and logs checked estimated servings without requiring catalog matching. Model names and file-import controls are absent from the app flow; an existing Keychain connection is reused automatically. A fresh device still needs its own connection under advanced settings. No service credential is embedded in the source or IPA.

Kitchen imports public recipe links or pasted text into ingredients, quantities, preparation steps, explicit servings, whole-recipe nutrition and per-serving nutrition. Public web retrieval and YouTube analysis depend on provider access; blocked/private Instagram posts require pasted recipe text. Missing values remain absent and block saving; inferred nutrition is labelled estimated. Metadata retains source and organized steps through backups.

SwiftUI styling adapts the exact Sandow v1.2 dark Community preview by strangehelix.bio, with in-app CC BY 4.0 attribution. Its free nutrition sections are flattened previews, not the editable paid kit. Functional views use real diary data; no stock recipe photos or invented history are inserted.

Food catalog: 744 supplied MFP regional foods and six OFF starter products, plus live OFF search. All 3,830 declared MFP portions retain source nutrition multipliers; 31 incomplete food records and 94 unknown portions remain unknown. This is not MFP's complete server database or private ranking algorithm.

Build on macOS/Xcode through the included workflow. Default CI tests Core and build tools, compiles the Release device app and captures six native screens. Historical local vision audits are optional manual checks; cloud analysis is the visible integrated path. Preserve the installed app identifier and Apple account when personally re-signing updates. See README-AR.md, GEMINI-SETUP-AR.md, HEALTH-SETUP-AR.md and VALIDATION.md.

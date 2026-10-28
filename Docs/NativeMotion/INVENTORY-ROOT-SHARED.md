# Root, shared components and native surfaces

All files under `Luqma/Views`, the application root and SwiftUI imports in
Core/Services were included in discovery. No Core model contains an overlooked
product screen. The three companion inventories cover the feature Views and
their nested editors, loading, empty, error and completion states.

| Unit | Existing interaction / implementation | Runtime status at source commit |
|---|---|---|
| RootView four tabs | Stable existing TabView/NavigationStack identity; selected icon/background/underline transition, press feedback, native selection feedback | Pending native suite |
| Root add action | Same full-screen FoodAddView and commit closures; press feedback; no deferred action | Pending native suite |
| Root notification destination | Existing queued routing and draft preservation; unchanged | Existing service behavior retained, regression suite pending |
| Root app alerts | Native iOS alert presentation/dismissal and button behavior retained | Native behavior; relevant UI scenarios pending |
| Original launch storyboard | Unchanged static storyboard and 96pt original mark; a 200ms noninteractive first-frame continuation disappears permanently | Pending launch recording; no artificial wait |
| Global Reduce Motion | Actual SwiftUI environment gates custom transforms/transitions; DEBUG override used only by isolated review | Policy probe and actual environment captures pending |
| LuqmaPrimaryButtonStyle / Secondary | Original sizes, fonts, colors, disabled and pressed opacity; scoped press transform only | Pending interaction suite |
| Plain custom buttons | LuqmaPressStyle preserves settled content; 0.98 press transform, immediately interruptible | Pending native suite |
| LuqmaProgressRing / MacroRings | Animate actual finite progress; same original geometry and colors | Capture/runtime pending |
| LuqmaPill | Existing selected state; brief value-specific change and press feedback | Pending captures |
| NutritionView | Actual read-only kcal and macro numeric transitions | Pending native quantity tests |
| NumericInput | Existing field, formatting and focus semantics; **no** input-buffer animation | Functional regression pending |
| FoodRow | Original card and metadata, press feedback; stable food identity | Functional regression pending |
| SandowNavigationChrome | Native push, back and sheet dismissal retained; button feedback only | Pending native suite |
| SandowOperationState | Original glyph pulses for real visible work; stops when inactive/reduced/removed | Actual loading only; remote operations not verified here |
| SandowStateAlert / EmptyState / SavedConfirmation | Existing text and actions, opacity transition, no fabricated completion or waiting period | Controlled presentation captures pending; not real operation evidence |
| LuqmaPageHeader / SectionHeader / Notice | Static hierarchy retained; no gratuitous perpetual motion | Not Applicable to independent motion |
| EditorialFill / EditorialPanel | Original decorative photos/cropping; no continuous image movement | Not Applicable to independent motion |
| LuqmaTypography / font modifier | Changa Bold registration, scale and shaping unchanged | Existing native font checks plus new captures pending |
| CameraPhoto / UIImagePickerController | Genuine system camera, shutter, controls, dismissal retained | Physical camera unavailable; Not Runtime-Tested |
| BarcodeCamera / ScannerController | Genuine AVCapture preview and lifecycle unchanged; scan ROI stays aligned with static guide | Physical camera unavailable; Not Runtime-Tested |
| BarcodeScanGuide / UIKit guide | Same original guidance, boundaries and layers; no independent geometry animation | Not Applicable to extra motion; hardware scan unverified |
| Performance fixture marker | Existing DEBUG-only benchmark hook untouched; no production or fake health data | Separate performance jobs pending |
| Shapes / layout utilities | Pure drawing/measurement, retained unchanged | Not Applicable to independent animation |

Native DatePicker, Picker, Toggle, Slider, Stepper, Menu, DisclosureGroup,
confirmation dialogs, file import/export panels and all keyboard behavior retain
platform interaction. Custom transitions do not replace these controls or their
interactive dismissal/back gestures. The inventories explicitly record cases
where extra hero/shimmer/icon movement would change the approved design.

An audited or source-implemented row is not a claim of physical or runtime
verification. Final delivery must update evidence links and disclose every
unavailable camera, network, Health record, haptic and frame-pacing test.

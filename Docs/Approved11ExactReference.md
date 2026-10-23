# Additional native reference-size verification

This verification-only branch starts at9d1442e07321d9915884a15bdb3b9896fd8f32de. It changes no application, project, approved asset, test case, nutrition or performance source. Its dedicated workflow avoids repeating unrelated build/performance jobs.

The original approved PNGs are1125x2436. Earlier actual iPhone13mini captures are1080x2340. The additional script explicitly requests an available iPhone11Pro Simulator and verifies13 unmodified native PNGs at1125x2436, with the existing process/readiness/empty-frame/uniqueness/font checks. Missing device support, build failure, wrong dimensions or missing audits fails the job; there is no fallback, resizing or synthetic screenshot generation. Existing capture CLI defaults remain unchanged.

Additional files: `Scripts/approved_reference_capture.py` invokes the existing real capture; `.github/workflows/approved-reference.yml` runs only the dedicated verification branch; `Scripts/ui_preview.py` records the actual device name/identifier from simctl inventory instead of its previous two-name assumption. This document and checksum are bookkeeping.

These captures remain DEBUG UI fixtures, not functional tests, real user meals, live AI responses, physical camera evidence or FPS measurements. Pixel equality is not assumed. Native execution and visual review remain pending at commit creation.

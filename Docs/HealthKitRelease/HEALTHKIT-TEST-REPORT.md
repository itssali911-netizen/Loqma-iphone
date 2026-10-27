# HealthKit validation scope

This document's measured section is generated only after actual CI SDK builds, Core/BuildTests, native empty-Simulator UI tests, final-IPA inspection and packaging gates succeed. Synthetic mock results are controller logic tests, not actual Health records.

Physical iPhone installation, actual HealthKit read consent/data, re-signing through iLoader/AltStore/SideStore, free-account issuance and background delivery: NOT TESTED. No Apple signing credential/profile or attached iPhone was available in this environment. A development-signed IPA is not produced. The release candidate has only local hash signing and needs compatible Apple signing.

Sleep overlap/deletion/range/calendar/DST/unit/unknown handling has Core coverage. Service tests inject isolated synthetic readers to verify partial results, cancellation, late responses, range changes, foreground observers and preference-only persistence. The actual compiled app is launched on a fresh empty Simulator for Arabic/English navigation, connection response, unknown-value presentation and calorie-target preservation. Screenshots are from that Simulator and are not physical-device or real-measurement proof.

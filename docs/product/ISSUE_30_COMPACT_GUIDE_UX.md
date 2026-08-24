# Issue #30 Compact Guide UX Foundation

## Result

**PASS / DRAFT REVIEW.** Issue #30 adds a replaceable Compact Guide presentation on the verified Viewer panel-host boundary. The guide is compact by default, expands only on explicit request, adapts to narrow Viewers, remains owned by one Viewer and one exact Study/Series/SOP/frame identity, and separates calibration status from user-confirmation status. It adds no clinical calculation, suitability decision, automatic image qualification, or production persistence.

The isolated arm64 build, ad-hoc signature verification, deterministic model tests, public-AppKit layout checks, and Horos 4.0.1 runtime matrix passed. No patient or unknown data was encountered, no external connection succeeded, and no Issue #30-specific Horos database, DICOM, ROI, preference, or standalone-record mutation was detected.

## Verified facts

- Work started from the reviewed Platform Gate commit on the dedicated Issue #30 branch. Issue #31 and later work were not started.
- The panel content is 248 by 124 points in the standard compact layout. The policy selects the standard layout at Viewer content sizes of at least 640 by 480 points and a 180–220 point wide, at most 180 point high compact layout below that threshold.
- Placement is deterministic: right of the Viewer, then left, then a top-right floating fallback inside the public content-layout rectangle. The final fallback avoids the image center, standard Viewer controls, the visible-screen edge, and private window hierarchy assumptions.
- Details is per-Viewer, nonpersistent, compact by default, and independent of measurement state and image identity. Viewer close, panel close/reopen, and a new panel instance return to compact.
- The deterministic presentation model covers idle, collecting, editing, calculated-unconfirmed, confirmed, modified-after-confirmation, cancelled, and unavailable.
- Calibration status covers calibrated, DICOM spacing only, and unknown. It is displayed for user judgment and does not automatically allow or prohibit a measurement.
- Confirmation status covers not reviewed, user confirmed, and modified after confirmation. Confirm is an in-memory review marker only; it does not claim clinical suitability and does not save data.
- Editing a confirmed endpoint marks the result modified and requires a new Confirm. A no-change edit preserves the prior confirmation.
- Cancel clears partial collecting input, cancels an active edit back to its prior state, or discards a calculated-but-unconfirmed operation. It is not a delete operation and does not remove an existing stored record.
- Presentation state stores an independent copied image identity and no Viewer, pixel, ROI, managed-object, database, or other Horos runtime object.
- Viewer ownership uses per-Viewer weak-key maps. Study, Series, SOP, and frame are all checked before a guide or overlay is retained.
- Japanese primary strings and English fallback strings use the same complete localization-key set. Missing keys have a deterministic nonempty fallback. The final GUI matrix exercised the English fallback; both resource sets and fallback behavior passed model validation.
- State is communicated with text, a standard semantic icon, and a system semantic color. Color alone is never the only signal, and confirmed is not labeled as clinically safe or suitable.
- The declared keyboard chain is Details, Cancel, Confirm, then back to Details. VoiceOver metadata exposes short mode, instruction, progress, calibration, confirmation, and action label/value/help text.
- No fake API, compatibility shim, inferred selector, private Viewer layout, standard ROI, clinical algorithm, manufacturer recommendation, or automatic image-suitability rule was added.

## Files changed

- `Makefile`: includes localization resources, the compact-guide model test, and architecture, safety, focus-order, real-API, arm64, and signing gates.
- `plugin/CompactGuideViewState.h` and `.m`: independent Viewer/image-bound presentation state and allowed transitions.
- `plugin/CompactGuidePresentation.h` and `.m`: deterministic state-to-copy and semantic-role mappings.
- `plugin/CompactGuideLayoutPolicy.h` and `.m`: standard, narrow, expanded, and three-stage placement policy.
- `plugin/CompactGuideLocalization.h` and `.m`: Japanese-primary and English-fallback lookup boundary.
- `plugin/Resources/ja.lproj/Localizable.strings` and `plugin/Resources/en.lproj/Localizable.strings`: product-owned UI copy and accessibility metadata.
- `plugin/ViewerInspectorPanelHost.h` and `.m`: replaceable compact panel presentation, controls, adaptive layout, accessibility, and cleanup.
- `plugin/MeasurementPanelHost.h`: presentation binding contract used by the Viewer owner.
- `plugin/MedisalePluginFilter.m`: per-Viewer guide ownership, exact image identity binding, progress, restore, and teardown integration.
- `plugin/TwoPointInputController.h` and `.m`: read-only input-progress callback.
- `plugin/TransientLineOverlayController.h` and `.m`: safe current-edit cancellation used by the presentation boundary.
- `plugin/GuideEngine.m`: localization-key-backed short guidance.
- `plugin/Info.plist`: candidate spike version metadata.
- `tests/CompactGuideTests.m`: deterministic state, identity, localization, semantic-role, and layout-policy tests.
- `docs/product/ISSUE_30_COMPACT_GUIDE_UX.md`: this anonymized report.

## Tests

### Build and model verification

- `make verify`: PASS.
- Candidate output: arm64 Mach-O bundle built against the installed real `PluginFilter` and OsiriXAPI headers.
- Candidate ad-hoc strict signature verification: PASS.
- Existing standalone persistence regression harness: 153 assertions PASS.
- Compact Guide state/localization/layout harness: PASS.
- Static safety gates found no managed-object, Horos database, DICOM, ROI, filesystem, defaults, or network write API in the Issue #30 presentation path.
- Static ownership gates confirmed exact image matching, per-Viewer maps, public AppKit layout notifications, explicit invalidation, and the declared focus chain.

### Horos 4.0.1 runtime matrix

| Case | Result | Evidence |
|---|---|---|
| Standard compact | PASS | Observed 248 by 124 point content; title-bar-inclusive window measured 248 by 143 points. |
| Expanded and collapse | PASS | Explicit Details expanded the same Viewer-owned panel, then returned exactly to compact dimensions without changing measurement state. |
| Narrow Viewer | PASS | A sub-640-by-480 Viewer selected a 220 point wide adaptive panel whose compact content remained within the narrow height bound. |
| Right placement | PASS | Panel was placed outside the Viewer on the right when visible space existed. |
| Left placement | PASS | Panel moved outside the Viewer on the left when the right side did not fit. |
| Top-right floating fallback | PASS | With neither side available, the panel remained on-screen at the top-right of the public content area below standard controls. |
| Collecting and progress | PASS | Fresh input displayed 0 of 2, then 1 of 2 after a valid synthetic-image point. |
| Image-outside click | PASS | The invalid click was rejected and the existing one-point state remained intact. |
| Collecting Cancel | PASS | Partial input showed cancelled and settled to idle without a retained point. |
| Calculated-unconfirmed | PASS | Two valid image-coordinate points produced a calculated, not-reviewed state with Details, Cancel, and Confirm. |
| Confirm | PASS | Confirm changed only the in-memory user-review state; Cancel and Confirm hid until a subsequent change. |
| Editing and modified-after-confirmation | PASS | Endpoint drag updated the overlay and changed the presentation to modified; Confirm became available again. |
| Normal Horos tool coexistence | PASS | A drag away from endpoints left Compact Guide state unchanged. |
| Frame switch | PASS | The prior frame's panel and overlay disappeared immediately and returned only on the exact recorded frame. |
| Two Viewers | PASS | The guide followed only its owning Viewer, hid when the other Viewer became active, and the remaining Viewer continued after the other closed. |
| Panel close/reopen | PASS | Standard panel close removed the panel; the same Viewer action re-presented it at compact dimensions. |
| Viewer close | PASS | Guide, partial input, overlay, observers, and panel disappeared; Horos returned normally to the database window. |
| VoiceOver metadata | PASS | Runtime accessibility inspection returned distinct short labels, values, and help for measurement, calibration, confirmation, Details, Cancel, and Confirm. |
| Horos exit | PASS | Horos exited normally; no Horos process, candidate panel, or new crash report remained. |

### Isolation and data-safety evidence

- The runtime account was the designated standard user. Additional volumes and network shares were zero.
- The contained database held only the retained known synthetic set: three Studies, three Series, five image records, and four stored DICOM files. Patient identifiers, dates of birth, institution or physician values, clinical images, and unknown records were absent.
- The plug-in inventory contained the candidate and one anonymous immutable baseline artifact only. Identifier, principal-class, and executable-name collision count was zero.
- Horos was started directly beneath the previously validated temporary process-level network-deny sandbox. TCP, UDP, loopback, IPv6, and child-process network capability probes were denied while ordinary file reads and process execution remained available.
- Horos and child-process successful network connections were zero throughout the valid GUI run. Global Wi-Fi, proxy, DNS, packet-filter, firewall, Gatekeeper, SIP, and other security settings were not changed.
- After Horos fully exited, read-only query-only comparisons retained the same Horos schema, Study/Series/Instance counts and known synthetic identity sets, principal semantic values, DICOM set and body hashes, and SQLite integrity result.
- The standalone P1-11 store retained its five-record complete semantic set and integrity result. Neither Confirm, Cancel, Details, frame switching, nor panel lifecycle added, updated, or deleted a record.
- The existing guide preference retained its pre-test value. Issue #30 Details never reads or writes that preference.
- The anonymous immutable baseline artifact retained its content, resource, metadata, file-count, and recognition manifest. It was not opened by Issue #30 code, changed, moved, disabled, deleted, copied, or re-signed.
- Whole-bundle database fingerprints are not treated as a sole PASS signal because Horos performs ordinary Viewer bookkeeping. No action-specific semantic or DICOM change was detected.

## Evidence

- Local evidence includes the exact candidate architecture and signature result, deterministic assertion output, runtime dimensions and placement classifications, accessibility metadata, anonymous process/network counts, query-only semantic fingerprints, DICOM content fingerprints, SQLite integrity, preference state, crash count, and prospective baseline manifest comparison.
- Raw logs, screenshots, image data, UIDs, paths, hashes, usernames, device identifiers, signature identities, and baseline artifact identifiers are intentionally excluded.
- Preliminary GUI or immediate post-exit launch attempts that did not reach the intended test state were invalidated, closed safely, and excluded from PASS evidence. They produced no successful connection and no crash.

## Known issues

- This is an isolated UX foundation, not production readiness or clinical validation. Copy with clinical meaning still requires future veterinarian review.
- The final full GUI matrix used the English fallback because the documented direct-executable Horos sandbox launch requires a process-only readable language selection on this host. Japanese strings, key parity, missing-key behavior, and wrapping policy passed deterministic tests; Japanese runtime typography remains a later environment-specific visual check.
- Runtime keyboard focus could not be introspected as focused under the host's current keyboard-navigation policy without changing a global accessibility setting. The AppKit `nextKeyView` cycle and all action accessibility metadata are enforced by source and build gates; no macOS setting was changed.
- The expanded P1-09/P1-11 inspector fallback still exposes the pre-existing explicit spike-store save action. Issue #30 does not invoke it, and Details, Confirm, and Cancel do not persist. Production persistence remains a separate future issue.
- Repeated read-only strict signature verification of the immutable baseline produced the already approved context-dependent classification difference while its full content and metadata manifest remained unchanged. Consistent with the Platform Gate decision, this is not treated as artifact mutation; canonical verification policy remains future work.
- Horos reports the ad-hoc candidate as not Horos-validated, as expected for an isolated proof of concept. Build warnings originate from deprecated declarations in the installed Horos headers.
- Exact dimensions and layout thresholds are isolated in a policy object for later adjustment after broader display, localization, and accessibility testing.

## Architecture impact

- Presentation policy, localized copy, deterministic view state, and the Horos panel host are separate boundaries. Future TPA, TPLO, and TTA modes can replace the mode-specific presentation without moving Horos runtime objects into the measurement domain.
- Image-coordinate measurement truth and Study/Series/SOP/frame identity remain independent values. Viewer and panel ownership stay at the Horos adapter edge.
- P1-09 remains the public AppKit hosting fallback and P1-10 remains the short-guide source. Issue #30 does not infer a private dock or toolbar hierarchy.
- Confirm is deliberately separated from persistence and clinical suitability. This keeps later calibration, audit, persistence, and clinical-validation policies replaceable.

## Data-safety impact

- Only known synthetic fixtures inside the dedicated contained environment were displayed.
- No patient, customer, clinical, existing unknown Study, or external-volume data was accessed, copied, changed, or uploaded.
- Issue #30 introduced no Horos database, DICOM, standard ROI, defaults, standalone-record, baseline artifact, Horos application, network-setting, or macOS security-setting write.
- No medical image, DICOM, screenshot, raw log, local path, user or device identifier, signature identity, or baseline/old-plug-in identity is included in Git.

## Next prerequisite

- Review the Issue #30 Draft PR, state semantics, product copy, adaptive policy, and known limitations.
- Merge requires separate explicit approval. Issue #30 remains open until an approved merge.
- Issue #31 Hold-Space temporary PAN and Issue #26 clinical-data collection remain blocked. No later feature issue is authorized by this Draft PR.

## STOP required

No Issue #30 implementation STOP condition remains. Stop after opening the Draft PR. Do not merge it, close Issue #30, change Issue #31 or Issue #26 status, launch clinical-data work, or begin a later feature.

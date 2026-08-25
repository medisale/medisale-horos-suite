# Issue #31 Hold-Space Temporary PAN

## Result

**PASS / DRAFT REVIEW.** Issue #31 adds a Viewer-owned temporary PAN mode that is active only while an unmodified Space key is held. Left-mouse events are translated into the same public AppKit middle-mouse event path used by the verified native Horos PAN interaction. The implementation never changes the persistent Horos tool selection, does not implement custom image translation, and contains no direct Horos database, DICOM, ROI, measurement, preference, filesystem, or network write path.

An isolated conditional A/B/C comparison passed. The candidate produced only the same Horos-owned native display-position state classification observed after direct native PAN. No candidate-only persistent change was detected. Protected clinical identity, image, measurement, ROI, tool/default, schema, integrity, and anonymous baseline-artifact state remained unchanged.

## Verified facts

- Work started from the approved main commit on `feature/issue-31-hold-space-pan`. Issue #32 and later work were not started.
- Bare Space begins temporary PAN only for the owning Viewer's verified image-view responder hierarchy. Modifier-bearing Space, key repeat, text-entry focus, button focus, unrelated views, and other windows are not captured.
- Temporary PAN is bound to an independent Study/Series/SOP/frame identity. Identity change ends PAN and prevents restoration into the new image or frame.
- During PAN, two-point collection, endpoint selection, endpoint drag, and measurement commit paths ignore left-mouse events.
- Mouse down, drag, and up are routed as native middle-button AppKit events. The current Horos tool is never read, replaced, or persisted by Issue #31.
- Key up ends temporary PAN. Escape ends PAN first and then re-posts Escape so the pre-existing measurement-cancel behavior runs unchanged.
- Viewer focus loss, Viewer close, application resign, image/frame change, lost key-up detection, plug-in unload, and teardown force PAN to end.
- If forced teardown occurs during a native mouse drag, the owning image view receives a matching native middle-button up before PAN state is released. A subsequent PAN can start normally; no stuck interaction remains.
- Temporary PAN ownership is per Viewer. Two simultaneous Viewers retained distinct measurement and overlay state, and PAN in one did not move or edit the other.
- The image-coordinate endpoints remained unchanged while the native display position moved. Overlay rendering continued to derive display position from image-coordinate truth.
- No fake API, compatibility shim, private selector, inferred Horos tool API, custom translation, standard ROI, or persistent-tool mutation was added.

## Files changed

- `Makefile`: adds the Issue #31 source, model test, native-event checks, direct-write prohibitions, and regression gate.
- `plugin/HoldSpacePanState.h` and `.m`: independent keyboard, focus, activation, and Study/Series/SOP/frame identity policy.
- `plugin/TemporaryPanController.h` and `.m`: per-Viewer local event routing, native middle-event delegation, forced mouse release, lost-key detection, lifecycle observers, and cleanup.
- `plugin/TwoPointInputController.h` and `.m`: suppresses measurement point collection while the owning temporary PAN state is active.
- `plugin/TransientLineOverlayController.h` and `.m`: suppresses endpoint selection and editing while temporary PAN is active.
- `plugin/MedisalePluginFilter.m`: creates and releases one temporary PAN controller per Viewer and shares its state with input and overlay owners.
- `tests/HoldSpacePanTests.m`: deterministic keyboard, focus, identity, lifecycle, and native-event construction tests.
- `docs/product/ISSUE_31_HOLD_SPACE_PAN.md`: this anonymized report.

## Tests

### Build and deterministic verification

- `make clean verify`: PASS.
- Candidate output: arm64 Mach-O bundle built against the installed real `PluginFilter` and OsiriXAPI headers.
- Candidate ad-hoc strict signature verification: PASS.
- Compact Guide regression: 238 assertions PASS.
- Transactional persistence regression: 153 assertions PASS.
- Hold-Space PAN policy/state: 46 assertions PASS.
- Static source audit found no direct Horos database, managed-object, DICOM, ROI, measurement-store, defaults, filesystem, network, image-origin, or persistent-tool write in the Issue #31 path.

### Conditional native-PAN comparison

| Run | Action | Result |
|---|---|---|
| A: No-PAN control | Opened and closed the same known synthetic image without PAN. | PASS. Ordinary Horos Viewer-management state changed; the PAN-specific display-position category did not. |
| B: Native-PAN control | Used the verified direct native Horos PAN path without the candidate shortcut. | PASS. Only the limited Horos-owned display-position category attributable to native PAN was added to ordinary Viewer bookkeeping. |
| C: candidate PAN-only | Used bare Space plus left drag, delegated to the same native path. | PASS. The native display-position category matched B; candidate-only persistent changes were zero. |

Across the valid A/B/C comparison, schema, Study/Series/Instance counts, known synthetic UID sets, DICOM set and body hashes, SQLite integrity, ROI state, tool/default state, guide preference, standalone measurement-store semantics, anonymous immutable baseline artifact, and crash set remained unchanged. Coordinate values were intentionally not compared for equality because movement amount differs between manual drags.

Preliminary runs that did not reach candidate PAN, selected an unreadable process localization, or omitted empty-store baseline initialization were invalidated and excluded. They were closed safely, had zero successful external connections, and did not alter protected semantic data. The previously changed dedicated synthetic database was preserved, not repaired, deleted, rolled back, manually edited, or reused as the conditional baseline.

### Horos 4.0.1 runtime matrix

| Case | Result | Evidence |
|---|---|---|
| Collecting, zero points | PASS | PAN moved the synthetic image while the input state remained zero of two. |
| Collecting, one point | PASS | PAN preserved exactly one image-coordinate point and did not add or commit another point. |
| Completed overlay | PASS | The line followed native PAN while both image-coordinate endpoint values remained unchanged. |
| Endpoint editing | PASS | An endpoint edit updated only that endpoint; later PAN did not select, drag, or commit either endpoint. |
| 100 percent and fit | PASS | PAN worked after both scale modes and retained image-coordinate truth. |
| Viewer resize | PASS | PAN and overlay tracking remained functional after shrink and restore. |
| Mouse down/drag/up | PASS | The complete native middle-event route moved the image and did not enter measurement input. |
| Key up during mouse drag | PASS | Forced native middle-up ended the in-progress drag; a subsequent PAN started normally with no stuck state. |
| Escape | PASS | PAN ended first, then the existing incomplete-input cancellation cleared the pending point. |
| Key repeat | PASS | Repeat was ignored and no stuck PAN or measurement mutation occurred. |
| Modifier-bearing Space | PASS | The event was not captured by the Viewer shortcut. |
| Text/button focus policy | PASS | Real AppKit text-field and button responders were rejected by deterministic focus tests; the Viewer monitor also ignored events from other windows. |
| Viewer/application focus loss | PASS | Active PAN was forced off; returning to the Viewer allowed a fresh PAN. |
| SOP and frame switch | PASS | PAN ended on identity change and no prior overlay or interaction state appeared in the new identity. |
| Two Viewers | PASS | Distinct overlays and native display positions remained separated. Each Viewer panned independently. |
| Close one of two Viewers | PASS | The remaining Viewer continued to PAN; the closed Viewer released its view/window resources. |
| All Viewers and Horos exit | PASS | Horos returned to its database window, exited normally, and left no Horos or sandbox process. |

### Isolation and data-safety evidence

- Runtime tests used only disposable isolated homes, dedicated synthetic databases, and known generated single- and multi-frame fixtures under the designated standard user.
- Patient or unknown data, clinical images, additional volumes, network shares, and old plug-ins used by the candidate were zero.
- The plug-in inventory contained the candidate and one anonymous immutable baseline artifact only. Identity collisions were zero.
- The anonymous immutable baseline artifact retained its content and metadata fingerprint and was not accessed by Issue #31 code, changed, moved, disabled, deleted, or re-signed.
- Horos ran directly beneath the validated process-level network-deny sandbox. Horos and child-process successful external connections were zero.
- Global Wi-Fi, proxy, DNS, packet-filter, firewall, Gatekeeper, SIP, AMFI, and other network or security settings were not changed.
- Query-only before/after checks retained the same protected semantic state and SQLite integrity result. Aggregate database fingerprints changed because Horos performs normal Viewer bookkeeping and stores native display state; this was disclosed and was not used as the sole PASS signal.
- No screenshot, raw log, image, DICOM, UID, database field or value, local path, hash, username, device identifier, signature identity, or baseline-artifact identifier is included in Git.

## Evidence

- Local evidence includes candidate architecture and signature results, assertion counts, verified AppKit event classifications, anonymous process/network counts, Viewer/image/frame ownership outcomes, resource-release outcomes, query-only semantic comparisons, DICOM content comparisons, SQLite integrity, crash counts, and prospective baseline-artifact comparison.
- The valid PAN-only candidate comparison repeated the direct native PAN change classification while all protected semantic classifications remained unchanged.
- The full GUI matrix also exercised zoom, fit, resize, Viewer tiling, image/frame switching, and normal Horos window lifecycle. Those operations caused additional ordinary Horos-owned display/window bookkeeping but no protected or candidate-specific semantic mutation.

## Known issues

- This is an isolated interaction foundation, not production readiness, release approval, clinical validation, or permission to use a patient database.
- Horos normally persists limited Viewer display-position state after native PAN. Issue #31 neither writes this state directly nor uses it as a measurement store; its allowance is limited to the verified dedicated synthetic environment and the same change classification as direct native PAN.
- The host's current keyboard-navigation policy does not expose every panel button as a runtime focused responder without changing a global accessibility setting. No global setting was changed. Text-entry and button exclusion use public AppKit type checks and deterministic real-AppKit tests.
- A process-only English resource selection was used for direct-executable sandbox launches because the installed alternate localization resource is unreadable to the dedicated account. This did not modify Horos or global language settings.
- Horos reports the ad-hoc candidate as not Horos-validated, as expected for an isolated proof of concept. Build warnings originate from deprecated declarations in installed Horos headers.
- Whole database bundle fingerprints are expected to change during ordinary Horos Viewer lifecycle and are retained only as supporting evidence. PASS is based on the control/action semantic classification.

## Architecture impact

- Temporary input-mode policy is separated from Horos event routing. `HoldSpacePanState` stores only independent identity values; `TemporaryPanController` alone owns Viewer/runtime events.
- The candidate delegates to the verified native Horos middle-mouse event path and does not introduce a second transform or display-coordinate model.
- Input and overlay controllers share only the temporary PAN state, preserving image-coordinate measurement truth and existing per-Viewer ownership.
- The design does not add persistence. Future calibration, TPA, TPLO, TTA, production persistence, and audit work remain separate issues.

## Data-safety impact

- Only known synthetic fixtures in disposable contained environments were displayed.
- No patient, customer, clinical, unknown Study, external-volume, or network-share data was accessed, copied, changed, or uploaded.
- Issue #31 introduced no direct Horos database, DICOM, standard ROI, measurement-store, defaults, baseline artifact, Horos application, network-setting, or macOS security-setting write.
- The only conditionally allowed persistent difference was Horos-owned native display-position state, matching the direct native PAN control and not carrying clinical identity, ROI, measurement, or tool/default changes.

## Next prerequisite

- Review the Issue #31 Draft PR, native delegation boundary, forced-release behavior, conditional A/B/C result, and known limitations.
- Merge requires separate explicit approval. Issue #31 remains open until an approved merge.
- Issue #32 and Issue #26 remain blocked. No later feature or clinical-data work is authorized by this Draft PR.

## STOP required

No Issue #31 implementation STOP condition remains. Stop after opening the Draft PR. Do not merge it, close Issue #31, change Issue #32 or Issue #26 status, launch clinical-data work, or begin a later feature.

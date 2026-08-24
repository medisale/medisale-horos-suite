# Platform Spike Results

## Gate status

**P1-01 through P1-13 are technically PASS, subject to review.** P1-13 is the final lifecycle/stability candidate and remains unmerged. This matrix is evidence for a separate Platform Gate review; it does not authorize production, clinical, release, installation, or post-Platform feature work.

## P1 Platform Gate matrix

| Issue / phase | Result | Verified integration point | Principal evidence | Known limitations | Architecture impact | Data-safety impact | Unresolved risk | Platform Gate prerequisite |
|---|---|---|---|---|---|---|---|---|
| P1-01 Horos 4.0.1 baseline | PASS / COMPLETE | Target macOS, arm64, Horos version, installed API/header, account, and isolation baseline | `HOROS_4_0_1_BASELINE.md` | One isolated Mac/OS/Horos combination | Establishes the only supported spike runtime | Synthetic-only and contained-user rules established | Other Horos/macOS versions unverified | Dedicated target and baseline evidence available |
| P1-02 real `PluginFilter` skeleton | PASS / COMPLETE | Minimal real OsiriXAPI plug-in build, load, menu dispatch, and alert | `P1_02_PLUGINFILTER.md` and runtime action | Ad-hoc/non-validated spike bundle | Confirms real plug-in entry boundary | Candidate-only deployment; no patient/DB operation | Distribution/signing model unresolved | P1-01 PASS |
| P1-03 Viewer toolbar | PASS / COMPLETE | Toolbar item bound to the owning real Viewer | `P1_03_VIEWER_TOOLBAR.md` | Proof-of-concept action only | Viewer ownership is explicit | Read-only synthetic Viewer action | Final product toolbar design unresolved | P1-02 PASS |
| P1-04 Browser toolbar | PASS / COMPLETE | Browser selection states through verified real API | `P1_04_BROWSER_TOOLBAR.md` | Read-only context proof, not workflow UI | Browser edge remains separate from measurement domain | No Browser/DB/DICOM mutation | Large real-world selection patterns unverified | P1-03 PASS |
| P1-05 Horos adapter | PASS / COMPLETE | Current image converted to independent Study/Series/SOP/frame/dimension/spacing values | `P1_05_HOROS_ADAPTER.md` | Only verified fields and current-image cases | Horos runtime objects stop at adapter boundary | Independent values; synthetic fixtures only | Broader modality/geometry semantics unverified | P1-04 PASS |
| P1-06 two-point input | PASS / COMPLETE | Image-coordinate input, outside rejection, Escape, and Viewer separation | `P1_06_TWO_POINT_INPUT.md` | Two-point transient interaction only | Per-Viewer input controller owns monitors/observers | No ROI, DICOM, DB, or settings write | Accessibility and exotic input devices unverified | P1-05 PASS |
| P1-07 overlay renderer | PASS / COMPLETE | Transient line from image coordinates through zoom, pan, resize, image/frame/Viewer separation | `P1_07_OVERLAY_RENDERER.md` | Line-only transient renderer | Display coordinates are derived only at draw time | No standard ROI or persistence | Long-duration rendering soak unverified | P1-06 PASS |
| P1-08 endpoint editing | PASS / COMPLETE | Endpoint hit-test/drag with live image-coordinate distance and normal-tool coexistence | `P1_08_ENDPOINT_EDITING.md` | Endpoint editing only; no clinical semantics | Edit state remains Viewer/image/frame scoped | No implicit save or standard ROI | Full input-device/tool matrix unverified | P1-07 PASS |
| P1-09 measurement panel host | PASS / COMPLETE | Viewer-bound inspector fallback, model updates, close/reopen, cleanup | `P1_09_MEASUREMENT_PANEL_HOST.md` | Inspector fallback, not final compact product UI | Panel consumes independent model through a protocol | Panel has no Horos DB/DICOM write path | Final placement and accessibility review pending | P1-08 PASS |
| P1-10 guide engine | PASS / COMPLETE | Shared short instructions and explicit detailed-guide preference | `P1_10_GUIDE_ENGINE.md` | Spike copy and one contained preference | Guide engine/store are replaceable boundaries | Preference contains no clinical data | Final content/localization governance unresolved | P1-09 PASS |
| P1-11 spike persistence | PASS / COMPLETE | Transactional plug-in-owned SQLite insert/update/rollback/close | `P1_11_SPIKE_PERSISTENCE.md` | Standalone spike schema lacks production governance | Persistence protocol isolates SQLite from Viewer/domain | Writes only independent measurement values to owned store | Encryption, migration, retention, audit, recovery unresolved | P1-10 PASS |
| P1-12 reload / restore | PASS / COMPLETE | Exact Study/Series/SOP/frame lookup and correct transient restore after Viewer/Horos reopen | `P1_12_RELOAD_RESTORE.md` | Latest exact-record policy only | Restore stays at adapter edge and returns independent values | Query-only read; no fallback to another image/frame | Multi-process and corrupt-store recovery unresolved | P1-11 PASS |
| P1-13 lifecycle / stability | PASS / REVIEW | Ten Viewer cycles; dual Viewer; Study/Series/SOP/frame changes; close/cancel/edit/panel/guide; relaunch/restore; sleep/wake; SQLite lifecycle; cleanup | `P1_13_LIFECYCLE_STABILITY.md`, 153-assertion harness, isolated runtime comparisons | Isolated functional lifecycle, not whole-product endurance or clinical validation | Confirms ownership, identity, persistence, and cleanup contracts across the spike | Semantic Horos DB/DICOM/store state unchanged; external connections zero | Baseline verifier classification observation, Horos bookkeeping, localization launch constraint, production persistence/security design | Review and merge P1-13, then separate explicit Platform Gate decision |

## Cross-phase architecture finding

- The stable boundary is: verified Horos runtime objects → `HorosAdapter` → independent `ImageContext` and measurement values → transient Viewer-owned presentation and plug-in-owned persistence.
- Image coordinates are the sole measurement truth. Display coordinates are temporary rendering/hit-test values and are never stored.
- Viewer plus exact Study/Series/SOP/frame identity controls input, overlay, editing, panel, and restore ownership. No fallback path substitutes another image or frame.
- The measurement domain and persistence records contain no Viewer, pixel, ROI, managed object, Horos database object, or DICOM runtime object.
- The P1-11 standalone SQLite boundary is transactional and replaceable; it is not a production storage approval.

## Cross-phase data-safety finding

- All runtime evidence used known synthetic fixtures in the dedicated user's contained Horos environment.
- Horos DB and DICOM aggregate bookkeeping was separated from semantic state by control/action comparison. Schema, counts, known identity sets, DICOM bodies, principal semantic values, and integrity remained unchanged.
- Measurement actions never used a standard ROI and did not write Horos DB, DICOM, or Horos defaults. The only retained measurement writes were explicit P1-11 standalone-store saves performed before the applicable semantic baseline.
- Process-level network denial covered Horos and descendants; valid runtime runs observed zero successful connections. No global network/security setting was changed.
- The anonymous immutable baseline plug-in was never used by spike code and its full prospective artifact fingerprint remained unchanged.
- Published reports intentionally exclude patient data, DICOM, medical images, raw metadata, screenshots, raw logs, local paths, usernames, device identifiers, signature identities, baseline identifiers, exact UIDs/hashes, and communication destinations.

## Gate limitations and unresolved risks

- The spike covers one documented Horos 4.0.1 arm64 environment. Compatibility outside that baseline is unknown.
- Ad-hoc signing and Horos non-validated status are acceptable only for the isolated proof of concept.
- The standalone SQLite design still needs production decisions for encryption, key management, migration, retention, deletion, audit, backup, recovery, locking, and multi-process behavior.
- The baseline artifact was unchanged, but P1-13 observed one non-reproducible preflight deep-strict verifier result before stable successful post-run repeats. Review must choose the future gate's canonical artifact/signature evidence.
- Horos database aggregate hashes change under no-action control bookkeeping; semantic comparison and integrity checks remain required.
- Direct sandboxed launch needs a process-only language argument because an installed localization resource is unreadable to the designated user. No application or preference change was made.
- Functional cleanup and the Foundation leak harness passed, but longer soak, performance, memory-pressure, accessibility, localization, modality breadth, clinical algorithm, and clinical validation work remain outside P1.

## Required Platform Gate decision

The reviewer must separately decide whether the evidence is sufficient to close P1-13 and merge its Draft PR. Even after that merge, post-Platform Issues must remain blocked until an explicit Platform Gate approval defines the next authorized scope. Compact UI, Space-PAN, TPA/TPLO/TTA measurements, production persistence, validation-data collection, release, and clinical installation are not authorized by this document.

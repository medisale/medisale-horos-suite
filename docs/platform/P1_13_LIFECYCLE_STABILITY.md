# P1-13 Lifecycle / Stability Report

## Result

**PASS / REVIEW.** The complete P1-02 through P1-12 platform spike survived the required isolated lifecycle and stability matrix on Horos 4.0.1. Viewer ownership, Study/Series/SOP/frame identity, transient rendering, endpoint editing, panel hosting, guide state, exact reload/restore, transactional persistence, sleep/wake, and cleanup all remained separated and stable. No patient or unknown data was encountered, no external connection succeeded, and no P1-13 action-specific Horos database, DICOM, ROI, defaults, or standalone-store mutation was detected. This result is a technical Platform Gate candidate only; it is not production readiness, clinical validation, release approval, or authorization for a post-Platform issue.

## Verified facts

- P1-13 was run from the reviewed P1-12 merge commit on the dedicated branch and adds no clinical feature or production implementation.
- The runtime account was the designated standard macOS user. The isolated Horos database, known synthetic fixtures, candidate plug-in, and standalone measurement store were contained inside that user's home without symlinks, ownership mismatch, external/shared references, additional mounted volumes, or network shares.
- The isolated Horos database contained only known synthetic fixtures: three Studies, three Series, five image records, and four stored DICOM files. Patient identifiers, dates of birth, institutions, physicians, unknown records, clinical images, and burned-in identifying content were absent.
- The installed real Horos 4.0.1 headers, real `PluginFilter`, real OsiriXAPI notification constants, public Viewer interfaces, and public SQLite interfaces remained the only runtime/API boundary. No fake API, compatibility shim, inferred selector, standard ROI, or Horos private database write path was introduced.
- The arm64 candidate bundle was built against the installed real API and only that newly built candidate was ad-hoc signed. Its strict signature verification passed.
- The candidate and the one anonymous immutable baseline plug-in had no bundle identifier, principal-class, or executable-name collision.
- The baseline plug-in's prospective full content/resource/metadata/xattr manifest and file count were identical before and after all runtime tests. It was not accessed by P1-13 code, moved, edited, repaired, disabled, deleted, copied, or re-signed.
- Horos was launched directly under a temporary process-level sandbox whose only additional restriction denied network operations. The capability probe allowed normal file reads and child execution while denying TCP, UDP, loopback, and child-process network operations.
- Wi-Fi, proxy, DNS, pf, firewall, power, security, Horos application, and baseline plug-in settings were not changed.

## Files changed

- `tests/PersistenceStoreTests.m`: adds ten clean open/save/update/restore/close/reopen store cycles, exclusive-lock acquisition after close, integrity checks, and duplicate/partial-row checks.
- `TASKS.md`: records P1-12 complete and P1-13 pass/review while retaining the separate Platform Gate requirement.
- `docs/platform/P1_13_LIFECYCLE_STABILITY.md`: this anonymized lifecycle and stability report.
- `docs/platform/PLATFORM_SPIKE_RESULTS.md`: the P1-01 through P1-13 Platform Gate matrix.

## Tests and evidence

- `make -B verify`: PASS. The candidate was an arm64 Mach-O bundle, linked to the real `PluginFilter` runtime class and expected verified Horos symbols, and passed strict ad-hoc signature verification.
- The Foundation persistence harness completed 153 assertions. Existing constraint, statement, busy, read-only I/O, pre-commit, and interrupted-save rollback cases remained clean. The new ten-cycle loop verified open, insert, update, exact restore, close, reopen, integrity, no duplicate or partial row, and exclusive lock acquisition after each close.
- `/usr/bin/leaks --atExit` completed the persistence harness with zero leaked allocations.
- Static checks confirmed that the measurement domain retains no Viewer, pixel, ROI, managed object, Horos database, or DICOM runtime object. Viewer/input/overlay/panel teardown removes event monitors, observers, blocks, points, views, panels, and Viewer references.

### Runtime lifecycle matrix

| Lifecycle case | Result | Principal observation |
|---|---|---|
| Viewer open/close, ten cycles | PASS (10/10) | Each cycle created a real Viewer, kept the candidate bound to its owning Viewer and current synthetic identity, entered measurement lifecycle work, retained an image-coordinate overlay, then completed or cancelled and returned to one/zero Viewer without hang, crash, stale panel, or lock. |
| Two simultaneous Viewers | PASS | Independent Viewer bindings were retained. Closing/cancelling one did not alter the other's completed restored overlay or panel, and the remaining Viewer continued normally. |
| Study and Series changes | PASS | Switching among isolated synthetic Browser entries created only the requested Viewer/Series state; a measurement was never substituted for another Study or Series. |
| SOP/image change | PASS | Moving to an adjacent synthetic SOP/image removed the old panel and overlay immediately; returning to the recorded SOP restored only its exact record. |
| Single-frame and multi-frame | PASS | Both retained synthetic forms opened normally and preserved independent identity binding. |
| Frame change | PASS | The frame-zero measurement disappeared on frame one and reappeared only after returning to frame zero. No cross-frame overlay was observed. |
| Mid-measurement Viewer close | PASS | A one-point incomplete input was cancelled by Viewer close, with no remaining event monitor or unfinished point. The second Viewer remained complete and bound. |
| Overlay-visible Viewer close | PASS | Closing a Viewer with a restored transient overlay removed its panel and overlay resources without creating or saving a standard ROI. |
| Endpoint-editing Viewer close | PASS | A verified endpoint hit-test entered active editing at 100% display; closing the owning Viewer before mouse-up released the Viewer, overlay, panel, and edit state without crash or residual window. |
| Panel close/reopen | PASS | The inspector closed independently, then the same Viewer action re-presented it with the same binding and model. |
| Detailed guide OFF/ON | PASS | The shared guide state toggled OFF and back ON and retained the pre-test ON value across panel reopen, Horos relaunch, and sleep/wake. |
| Zoom, pan, resize | PASS | 100%/fit scale transitions, a normal-tool pan away from endpoints, and Viewer resize left image-coordinate endpoints and completed model state unchanged. Endpoint editing remained limited to endpoint hit-tests. |
| Horos exit/relaunch/restore | PASS | Horos returned to the database screen, exited normally, and relaunched under the same sandbox. The stored record returned to the same SOP/frame and exact stored image coordinates; unsaved endpoint changes did not replace it. |
| Sleep/wake | PASS | Normal macOS sleep and wake updated the kernel sleep/wake counters in order. Before any post-wake plug-in action, the sandbox capability was rechecked, Horos remained alive, the process-tree monitor still reported zero connections, and the same Viewer/panel/overlay/store state remained valid. |
| Plug-in/Horos cleanup | PASS | After all Viewers and Horos closed, no Horos process, candidate panel, Viewer, or runtime monitor remained, and no new crash report appeared. |

### SQLite lifecycle

- Clean open/close, initial insert, transactional update, exact reopen restore, and integrity checks passed in every added lifecycle cycle.
- Constraint, statement, busy-lock, read-only I/O, pre-commit, and interrupted-save injections all rolled back without a changed existing record, partial row, duplicate row, or integrity failure.
- The standalone store accepted a new exclusive transaction after primary and reopened store objects were released, demonstrating lock release.
- The retained isolated standalone store's schema, record count, semantic record set, and integrity were identical before and after the GUI/action, relaunch, and sleep/wake runs. P1-13 did not press the save control or add a retained record.

### Process-level network sandbox

- Valid action, relaunch/sleep-wake, and no-action control runs together produced more than thirty-six thousand anonymous process-tree samples with zero network descriptors, zero successful connections, and zero policy violations.
- The sandbox capability gate passed before runtime and again after wake. DNS-dependent TCP, UDP, loopback, and child-process network operations were denied.
- The expected unavailable-listener alert was dismissed without changing a setting. No cloud login, synchronization, upload, update, or baseline plug-in operation was used.
- Preliminary launch or GUI-harness attempts that did not reach their intended test state were invalidated, closed safely, and excluded from PASS evidence. They produced zero successful connections and no crash.
- Destinations, addresses, payloads, hostnames, paths, screenshots, and raw communication logs are intentionally omitted.

### Database, DICOM, preference, store, and baseline comparison

- Read-only comparison used the inspected Horos schema, query-only SQLite connections, semantic record-set fingerprints, synthetic identity-set fingerprints, DICOM set/content fingerprints, integrity checks, standalone-store semantics, guide preference state, crash set, and prospective baseline manifest.
- The action run changed the Horos database bundle's aggregate fingerprint. A subsequent no-Viewer/no-plug-in-action control run reproduced another aggregate change.
- Across both action and control runs, schema, Study/Series/Instance counts, known synthetic identity sets, principal semantic values, DICOM set and DICOM body hashes, both SQLite integrity checks, standalone-store schema/records, and the final guide preference were unchanged. The aggregate change is therefore recorded as Horos normal bookkeeping rather than P1-13-specific semantic mutation.
- The immutable baseline plug-in's complete prospective artifact fingerprint was byte-identical before and after testing. One preflight invocation of deep strict signature verification returned a nonzero result, while the post-run invocation and three immediate read-only repeats returned the same successful result without any artifact change. This non-reproducible verifier classification is retained as a Platform Gate review item; it is not treated as evidence of bundle mutation because all content, resource, metadata, mtime, xattr, file-count, and recognition-roster evidence was unchanged.
- Candidate plug-in signature state, plug-in inventory counts, identifier-collision result, P1-10 preference, DICOM set, crash set, and semantic databases were unchanged.

## Known issues

- This is an isolated platform spike. It does not define production migration, encryption, retention, audit, recovery, multi-process coordination, clinical validation, or release operations.
- Horos database bundle aggregate hashes change during ordinary startup/database-window/exit bookkeeping even when semantic records, DICOM content, and integrity are unchanged.
- The baseline artifact was completely unchanged, but one non-reproducible preflight strict-verifier exit classification differed from the stable post-run repeats. Platform Gate review should decide whether a future gate should use artifact fingerprinting alone or also require repeated verifier classification.
- Network denial produces an expected unavailable-listener warning. No system network or security setting was changed and no connection succeeded.
- Direct executable launch requires a transient process-only language selection because an installed localization resource is unreadable to the designated user. Horos.app, its permissions, and persistent preferences were not changed.
- The first two post-exit relaunch attempts omitted that process-only locale argument and exited before UI initialization. They had zero successful connections and zero crash reports and were replaced by a complete valid relaunch run.
- Kernel sleep/wake counters were used because the local power-management history command exposed no entries. The counters, continued process-tree sampling, post-wake sandbox capability test, and unchanged Viewer/store state jointly form the evidence.
- Horos reports the ad-hoc candidate as not Horos-validated, as expected for an isolated proof of concept. Deprecation warnings originate in installed Horos headers.
- Resource-leak evidence covers the Foundation store harness and observed runtime ownership/teardown. It does not constitute a whole-product long-duration soak or Instruments profile.

## Architecture impact

- P1-13 adds no production feature. It strengthens the reusable SQLite test harness and documents the lifecycle contract already implemented across P1-05 through P1-12.
- Independent image-coordinate values remain the only measurement truth. Viewer, overlay, panel, and persistence ownership stays at the Horos adapter edge.
- Viewer and image/frame identity are re-evaluated on every relevant transition. Missing or mismatched records produce no fallback display.
- Persistence remains behind `MeasurementPersistenceStore`; Horos database, DICOM, ROI, and defaults are not measurement stores.
- Cleanup responsibility remains explicit at input, overlay, panel, Viewer, store, plug-in, and Horos termination boundaries.

## Data-safety impact

- Testing used only retained, known synthetic single-frame and two-frame fixtures inside the dedicated user's contained environment.
- No patient, clinical, customer, existing Study, or unknown data was accessed, displayed, copied, changed, or uploaded.
- P1-13 produced no semantic Horos database, DICOM, ROI, Horos preference, standalone measurement record, baseline plug-in, Horos.app, network-setting, or macOS security-setting change.
- No global Wi-Fi, proxy, DNS, pf, or firewall mutation command was used. All Horos runtime network isolation was process-scoped and temporary.
- No DICOM, image, metadata, screenshot, raw log, database content, local path, username, device identifier, signature identity, baseline identity, or communication destination is included in Git.

## Next prerequisites

- Review the P1-13 Draft PR and this Platform Gate matrix.
- P1-13 merge requires separate SHIP approval.
- After merge, a separate explicit Platform Gate review must evaluate the complete P1 evidence, known limitations, baseline-verifier observation, and remaining product risks.
- Production readiness, clinical validation, release, installation, Compact UI, Space-PAN, clinical measurement algorithms, and validation-data collection remain unauthorized.
- Post-Platform Issues remain blocked until that review grants a new explicit authorization.

## STOP required

No P1-13 implementation STOP condition remains. Stop after opening the Draft PR. Do not merge it, close Issue #13, approve the Platform Gate, change Post-Platform Issue status, or begin feature development.

# Issue #32 Calibration and User-Confirmation State

## Result

**PASS.** Calibration provenance and user-confirmation are now deterministic,
Horos-independent value models. The Compact Guide identifies both states without
claiming clinical suitability. Isolated Horos 4.0.1 testing used only known
synthetic fixtures and detected no candidate-specific persistent change.

## Verified facts

- Calibration has three explicit states: calibrated, DICOM spacing only, and
  unknown. DICOM-derived spacing never becomes calibrated, and Confirm changes
  only the review state.
- The calibrated model requires an explicit safe provenance identifier, method
  version, finite positive row/column spacing, units, derivation status, warnings,
  and schema version. Runtime does not invent an explicit calibration source.
- Missing, one-axis, zero, negative, non-finite, or provenance-free spacing is
  unknown. Unknown status does not block image-coordinate input.
- Finite positive anisotropic spacing remains valid. Row and column values are
  retained separately and applied to their corresponding image axes.
- Confirmation binds exact Study, Series, SOP, frame, endpoints, calibration
  provenance, calculation method version, raw result, and versioned display policy.
- Endpoint/result/calibration changes require renewed confirmation. Identity,
  incompatible-version, invalid-value, or provenance-loss conditions invalidate
  a stale confirmation.
- Expand/collapse, panel movement, zoom, PAN, resize, and Hold-Space PAN do not
  alter the confirmation snapshot.
- The value models retain no Viewer, pixel object, ROI, managed object, DICOM
  runtime object, local path, device identifier, or identifying metadata.
- No production persistence schema or clinical algorithm was added.

## Files changed

- Build verification adds the calibration/confirmation model test and static
  boundary checks.
- A new independent calibration provenance, review snapshot, confirmation-state,
  and display-formatting model was added.
- Compact Guide state/presentation, the Horos adapter boundary, and the panel host
  now consume the independent models.
- English and Japanese Compact Guide copy covers DICOM-only, unknown, modified,
  and invalidated states.
- Synthetic model and Compact Guide regression tests cover the new contracts.
- The candidate bundle version was advanced for the isolated runtime build.

No fixture, DICOM, database, plug-in bundle, screenshot, or raw runtime artifact is
tracked.

## Tests

| Test | Result |
| --- | --- |
| Transactional persistence regression | PASS — 153 assertions |
| Compact Guide state/localization/layout regression | PASS — 238 assertions |
| Hold-Space PAN policy/state regression | PASS — 46 assertions |
| Calibration/confirmation model suite | PASS — 92 assertions |
| arm64 candidate build using installed real headers | PASS |
| Real `PluginFilter` / OsiriXAPI linkage checks | PASS |
| Candidate-only ad-hoc signature verification | PASS |
| Process-level network-deny capability | PASS |
| Isolated Horos 4.0.1 control/action/final-smoke runs | PASS |

## Evidence

- A valid anisotropic synthetic image displayed DICOM spacing only and separate
  row/column values. Confirm did not change that calibration classification.
- A synthetic image with no spacing displayed unknown, explained why physical
  distance was unavailable, and still allowed two-point image-coordinate input.
- Runtime review transitions were observed from not reviewed to user confirmed,
  then modified after an endpoint drag, and back to user confirmed only after an
  explicit second Confirm.
- 100%/fit zoom changes, Viewer resize, panel move, expand/collapse, and an actual
  Hold-Space native PAN retained the same review state and image-coordinate values.
- A real frame-slider change removed the prior frame's transient Guide/overlay;
  returning or acting on another frame did not expose stale confirmed state.
- Two simultaneous Viewers retained different calibration, input, and confirmation
  states. Cancelling one Viewer did not change the other, and closing one left the
  other operational.
- Closing all Viewers removed their panels, inputs, overlays, monitors, observers,
  and Viewer ownership. Horos returned to the database window and exited normally.
- The approved synthetic no-spacing fixture was imported only as test preparation.
  Import increased Study, Series, Instance, and stored-DICOM counts by exactly one;
  the post-import state became the shared comparison baseline.
- Before/after and control/action comparisons kept schema, Study/Series/Instance
  counts and identity sets, DICOM set and content, ROI state, standalone measurement
  records, preferences, and SQLite integrity unchanged.
- Horos changed aggregate management files and native display-position state in
  both control and action use. No Issue #32-specific semantic persistence was found.
- External network connection successes were zero. The anonymous immutable
  baseline artifact remained byte/metadata-identical and unchanged in recognition.
- Static inspection found no Issue #32 DB, DICOM, ROI, defaults, filesystem, or
  network write path.

## Known issues

- Horos legacy headers emit deprecation warnings during the successful build.
- Explicit calibration is model/test scaffolding only; no calibration-marker
  detection or calibration workflow is implemented.
- Confirmation remains in-memory by design. Production persistence and migration
  belong to the later persistence/audit issue.
- Horos normal Viewer use changes aggregate database-management fingerprints and
  native display-position state. Semantic control/action comparison, rather than
  aggregate equality alone, is required.
- The no-spacing fixture import is an expected synthetic baseline-preparation
  change, not an Issue #32 action or production data workflow.

## Architecture impact

- HorosAdapter remains the only boundary that converts verified runtime values to
  independent ImageContext data.
- Calibration provenance and confirmation snapshots are standalone domain values;
  the Compact Guide receives those values instead of Horos runtime objects.
- Raw double values remain calculation inputs. Locale-aware formatting produces
  display strings only, with a versioned rounding policy and precision.
- The integration extends the existing per-Viewer/SOP/frame ownership and lifecycle
  boundary without changing the retained production schema.

## Data-safety impact

- Runtime testing used a dedicated standard account, disposable isolated homes,
  the contained synthetic database, and known synthetic fixtures only.
- Patient or unknown data, clinical images, additional volumes, network shares,
  and old plug-ins used by the candidate were zero.
- The Horos process and its children ran under the verified network-deny sandbox;
  global Wi-Fi, proxy, DNS, firewall, packet-filter, and security settings were not
  changed.
- The candidate did not write Horos DB clinical identity, DICOM, ROI, unrelated
  defaults, or the standalone measurement store. The baseline artifact was not
  accessed by candidate code or modified.

## Next prerequisites

- Review and merge the Issue #32 Draft PR under a separate fixed-head approval.
- Reassess Issue #33 Definition of Ready only after Issue #32 is merged and closed.
- Keep the clinical-validation issue blocked and do not collect clinical data.

## STOP decision

STOP is not required for Issue #32. The requested Draft PR may be created. Issue
#32 remains open until a separately approved merge; Issue #33 and later work remain
untouched.

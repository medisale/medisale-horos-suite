# Issue #43 Named-Landmark Measurement Domain

## Result

**PASS.** A pure Foundation measurement domain, versioned persistence DTO, and
explicit legacy-distance adapter now form the storage boundary. Existing two-point
records retain their exact raw value and transactional behavior. No Viewer,
overlay, panel, clinical method, or Horos runtime behavior was added or changed.

## Verified facts

- Measurement kind, method identifier, method version, unit, validity, warning,
  and landmark identifiers are stable allowlisted values rather than class names,
  localized labels, or caller-provided state strings.
- The first supported method is the existing image-coordinate distance contract.
  It requires explicitly named endpoint A and endpoint B landmarks and stores no
  clinical method name or clinical geometry.
- A named-landmark snapshot rejects missing, duplicate, unknown, non-finite, and
  out-of-image landmarks. Caller-owned arrays cannot mutate the snapshot, and
  canonical identifier ordering makes input order irrelevant.
- Image context is an immutable Study, Series, SOP, frame, width, and height value.
  Frame must be non-negative and dimensions positive. It retains no Viewer,
  image-pixel object, managed object, ROI, or other Horos runtime object.
- A versioned result stores a finite, non-negative, raw unrounded value, explicit
  unit and validity enums, method identity, and a bounded warning-code set. It
  stores no presentation or localized display value.
- Snapshot construction verifies that the legacy raw distance matches the named
  image-coordinate inputs without introducing artificial numeric changes. The
  generic snapshot delegates this check to a typed pure method evaluator and does
  not reference endpoint names or a calculation formula.
- The legacy distance V1 evaluator is the only measurement-domain component that
  knows endpoint A, endpoint B, and the distance calculation. Method identity,
  landmark serialization codes, required landmarks, units, and result validation
  are owned by that evaluator contract.
- Calibration state and confirmation association are not redefined in this issue.
  The Issue #32 `CalibrationProvenanceModel` remains the single canonical state,
  provenance, derivation, version, spacing, warning, round-trip, and confirmation
  implementation. Generic association integration is explicitly deferred to
  Issue #45.
- The persistence DTO is typed and versioned. Serialization is centralized,
  deterministic, and fail-closed for exact key sets, unsupported versions,
  unsupported units, unsafe warnings, invalid context, and corrupt landmarks.
- The pure domain and DTO import Foundation only. They do not import SQLite,
  AppKit, Horos, OsiriXAPI, or Viewer types.
- The legacy adapter maps stored A and B fields to named identifiers explicitly.
  Conversion and restore preserve raw double values and timestamps, require exact
  image identity and dimensions, and reject unknown or future schemas.
- The standalone SQLite store validates saves and restores through the typed DTO
  adapter while retaining its existing schema and transaction behavior. It does
  not silently migrate or upgrade legacy rows.

## Files changed

- `plugin/MeasurementDomain.h` and `.m`: pure immutable evaluator, method,
  context, landmark, result, and snapshot types.
- `plugin/MeasurementPersistenceDTO.h` and `.m`: strict versioned DTO and
  deterministic JSON boundary.
- `plugin/LegacyDistanceMeasurementAdapter.h` and `.m`: explicit legacy A/B
  conversion and restoration boundary.
- `plugin/SQLiteMeasurementStore.m`: validates legacy save and restore through
  the typed adapter without changing its schema or transaction ownership.
- `tests/MeasurementDomainTests.m`: pure evaluator, domain, DTO, and legacy
  compatibility tests.
- `Makefile`: adds the new source and test targets plus architecture boundary
  checks.
- This anonymous architecture report.

No UI, overlay, panel, controller, localization, fixture, DICOM, database,
plug-in bundle, screenshot, or runtime artifact is tracked.

## Tests

| Test | Result |
| --- | --- |
| Named-landmark domain and DTO | PASS — 273 assertions |
| Transactional persistence regression | PASS — 153 assertions |
| Compact Guide regression | PASS — 249 assertions |
| Hold-Space PAN regression | PASS — 46 assertions |
| Calibration and confirmation regression | PASS — 179 assertions |
| Total model assertions | PASS — 900 assertions |
| Clean arm64 candidate build | PASS |
| Real `PluginFilter` and OsiriXAPI linkage checks | PASS |
| Candidate-only ad-hoc signature verification | PASS |
| Pure-domain forbidden-dependency checks | PASS |
| Pure-domain process leak check | PASS — 0 leaks |

## Evidence

- Valid named-landmark data round-tripped through the typed DTO with an identical
  raw double value and deterministic serialized bytes.
- Reordered dictionary fields decoded to the same typed contract.
- The generic snapshot accepted a registered evaluator result, propagated an
  evaluator rejection, and contained no endpoint identifier or formula reference.
- Known legacy evaluator vectors returned their exact image-coordinate distances;
  unknown method identities and future versions failed closed.
- Missing, duplicate, unknown, non-finite, out-of-bounds, negative-frame,
  invalid-dimension, unsafe-warning, unsupported-unit, corrupt, partial, and
  future-version inputs all failed closed with bounded errors.
- Mutating a caller-owned landmark array after construction did not mutate the
  immutable snapshot.
- Legacy A and B converted by explicit identifier, restored to the same endpoints
  and raw result, and were rejected against a different image identity.
- Existing injected constraint, statement, pre-commit, and interrupted-save
  failures retained record count, previous record content, and SQLite integrity.
- Static source inspection found no AppKit, Viewer, Horos, OsiriXAPI, SQLite,
  managed-object, ROI, defaults, filesystem-write, network-write, reflection, KVC,
  fake-API, compatibility-shim, or clinical-method dependency in the pure domain
  and DTO boundary.
- The full clean build continued to resolve the installed real Horos headers and
  real `PluginFilter` runtime class. No Horos process was launched.

## Known issues

- The standalone SQLite schema remains the verified legacy spike schema. This
  issue adds a typed validation and conversion boundary; it does not claim a
  production migration, audit format, or general multi-method database schema.
- The only registered measurement method in this issue is legacy image-coordinate
  distance. Later methods require an explicit reviewed method definition and
  version; unknown methods fail closed.
- Existing Viewer, overlay, panel, and controller code remains two-point-specific.
  Its refactor is intentionally deferred to Issues #44 and #45.
- Calibration and confirmation remain solely in the canonical Issue #32 model.
  Their measurement-neutral association is not claimed by this issue and is an
  explicit dependency for Issue #45.
- The successful arm64 build still reports deprecation warnings originating from
  installed Horos legacy headers.

## Architecture impact

- Dependency direction is now domain to DTO adapter to standalone store. The pure
  domain does not know about storage, SQLite, UI, or Horos runtime objects.
- Landmark meaning is explicit and separate from array order. Raw result values
  and presentation values are separate by construction.
- Generic snapshot validation depends on a typed evaluator protocol. Adding a
  future registered method does not add landmark names or formulas to the generic
  snapshot or DTO.
- Legacy compatibility is isolated in one adapter instead of adding persistence
  responsibility to the old record class.
- Calibration and confirmation retain the one existing canonical model. Existing
  tests continue to prove unknown, runtime-spacing-only, explicit, round-trip,
  actual-input-change, and no-fake-raw-mutation behavior.
- Issues #44 and #45 remain required before a clinical measurement issue can use
  a neutral Viewer session, overlay, panel, or registry.

## Data-safety impact

- Work was limited to source, build outputs, and synthetic scalar test values in
  the dedicated repository environment.
- Patient data, clinical data, existing Study, Horos Data, DICOM, old plug-ins,
  immutable baseline artifacts, external volumes, and network shares were not
  accessed.
- Horos was not launched and no candidate bundle was placed into a plug-in
  directory. The generated build bundle was used only for local compile, linkage,
  and signature verification.
- There were no writes to Horos DB, DICOM, standard ROI, Horos defaults, or any
  production persistence location.

## Next prerequisites

- Review and merge the Issue #43 Draft PR under a separate fixed-head approval.
- Keep Issue #44 blocked until Issue #43 is merged and closed.
- After Issue #43 merge, review Issue #44 DoR before starting its Viewer-session
  and multi-landmark overlay work.
- Keep Issue #45 blocked until Issue #44 is merged.
- Keep Issue #33 blocked until Issues #43, #44, and #45 are all merged.
- Keep Issue #26 and Issues #34 and later blocked; do not collect clinical data.

## STOP decision

STOP is not required for Issue #43. The implementation and local verification
meet the issue PASS conditions, so a Draft PR may be created. Stop after the Draft
PR; do not merge it or begin Issue #44, Issue #45, Issue #33, or later work.

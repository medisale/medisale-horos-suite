# Issue #44 Viewer Measurement Interaction Session

## Result

**IMPLEMENTATION PASS / RUNTIME QA PENDING.** The reusable measurement
interaction session, typed overlay topology, Viewer/image ownership checks, and
lazy standalone-store boundary pass local architecture and regression review.
The prior GUI run completed 10 of 11 checks, but the independent second-Viewer
runtime path is not complete. This Draft PR must not be made Ready, merged, or
used to close Issue #44 until a later authorized synthetic runtime run passes.

## Verified facts

- The reviewed source handoff matched its recorded base, file list, and content
  hash before architecture-review amendments were applied.
- `MeasurementInteractionSession` is the single owner of interaction state,
  Viewer ownership identity, Study/Series/SOP/frame identity, method-defined
  landmark order, selection, drag rollback, undo/redo, cancellation, and
  invalidation.
- A typed interaction definition accepts exactly two through five landmarks and
  explicit overlay segments. One-landmark and more-than-five-landmark
  definitions fail closed.
- The generic session and topology contain no endpoint A/B or distance-formula
  dependency. Legacy two-point topology is isolated in its adapter, while legacy
  result validation remains isolated in its existing evaluator.
- The overlay/presentation layer consumes the session snapshot and topology. The
  domain has no reverse dependency on session or presentation, and the session
  has no reverse dependency on overlay, panel, persistence, SQLite, or Horos UI.
- Viewer, SOP, and frame mismatches reject events and invalidate stale state. A
  session owned by one Viewer cannot accept another Viewer's events.
- Input and overlay teardown remove their local event monitors and notification
  observers. Overlay teardown also invalidates its timer, detaches its view,
  releases session state, and clears its Viewer reference.
- The main plug-in filter was not changed by this issue. Session behavior remains
  in the reusable session/controllers instead of adding another responsibility
  to the plug-in entry point.
- No reflection, KVC dispatch, class-name dispatch, compatibility shim, giant
  method switch, or fake Horos API was added.
- Test fixture classes and test executables are absent from the production
  bundle.
- No responsibility assigned to Issue #45 was implemented.

## Empty-store defect and lazy-store correction

The empty-store defect was caused by standalone-store initialization opening the
database and creating its parent directories before an explicit save. Restore
startup requested a store object even when no record existed, so a read-only
workflow could leave an empty database artifact.

Store construction now performs only lexical and containment validation. Reads
open an existing database in SQLite read-only/query-only mode and return no
record when the file is absent. They create no directory, database, journal,
WAL, or shared-memory file. The first filesystem creation occurs only after a
valid measurement reaches the user-confirmed save boundary. Schema creation and
the first record are committed in that save transaction. Any failed first save
removes the database, sidecars, and directories created by that attempt.

The presentation state now owns an explicit persistence permission. An
unconfirmed, editing, cancelled, modified-after-confirmation, invalidated, or
otherwise incomplete measurement cannot invoke persistence. Both control
enablement and the save action enforce the same permission.

## Files changed

- Build verification rules and source lists.
- Generic measurement interaction definition, session, hit testing, and tests.
- Legacy interaction topology adapter.
- Two-point input and transient overlay controllers.
- Compact Guide persistence-permission state and tests.
- Standalone SQLite store and persistence tests.
- Inspector save-boundary enforcement.
- This anonymous architecture report.

No DICOM, medical image, Horos database, user preference, plug-in installation,
screen capture, runtime log, or test-user artifact is tracked.

## Tests

| Test | Result |
| --- | --- |
| Transactional and lazy persistence | PASS — 184 assertions |
| Compact Guide and persistence permission | PASS — 254 assertions |
| Hold-Space PAN regression | PASS — 46 assertions |
| Calibration and confirmation regression | PASS — 179 assertions |
| Measurement domain regression | PASS — 273 assertions |
| Generic interaction session and topology | PASS — 432 assertions |
| Total model assertions | **PASS — 1368 assertions** |
| Clean arm64 production bundle | PASS |
| Real `PluginFilter` and OsiriXAPI symbol checks | PASS |
| Strict ad-hoc signature verification | PASS |
| Production bundle test-fixture exclusion | PASS |

## Evidence

- Store initialization, absent-store restore, invalid pre-save input, and session
  cancellation paths leave zero standalone-store artifacts.
- Confirmed first save creates one restrictive store, initializes the expected
  schema, and commits one record.
- Constraint, unavailable-statement, pre-commit, and interrupted first-save
  failures leave no database, sidecar, store directory, or partial root.
- Existing-store reads create no new file. Existing constraint, statement,
  lock, read-only I/O, pre-commit, interruption, update, reopen, and integrity
  regressions remain passing.
- Generic session tests cover typed topology for two, three, four, and five
  landmarks; collection; immutable restore; Viewer/SOP/frame isolation;
  selection; bounded editing; drag cancellation; focus loss; undo/redo; and
  repeated invalidation.
- The final clean build used installed real Horos headers and retained the real
  unresolved `PluginFilter` runtime class. The resulting bundle is arm64 and its
  ad-hoc signature passes strict verification.
- Static review found no forbidden dependency, dynamic dispatch mechanism,
  test-fixture symbol, or Issue #45 clinical-method responsibility in the new
  generic layer.

## Runtime QA status

- Prior authorized GUI evidence is **10/11**, not a full pass.
- The independent second-Viewer runtime route remains incomplete and cannot be
  inferred from unit or static evidence.
- Multiple runtime attempts stopped at QA-infrastructure gates before a complete
  valid run. Those STOPs are retained as limitations and are not converted into
  product failures or passes.
- Runtime authorization changed from process-level network denial to
  synthetic-only QA with monitored network and no process-level deny. This
  implementation task did not perform that runtime run.
- Runtime QA remains required from the exact Draft PR head before merge review.

## Known issues

- No complete two-Viewer runtime PASS exists for this head.
- GUI item 11 and the final normal-termination/cleanup route require a fresh
  authorized synthetic run under the revised monitored-network policy.
- Deprecation warnings originate from installed Horos legacy headers.
- The standalone SQLite schema remains the existing legacy spike schema. This
  issue changes its creation boundary, not production migration, encryption,
  retention, recovery, or audit design.
- Runtime QA pending means this Draft PR is not mergeable by policy even if the
  hosting service reports no mechanical merge conflict.

## Architecture impact

- Dependency direction is domain to interaction session to
  overlay/presentation. Horos runtime adaptation stays at the controllers.
- Viewer and image/frame ownership have one canonical session check rather than
  controller-local point arrays.
- Generic topology is method-defined and bounded to two through five named
  landmarks. Legacy distance topology and evaluation stay in explicit legacy
  boundaries.
- Persistence is a lazy write boundary. Construction, restore, cancellation,
  and unconfirmed interaction remain side-effect free.
- Plug-in-filter responsibility and Issue #45 scope are unchanged.

## Data-safety impact

- Development and verification used source, build outputs, and synthetic scalar
  fixtures only.
- Horos was not launched or controlled, and no candidate was installed by the
  development account.
- No test account, Horos Data, DICOM, image, active database, patient data,
  customer data, clinical data, screen content, or raw runtime log was accessed.
- No external connection was required for local build and test verification.

## Next prerequisites

- Review this Draft PR without making it Ready or merging it.
- Run the exact-head candidate in the designated synthetic runtime environment
  under monitored network and the revised no-process-deny authorization.
- Require all GUI checks, independent second-Viewer isolation, semantic
  invariants, normal termination, and cleanup to pass before merge review.
- Do not close Issue #44 until that runtime gate passes and a separate merge
  approval is granted.
- Do not begin Issue #45 or any later issue.

## STOP decision

No implementation or architecture STOP remains. Stop after creating the Draft
PR and staging its exact-head candidate. Runtime QA remains pending; do not make
the PR Ready, merge it, close Issue #44, or begin Issue #45.

# Tasks

## Status rules

- `GO / READY`: approved and all prerequisites satisfied
- `BLOCKED`: must not start
- A passing issue unlocks only its direct successor after review.
- P1-13 completion does not automatically authorize feature development; a Platform Gate review is required.

## Epic P1 - Platform Spike

| ID | Title | Status | Dependency | Primary evidence |
|---|---|---|---|---|
| P1-01 | Horos 4.0.1 Platform Baseline | **GO / READY** | Target Mac available | `docs/platform/HOROS_4_0_1_BASELINE.md` |
| P1-02 | Real PluginFilter Skeleton | **PASS / COMPLETE** | P1-01 PASS | Plugin executes `Medisale Plugin OK` |
| P1-03 | Viewer Toolbar PoC | **PASS / COMPLETE** | P1-02 PASS | Correct viewer-bound toolbar action |
| P1-04 | Browser Toolbar PoC | **PASS / COMPLETE** | P1-03 PASS | Read-only selection context tests |
| P1-05 | HorosAdapter Foundation | **PASS / COMPLETE** | P1-04 PASS | Independent `ImageContext` output |
| P1-06 | Two Point Input | **PASS / COMPLETE** | P1-05 PASS | Image-coordinate input |
| P1-07 | Overlay Renderer | **PASS / COMPLETE** | P1-06 PASS | Zoom/pan/resize tracking |
| P1-08 | Endpoint Editing | **PASS / COMPLETE** | P1-07 PASS | Editable endpoints without tool conflict |
| P1-09 | Measurement Panel Host Spike | **PASS / COMPLETE** | P1-08 PASS | Stable docked panel or inspector fallback |
| P1-10 | Guide Engine PoC | **PASS / COMPLETE** | P1-09 PASS | Persistent guide preference and short instructions |
| P1-11 | Spike Persistence | **PASS / COMPLETE** | P1-10 PASS | Transactional standalone SQLite store |
| P1-12 | Reload / Restore | **PASS / COMPLETE** | P1-11 PASS | SOP UID + frame exact restore |
| P1-13 | Lifecycle / Stability Test | **PASS / REVIEW** | P1-12 PASS | Regression report and Platform Gate matrix |

Detailed scope, acceptance criteria, and STOP conditions are in `docs/platform/PLATFORM_SPIKE.md` and the corresponding GitHub Issues.

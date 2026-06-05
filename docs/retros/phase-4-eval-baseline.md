# Phase 4 eval baseline

T-4.1 records the Phase 3 decomposition baseline before the structure-first
pipeline lands. The baseline uses the existing single-pass engine with a mocked
LLM response that reproduces the observed failure: a lone `types.ts` and a
shared `utils/` helper are emitted as standalone modules.

## Fixture: express-saas

Expected capabilities:

- Google OAuth login
- Stripe subscription billing

Negative traps:

- `src/types.ts`
- `src/utils/`

Baseline scorecard:

```text
file_precision: 0.50
file_recall: 0.50
tag_accuracy: 0.50
expected_modules: 2
actual_modules: 3
module_count_delta: 1
trivial_module_false_positives: 2
trivial_module_false_positive_rate: 1.00
```

The baseline finds the Google OAuth capability, misses Stripe subscription
billing, and emits both negative traps as modules. That is the numeric failure
Phase 4 must eliminate.

## Fixture: next-media

Expected capabilities:

- S3 image upload
- Email invite sending

Negative traps:

- `src/types.ts`
- `src/utils/`

Baseline scorecard:

```text
file_precision: 0.50
file_recall: 0.50
tag_accuracy: 0.50
expected_modules: 2
actual_modules: 2
module_count_delta: 0
trivial_module_false_positives: 1
trivial_module_false_positive_rate: 0.50
```

The baseline finds the S3 upload capability, misses email invite sending, and
still emits `src/types.ts` as a module. Its traps should remain zero false
positives once deterministic quality gates land.

## T-4.11 new-pipeline gate

T-4.11 reruns the eval harness through the full capability-centric pipeline:
scan, symbols, code graph, capability fingerprints, structural repo map, survey,
expansion, refinement, quality gates, persistence, and extraction. The survey
and refinement calls are mocked with realistic structured outputs so the gate is
deterministic while still exercising the actual orchestration path.

### Fixture: express-saas

New-pipeline scorecard:

```text
file_precision: 1.00
file_recall: 1.00
tag_accuracy: 1.00
expected_modules: 2
actual_modules: 2
module_count_delta: 0
trivial_module_false_positives: 0
trivial_module_false_positive_rate: 0.00
```

The new pipeline finds both Google OAuth login and Stripe subscription billing,
keeps their route/service/config/type closures together, and emits neither the
lone `src/types.ts` nor the shared `src/utils/` helper as modules.

### Fixture: next-media

New-pipeline scorecard:

```text
file_precision: 1.00
file_recall: 1.00
tag_accuracy: 1.00
expected_modules: 2
actual_modules: 2
module_count_delta: 0
trivial_module_false_positives: 0
trivial_module_false_positive_rate: 0.00
```

The new pipeline finds both S3 image upload and email invite sending, and the
quality gates keep the `src/types.ts` trap out of persisted modules.

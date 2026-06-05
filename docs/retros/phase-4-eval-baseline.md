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

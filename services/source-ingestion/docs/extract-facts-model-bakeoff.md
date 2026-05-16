# Extract-facts model bake-off (matter c744)

**Status:** Complete. Decision: `Qwen/Qwen3-Next-80B-A3B-Instruct`.
**Date:** 2026-05-12
**Driving question:** which open-weight model on DeepInfra is best suited to the `extract-facts` stage?

---

## Background

The matter (`c744`) named `Qwen/Qwen2.5-72B-Instruct` for `extract-facts` because it
fit the "Qwen extractor + DeepSeek verifier" different-family pairing. There was no
empirical comparison against other models.

First Phase B corpus runs (Cook + Philippines + Nicholls) showed Qwen-2.5-72B on
DeepInfra is slower than ideal and unreliable on long generations:

- ~14 output tokens/sec (vs ~25 for DeepSeek-V4-Flash on verify-claims)
- 32K context cap on this DeepInfra deployment (not Qwen's native 128K)
- 12% of extract-facts calls hit the 300 s `total_timeout_s` and never returned

DeepInfra's catalog has 74 text-gen models with ≥100K context. Worth comparing on
merit rather than continuing on the matter's default pick.

## Iteration corpus

- `test-corpus/Cook_Fremlin_Bowdrey_Cecidology_2026.pdf` — 8 pages, 2 candidates after
  find-candidates. Smallest paper, fastest feedback.
- `test-corpus/Mutun_2015_Twelve_oak_gall_wasp_species_new_to_Turkish_fauna.pdf` —
  3 pages, 13 candidates after find-candidates. Info-dense, exercises the
  per-candidate fan-out without being huge.

(Philippines and Cuesta excluded from the bake-off — Philippines is OCR'd, Cuesta is
slow and we don't need its volume to compare models.)

## Methodology

Per-stage isolation: only the `extract-facts` model varied. find-candidates,
metadata, verify-claims (stub), taxonomy held constant. Configs in
`pipelines/bakeoff/extract-facts-<slug>.yaml`, generated programmatically from the
shared phase-b base so only the extract-facts stage's `model` field differs.

Pipeline-level fixtures:

- `find-candidates`: `deepseek-ai/DeepSeek-V4-Flash` (proven), n_samples=3, agreement_threshold=2
- `extract-facts`: **the variable**, max_workers=8, idle_timeout_s=90, total_timeout_s=300
- `verify-claims`: STUB prompt (returns `not_enough_evidence` for everything)

Models tested (all on DeepInfra):

1. `openai/gpt-oss-120b` — 131K, $0.039/$0.190, reasoning
2. `deepseek-ai/DeepSeek-V4-Flash` — 1M, $0.140/$0.280, reasoning available
3. `nvidia/Nemotron-3-Nano-30B-A3B` — 131K, $0.050/$0.200, reasoning, MoE (3B active)
4. `Qwen/Qwen3-Next-80B-A3B-Instruct` — 262K, $0.090/$1.100, MoE (3B active), structured-output
5. `MiniMaxAI/MiniMax-M2.5` — 196K, $0.150/$1.150, reasoning
6. `Qwen/Qwen2.5-72B-Instruct` — baseline, 32K (DeepInfra cap), $0.075/$0.200

12 runs total (6 models × 2 papers).

## Round 1 — speed, reliability, hallucination

### Speed (extract-facts wall time, all stages 8-wide)

| model | Cook (2 cands) | Mutun (13 cands) | median per-call | output tok/sec |
|---|---:|---:|---:|---:|
| **Qwen3-Next-80B-A3B-Instruct** | **14 s** | **20 s** | 11 s | **204** |
| DeepSeek-V4-Flash | 82 s | 175 s | ~48 s | 30–42 |
| MiniMax-M2.5 | 82 s | 132 s | ~58 s | 36–40 |
| gpt-oss-120b | 300 s* | 235 s | ~140 s | 35–37 |
| Qwen2.5-72B (baseline) | 300 s* | 378 s | ~135 s | 17–23 |
| Nemotron-3-Nano-30B-A3B | 300 s* | 385 s | ~200 s | 53–91 |

\* Hit one or more `total_timeout_s=300` ceilings — actual time would be longer if cap raised.

**Qwen3-Next is 5–19× faster than the field.** The MoE 80B-total / 3B-active
architecture pays off massively on this workload. Per-call median is ~11 s vs
~50–200 s for everything else.

### Reliability (Instructor exhausted retries / TimeoutError)

| model | total errors / 15 calls |
|---|---:|
| Qwen3-Next-80B-A3B-Instruct | 0 |
| MiniMax-M2.5 | 0 |
| DeepSeek-V4-Flash | 0 |
| gpt-oss-120b | 1 |
| Qwen2.5-72B | 3 |
| Nemotron-3-Nano-30B-A3B | **8 (53% failure rate)** |

Graceful failure caught all of these — the pipeline continued and produced valid
bundles in every case — but a model with high error rate means losing the
extraction work for those candidates entirely.

### Hallucination caught by substring gate

The substring gate is a deterministic check: every cited evidence quote must be a
fuzzy-substring match (RapidFuzz partial_ratio ≥ 90) of the cited block's text.
Mismatches indicate the extractor cited a quote that isn't actually in the source.

| model | total subst_mm warnings (Cook + Mutun) |
|---|---:|
| **Qwen3-Next-80B-A3B-Instruct** | **1** |
| MiniMax-M2.5 | 3 |
| DeepSeek-V4-Flash | 7 |
| gpt-oss-120b | 8 |
| Nemotron-3-Nano-30B-A3B | 11 |
| Qwen2.5-72B (baseline) | 30 |

Qwen3-Next has the lowest hallucination signal by a large margin. Qwen2.5-72B has
30 — the worst.

### Cell volume per record

How many cells the extractor emits per record (a proxy for completeness):

| model | Mutun cells/record | abstain rate |
|---|---:|---:|
| Qwen3-Next | 18 | 45% |
| MiniMax-M2.5 | 12 | 12% |
| DeepSeek-V4-Flash | 11 | 24% |

Qwen3-Next emits the most cells but abstains most often. Consistent with
"conservative completeness" — fills out the schema fully but declines to claim
when uncertain.

### Round 1 verdict

**Qwen3-Next-80B-A3B-Instruct wins on every measurable axis:**

- 5–19× faster than alternatives
- Zero errors
- Lowest hallucination signal
- Highest per-record cell volume

**Honorable mentions:** DeepSeek-V4-Flash and MiniMax-M2.5 — both reliable, both
moderately fast. Either could be a fallback if Qwen3-Next fails on real prompts.

**Eliminated from further consideration:**

- `Nemotron-3-Nano-30B-A3B` — 53% failure rate, unusable
- `Qwen2.5-72B` (the matter's original pick) — slow, 3 timeouts in 15 calls,
  30 hallucinations
- `gpt-oss-120b` — slow on small papers, some errors

## Round 2 — extraction quality with real verify-claims (in progress)

Round 1 measured speed and the substring-gate-catchable hallucination rate, but
not whether the extracted facts are *correct*. To assess that, the verifier
(currently a different-family DeepSeek model) needs to actually run.

Re-running the top three on Cook + Mutun with `prompts/verify-claims.md` (real
verifier) wired in. Outcomes to compare:

- `supported` cell count (extractor + verifier agreement)
- `not_enough_evidence` cell count (verifier disagrees)
- `evidence_substring_mismatch` count (substring gate catches)
- Records that emerge with at least one `supported` field per category

### Notes on family pairing

For Qwen3-Next and MiniMax-M2.5, verify-claims on DeepSeek-V4-Flash satisfies the
matter's "different family" principle.

For DeepSeek-V4-Flash as the extractor, verify-claims on DeepSeek-V4-Flash is
same-family and theoretically weaker (shared biases). If DeepSeek-V4-Flash wins
Round 2, we'd separately decide on a non-DeepSeek verifier — Qwen3-Next or
MiniMax-M2.5 are both viable.

### Round 2 results

Configs: `pipelines/bakeoff/verify-claims-r2-{slug}.yaml`. Same as Round 1 but with
`prompts/verify-claims.md` (real verifier on `deepseek-ai/DeepSeek-V4-Flash`).

#### Stage timings

| model | extract-facts (Cook + Mutun) | verify-claims (Cook + Mutun) |
|---|---:|---:|
| **Qwen3-Next-80B-A3B-Instruct** | **12 s + 35 s = 47 s** | 111 s + 116 s = 227 s |
| DeepSeek-V4-Flash | 159 s + 328 s = 487 s | 28 s + 43 s = 71 s |
| MiniMax-M2.5 | 121 s + 268 s = 389 s | 27 s + 117 s = 144 s |

Qwen3-Next is **8–10× faster on extract-facts** with real verify-claims wired in.
The verify-claims stage takes longer for Qwen3-Next because it emits more cells per
record and there are more cells to verify (130 vc calls vs 101 for DeepSeek and 112
for MiniMax across both papers).

#### Records emerging with `supported` scientific_name

| model | Cook (2 records) | Mutun (13 records) |
|---|---:|---:|
| Qwen3-Next-80B-A3B-Instruct | 1/2 | 9/13 |
| DeepSeek-V4-Flash | 1/2 | 11/13 |
| MiniMax-M2.5 | 1/2 | 11/13 |

All three correctly identify Cook's *A. coriarius* as supported and downgrade
*A. quercuscalicis* to `not_enough_evidence` (it appears in the paper only as a
comparison reference). On Mutun, Qwen3-Next has 2 fewer "fully verified" records
than the others — though the missed two emit cells with evidence that the
verifier judged not-enough rather than the model failing to extract.

#### Cell-level outcomes (across both papers)

| model | supported | abstained | not_enough_evidence | substring_mismatch | hallucination rate |
|---|---:|---:|---:|---:|---:|
| Qwen3-Next-80B-A3B-Instruct | 84 | 120 | 67 | 5 | 5.6% |
| DeepSeek-V4-Flash | 78 | 32 | 52 | 3 | **3.7%** |
| MiniMax-M2.5 | 76 | 11 | 59 | 8 | 9.5% |

Hallucination rate = `subst_mm / (subst_mm + supported)`.

Convergence on hosts: all three models got exactly **7/21 hosts supported on Mutun**
— suggests the verifier's hosts-supported set is the same regardless of extractor,
because the underlying evidence pack and verifier logic are identical, and the
"obvious" host claims are pretty stable across extractors.

#### Trade-off summary

| | Qwen3-Next | DeepSeek-V4-Flash | MiniMax-M2.5 |
|---|---|---|---|
| Speed | ⚡⚡ 8–10× faster | baseline | similar to DeepSeek |
| Reliability | ✅ 0 errors | ✅ 0 errors | ✅ 0 errors |
| Supported cell count | 84 (highest) | 78 | 76 |
| Hallucination rate | 5.6% | 3.7% (lowest) | 9.5% (highest) |
| Abstention rate | 45% (highest) | 24% | 12% (lowest) |

Qwen3-Next emits the most cells, abstains the most when uncertain, and has a
moderate hallucination rate. DeepSeek-V4-Flash is the most conservative on
hallucinations but slowest. MiniMax-M2.5 is the most aggressive on extraction
(fewest abstentions) but the most likely to hallucinate.

## Decision

**`Qwen/Qwen3-Next-80B-A3B-Instruct`** for extract-facts.

Rationale:

- **8–10× speed advantage** is the dominant factor — extract-facts is the pipeline
  bottleneck and a typical big paper has 30–50 candidates. Cutting per-call latency
  from ~150 s to ~15 s collapses an hour-long run to ~10 minutes.
- **Quality is competitive** — supported cell count is highest (84 vs 78 vs 76) and
  hallucination rate is mid-range (5.6%, well below MiniMax's 9.5%).
- **Conservatism is acceptable** — Qwen3-Next abstains more, which costs recall but
  saves verifier time and reduces false positives the human reviewer has to reject.
  If recall becomes a problem, the prompt can be tuned to reduce abstention without
  changing the model.
- **Different family from the verifier** — Qwen extractor + DeepSeek verifier
  matches the matter's original different-family principle. No reshuffle needed.

### Production wiring

- `pipelines/north-star-v0.yaml`: change `extract-facts.model` from
  `deepinfra/Qwen/Qwen2.5-72B-Instruct` to
  `deepinfra/Qwen/Qwen3-Next-80B-A3B-Instruct`.
- `pipelines/phase-b-extract-facts.yaml` and the verify-claims iteration config can
  be updated as part of the same change.
- `pipelines/bakeoff/` configs are kept for re-running future bake-offs against new
  models or tuning concurrency.

### Open questions

- **Concurrency.** This bake-off used `max_workers=8`. DeepInfra allows up to 200
  concurrent requests per model; bumping to 16–32 should compress wall time
  further. Worth re-testing with the chosen model. (Tracked as a separate
  follow-up.)
- **Abstention rate.** Qwen3-Next's 45% abstention rate is highest among the three.
  If post-Phase-B production runs show too many `abstained` fields where the human
  curator can clearly see the answer in the source text, tighten the prompt's
  abstention rule to require evidence rather than uncertainty.
- **Same-family check.** We only tested DeepSeek as the verifier. If the verifier
  needs replacement, MiniMax-M2.5 (different family from Qwen) is the obvious
  candidate with proven reliability and reasoning capability.

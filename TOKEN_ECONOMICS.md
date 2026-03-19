# Token Economics

## Token Value
- **1 Forge token ≈ $0.05** effective value (user perspective via actions). Real cost ~$0.003–$0.02. Config: `FORGEAI_TOKEN_VALUE_USD=0.05`.

## Action Pricing (default config)

| Action | Tokens | Tier |
|--------|--------|------|
| explain_code | 2 | simple |
| fix_bug | 6 | medium |
| generate_tests | 8 | medium |
| refactor_code | 10 | heavy |
| deep_repo_analysis | 25 | heavy |
| ai_suggestion | 8 | medium |
| create_branch | 12 | simple |
| commit | 24 | simple |
| open_pr | 16 | simple |
| merge_pr | 18 | simple |
| run_tests | 30 | medium |
| run_lint | 10 | simple |
| build_project | 40 | medium |

Source of truth: `functions/src/pricing.ts` and `config/monetization.json`. Flutter display: `lib/src/core/config/forge_economics_config.dart`.

## Provider Cost Assumptions (backend)
- **Blended target**: input $1/1M, output $4/1M (typical request ~2k in / 1k out ≈ $0.006).
- Per-provider env overrides: `OPENAI_INPUT_COST_PER_1K_USD`, `OPENAI_OUTPUT_COST_PER_1K_USD`, etc.

## Margin Strategy
- Minimum **5x** gross margin on AI cost; prefer **8x+** where feasible.
- All pricing is tuned to remain profitable after Apple’s 30% IAP cut.

## Plans and Caps
- **Free**: 20 tokens/mo, 10 actions/day, basic model tier.
- **Pro**: $14.99/mo (Apple net ~$10.49), 300 tokens/mo, 50 actions/day, standard tier.
- **Power**: $29.99/mo (Apple net ~$20.99), 800 tokens/mo, 150 actions/day, priority tier.

## Top-Up Packs (production)
- pack_small: 100 tokens → **$5.99** (Apple net $4.19)
- pack_medium: 300 tokens → **$14.99** (Apple net $10.49)
- pack_large: 1000 tokens → **$34.99** (Apple net $24.49)

## Daily / Monthly Limits
- Plan-based **daily action cap** (total actions per day) enforced in backend.
- Per-action-type daily caps from pricing rules.
- Monthly included tokens and monthly used enforced on capture.

## Refund Rules
- AI: release reservation on provider failure; capture only after a reviewable draft is created.
- Git: release on remote failure or missing provider config.
- Checks: release on dispatch failure or missing provider config.

## Verification
```bash
npm run simulate:tokens
```
See `REVENUE_SIMULATION.md` for scenario descriptions and margin thresholds.

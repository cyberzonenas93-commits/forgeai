# Revenue Simulation

## Script
```bash
npm run simulate:tokens
```
Uses `tool/token_economics_simulator.mjs` and env from `config/launch-config.json` / `.env`.

## What It Does
- Loads token value (default $0.01), Apple cut (30%), and target margin (5x).
- Runs scenarios mixing Free / Pro / Power users, AI and API action usage, and optional top-ups.
- Computes gross revenue, Apple net, provider cost, and margin multiple.
- Prints ✓ or ✗ when margin is above or below target.

## Scenarios (examples)
- **100 free / 50 pro / 20 power**: Mixed base with moderate AI and API usage and some top-ups.
- **Heavy deep_repo_analysis**: Pro/Power-heavy, high token usage per user; validates margin on expensive actions.
- **High failure / refund case**: Simulates ~15% refund rate to ensure margins hold.

## Tuning
- Set `FORGEAI_TOKEN_VALUE_USD` (e.g. `0.01`) and provider cost env vars to match production assumptions.
- Adjust scenarios in `token_economics_simulator.mjs` to match expected user mix and usage.

## Margin Assumptions
- Target **5x** minimum gross margin (Apple net / provider cost).
- Alert or fail the script if any scenario falls below this threshold (script currently prints ✗).

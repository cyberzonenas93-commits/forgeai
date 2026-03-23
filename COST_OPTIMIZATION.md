# Cost Optimization

## Goal
Keep the coding-agent runtime closer to Cursor / Claude Code behavior without letting planning, repair, or repeated retries burn uncontrolled model spend.

## Implemented Files
- `/Users/angelonartey/Desktop/ForgeAI/functions/src/cost_optimization.ts`
- `/Users/angelonartey/Desktop/ForgeAI/functions/src/routing_engine.ts`
- `/Users/angelonartey/Desktop/ForgeAI/functions/src/index.ts`

## Budget Snapshot
Each agent task now gets a task-local budget snapshot derived from:
- deep mode
- token guardrail budget
- retry budget

Stored fields include:
- cost profile
- task token budget
- repair reserve tokens
- task soft USD budget
- daily soft USD budget

## Cost Profiles
- `economy`
  - prefer cheaper planning and context routing
  - used more often when budget headroom is low
- `balanced`
  - default mixed mode
- `quality`
  - used for harder repair or deeper edit phases when budget allows

## Routing Behavior
Routing now considers:
- stage
- deep mode
- repo size class
- retry count
- cost profile

That means:
- planning and context can stay cheaper when appropriate
- repair can still escalate toward stronger reasoning providers
- large repos do not always force the most expensive provider if the remaining budget is tight

## Cost Ledger
Task metadata now accumulates:
- estimated tokens per stage
- estimated provider cost per stage
- total estimated agent tokens
- total estimated agent cost
- latest cost entry

Current tracked stages:
- planning
- context
- editing
- validation
- repair
- git

## Why This Matters
The old system mainly routed by stage quality and repo size. The new system still does that, but it now also:
- records the spend story for the task
- tracks remaining budget ratio
- uses that ratio when choosing cost profiles
- makes repeated repair passes less likely to waste expensive routing early

## Current Limits
- Cost estimation is heuristic, not provider-billed ground truth.
- Validation tools are mostly local or GitHub-driven, so their ledger impact is primarily execution metadata, not provider token cost.
- User-facing budget controls are not yet a first-class mounted product surface.

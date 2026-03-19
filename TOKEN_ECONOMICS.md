# Token Economics

## Token Value
- `1 token = $0.0010` app revenue assumption

## Action Pricing
- `create_branch`: 12 tokens
- `commit`: 24 tokens
- `open_pr`: 16 tokens
- `merge_pr`: 18 tokens
- `run_tests`: 30 tokens
- `run_lint`: 10 tokens
- `build_project`: 40 tokens
- `ai_suggestion`: 80 token floor

Source of truth: `functions/src/pricing.ts`

## Provider Cost Assumptions
- OpenAI: `$0.0004 / 1K input`, `$0.0016 / 1K output`
- Anthropic: `$0.0030 / 1K input`, `$0.0150 / 1K output`
- Gemini: `$0.00015 / 1K input`, `$0.00060 / 1K output`

## Daily Caps
- `create_branch`: 80
- `commit`: 80
- `open_pr`: 80
- `merge_pr`: 60
- `run_tests`: 40
- `run_lint`: 80
- `build_project`: 30
- `ai_suggestion`: 30

Daily caps are now enforced during reservation in the backend wallet path.

## Monthly Caps
- Enforced when `wallet.monthlyLimit > 0`
- Capture fails if the next token charge would exceed the configured monthly limit

## Refund Rules
- AI suggestion: release reservation on generation failure
- Git actions: release reservation on remote failure, missing provider config, or empty commit payload
- Check actions: release reservation on dispatch failure or missing provider config

## Margin Verification
Run:
```bash
npm run simulate:tokens
```

Current modeled margins from the simulator are above 90% for light, typical, and heavy beta scenarios under the present assumptions.

## Beta Protections
- Guest and signed-in limits remain policy-controlled in wallet documents
- No token capture occurs without a matching reservation
- Queued or failed actions now release previously reserved tokens where required

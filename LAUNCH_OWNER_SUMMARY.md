# Launch owner summary: monetization

One-page view for the launch owner: recommended config, margins, risks, and one high-leverage tweak.

---

## 1. Recommended Free / Pro / Power configuration

| Plan   | Price (display) | Apple net (30%) | Monthly tokens | Daily action cap | Model tier |
|--------|------------------|-----------------|----------------|------------------|------------|
| **Free**  | $0               | $0              | 20             | 10               | basic      |
| **Pro**   | $14.99/mo        | $10.49          | 300            | 50               | standard   |
| **Power** | $29.99/mo        | $20.99          | 800            | 150              | priority   |

**Why this works**
- Free is enough to try the product (20 tokens ≈ a handful of AI actions) but caps usage so power users upgrade.
- Pro at $14.99 is a standard “indie pro” price; 300 tokens + 50/day supports daily use without constant top-ups.
- Power at $29.99 captures heavy users; 800 tokens + 150/day keeps them on subscription instead of burning through top-ups.

**Config location**: `config/monetization.json`, `functions/src/economics-config.ts`, `lib/src/core/config/forge_economics_config.dart`.

---

## 2. Recommended top-up configuration (production — set exactly)

| Pack   | Tokens | Price (display) | Apple net (30%) | $/token (gross) |
|--------|--------|------------------|-----------------|------------------|
| Small  | 100    | **$5.99**        | **$4.19**       | ~$0.06           |
| Medium | 300    | **$14.99**       | **$10.49**      | ~$0.05           |
| Large  | 1000   | **$34.99**       | **$24.49**      | ~$0.035          |

**Why this works**
- Slightly above “round” numbers; optimized for Apple’s cut and psychologically acceptable.
- Top-ups are where you make the most margin; these prices are the critical revenue lever.
- Same product IDs and amounts are in code; set these exactly in App Store Connect.

---

## 3. Expected margins under Apple 30%

- **Token value**: 1 token ≈ **$0.05** effective value (user perspective). Your real cost ~$0.003–$0.02 per token. After Apple, you keep 70% of pack/subscription gross.
- **Subscriptions**: Pro $14.99 → you get **$10.49**; cost ~$2–4 → **profit ~$6–8/user/month**. Power $29.99 → you get **$20.99**; cost ~$6–10 → **profit ~$11–15/user/month**.
- **Real scenario**: Pro uses 300 tokens → cost ~$3 → profit ~**$7.50**. Power uses 800 tokens → cost ~$8 → profit ~**$13**.
- **Action-level**: Explain 2 tokens = $0.10 value, ~$0.003 cost → ~$0.097 profit; deep analysis 25 tokens = $1.25 value, ~$0.04 cost → ~$1.21 profit. Model routing and caps keep cost under control.

---

## 4. Biggest risks to profitability

1. **Heavy use of expensive models**  
   Power users on priority tier (e.g. Claude/GPT-4) with lots of refactor_code / deep_repo_analysis can push per-request cost toward the token charge. **Mitigation**: Route simple/medium actions to cheaper models (basic/standard); keep heavy actions and caps tight (e.g. deep_repo_analysis 25 tokens, dailyCap 10).

2. **Provider price increases**  
   If OpenAI/Anthropic/Gemini raise prices and you don’t adjust token price or action costs, margin compresses. **Mitigation**: Centralized pricing and cost assumptions (e.g. in `pricing.ts` and env); revisit token value and action prices when provider pricing changes.

3. **Refunds and failures**  
   High failure/refund rate means you release reservations and don’t capture revenue but may still have incurred partial provider cost. **Mitigation**: Refund policy is already “release on failure”; monitor refund rate and fix failure modes (e.g. timeouts, provider errors).

4. **Free users consuming more than 20 tokens/month**  
   If caps are gamed or mis-enforced, free can look like a heavy free tier. **Mitigation**: Enforce daily (10) and monthly (20) caps in backend; keep Free clearly “taste only.”

5. **Apple 30% on everything**  
   Already baked into “Apple net” and simulator. Biggest lever if it stays is to keep **subscription share of revenue high** (recurring) and **blended cost per token low** (routing + pricing).

---

## 5. Pricing locked (production)

Final prices are set in code and config:

- **Subscriptions**: $14.99 / $29.99 (Apple net $10.49 / $20.99).
- **Token packs**: **$5.99 / $14.99 / $34.99** (Apple net $4.19 / $10.49 / $24.49).
- **Token value**: 1 token ≈ $0.05 effective value; cost ~$0.003–$0.02.

These are intentionally slightly above round numbers and optimized for Apple’s cut. Subscription = predictable revenue; tokens = scalable revenue; model routing = cost control; caps = protection; top-ups = profit multiplier.

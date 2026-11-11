# Blockchain Necessity Analysis

**Question:** does Milestone need a blockchain, or would PostgreSQL, a REST API, and a payment
processor deliver the same product?

**Short answer:** the product works on a database. The guarantee does not. Exactly one property
requires the chain: donor funds are held by code that no operator key can redirect. Every other
row of the comparison favours the database, and this document says so.

## Method

1. Steelman the centralised alternative. Do not use a strawman.
2. Characterise the workload: who trusts whom, what must be public, what an attacker controls.
3. Score the trade-offs with explicit weights, then test whether the conclusion survives a change
   in those weights.
4. Quantify cost and throughput with a re-runnable model, not remembered figures.

## Workload and trust

| Question | Answer for Milestone |
|---|---|
| Who holds value? | The platform, for weeks, before any service is delivered |
| Mutually distrusting parties? | Creator, N donors, operator. N is tens, not thousands |
| Must the record be public? | Yes. A donor's refund claim must be verifiable without asking the operator |
| Sub-second finality required? | No. 12-second blocks and a 5-day challenge window are acceptable |
| External data needed? | No. Deliberate: it removes the oracle from the trust model |

The last row matters. The moment a contract needs a price feed or a KYC verdict, an oracle
becomes the trusted party. Milestone reads no external data.

## The centralised alternative, steelmanned

Architecture: React SPA, REST API, PostgreSQL, Stripe for collection and payouts, S3 for files,
an admin UI for approving releases, refunds by operator action.

Why it is genuinely good: a contribution costs a fraction of a cent and settles in under a
second. Refunds to a card, chargebacks, tax reporting, and KYC work out of the box. Disputes
can be judged by a human who reads context. One `UPDATE` fixes a bug.

Why it still fails the requirement: every guarantee is a policy. The operator promises not to
touch the money, promises to honour refunds, promises not to delist. Each promise is
enforceable only after the fact, by a court, against a company that may already be insolvent.
You cannot fix this inside the same architecture, because its defining feature is a privileged
account that can move money.

## Weighted comparison

Scores 1 (bad) to 5 (good) from the donor's point of view. Full arithmetic in
`docs/decision-matrix-output.md`.

| Criterion | Weight | Central | On-chain |
|---|---:|---:|---:|
| Custody risk | 25% | 2 | 5 |
| Rule transparency | 15% | 2 | 5 |
| Refund enforcement | 15% | 2 | 5 |
| Deplatforming resistance | 10% | 2 | 5 |
| Cost per transaction | 10% | 5 | 2 |
| Latency and UX | 10% | 5 | 2 |
| Privacy | 5% | 4 | 1 |
| Throughput | 5% | 5 | 2 |
| Fiat / regulation | 5% | 5 | 1 |
| **Total** | 100% | **3.00** | **3.85** |

The result changes with the weights, and that is the interesting part. Drop custody weight from 25% to
10%, raise cost to 20% and latency to 15%, and the database wins 3.45 to 3.40. The same facts
support opposite conclusions depending on what the reader values.

The honest claim is not "blockchain scores higher." The design is justified by one criterion:
custody. A platform that can take donor money is a worse failure than a system that is slow,
public, and expensive. Anyone who rejects that judgement should reject the project.

## Cost, quantified

Assumptions: ETH $3,000, L1 gas 10 gwei, L2 0.05 gwei, 40 donors x $50, 3 milestones. Generated
by `scripts/cost_model.py`.

| Design | L1 total | Share of funds | L2 total | Share of funds |
|---|---:|---:|---:|---:|
| A. Per-donor vote on every milestone | $256.20 | 12.81% | $1.28 | 0.064% |
| B. Optimistic release (implemented) | $79.80 | 3.99% | $0.399 | 0.020% |
| Card processing, same money | $75.00 | 3.75% | - | - |
| Central database | $0.0009 | 0.000% | - | - |

Three conclusions:

1. On L1, the chain is not cheaper than cards. $79.80 vs $75.00.
2. On an L2 it is roughly two orders of magnitude cheaper than cards. Hence the L2-first target.
3. Naive per-donor voting costs 69% of the campaign's gas to confirm work donors can already
   see. Design B exists because the cost model rejected Design A.

## Where the blockchain loses

- Privacy. Every contribution is public forever.
- Finality and reorgs. L1 finality is minutes; L2 "confirmed" is a sequencer's promise.
- UX cost. Wallet install, network switching, gas estimation, no password reset.
- Irreversibility cuts both ways. A bug is not a support ticket.
- Fiat. Refunds arrive as ETH.
- Censorship moves, it does not vanish. RPC, wallet, sequencer, and frontend host can each
  refuse to serve a user.
- Parameters instead of judgement. A 5-day window and a 10% quorum replace a human who can read
  the situation.

## Kill criteria

Milestone should not use a blockchain if any of these hold.

| If this is true | Then use |
|---|---|
| Campaigns are private, or donor lists must be confidential | Central DB |
| Settlement must be under one second | Central DB |
| Money must arrive as fiat, or refunds must reverse a card charge | Central DB |
| Disputes need contextual judgement, not a quorum parameter | Central DB plus human arbitration |
| The platform is the trusted party and users accept it | Central DB |
| Sustained load above about 10 writes per second | Central DB, or an L2 with batching |
| The operator is legally the custodian and liability is the point | Central DB with licensed escrow |

None of these applies to a public crowdfunding product where the operator should not be trusted
with the money.

## Residual trust

Blockchain moves trust, it does not remove it.

| Trusted thing | Why it remains | Mitigation |
|---|---|---|
| L2 sequencer | Orders transactions, can delay inclusion | Document it; L1 Sepolia as baseline |
| RPC provider | Can lie about state or censor | Users can point at any node; proxy is a convenience |
| R2 | Evidence files can disappear | Hash is on-chain; verifiable but not guaranteed available |
| Wallet vendor | Signs and may mislead | Show decoded intent in the UI |
| Contract code | A bug is a permanent rule | Invariant tests, no admin key, no upgrade path |
| Governance parameters | 5-day window, 10% quorum are chosen | Configurable per campaign, visible in UI |

## Verdict

Milestone passes the necessity test on one axis and fails it on four others.

- Necessary for: custody without a custodian; refunds as a right; rules a donor can verify
  without asking permission; a campaign no operator can delete.
- Not necessary for: cost, latency, privacy, fiat handling, dispute nuance.
- Therefore: use the chain for the money and the state machine; use ordinary web
  infrastructure for everything else.
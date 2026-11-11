# Security Preview

Week 1–2 scope: name the attacks, name the mitigation, name the test that proves it. The full
treatment belongs in the Week 8 report; this document fixes the design commitments early so the
contracts are written against them.

## 1. Threats and mitigations

| # | Threat | Where it bites | Mitigation | Test |
|---|---|---|---|---|
| T1 | **Reentrancy on refund**, a donor contract re-enters `claimRefund` | `claimRefund`, `withdraw` | Checks-Effects-Interactions: zero the claim flag before the transfer; `nonReentrant`; pull-over-push so no loop pays out | Attacker contract that re-enters; assert one payout and unchanged balance |
| T2 | **Reentrancy on release** | `withdraw` | Credit accounting updated before transfer; creator pulls, contract pushes nothing | Malicious creator contract |
| T3 | **Access control**, donor calls `deliver`, stranger calls `object` | `deliver`, `object` | `onlyCreator` modifier; `object` requires `balanceOf(msg.sender) > 0` **and** state `ChallengeWindow` | Negative tests for each role |
| T4 | **Integer and rounding**, proportional refunds leave or create wei | `claimRefund` | Solidity 0.8 checked arithmetic; refunds computed with floor; `INV-1` asserts `sum(liabilities) <= balance` | Fuzz contributions across 3–5 donors, assert no over-withdrawal |
| T5 | **Timestamp manipulation**, miner or sequencer shifts the deadline | `contribute`, `release` | Windows are days, not minutes; the only timing-sensitive rule is the challenge window; document the ±12 s L1 and sequencer-controlled L2 caveat | Test boundary: deadline−1, deadline, deadline+1 |
| T6 | **Griefing / spam campaigns** | `createCampaign` | On-chain: a small creation deposit is the only mechanism the contract can enforce. Turnstile protects the UI only, not the contract | Test that the deposit is returned on completion, forfeited on failure |
| T7 | **Evidence fraud**, creator posts a hash of a useless file | `deliver` | Cannot be solved on-chain. Donors judge and object; the hash proves non-tampering, not truth | Out of test scope; documented as a residual limitation |
| T8 | **Objection-weight sniping**, contribute after delivery to buy voting power | `object` | Contributions are only accepted in `Funding`, so weight is fixed before any delivery exists | Attempt `contribute()` in `Active`; expect revert |
| T9 | **Stuck funds**, an objection quorum reached on a milestone that no one can resolve | `object` | Structural removal: a quorum vetoes the milestone and cancels the campaign. There is no `Disputed` state to get stuck in. All unwithdrawn funds become pull-refundable; the only paths out of a canceled campaign are donor refunds and the creator's already-released credit | Quorum reached (weight > `totalRaised / 2`) → status `Canceled` → donors claim full refunds → any further `release`/`deliver` reverts with `WrongStatus` |
| T10 | **Forced ETH**, `selfdestruct` or block reward inflates the balance | `INV-1` | Internal accounting is the source of truth; the invariant is `balance >= liabilities`, not `==` | Force-send ETH in a test; confirm invariant holds |
| T11 | **Clone initialisation takeover**, attacker initialises a clone first | `clone.initialize` | `initializer` guard; factory initialises in the same transaction as deployment | Deploy, then attempt a second `initialize` |
| T12 | **Unbounded loop**, release iterates donors and runs out of gas | `release` | No iteration over donors anywhere. Payments are pull-based | Gas test with 500 contributions; release cost must be constant |

## 2. Invariants (implemented as Foundry invariant tests in Week 4)

- **INV-1** `address(campaign).balance >= totalRaised - creatorWithdrawn - refundsWithdrawn`
  (inequality, because ETH can be forced in).
- **INV-2** A donor can never withdraw more than they contributed, summed across refund and any
  other path.
- **INV-3** `totalRaised` never decreases during `Funding`.
- **INV-4** A milestone can only leave `ChallengeWindow` after `deliveredAt + challengeWindow`.
- **INV-5** No address other than a donor can increase `objectionWeight`.
- **INV-6** Once `Failed` or `Canceled`, the state never changes again.
- **INV-7** A vetoed milestone never releases: `release` reverts in `Canceled`, and no
  transition returns a `Canceled` campaign to `Active`.
- **INV-8** A campaign becomes `Canceled` only through `object`, and only when the objection
  weight exceeded `totalRaised / 2` at that moment. Fuzz: no sequence of contributions and
  objections below the majority bar may ever set `Canceled`.

## 3. Design choices that remove whole vulnerability classes

| Choice | Class removed |
|---|---|
| No owner key, no pause, no upgrade, no admin withdraw | Rug pull, key compromise, malicious upgrade |
| Pull-over-push for every payout | Reentrancy loops, gas-griefing on payout, one bad recipient blocking others |
| Factory + EIP-1167 clones, immutable implementation | Proxy storage collisions, upgrade attacks, unbounded per-campaign deployment cost |
| No external data, no oracle, no randomness | Oracle manipulation, weak randomness, flash-loan price attacks |
| Native ETH only, no ERC-20 | Fee-on-transfer accounting bugs, rebasing tokens, approval exploits |
| Contribution-weighted objections fixed at funding time | Vote buying after the fact, flash-loan governance attacks |
| Veto ends the campaign instead of freezing funds | Stuck-funds states and the "temporary" admin key that a stuck state always grows |

## 4. Known limitations, stated before anyone asks

1. **No arbitration.** An objection quorum vetoes the milestone and cancels the campaign. This
   is deliberately blunt: it ends the campaign rather than freezing it, because a frozen state
   has no legitimate exit in a system with no on-chain arbitration, and stuck funds are a worse
   failure than an ended campaign. **Chosen quorum rule (recorded in Week 2):** a veto requires
   strictly more than half of `totalRaised` — `totalRaised / 2 + 1` wei of objection weight,
   derived from the accounting total, never stored. Consequences:
   - No minority whale can veto alone; their weight is capped by their contribution.
   - The one residual case: a donor who personally contributed a majority of the money can veto
     alone. This is accepted, not mitigated. The majority funder of the money at risk ending the
     campaign is a coherent exercise of contribution weighting, not an attack; and no
     contribution-weighted rule can both protect donors and silence a majority funder.
   - The challenge window length stays the only timing knob; the quorum needs no configuration
     and no factory parameter.
2. **No privacy.** Contributions are public and permanent.
3. **No audit.** Test coverage is not an audit. The report says this in the abstract, not in a
   footnote.
4. **The frontend can lie.** A compromised frontend can show a false intent while the wallet signs a
   different transaction. Mitigation is decoded intent in the UI and an open-source verifiable
   bundle; a user who reads the wallet prompt is still the last line of defence.
5. **Deployment key.** The factory deployer has no ongoing power, but whoever deploys first chooses
   the implementation. Users should verify the implementation address against the repository.

---
created: 2026-11-11
agent: opencode
project: milestone-dapp
kind: guide
---

# Week 3-4 presentation guide: Milestone Solidity contracts

Purpose: give you the files to read, the code to point at, and the concepts to explain for a confident 5-minute class talk.

## What Week 3 is

Week 3 builds the on-chain core of Milestone: an escrow crowdfunding contract where donor money is released one milestone at a time, with donor-triggered objections and refunds as a right. The graded claim is one sentence: nobody, including the developer, can move donor funds.

Week 3 is built and green: factory plus EIP-1167 clones, full Campaign state machine, 38 unit tests, 4 invariants, Anvil deploy verified with cast, and a one-command demo script.

## What to read

Read these in order. Each file has one concept, so one search lands you on the right code.

- `contracts/interfaces/ICampaign.sol` — the public API, events, and errors. Read the contract header comment first: it states the security claim directly.
- `contracts/Campaign.sol` — the state machine: `contribute`, `deliver`, `object`, `release`, `claimRefund`, `withdraw`, `finalizeOutcome`.
- `contracts/CampaignFactory.sol` — deploys EIP-1167 clones, takes a creation deposit, holds no funds, and cannot move campaign money.
- `tests/CampaignCore.t.sol` — 38 unit tests covering factory validation, funding, refunds, veto => cancel, completion, and deposit return.
- `tests/Invariants.t.sol` — 4 fuzz invariants checked after every random fuzz sequence: balance matches ledger, refund never exceeds contribution, totalRaised never decreases, ledger agreement.
- `deploy/demo.sh` — the one-command demo: deploy, create, contribute, activate, deliver, release, withdraw.
- `README.md` — build commands and the three numbers: 69% of gas wasted by naive voting, $79.80 vs $75.00 on L1, 0.02% on L2.
- `PLAN.md` — Week 3-8 roadmap and definition of done.

## What to look for in the code

Point at these specific things during the talk:

**No admin key.** Search for `onlyCreator`. It gates only `deliver` and `withdraw`. There is no `onlyAdmin`, no `pause`, no `upgrade`, and no function in the factory that moves a campaign's funds.

**Veto cancels and refunds.** In `object()`, when objection weight passes `totalRaised / 2`, status becomes `Canceled` and every donor can call `claimRefund()` for their exact contribution. A vetoed milestone never releases.

**Permissionless release.** `release()` can be called by anyone after the challenge window closes without quorum. In the demo, the donor account releases milestone 0, not the creator. Point at this line: there is no admin.

**Pull-over-push.** `withdraw()` and `claimRefund()` zero the claim, update the ledger, then call `call{value:}`. The contract never pushes ETH to anyone, so a hostile creator contract cannot re-enter anything.

**Deposit locked.** The 0.01 ether creation deposit stays in the clone until completion, then returns to the creator. On cancel or fail, it is locked forever — the honest cost of an immutable, keyless contract.

## What to understand

Be able to explain these without notes:

- **Why blockchain:** a database can move money correctly. It cannot make the operator unable to move money wrongly. That single property is the whole justification.
- **Why optimistic release:** per-donor voting on every milestone wastes 69% of gas confirming work donors can already see. Optimistic release means silence is consent; dissent is a signal.
- **Quorum by money, not by headcount.** A $5 donor and a $5000 donor do not have equal weight. The bar is strictly more than half of `totalRaised`, derived at veto time and never stored.
- **Contribution cap:** money past the goal is refused because excess has no exit once the campaign activates. The contract never accepts funds it cannot return.
- **Failed is terminal:** once the deadline passes and the goal is missed, the campaign cannot return to Funding or Active. Refunds are open forever.
- **INV-1:** contract balance equals `totalRaised - creatorWithdrawn - refundsWithdrawn`, plus the locked deposit. This is fuzzed with 64 runs.

## 5-minute talk mapped to code

| Time | Beat | Code to reference |
|---|---|---|
| 0:00-0:35 | The claim: nobody can move the money | `ICampaign.sol` header comment |
| 0:35-1:15 | Why blockchain vs database | `README.md` three numbers, `docs/02-blockchain-necessity-analysis.md` |
| 1:15-1:55 | Design: veto => cancel, quorum by money, optimistic release | `Campaign.sol` `object()` and `release()` |
| 1:55-4:15 | Live demo | `deploy/demo.sh`, 8 narrated steps |
| 4:15-4:45 | Correctness: tests and invariants | `tests/CampaignCore.t.sol`, `tests/Invariants.t.sol` |
| 4:45-5:00 | Close: repo link and roadmap | `PLAN.md` Week 5-8 |

## Week 4 (mention briefly, do not claim as done)

- Exhaustive milestone edge matrix: multi-milestone flows, reentrancy attack test, deliver/objection edge cases.
- Gas optimization pass against the `.gas-snapshot` baseline.
- Sepolia deployment so the demo can show a testnet address.

## Gotchas: do not say these

- Do not say the factory can move campaign funds. It cannot.
- Do not say the creator can pause or upgrade the contract. There is no such function.
- Do not say refunds are automatic. Donors must call `claimRefund()` themselves.
- Do not say the quorum is by donor count. It is by money weight.
- Do not say Week 4 is finished. It is planned, not built.

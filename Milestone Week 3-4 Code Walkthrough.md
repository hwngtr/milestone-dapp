---
created: 2026-11-19
agent: opencode
project: milestone-dapp
kind: guide
---

# Milestone Week 3-4 Code Walkthrough

Purpose: explain every part of the Week 3 Solidity implementation, and give a run sheet for the
5-minute class demonstration. Read this before `Milestone Week 3-4 Presentation Guide.md`. That
file is the talk, and this file is the code behind it.

## 1. The graded claim

> Nobody, including the developer, can move donor funds.

Every design decision below exists to make that sentence true, or to make its cost explicit.
The presentation is not "look at my CRUD app on a chain". It is "look at the functions that are
missing".

## 2. The two contracts

```
Donor wallet ──contribute()──┐
                             ▼
Creator ──createCampaign()──► CampaignFactory ──create(55 bytes)──► Campaign clone (EIP-1167)
                                   │                                   │
                                   │ holds: no ETH                     │ holds: donor ETH + deposit
                                   │ power: none                       │ power: none over funds
                                   └── emits CampaignCreated           └── delegatecall to Campaign impl
```

- `contracts/CampaignFactory.sol` — deploys one `Campaign` implementation in its constructor, then
  every campaign is a 45-byte runtime clone that delegatecalls into it.
- `contracts/Campaign.sol` — the escrow and state machine. One copy of the code, one storage area
  per clone.
- `contracts/interfaces/` — the public API, events and errors. The header comment on
  `ICampaign.sol` states the claim directly.

Why clones: a full `Campaign` deployment costs far more gas than a 55-byte `CREATE`. The factory
pays for the implementation once, and each creator pays for a clone. The implementation is
immutable, so there is no upgrade path to attack.

## 3. Storage: why the fields look like that

`Campaign.sol:20-43`

```solidity
struct Milestone {
    uint96 amount;            // 96 bits
    uint40 deliveredAt;       // 40 bits
    uint96 objectionWeight;   // 96 bits
    MilestoneStatus mStatus;  //  8 bits  = 240 bits total, one slot
}
```

- 240 bits fits one 32-byte storage slot. Reading a milestone is one SLOAD, not four.
- `uint96` is enough for 79 billion ETH in wei. The type is a packing decision, not a business
  limit.
- `deliveredAt` is `uint40` because a Unix timestamp fits in 40 bits until year 36812.
- `evidenceHash` is deliberately NOT a struct field. It goes into the event only. Storing it would
  push the struct past one slot and cost every campaign more gas forever.
- `totalRaised`, `refundsWithdrawn`, `creatorCredit`, `creatorWithdrawn` are `uint256` running
  sums. They let the contract answer how much it owes without looping over donors.
- `contributionOf` is the per-donor ledger. `hasObjected[milestoneId][donor]` prevents double
  voting.
- `initialized` is the clone-initialisation guard. It shares a slot with `deadline`, `challengeWindow`, `releasedCount`, and `status`, so `_sync()` reads the deadline and status with one SLOAD.

## 4. The two state machines

### Campaign status (`ICampaign.sol:9-15`)

```
                 deadline passed, raised >= goal
   Funding ──────────────────────────────────────► Active ──all milestones released──► Completed
      │                                              │
      │ deadline passed, raised < goal               │ objection weight > totalRaised / 2
      ▼                                              ▼
   Failed                                        Canceled

   Failed, Canceled, Completed are terminal.
```

Two details matter in the talk:

1. **Transitions are lazy.** `_sync()` (`Campaign.sol:211-222`) performs the Funding → Active/Failed
   transition on the first call after the deadline. There is no cron job, no keeper, no admin
   transaction. `finalizeOutcome()` exists only so an indexer can force the event even when nobody
   acts. Calling it twice is a no-op.
2. **Failed is terminal.** Once the deadline passes short of the goal, no later contribution can
   revive the campaign. Refunds are open forever.

### Milestone status (`ICampaign.sol:17-22`)

```
   Pending ──deliver()──► ChallengeWindow ──release() after window──► Released
                               │
                               └──object() quorum──► Vetoed (campaign becomes Canceled)
```

- `deliver` is the only `onlyCreator` function on the milestone side.
- `release` is permissionless. The caller has no choice about the amount or destination, so the
  caller needs no privilege.
- A veto never releases. It cancels the whole campaign.

## 5. Function by function

Line numbers refer to `contracts/Campaign.sol`.

| Function | Lines | What it does | Why it is safe |
|---|---|---|---|
| `initialize` | 56-82 | Copies creator, goal, deadline, window, milestone amounts into the clone and records the deposit from `msg.value`. | `initialized` guard. The factory calls it in the same transaction that creates the clone, so no attacker can front-run (T11). |
| `contribute` | 88-96 | Accepts ETH only in `Funding`, only up to `goal`. | `_sync()` first, so a late contribution sees `Active`/`Failed`. Refuses money past the goal, because excess has no exit after activation. Zero-value contributions revert. |
| `deliver` | 103-114 | Creator marks a milestone delivered and opens the challenge window. | `onlyCreator`, `Active`, valid index, milestone must be `Pending`. Stores the timestamp and emits the evidence hash and window end. |
| `object` | 122-141 | Donor adds their contribution as objection weight. At strict majority of `totalRaised`, the contract vetoes the milestone and cancels the campaign. | Must be a donor with weight > 0, in `ChallengeWindow`, before the window closes, once per milestone. The contract derives the quorum and never stores it. |
| `release` | 146-166 | After the window closes with no quorum, credits the milestone amount to the creator. | Permissionless by design. Idempotent: second call reverts `MilestoneAlreadyReleased`. On the last milestone, status becomes `Completed` and the contract credits the deposit back. |
| `claimRefund` | 172-185 | Donor pulls their exact contribution from a failed or canceled campaign. | Checks-Effects-Interactions: zero the claim, update the refund sum, emit, then transfer. Second call reverts `NothingToWithdraw`. |
| `withdraw` | 190-197 | Creator pulls released milestone amounts plus the returned deposit. | `onlyCreator` and pull-over-push. The contract never sends ETH unprompted. |
| `finalizeOutcome` | 203-206 | Forces the deadline transition so the event exists. | Permissionless, idempotent. Reverts only if the deadline has not arrived. |
| `_sync` | 211-222 | Lazy Funding → Active/Failed transition. Returns the status so callers avoid a second storage read. | Pure state change with no external call and no money transfer. |

### The veto rule in one line

```solidity
if (m.objectionWeight > totalRaised / 2) { ... }
```

Strictly more than half of the money. `totalRaised / 2` floors, so with 10 ETH the bar is 5 ETH +
1 wei. A donor holding exactly half cannot cancel alone. A donor holding more than half can. There
is no headcount, no token, no snapshot.

Why so blunt: an objection either reaches a money majority or it does not. There is no
`Disputed` state to get stuck in, and no arbiter to bribe. The tradeoff is that a whale can cancel
a campaign. That is a documented, testable tradeoff, not an oversight.

## 6. The five mechanisms that carry the security claim

1. **No privileged function exists.** Grep for `onlyCreator`: it gates `deliver` and `withdraw`
   only. There is no `owner`, `pause`, `upgrade`, `setFee`, `emergencyWithdraw` or admin sweep.
   The factory has no function that touches a campaign's balance.
2. **Pull-over-push.** `claimRefund` and `withdraw` send ETH only when the recipient calls. No loop
   over donors, so one hostile recipient cannot block anyone else. This also removes gas-griefing
   and reentrancy loops (T2, T12).
3. **Checks-Effects-Interactions.** Both payout functions settle the ledger before `call{value:}`.
   Re-entry sees a zero claim. The contract needs no reentrancy lock because the state is already
   settled.
4. **Contribution cap at the goal.** The contract refuses overfunding. Once the campaign is
   `Active`, excess money would have no exit, so the contract never takes money it cannot return.
5. **Deposit as spam cost.** The factory forwards `0.01 ether` (immutable, chosen at factory
   deployment) to the clone. The clone returns it on `Completed` and locks it forever on
   `Failed`/`Canceled`. This is the honest cost of an immutable, keyless contract: the only
   anti-spam lever available on-chain.

## 7. Tests: what is proven, and what is not

Run: `make test` → 38 unit tests + 1 invariant suite, all green (`forge test`, 39 tests).

| Suite | Count | Covers |
|---|---|---|
| Factory validation | 10 | Zero goal, past deadline, zero window, empty milestones, sum mismatch, wrong deposit, zero factory deposit, creation event, double `initialize`, 45-byte clone with the implementation address. |
| Contributions and state | 9 | Ledger recording, accumulation, zero value, after-deadline both ways, permissionless/idempotent finalize, `Failed` terminal, cap at goal. |
| Refunds | 5 | Before deadline, after goal met, exact amount, double claim, stranger claim. |
| Withdraw | 2 | Non-creator, nothing to withdraw. |
| Milestones | 8 | Deliver guards, window opening, release before window, release pays, double release, completion returns deposit. |
| Veto | 4 | Veto cancels and refunds, double object, stranger object, exactly-half cannot veto alone. |
| Invariants | 4 functions | Ghost ledger over 5 actors: balance matches ledger, refund never exceeds contribution, `totalRaised` monotone, ledger agreement. |

The honest caveat for Week 4: the invariant handlers only call `contribute`, `claimRefund`, `warp`
and `finalize`. In practice `claimRefund` always reverts there because the campaign either is still
`Funding` or becomes `Active` at the goal cap. So the fuzz suite proves the funding ledger, not the
refund path. The unit tests cover refunds, but the refund path is not fuzzed. Adding milestone and
refund handlers is Week 4 work.

## 8. The demo, mapped to code

`make demo` runs `deploy/demo.sh` on a fresh Anvil node. Each step is one function call:

| Step | Command | Function | What to point at |
|---|---|---|---|
| 1 | `forge script deploy/DeployFactory.s.sol` | constructor | One implementation and a 45-byte clone per campaign. |
| 2 | `createCampaign(...)` | `CampaignFactory.createCampaign` | Deposit forwarded, milestones must sum to goal. |
| 3 | `contribute()` | `Campaign.contribute` | Contract balance = donor money. Nobody else holds it. |
| 4 | `evm_increaseTime`, `finalizeOutcome()` | `_sync`, `finalizeOutcome` | Lazy, permissionless deadline transition. |
| 5 | `deliver(0, hash)` | `Campaign.deliver` | The only creator-gated call, with the evidence hash in an event. |
| 6 | `release(0)` from anvil account #0 | `Campaign.release` | The caller is not the creator and not an admin. There is no admin. |
| 7 | `withdraw()` from creator | `Campaign.withdraw` | Pull, not push. 4 ETH, not the whole escrow. |
| 8 | `grep -rn "onlyOwner\|pause\|upgrade" contracts/` | — | No matches. That is the claim. |

If the live demo fails: run `make test`. A green suite is a stronger recovery than a retried demo,
and it shows more engineering.

## 9. Five-minute run sheet

| Time | Say | Show |
|---|---|---|
| 0:00-0:30 | The claim: custody, not code quality, is the failure. Nobody, including me, can move the money. | `ICampaign.sol` header comment |
| 0:30-1:10 | Why a chain: a database moves money correctly, yet cannot make the operator unable to move it wrongly. $79.80 vs $75 on L1, 0.02% on L2. | `README.md` three numbers |
| 1:10-1:45 | The mechanism: optimistic release, challenge window, money-weighted veto, cancel and refund. | `Campaign.sol:122-166` (`object`, `release`) |
| 1:45-3:45 | Live demo, steps 1-7. Narrate the missing admin at step 6. | Terminal |
| 3:45-4:30 | Tests: 38 unit tests, 4 invariants, ghost ledger, pull-over-push and CEI. | `tests/Invariants.t.sol`, `.gas-snapshot` |
| 4:30-5:00 | Repository link, then Week 4: edge matrix, reentrancy attack test, gas pass, Sepolia. | `PLAN.md` |

Cut order if time is short: drop the cost numbers to one sentence first, and never cut the demo or
the grep.

## 10. Questions you will get, with short answers

- **Why not a database?** A database can move money as expected. It cannot make the operator
  powerless. That is the only property that needs a chain, and the report says all other properties
  are worse.
- **Why clones?** Deployment cost. One implementation, 45-byte proxies, immutable target.
- **Why no OpenZeppelin?** The surface is deliberately tiny: no `Ownable`, no `Pausable`, no
  `UUPS`. A clone is 20 lines of assembly. Fewer dependencies, fewer upgrade paths.
- **What stops reentrancy?** CEI plus pull payments. The contract settles the state before the
  external call.
- **What if the creator never delivers?** Today the campaign stays `Active` and funds stay in
  escrow indefinitely. This is a known gap, see section 11.2. The answer is a delivery deadline,
  not an admin key.
- **What if donors never claim a refund?** Their money stays in the clone forever. There is no
  sweep, by design. An unclaimed refund is the donor's choice, not the operator's opportunity.
- **Can a whale cancel?** Yes, if they hold more than half the raised money. Deliberate tradeoff:
  it beats a frozen `Disputed` state and an arbiter key.
- **Is the evidence verified?** No. The hash proves the file did not change after delivery. Donors
  judge the content and object if it is fake. The report documents that as a residual limitation.
- **Can the contract be upgraded?** No. That is the point. Tests are the only safety net, which is
  why the invariant suite exists.

## 11. Gaps found on 2026-11-19 (Week 4 material)

These are real and reproducible. Do not claim we solved them yet.

### 11.1 A veto after a release leaves refunds unfunded

Scenario: milestone 0 releases and the creator withdraws 4 ETH. Then donors veto milestone 1.
`object()` sets `Canceled`, and `claimRefund()` still promises every donor their full
contribution. The contract holds 6.01 ETH but owes 10 ETH. Later claimers revert with
`TransferFailed`.

Reproduction (passes today, i.e. proves the failure):

```
activate with 4/3/3 -> deliver 0 -> warp -> release 0 -> creator withdraw()
deliver 1 -> donor2.object(1) -> donor3.object(1)   // 6 > 5, Canceled
donor1.claimRefund()                                // pays 4
donor2.claimRefund()                                // reverts TransferFailed
```

Fix direction: refund only the unreleased remainder. Track `releasedAmount` and make the refund
pro-rata, or make a post-release veto freeze the remaining escrow instead of promising a full
refund. Either way, the docs, tests and the "exact contribution" sentence must change together.
Add this as a regression test even before the fix, marked `vm.expectRevert`.

### 11.2 No delivery deadline

`deadline` only closes funding. Once `Active`, nothing forces delivery. A creator who disappears
leaves donor money in escrow forever, and `claimRefund` reverts in `Active`. Fix direction: a
global or per-milestone delivery deadline after which donors can cancel and refund. This is a
design change, not a one-line patch.

### 11.3 Smaller notes

- The creator can contribute to their own campaign, which also gives them objection weight and
  raises the veto bar. Not a fund-safety bug, so decide whether to forbid it.
- Milestones can be delivered out of order. Decide whether milestone `n` must wait for `n-1`.
- The implementation contract itself can be initialized by anyone. Harmless, because clones use
  their own storage and the implementation never holds funds. Mention it only if asked.
- `createCampaign` accepts `metadataURI` and ignores it. Intentional, but the interface should say
  so or drop the parameter.

## 12. Vocabulary for the talk

| Term | Meaning in this project |
|---|---|
| Escrow | The clone holds donor ETH until a rule releases or refunds it. |
| Optimistic release | Silence during the challenge window is consent, and the milestone pays. |
| Challenge window | Fixed seconds after `deliver` during which donors may object. |
| Objection weight | A donor's contribution, fixed at funding time. |
| Quorum | Strict majority of `totalRaised`, derived at veto time. |
| Veto | Quorum reached: the milestone never pays, the campaign cancels, and refunds open. |
| Pull-over-push | The recipient calls to withdraw, and the contract never sends unprompted. |
| CEI | Checks-Effects-Interactions ordering before any external call. |
| EIP-1167 | Minimal proxy: 45-byte runtime that delegatecalls to an implementation. |
| Ghost ledger | A test-side independent record used to check the contract's accounting. |
| Invariant | A property that must hold after every possible fuzz sequence. |

## 13. Files to open in this order

1. `contracts/interfaces/ICampaign.sol` — the claim, the API, the errors.
2. `contracts/Campaign.sol` — the state machine and the payouts.
3. `contracts/CampaignFactory.sol` — clones and validation.
4. `tests/CampaignCore.t.sol` — one test per rule, named after the rule.
5. `tests/Invariants.t.sol` — the ghost ledger.
6. `deploy/demo.sh` — the 8-step live demo.
7. `docs/04-security-preview.md` — T1-T12 and INV-1 to INV-8.

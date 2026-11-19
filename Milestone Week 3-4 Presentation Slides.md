---
created: 2026-11-19
agent: opencode
project: milestone-dapp
kind: slides
---

# Milestone Week 3-4 Presentation Slides (code demonstration)

**Format:** Beamer PDF, 7 slides, 16:9. The deck shows source code with line numbers and explains it. No cost model and no Week 1-2 architecture recap.
**Beamer source:** `Individual Project/slides/milestone-week3-4.tex`
**Compiled PDF:** `Individual Project/slides/milestone-week3-4.pdf`
**Academic HTML deck:** `Individual Project/slides/milestone-week3-4-slides.html` (source JSON: `slides/milestone-week3-4-deck.json`)
**PPTX:** `Individual Project/milestone-week3-4-code-demo.pptx`. Built from the print-style HTML by `slides/build-pptx.cjs`. Diagram PNGs used by the build: `slides/diagrams/state-machine.png` and `factory-clone.png`.
**Print-style HTML deck:** `Individual Project/slides/code-demo-print.html`. One self-contained file. Monochrome paper and ink. The dither code is inline. Navigation by arrow keys, space, Home, End, and buttons. Print button emits one slide per page.
**Pele diagrams:** `slides/diagrams/state-machine.mmd` and `factory-clone.mmd`. I rendered both to SVG with `pele-render` and monochrome variables, then inlined the SVGs into the deck. Both diagrams are full slides at positions 5 and 8. Next and back reach them in sequence. You need no click and no zoom.

**Local-only sources.** The `slides/` and `scripts/` folders stay on this machine. They are not part of the repository submission. The finished PPTX and the generated reports are in the repo.

---

## Slide 1: Files shown in this talk (0:00-0:15)

**One sentence:** nobody, including the developer, can move donor funds.

**Source on screen**

- `contracts/interfaces/ICampaign.sol` — the public API
- `contracts/Campaign.sol` — the escrow and state machine
- `contracts/CampaignFactory.sol` — clone deployment

**What I will show**

- The seven functions a caller can reach
- The rules that move ETH, with line numbers
- The functions that do not exist
- The demo and the test result

Leave this slide up while opening the files. Put the repository link here.

---

## Slide 2: Public functions in ICampaign (0:15-0:55)

**Code on screen** (`ICampaign.sol:4-8`, then lines 60, 66, 75, 80, 86, 91, 97):

```solidity
/// @dev Deliberately contains no function that lets an administrator move donor funds.
interface ICampaign {
```

```solidity
function contribute() external payable;
function deliver(uint8 milestoneId, bytes32 evidenceHash) external;
function object(uint8 milestoneId) external;
function release(uint8 milestoneId) external;
function claimRefund() external;
function withdraw() external;
function finalizeOutcome() external;
```

**Say:** The interface lists seven functions. There is no `owner`, `pause`, `upgrade`, or `sweep`. The two payout functions send ETH to a donor or to the creator.

---

## Slide 3: contribute() and deliver() (0:55-1:50)

**Code on screen** (`Campaign.sol:88-96`):

```solidity
function contribute() external payable {
    ICampaign.Status current = _sync();
    if (current != ICampaign.Status.Funding) revert WrongStatus(current);
    if (totalRaised + msg.value > goal) revert GoalAlreadyReached();
    if (msg.value == 0) revert ZeroAmount();
    totalRaised += msg.value;
    contributionOf[msg.sender] += msg.value;
    emit Contributed(msg.sender, msg.value, totalRaised);
}
```

```solidity
// Campaign.sol:111-113, inside deliver() (onlyCreator)
m.deliveredAt = uint40(block.timestamp);
m.mStatus = ICampaign.MilestoneStatus.ChallengeWindow;
emit MilestoneDelivered(milestoneId, evidenceHash,
                        uint64(m.deliveredAt) + challengeWindow);
```

**Say:** Line 91 rejects a contribution that would pass the goal. `onlyCreator` appears on `deliver()` and `withdraw()` only.

---

## Slide 4: object() and release() (1:50-2:40)

**Code on screen** (`Campaign.sol:129-140`, then lines 146-154):

```solidity
uint256 weight = contributionOf[msg.sender];
if (weight == 0) revert NotDonor();
if (hasObjected[milestoneId][msg.sender]) revert MilestoneAlreadyObjected(milestoneId);
hasObjected[milestoneId][msg.sender] = true;
m.objectionWeight += uint96(weight);
if (m.objectionWeight > totalRaised / 2) {
    m.mStatus = ICampaign.MilestoneStatus.Vetoed;
    status = ICampaign.Status.Canceled;
}
```

```solidity
// Campaign.sol:146-154, inside release() -- no access modifier
function release(uint8 milestoneId) external {
    ICampaign.Status current = _sync();
    if (current != ICampaign.Status.Active) revert WrongStatus(current);
    // checks the window, then credits creatorCredit
}
```

**Say:** The quorum compares `objectionWeight` with half of `totalRaised`. `release()` has no access modifier. The caller cannot change the amount or the destination.

---

## Slide 5: claimRefund() and withdraw() (2:40-3:20)

**Code on screen** (`Campaign.sol:172-185`, then lines 190-197):

```solidity
// claimRefund()
ICampaign.Status current = _sync();
if (current == ICampaign.Status.Funding) revert DeadlineNotReached();
if (current == ICampaign.Status.Active || current == ICampaign.Status.Completed)
    revert GoalAlreadyReached();
uint256 amount = contributionOf[msg.sender];
if (amount == 0) revert NothingToWithdraw();
contributionOf[msg.sender] = 0;              // Effects first
refundsWithdrawn += amount;
(bool ok,) = msg.sender.call{value: amount}("");  // Interaction last
if (!ok) revert TransferFailed();
```

```solidity
// withdraw() -- onlyCreator
uint256 amount = creatorCredit - creatorWithdrawn;
if (amount == 0) revert NothingToWithdraw();
creatorWithdrawn += amount;
(bool ok,) = msg.sender.call{value: amount}("");
if (!ok) revert TransferFailed();
```

**Say:** Both functions update state before the external call. A second call reverts. No function loops over donors.

---

## Slide 6: createCampaign() and the clone code (3:20-3:55)

**Code on screen** (`CampaignFactory.sol:44-62`, then lines 87-93):

```solidity
if (deadline <= block.timestamp) revert InvalidDeadline();
if (goal == 0) revert InvalidGoal();
if (milestoneAmounts.length == 0 || milestoneAmounts.length > type(uint8).max)
    revert LengthMismatch();
uint256 sum;
for (uint256 i = 0; i < milestoneAmounts.length; ++i) sum += milestoneAmounts[i];
if (sum != goal) revert AmountsDoNotSumToGoal(sum, goal);
if (msg.value != creationDeposit) revert DepositRequired(creationDeposit);
campaign = _deployClone(implementation);
Campaign(campaign).initialize{value: msg.value}(msg.sender, goal, deadline,
                                                challengeWindow, milestoneAmounts);
```

```solidity
// EIP-1167 creation code, 55 bytes
mstore(0x00, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
mstore(0x14, targetBytes)
mstore(0x28, 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
proxy := create(0, 0x00, 55)
```

**Say:** `initialize()` runs in the transaction that creates the clone. No earlier transaction contains the clone. The factory forwards the deposit and holds no campaign ETH.

---

## Slide 7: Demo and test results (3:55-5:00)

**`make demo` on Anvil**

1. Deploy factory, create campaign (10 ETH, milestones 4/3/3)
2. Donor contributes the goal
3. Deadline passes, `finalizeOutcome()`
4. Creator calls `deliver(0, hash)`
5. Window closes, **donor** calls `release(0)`
6. Creator calls `withdraw()`
7. `grep` the source: no admin function

**`make test`, green**

- 38 unit tests
- 4 fuzz invariants over a 5-actor ghost ledger
- Exact-half veto boundary tested: 5 of 10 ETH cannot cancel
- Veto cancels, refunds pay exact contributions
- Second refund and second release revert

In the demo, a donor calls `release(0)`. The creator does not. No admin role exists.

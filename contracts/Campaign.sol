// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ICampaign} from "./interfaces/ICampaign.sol";

/// @title Campaign
/// @notice One crowdfunding campaign. Holds donor ETH and releases it milestone by milestone
///         under an optimistic scheme: the creator delivers, a challenge window opens, and if
///         the objection quorum is not reached, anyone may release the milestone. A quorum
///         vetoes the milestone and cancels the campaign; funds only ever move to donors or to
///         the creator, under rules the donors accepted when they contributed.
/// @dev Deliberately contains no function that lets an administrator move donor funds. The
///         implementation is a singleton deployed by the factory; campaigns are EIP-1167
///         clones that delegatecall into it, so this contract's storage layout is the layout
///         every campaign runs on.
contract Campaign is ICampaign {
    // ----------------------------------------------------------- packed state
    /// @dev 96 + 40 + 96 + 8 = 240 bits: one storage slot per milestone, the packing the
    ///         Week 1–2 architecture document committed to.
    struct Milestone {
        uint96 amount;
        uint40 deliveredAt; // 0 until the creator delivers
        uint96 objectionWeight;
        ICampaign.MilestoneStatus mStatus;
    }

    address public creator;
    uint96 public goal;
    uint64 public deadline;
    uint32 public challengeWindow;

    Milestone[] private milestones;
    uint8 private releasedCount;

    uint256 public totalRaised;
    uint256 private refundsWithdrawn; // running sum, keeps INV-1 checkable without iterating donors
    uint256 private creatorCredit;    // released milestone amounts + the returned creation deposit
    uint256 private creatorWithdrawn;
    uint96 public lockedDeposit;      // creation deposit: returned on Completed, locked forever on Failed/Canceled

    mapping(address donor => uint256 amount) public contributionOf;
    mapping(uint8 milestoneId => mapping(address donor => bool)) private hasObjected;

    ICampaign.Status public status;
    bool private initialized;

    modifier onlyCreator() {
        if (msg.sender != creator) revert NotCreator();
        _;
    }

    /// @notice Initialises a fresh clone. The factory calls this in the same transaction that
    ///         deploys the clone, so no attacker can initialize it first (threat T11).
    /// @dev `msg.value` is the creation deposit, forwarded by the factory.
    function initialize(
        address creator_,
        uint96 goal_,
        uint64 deadline_,
        uint32 challengeWindow_,
        uint96[] calldata milestoneAmounts_
    ) external payable {
        if (initialized) revert AlreadyInitialized();
        initialized = true;
        // msg.value truncation is unreachable: the deposit is a uint96 immutable at the factory.
        lockedDeposit = uint96(msg.value);
        creator = creator_;
        goal = goal_;
        deadline = deadline_;
        challengeWindow = challengeWindow_;
        for (uint256 i = 0; i < milestoneAmounts_.length; ++i) {
            milestones.push(
                Milestone({
                    amount: milestoneAmounts_[i],
                    deliveredAt: 0,
                    objectionWeight: 0,
                    mStatus: ICampaign.MilestoneStatus.Pending
                })
            );
        }
        // `status` stays Funding, its enum default. No event: the factory emits CampaignCreated.
    }

    // ---------------------------------------------------------- contributions
    /// @notice Contribute ETH during the funding window, up to the goal. Contributions that
    ///         would push `totalRaised` past the goal revert: excess money has no exit once
    ///         the campaign activates, and the contract never accepts money it cannot return.
    function contribute() external payable {
        _sync();
        if (status != ICampaign.Status.Funding) revert WrongStatus(status);
        if (totalRaised + msg.value > goal) revert GoalAlreadyReached();
        if (msg.value == 0) revert ZeroAmount();
        totalRaised += msg.value;
        contributionOf[msg.sender] += msg.value;
        emit Contributed(msg.sender, msg.value, totalRaised);
    }

    // ------------------------------------------------------------- milestones
    /// @notice Creator attests delivery of a milestone and opens the challenge window.
    /// @param milestoneId Index into the milestone array.
    /// @param evidenceHash keccak256 of the evidence object pinned in R2. Not stored: the event
    ///         is the record, which keeps the milestone struct packed to one slot.
    function deliver(uint8 milestoneId, bytes32 evidenceHash) external onlyCreator {
        _sync();
        if (status != ICampaign.Status.Active) revert WrongStatus(status);
        if (milestoneId >= milestones.length) revert UnknownMilestone(milestoneId);
        Milestone storage m = milestones[milestoneId];
        if (m.mStatus != ICampaign.MilestoneStatus.Pending) {
            revert MilestoneAlreadyDelivered(milestoneId);
        }
        m.deliveredAt = uint40(block.timestamp);
        m.mStatus = ICampaign.MilestoneStatus.ChallengeWindow;
        emit MilestoneDelivered(milestoneId, evidenceHash, uint64(m.deliveredAt) + challengeWindow);
    }

    /// @notice Donor signals that a delivered milestone should not be paid. Weight is the
    ///         donor's contribution, fixed at funding time. Quorum = a majority of the money:
    ///         `totalRaised / 2 + 1` wei, derived here rather than stored. When the quorum is
    ///         reached the milestone is vetoed and the campaign is canceled; every donor may
    ///         then claim a full refund, and no milestone pays. Blunt by design: it needs no
    ///         oracle, and it makes frivolous objections socially expensive.
    function object(uint8 milestoneId) external {
        _sync();
        if (status != ICampaign.Status.Active) revert WrongStatus(status);
        if (milestoneId >= milestones.length) revert UnknownMilestone(milestoneId);
        Milestone storage m = milestones[milestoneId];
        if (m.mStatus != ICampaign.MilestoneStatus.ChallengeWindow) revert MilestoneNotDelivered();
        if (block.timestamp >= uint64(m.deliveredAt) + challengeWindow) revert ChallengeWindowClosed();
        uint256 weight = contributionOf[msg.sender];
        if (weight == 0) revert NotDonor();
        if (hasObjected[milestoneId][msg.sender]) revert MilestoneAlreadyObjected(milestoneId);
        hasObjected[milestoneId][msg.sender] = true;
        m.objectionWeight += uint96(weight);
        emit MilestoneObjected(milestoneId, msg.sender, weight);
        if (m.objectionWeight > totalRaised / 2) {
            m.mStatus = ICampaign.MilestoneStatus.Vetoed;
            status = ICampaign.Status.Canceled;
            emit MilestoneVetoed(milestoneId, m.objectionWeight);
            emit CampaignCanceled(milestoneId, totalRaised - refundsWithdrawn);
        }
    }

    /// @notice Release a milestone whose challenge window closed without reaching the quorum.
    ///         Callable by anyone: the caller has no discretion, so no privileged caller is
    ///         needed. A vetoed milestone never releases (INV-7).
    function release(uint8 milestoneId) external {
        _sync();
        if (status != ICampaign.Status.Active) revert WrongStatus(status);
        if (milestoneId >= milestones.length) revert UnknownMilestone(milestoneId);
        Milestone storage m = milestones[milestoneId];
        if (m.mStatus == ICampaign.MilestoneStatus.Released) revert MilestoneAlreadyReleased();
        if (m.mStatus != ICampaign.MilestoneStatus.ChallengeWindow) revert MilestoneNotDelivered();
        if (block.timestamp < uint64(m.deliveredAt) + challengeWindow) revert ChallengeWindowOpen();

        m.mStatus = ICampaign.MilestoneStatus.Released;
        creatorCredit += m.amount;
        ++releasedCount;
        emit MilestoneReleased(milestoneId, m.amount);

        if (releasedCount == milestones.length) {
            status = ICampaign.Status.Completed;
            creatorCredit += lockedDeposit; // deposit returns on completion (threat T6)
            lockedDeposit = 0;
            emit CampaignCompleted(creatorCredit);
        }
    }

    // ---------------------------------------------------------------- payouts
    /// @notice Donor withdraws their exact contribution from a failed or canceled campaign.
    ///         Repeatable in principle, idempotent in effect: the second call reverts with
    ///         `NothingToWithdraw`, and nothing moves.
    function claimRefund() external {
        _sync();
        if (status == ICampaign.Status.Funding) revert DeadlineNotReached();
        if (status == ICampaign.Status.Active || status == ICampaign.Status.Completed) revert GoalAlreadyReached();

        uint256 amount = contributionOf[msg.sender];
        if (amount == 0) revert NothingToWithdraw();
        // Checks-Effects-Interactions: zero the claim and account before any transfer (T1).
        contributionOf[msg.sender] = 0;
        refundsWithdrawn += amount;
        emit RefundClaimed(msg.sender, amount);
        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    /// @notice Pull accumulated creator credit: released milestone amounts plus the returned
    ///         creation deposit. Pull-over-push: the contract never pushes ETH to the creator,
    ///         so a hostile creator contract cannot re-enter anything (T2).
    function withdraw() external onlyCreator {
        uint256 amount = creatorCredit - creatorWithdrawn;
        if (amount == 0) revert NothingToWithdraw();
        creatorWithdrawn += amount;
        emit Withdrawn(msg.sender, amount);
        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    // ---------------------------------------------------------- state machine
    /// @notice Materializes the outcome at or after the deadline. Anyone may call it: the caller
    ///         has no discretion, so no privileged caller is needed. Exists so the indexer
    ///         receives the transition event even when no donor or creator acts.
    function finalizeOutcome() external {
        _sync();
        if (status == ICampaign.Status.Funding) revert DeadlineNotReached();
    }

    /// @dev Lazy state transition. Failed and Active are only real once the deadline has
    ///         passed; until then the campaign is Funding, whatever the raised amount. Once
    ///         Failed, nothing returns to Funding or Active (INV-6); once Canceled, nothing
    ///         returns to Active (INV-7).
    function _sync() internal {
        if (status == ICampaign.Status.Funding && block.timestamp >= deadline) {
            if (totalRaised >= goal) {
                status = ICampaign.Status.Active;
                emit CampaignActivated(totalRaised);
            } else {
                status = ICampaign.Status.Failed;
                emit CampaignFailed(totalRaised);
            }
        }
    }

    // ------------------------------------------------------------------ views
    function milestoneCount() external view returns (uint8) {
        return uint8(milestones.length);
    }

    function milestoneStatus(uint8 milestoneId) external view returns (ICampaign.MilestoneStatus) {
        if (milestoneId >= milestones.length) revert UnknownMilestone(milestoneId);
        return milestones[milestoneId].mStatus;
    }
}

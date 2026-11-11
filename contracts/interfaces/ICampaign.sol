// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title ICampaign
/// @notice Public interface of one crowdfunding campaign. Implementation lands in Week 3.
/// @dev Deliberately contains no function that lets an administrator move donor funds.
interface ICampaign {
    enum Status {
        Funding,        // contributions accepted until deadline
        Failed,         // deadline passed, goal missed, refunds open forever
        Active,         // goal met, milestones in progress
        Canceled,       // objection quorum reached; milestone rejected, refunds open forever
        Completed       // every milestone released and paid
    }

    enum MilestoneStatus {
        Pending,        // nothing delivered yet
        ChallengeWindow,// creator delivered, donors may object
        Vetoed,         // objection quorum reached; the milestone will never pay
        Released        // escrow credited to the creator
    }

    // ---------------------------------------------------------------- events
    event Contributed(address indexed donor, uint256 amount, uint256 totalRaised);
    event MilestoneDelivered(uint8 indexed milestoneId, bytes32 evidenceHash, uint64 windowEndsAt);
    event MilestoneObjected(uint8 indexed milestoneId, address indexed donor, uint256 weight);
    event MilestoneVetoed(uint8 indexed milestoneId, uint256 objectionWeight);
    event CampaignCanceled(uint8 indexed milestoneId, uint256 refundableTotal);
    event MilestoneReleased(uint8 indexed milestoneId, uint256 amount);
    event RefundClaimed(address indexed donor, uint256 amount);
    event Withdrawn(address indexed payee, uint256 amount);
    event CampaignFailed(uint256 totalRaised);
    event CampaignActivated(uint256 totalRaised);
    event CampaignCompleted(uint256 totalPaidToCreator);

    // ---------------------------------------------------------------- errors
    error DeadlineNotReached();
    error GoalAlreadyReached();
    error NotCreator();
    error NotDonor();
    error MilestoneNotDelivered();
    error MilestoneAlreadyDelivered(uint8 milestoneId);
    error MilestoneAlreadyReleased();
    error MilestoneAlreadyObjected(uint8 milestoneId);
    error UnknownMilestone(uint8 milestoneId);
    error ChallengeWindowOpen();
    error ChallengeWindowClosed();
    error WrongStatus(Status current);
    error NothingToWithdraw();
    error AlreadyInitialized();
    error TransferFailed();
    error ZeroAmount();
    error LengthMismatch();

    // ---------------------------------------------------------- contributions
    /// @notice Contribute ETH during the funding window, up to the goal. Reverts outside
    ///         `Funding` and once the contribution would exceed the goal: excess money would
    ///         have no exit in `Active`, so the contract never accepts it.
    function contribute() external payable;

    // ------------------------------------------------------------- milestones
    /// @notice Creator attests delivery of a milestone and opens the challenge window.
    /// @param milestoneId Index into the milestone array.
    /// @param evidenceHash keccak256 of the evidence object pinned in R2.
    function deliver(uint8 milestoneId, bytes32 evidenceHash) external;

    /// @notice Donor signals that a delivered milestone should not be paid. Weight is the donor's
    ///         contribution, fixed at funding time. When the objection quorum is reached, the
    ///         milestone is vetoed and the campaign is canceled: every donor may claim a full
    ///         refund, and no milestone pays. The veto is deliberately blunt: it needs no oracle,
    ///         and it makes frivolous objections socially expensive.
    /// @dev Quorum = a majority of the money: `totalRaised / 2 + 1` wei of objection weight.
    ///         Derived from `totalRaised` at veto time; never stored, never configured.
    function object(uint8 milestoneId) external;

    /// @notice Release a milestone whose challenge window closed without a quorum. Callable by
    ///         anyone: the caller has no discretion, so no privileged caller is needed. Requires
    ///         the campaign to still be `Active`; a vetoed milestone never releases.
    function release(uint8 milestoneId) external;

    // ---------------------------------------------------------------- payouts
    /// @notice Donor withdraws their exact contribution from a failed or canceled campaign.
    ///         Repeatable in principle, idempotent in effect: the second call reverts and
    ///         nothing moves.
    function claimRefund() external;

    /// @notice Pull accumulated creator credit: released milestone amounts plus the returned
    ///         creation deposit. Pull-over-push: the contract never pushes ETH to the creator,
    ///         so a hostile creator contract cannot re-enter anything.
    function withdraw() external;

    // ------------------------------------------------------------------ views
    /// @notice Materializes the outcome at or after the deadline. Anyone may call it: the caller
    ///         has no discretion, so no privileged caller is needed. The indexer receives the
    ///         Funding → Active/Failed event even when no donor or creator acts.
    function finalizeOutcome() external;

    function status() external view returns (Status);
    function goal() external view returns (uint96);
    function deadline() external view returns (uint64);
    function totalRaised() external view returns (uint256);
    function creator() external view returns (address);
    function contributionOf(address donor) external view returns (uint256);
    function milestoneCount() external view returns (uint8);
    function milestoneStatus(uint8 milestoneId) external view returns (MilestoneStatus);
}

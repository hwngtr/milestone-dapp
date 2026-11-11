// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title ICampaignFactory
/// @notice Creates and indexes campaigns. Holds no funds and has no power over a campaign.
interface ICampaignFactory {
    event CampaignCreated(
        address indexed campaign,
        address indexed creator,
        string title,
        uint96 goal,
        uint64 deadline,
        uint256 creationDeposit
    );

    error InvalidDeadline();
    error InvalidGoal();
    error InvalidChallengeWindow();
    error LengthMismatch();
    error AmountsDoNotSumToGoal(uint256 sum, uint256 goal);
    error DepositRequired(uint256 expected);

    /// @notice Deploy a campaign as an EIP-1167 minimal clone.
    /// @dev Milestone amounts must sum to `goal`, and `deadline` must be in the future.
    function createCampaign(
        string calldata title,
        string calldata metadataURI,
        uint96 goal,
        uint64 deadline,
        uint96[] calldata milestoneAmounts,
        uint32 challengeWindow
    ) external payable returns (address campaign);

    function implementation() external view returns (address);
    function campaignCount() external view returns (uint256);
    function campaignAt(uint256 index) external view returns (address);
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ICampaignFactory} from "./interfaces/ICampaignFactory.sol";
import {ICampaign} from "./interfaces/ICampaign.sol";
import {Campaign} from "./Campaign.sol";

/// @title CampaignFactory
/// @notice Creates and indexes campaigns as EIP-1167 minimal clones. Holds no funds and has no
///         power over a campaign: there is no function here that can move a campaign's ETH,
///         pause it, or upgrade it. The only money this contract ever touches is the creation
///         deposit, which it forwards to the clone at initialization and never sees again.
/// @dev The deployer chooses the deposit size once, at deployment. It is immutable, so no key
///         retains ongoing authority over spam protection.
contract CampaignFactory is ICampaignFactory {
    /// @notice The implementation every clone delegates to. Deployed once, immutable, never upgraded.
    address public immutable implementation;

    /// @notice Exact ETH a creator must attach to createCampaign. Returned on completion,
    ///         forfeited (locked in the campaign forever) on failure.
    uint96 public immutable creationDeposit;

    address[] private _campaigns;

    constructor(uint96 deposit_) {
        if (deposit_ == 0) revert InvalidGoal(); // a zero deposit buys no spam resistance
        implementation = address(new Campaign());
        creationDeposit = deposit_;
    }

    /// @notice Deploy a campaign as an EIP-1167 minimal clone and initialise it in the same
    ///         transaction. Same-transaction initialisation closes the clone-initialisation
    ///         takeover race (T11): no attacker can initialise a clone before its factory does,
    ///         because the clone does not exist in any earlier transaction.
    /// @dev Milestone amounts must sum to `goal`, `deadline` must be in the future, and
    ///         `msg.value` must equal `creationDeposit` exactly.
    function createCampaign(
        string calldata title,
        string calldata _metadataURI, // event-only: files live in R2, hashes on-chain
        uint96 goal,
        uint64 deadline,
        uint96[] calldata milestoneAmounts,
        uint32 challengeWindow
    ) external payable returns (address campaign) {
        if (deadline <= block.timestamp) revert InvalidDeadline();
        if (goal == 0) revert InvalidGoal();
        if (challengeWindow == 0) revert InvalidChallengeWindow();
        if (milestoneAmounts.length == 0 || milestoneAmounts.length > type(uint8).max) {
            revert LengthMismatch();
        }

        uint256 sum;
        for (uint256 i = 0; i < milestoneAmounts.length; ++i) {
            sum += milestoneAmounts[i];
        }
        if (sum != goal) revert AmountsDoNotSumToGoal(sum, goal);
        if (msg.value != creationDeposit) revert DepositRequired(creationDeposit);

        campaign = _deployClone(implementation);
        _campaigns.push(campaign);
        Campaign(campaign).initialize{value: msg.value}(
            msg.sender, goal, deadline, challengeWindow, milestoneAmounts
        );

        emit CampaignCreated(campaign, msg.sender, title, goal, deadline, msg.value);
        // metadataURI is event-only: the report's read path stores files in R2 and anchors
        // their hashes on-chain, so the chain never stores a string it cannot use.
    }

    function campaignCount() external view returns (uint256) {
        return _campaigns.length;
    }

    function campaignAt(uint256 index) external view returns (address) {
        return _campaigns[index];
    }

    /// @dev Standard EIP-1167 minimal proxy: 55-byte creation code, delegatecalls everything to
    ///         the implementation. No storage collision risk with the implementation because the
    ///         implementation is never initialized.
    function _deployClone(address target) internal returns (address proxy) {
        bytes20 targetBytes = bytes20(target);
        assembly {
            // EIP-1167 creation code, 55 bytes:
            //   0x00-0x09 creation prefix, 0x0a-0x13 dispatcher,
            //   0x14-0x27 target address, 0x28-0x36 forwarder tail.
            // The runtime returned to the chain is creation[0x0a:0x37] = 45 bytes.
            mstore(0x00, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            // A bytes20 value is left-aligned in a 256-bit word, so it lands at offset 0x14
            // as-is; no shift is needed (and shl(96) would push it out of the word).
            mstore(0x14, targetBytes)
            mstore(0x28, 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            proxy := create(0, 0x00, 55)
        }
    }
}

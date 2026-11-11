// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {CampaignFactory} from "../contracts/CampaignFactory.sol";
import {ICampaign} from "../contracts/interfaces/ICampaign.sol";

/// @notice Week 3 invariants over funding and refunds. The fuzzer drives arbitrary sequences of
///         contributions, refunds, warps, and finalizations against one campaign; the
///         invariants must hold after every sequence. Milestone handlers join this suite in
///         Week 4, extending INV-1 across releases.
contract CampaignInvariantsTest is Test {
    uint96 internal constant DEPOSIT = 0.01 ether;
    uint96 internal constant GOAL = 10 ether;
    uint64 internal constant START = 1_800_000_000;

    ICampaign internal campaign;
    address[5] internal actors;

    // ghost ledger: the source of truth the contract's accounting is checked against
    uint256[5] internal ghostContributed;
    uint256[5] internal ghostWithdrawn;
    uint256 internal ghostTotalContributed;
    uint256 internal ghostTotalRefunded;
    uint256 internal ghostLastTotalRaised;

    function setUp() public {
        vm.warp(START);
        CampaignFactory factory = new CampaignFactory(DEPOSIT);
        vm.deal(address(this), DEPOSIT); // the test contract pays the creation deposit
        for (uint256 i = 0; i < 5; ++i) {
            actors[i] = makeAddr(string.concat("actor", vm.toString(i)));
            vm.deal(actors[i], 1_000 ether);
        }
        // actor 0 is the creator: it must exist before the factory pranks it.
        vm.prank(actors[0]); // the creator never contributes to its own campaign
        factory.createCampaign{value: DEPOSIT}(
            "invariant campaign",
            "r2://uri",
            GOAL,
            START + 7 days,
            _milestones(),
            5 days
        );
        campaign = ICampaign(factory.campaignAt(0));
        ghostLastTotalRaised = 0;
    }

    function _milestones() internal pure returns (uint96[] memory a) {
        a = new uint96[](3);
        a[0] = 4 ether;
        a[1] = 3 ether;
        a[2] = 3 ether;
    }

    // ------------------------------------------------------------ handlers

    function contribute(uint256 actorSeed, uint256 amount) external {
        uint256 i = bound(actorSeed, 0, 4);
        if (i == 0) return; // the creator does not contribute to their own campaign
        amount = bound(amount, 0.01 ether, 2 ether);
        vm.prank(actors[i]);
        (bool ok,) = address(campaign).call{value: amount}(
            abi.encodeCall(ICampaign.contribute, ())
        );
        if (ok) {
            ghostContributed[i] += amount;
            ghostTotalContributed += amount;
            ghostLastTotalRaised = campaign.totalRaised();
        }
    }

    function claimRefund(uint256 actorSeed) external {
        uint256 i = bound(actorSeed, 0, 4);
        uint256 owed = campaign.contributionOf(actors[i]);
        if (owed == 0) return;
        vm.prank(actors[i]);
        (bool ok,) = address(campaign).call(abi.encodeCall(ICampaign.claimRefund, ()));
        if (ok) {
            ghostWithdrawn[i] += owed;
            ghostTotalRefunded += owed;
        }
    }

    function warp(uint256 timestamp) external {
        vm.warp(bound(timestamp, START, START + 9 days));
    }

    function finalize() external {
        try ICampaign(campaign).finalizeOutcome() {} catch {}
    }

    // ---------------------------------------------------------- invariants

    /// @notice INV-1, exact form for Week 3: with no releases and no forced ETH, the balance
    ///         must equal the locked deposit plus raised money minus refunded money. The
    ///         documented inequality `balance >= totalRaised - creatorWithdrawn -
    ///         refundsWithdrawn` follows a fortiori, and the forced-ETH case is covered by the
    ///         inequality in Week 4's extended suite.
    function invariant_INV1_balanceMatchesLedger() public view {
        assertEq(
            address(campaign).balance,
            DEPOSIT + campaign.totalRaised() - ghostTotalRefunded,
            "balance drifted from totalRaised minus refunds"
        );
    }

    /// @notice INV-2: no actor ever withdraws more than they contributed.
    function invariant_INV2_refundNeverExceedsContribution() public view {
        for (uint256 i = 0; i < 5; ++i) {
            assertLe(
                ghostWithdrawn[i],
                ghostContributed[i],
                "an actor withdrew more than they contributed"
            );
        }
    }

    /// @notice INV-3: totalRaised never decreases during the campaign's life.
    function invariant_INV3_totalRaisedMonotone() public view {
        assertGe(campaign.totalRaised(), ghostLastTotalRaised, "totalRaised decreased");
    }

    /// @notice Cross-check: the contract's totalRaised must equal the sum of accepted
    ///         contributions. Catches lost or duplicated accounting directly.
    function invariant_ledgerAgreement() public view {
        assertEq(
            campaign.totalRaised(),
            ghostTotalContributed,
            "totalRaised lost or duplicated a contribution"
        );
    }
}

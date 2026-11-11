// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {CampaignFactory} from "../contracts/CampaignFactory.sol";
import {Campaign} from "../contracts/Campaign.sol";
import {ICampaign} from "../contracts/interfaces/ICampaign.sol";
import {ICampaignFactory} from "../contracts/interfaces/ICampaignFactory.sol";

/// @notice Week 3 unit suite: factory validation, funding, refunds, and the core payout path.
///         Milestone tests here cover the happy path and the veto⇒cancel rule so the state
///         machine is never untested; the exhaustive Week 4 suite builds on these.
contract CampaignCoreTest is Test {
    uint96 internal constant DEPOSIT = 0.01 ether;
    uint96 internal constant GOAL = 10 ether;
    uint64 internal constant FUNDING_PERIOD = 7 days;
    uint32 internal constant WINDOW = 5 days;

    CampaignFactory internal factory;
    ICampaign internal campaign;

    address internal creator = makeAddr("creator");
    address internal donor1 = makeAddr("donor1");
    address internal donor2 = makeAddr("donor2");
    address internal donor3 = makeAddr("donor3");
    address internal stranger = makeAddr("stranger");

    function setUp() public {
        vm.warp(1_800_000_000);
        vm.deal(address(this), 1000 ether); // the test contract pays creation deposits
        factory = new CampaignFactory(DEPOSIT);
        campaign = ICampaign(_createCampaign());
    }

    // ------------------------------------------------------------ helpers

    function _milestones() internal pure returns (uint96[] memory a) {
        a = new uint96[](3);
        a[0] = 4 ether;
        a[1] = 3 ether;
        a[2] = 3 ether;
    }

    function _createCampaign() internal returns (address c) {
        vm.deal(creator, 1000 ether); // prank + value: the pranked account funds the deposit
        vm.prank(creator);
        factory.createCampaign{value: DEPOSIT}(
            "Milestone test campaign",
            "r2://uri",
            GOAL,
            uint64(block.timestamp + FUNDING_PERIOD),
            _milestones(),
            WINDOW
        );
        c = factory.campaignAt(factory.campaignCount() - 1);
    }

    function _contribute(address donor, uint96 amount) internal {
        vm.deal(donor, amount);
        vm.prank(donor);
        (bool ok,) = address(campaign).call{value: amount}(
            abi.encodeCall(ICampaign.contribute, ())
        );
        require(ok, "contribute reverted");
    }

    // ------------------------------------------------------------ factory

    function test_RevertWhen_GoalIsZero() public {
        vm.prank(creator);
        vm.expectRevert(ICampaignFactory.InvalidGoal.selector);
        factory.createCampaign{value: DEPOSIT}(
            "t", "u", 0, uint64(block.timestamp + 1 days), _milestones(), WINDOW
        );
    }

    function test_RevertWhen_DeadlineInPast() public {
        vm.prank(creator);
        vm.expectRevert(ICampaignFactory.InvalidDeadline.selector);
        factory.createCampaign{value: DEPOSIT}(
            "t", "u", GOAL, uint64(block.timestamp), _milestones(), WINDOW
        );
    }

    function test_RevertWhen_ChallengeWindowIsZero() public {
        vm.prank(creator);
        vm.expectRevert(ICampaignFactory.InvalidChallengeWindow.selector);
        factory.createCampaign{value: DEPOSIT}(
            "t", "u", GOAL, uint64(block.timestamp + 1 days), _milestones(), 0
        );
    }

    function test_RevertWhen_MilestonesEmpty() public {
        uint96[] memory empty = new uint96[](0);
        vm.prank(creator);
        vm.expectRevert(ICampaignFactory.LengthMismatch.selector);
        factory.createCampaign{value: DEPOSIT}(
            "t", "u", GOAL, uint64(block.timestamp + 1 days), empty, WINDOW
        );
    }

    function test_RevertWhen_MilestonesDoNotSumToGoal() public {
        uint96[] memory wrong = new uint96[](2);
        wrong[0] = 4 ether;
        wrong[1] = 3 ether;
        vm.prank(creator);
        vm.expectRevert(
            abi.encodeWithSelector(ICampaignFactory.AmountsDoNotSumToGoal.selector, 7 ether, GOAL)
        );
        factory.createCampaign{value: DEPOSIT}(
            "t", "u", GOAL, uint64(block.timestamp + 1 days), wrong, WINDOW
        );
    }

    function test_RevertWhen_DepositIsWrong() public {
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(ICampaignFactory.DepositRequired.selector, DEPOSIT));
        factory.createCampaign{value: DEPOSIT - 1}(
            "t", "u", GOAL, uint64(block.timestamp + 1 days), _milestones(), WINDOW
        );
    }

    function test_RevertWhen_FactoryDepositIsZero() public {
        vm.expectRevert(ICampaignFactory.InvalidGoal.selector);
        new CampaignFactory(0);
    }

    function test_CreateCampaign() public {
        assertEq(factory.campaignCount(), 1);
        assertEq(factory.campaignAt(0), address(campaign));
        assertEq(campaign.creator(), creator);
        assertEq(campaign.goal(), GOAL);
        assertEq(uint8(campaign.status()), uint8(ICampaign.Status.Funding));
        assertEq(campaign.milestoneCount(), 3);
        assertEq(uint8(campaign.milestoneStatus(0)), uint8(ICampaign.MilestoneStatus.Pending));
        assertEq(address(campaign).balance, DEPOSIT, "deposit must be locked in the clone");

        // Topic 1 (campaign address) is skipped: it is the new clone's address, unknowable
        // before the call. Everything else must match.
        vm.expectEmit(false, true, true, true, address(factory));
        emit ICampaignFactory.CampaignCreated(
            address(1), creator, "x", GOAL, uint64(block.timestamp + FUNDING_PERIOD), DEPOSIT
        );
        vm.prank(creator);
        factory.createCampaign{value: DEPOSIT}(
            "x", "u", GOAL, uint64(block.timestamp + FUNDING_PERIOD), _milestones(), WINDOW
        );
    }

    function test_CloneCannotBeReinitialized() public {
        // Threat T11: a second initialize must never succeed.
        vm.expectRevert(ICampaign.AlreadyInitialized.selector);
        Campaign(address(campaign)).initialize(
            stranger, GOAL, uint64(block.timestamp + 1), 1, _milestones()
        );
    }

    function test_CloneDelegatesToImplementation() public view {
        // EIP-1167 runtime bytecode must delegate to the factory's immutable implementation.
        bytes memory code = address(campaign).code;
        assertEq(code.length, 45, "EIP-1167 runtime is 45 bytes");
        assertTrue(_codeContains(code, bytes20(factory.implementation())));
    }

    function _codeContains(bytes memory code, bytes20 target) internal pure returns (bool) {
        for (uint256 i = 0; i + 20 <= code.length; ++i) {
            bool match_ = true;
            for (uint256 j = 0; j < 20; ++j) {
                if (code[i + j] != target[j]) {
                    match_ = false;
                    break;
                }
            }
            if (match_) return true;
        }
        return false;
    }

    // -------------------------------------------------------- contributions

    function test_ContributeRecordsWeight() public {
        vm.expectEmit(true, true, true, true, address(campaign));
        emit ICampaign.Contributed(donor1, 2 ether, 2 ether);
        _contribute(donor1, 2 ether);
        assertEq(campaign.totalRaised(), 2 ether);
        assertEq(campaign.contributionOf(donor1), 2 ether);
        assertEq(uint8(campaign.status()), uint8(ICampaign.Status.Funding), "Active waits for the deadline");
    }

    function test_ContributeAccumulatesPerDonor() public {
        _contribute(donor1, 2 ether);
        _contribute(donor1, 1 ether);
        assertEq(campaign.contributionOf(donor1), 3 ether);
        assertEq(campaign.totalRaised(), 3 ether);
    }

    function test_RevertWhen_ContributeZero() public {
        vm.deal(donor1, 1 ether);
        vm.prank(donor1);
        vm.expectRevert(ICampaign.ZeroAmount.selector);
        campaign.contribute{value: 0}();
    }

    function test_RevertWhen_ContributeAfterDeadlineWhenGoalMet() public {
        _contribute(donor1, GOAL);
        vm.warp(block.timestamp + FUNDING_PERIOD);
        vm.expectEmit(true, true, true, true, address(campaign));
        emit ICampaign.CampaignActivated(GOAL);
        campaign.finalizeOutcome();
        assertEq(uint8(campaign.status()), uint8(ICampaign.Status.Active));

        vm.deal(donor2, 1 ether);
        vm.prank(donor2);
        vm.expectRevert(abi.encodeWithSelector(ICampaign.WrongStatus.selector, ICampaign.Status.Active));
        campaign.contribute{value: 1 ether}();
    }

    function test_RevertWhen_ContributeAfterDeadlineWhenGoalMissed() public {
        _contribute(donor1, 1 ether);
        vm.warp(block.timestamp + FUNDING_PERIOD);
        vm.expectEmit(true, true, true, true, address(campaign));
        emit ICampaign.CampaignFailed(1 ether);
        campaign.finalizeOutcome();
        assertEq(uint8(campaign.status()), uint8(ICampaign.Status.Failed));

        vm.deal(donor2, 1 ether);
        vm.prank(donor2);
        vm.expectRevert(abi.encodeWithSelector(ICampaign.WrongStatus.selector, ICampaign.Status.Failed));
        campaign.contribute{value: 1 ether}();
    }

    function test_FinalizeIsPermissionlessAndIdempotent() public {
        _contribute(donor1, GOAL);
        vm.warp(block.timestamp + FUNDING_PERIOD);
        vm.prank(stranger); // no privilege needed: the caller has no discretion
        campaign.finalizeOutcome();
        campaign.finalizeOutcome(); // second call is a no-op, not a second transition
        assertEq(uint8(campaign.status()), uint8(ICampaign.Status.Active));
    }

    function test_RevertWhen_FinalizeBeforeDeadline() public {
        vm.expectRevert(ICampaign.DeadlineNotReached.selector);
        campaign.finalizeOutcome();
    }

    function test_FailedIsTerminal() public {
        // INV-6: once Failed, nothing returns to Funding or Active.
        _contribute(donor1, 1 ether);
        vm.warp(block.timestamp + FUNDING_PERIOD);
        campaign.finalizeOutcome();
        vm.warp(block.timestamp + 1 days);
        campaign.finalizeOutcome();
        vm.deal(donor2, 1 ether);
        vm.prank(donor2);
        vm.expectRevert(abi.encodeWithSelector(ICampaign.WrongStatus.selector, ICampaign.Status.Failed));
        campaign.contribute{value: 1 ether}();
        assertEq(uint8(campaign.status()), uint8(ICampaign.Status.Failed));
    }

    // ------------------------------------------------------------- refunds

    function test_RevertWhen_ClaimBeforeDeadline() public {
        _contribute(donor1, 1 ether);
        vm.prank(donor1);
        vm.expectRevert(ICampaign.DeadlineNotReached.selector);
        campaign.claimRefund();
    }

    function test_RevertWhen_ClaimWhenGoalWasMet() public {
        _contribute(donor1, GOAL);
        vm.warp(block.timestamp + FUNDING_PERIOD);
        campaign.finalizeOutcome();
        vm.prank(donor1);
        vm.expectRevert(ICampaign.GoalAlreadyReached.selector);
        campaign.claimRefund();
    }

    function test_ClaimRefundReturnsExactContribution() public {
        _contribute(donor1, 2 ether);
        _contribute(donor2, 1 ether);
        vm.warp(block.timestamp + FUNDING_PERIOD);
        campaign.finalizeOutcome(); // Failed: 3 < 10

        uint256 before = donor1.balance;
        vm.expectEmit(true, true, true, true, address(campaign));
        emit ICampaign.RefundClaimed(donor1, 2 ether);
        vm.prank(donor1);
        campaign.claimRefund();
        assertEq(donor1.balance, before + 2 ether, "refund must be exact");
        assertEq(campaign.contributionOf(donor1), 0);
        assertEq(address(campaign).balance, DEPOSIT + 1 ether, "only donor2's share remains");
    }

    function test_RevertWhen_DoubleClaim() public {
        _contribute(donor1, 2 ether);
        vm.warp(block.timestamp + FUNDING_PERIOD);
        campaign.finalizeOutcome();
        vm.startPrank(donor1);
        campaign.claimRefund();
        vm.expectRevert(ICampaign.NothingToWithdraw.selector);
        campaign.claimRefund();
        vm.stopPrank();
    }

    function test_RevertWhen_ClaimByStranger() public {
        vm.warp(block.timestamp + FUNDING_PERIOD);
        campaign.finalizeOutcome();
        vm.prank(stranger);
        vm.expectRevert(ICampaign.NothingToWithdraw.selector);
        campaign.claimRefund();
    }

    // ------------------------------------------------------------ withdraw

    function test_RevertWhen_WithdrawByNonCreator() public {
        vm.prank(stranger);
        vm.expectRevert(ICampaign.NotCreator.selector);
        campaign.withdraw();
    }

    function test_RevertWhen_WithdrawWithNoCredit() public {
        vm.prank(creator);
        vm.expectRevert(ICampaign.NothingToWithdraw.selector);
        campaign.withdraw();
    }

    // ------------------------------------------------- milestone lifecycle

    function _activate() internal {
        _contribute(donor1, 4 ether);
        _contribute(donor2, 3 ether);
        _contribute(donor3, 3 ether); // exactly the 10-ether goal
        vm.warp(block.timestamp + FUNDING_PERIOD);
        campaign.finalizeOutcome();
    }

    function test_RevertWhen_DeliverDuringFunding() public {
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(ICampaign.WrongStatus.selector, ICampaign.Status.Funding));
        campaign.deliver(0, keccak256("evidence"));
    }

    function test_RevertWhen_DeliverByNonCreator() public {
        _activate();
        vm.prank(stranger);
        vm.expectRevert(ICampaign.NotCreator.selector);
        campaign.deliver(0, keccak256("evidence"));
    }

    function test_RevertWhen_DeliverUnknownMilestone() public {
        _activate();
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(ICampaign.UnknownMilestone.selector, 3));
        campaign.deliver(3, keccak256("evidence"));
    }

    function test_DeliverOpensChallengeWindow() public {
        _activate();
        vm.prank(creator);
        vm.expectEmit(true, true, true, true, address(campaign));
        emit ICampaign.MilestoneDelivered(0, keccak256("evidence"), uint64(block.timestamp) + WINDOW);
        campaign.deliver(0, keccak256("evidence"));
        assertEq(uint8(campaign.milestoneStatus(0)), uint8(ICampaign.MilestoneStatus.ChallengeWindow));
    }

    function test_RevertWhen_ReleaseBeforeWindowEnds() public {
        _activate();
        vm.prank(creator);
        campaign.deliver(0, keccak256("evidence"));
        vm.expectRevert(ICampaign.ChallengeWindowOpen.selector);
        campaign.release(0);
    }

    function test_ReleasePaysCreator() public {
        _activate();
        vm.prank(creator);
        campaign.deliver(0, keccak256("evidence"));
        vm.warp(block.timestamp + WINDOW + 1);
        vm.prank(stranger); // permissionless release: no privileged caller exists
        campaign.release(0);
        assertEq(uint8(campaign.milestoneStatus(0)), uint8(ICampaign.MilestoneStatus.Released));

        uint256 before = creator.balance;
        vm.prank(creator);
        campaign.withdraw();
        assertEq(creator.balance, before + 4 ether);
        assertEq(address(campaign).balance, DEPOSIT + 6 ether);
    }

    function test_RevertWhen_ReleaseTwice() public {
        _activate();
        vm.prank(creator);
        campaign.deliver(0, keccak256("evidence"));
        vm.warp(block.timestamp + WINDOW + 1);
        campaign.release(0);
        vm.expectRevert(ICampaign.MilestoneAlreadyReleased.selector);
        campaign.release(0);
    }

    function test_CompletionReturnsDepositToCreator() public {
        _activate();
        for (uint8 i = 0; i < 3; ++i) {
            vm.prank(creator);
            campaign.deliver(i, keccak256(abi.encode("evidence", i)));
            vm.warp(block.timestamp + WINDOW + 1);
            campaign.release(i);
        }
        assertEq(uint8(campaign.status()), uint8(ICampaign.Status.Completed));
        assertEq(Campaign(address(campaign)).lockedDeposit(), 0, "deposit leaves escrow at completion");

        uint256 before = creator.balance;
        vm.prank(creator);
        campaign.withdraw(); // 4 + 3 + 3 milestone credit + 0.01 deposit
        assertEq(creator.balance, before + 10.01 ether);
        assertEq(address(campaign).balance, 0);
    }

    // ---------------------------------------------------- veto => cancel

    function test_VetoCancelsCampaignAndRefundsEveryone() public {
        _activate(); // donor1 4, donor2 3.5, donor3 3; quorum bar = 5.25
        vm.prank(creator);
        campaign.deliver(0, keccak256("evidence"));

        vm.prank(donor1);
        campaign.object(0); // 4 < 5.25: not yet
        assertEq(uint8(campaign.status()), uint8(ICampaign.Status.Active));

        vm.expectEmit(true, true, true, true, address(campaign));
        emit ICampaign.CampaignCanceled(0, 10 ether);
        vm.prank(donor2);
        campaign.object(0); // 7 > 5: quorum
        assertEq(uint8(campaign.status()), uint8(ICampaign.Status.Canceled));
        assertEq(uint8(campaign.milestoneStatus(0)), uint8(ICampaign.MilestoneStatus.Vetoed));

        // A vetoed milestone never releases (INV-7).
        vm.warp(block.timestamp + WINDOW + 1);
        vm.expectRevert(abi.encodeWithSelector(ICampaign.WrongStatus.selector, ICampaign.Status.Canceled));
        campaign.release(0);

        // Every donor withdraws their exact contribution.
        uint256 b1 = donor1.balance;
        uint256 b2 = donor2.balance;
        vm.prank(donor1);
        campaign.claimRefund();
        vm.prank(donor2);
        campaign.claimRefund();
        assertEq(donor1.balance, b1 + 4 ether);
        assertEq(donor2.balance, b2 + 3 ether);
        // donor3 never claimed: unclaimed funds stay in escrow, reachable forever.
        assertEq(address(campaign).balance, DEPOSIT + 3 ether);
        // The deposit is forfeited on cancel: the creator has no credit (T6).
        vm.prank(creator);
        vm.expectRevert(ICampaign.NothingToWithdraw.selector);
        campaign.withdraw();
    }

    function test_RevertWhen_ObjectTwice() public {
        _activate();
        vm.prank(creator);
        campaign.deliver(0, keccak256("evidence"));
        vm.prank(donor1);
        campaign.object(0);
        vm.prank(donor1);
        vm.expectRevert(abi.encodeWithSelector(ICampaign.MilestoneAlreadyObjected.selector, 0));
        campaign.object(0);
    }

    function test_RevertWhen_ObjectByStranger() public {
        _activate();
        vm.prank(creator);
        campaign.deliver(0, keccak256("evidence"));
        vm.prank(stranger);
        vm.expectRevert(ICampaign.NotDonor.selector);
        campaign.object(0);
    }

    function test_MajorityFunderCanVetoAlone_MinorityCannot() public {
        // Explicit geometry: the quorum rule is majority-of-money.
        _contribute(donor1, 5 ether);
        _contribute(donor2, 5 ether); // total 10, bar = 5
        vm.warp(block.timestamp + FUNDING_PERIOD);
        campaign.finalizeOutcome();
        vm.prank(creator);
        campaign.deliver(0, keccak256("evidence"));

        vm.prank(donor1);
        campaign.object(0); // 5 > 5 is false: exactly half cannot cancel alone
        assertEq(uint8(campaign.status()), uint8(ICampaign.Status.Active));

        vm.prank(donor2);
        campaign.object(0); // 10 > 5
        assertEq(uint8(campaign.status()), uint8(ICampaign.Status.Canceled));
    }

    function test_RevertWhen_ContributeBeyondGoal() public {
        _contribute(donor1, 8 ether);
        vm.deal(donor2, 3 ether);
        vm.prank(donor2);
        vm.expectRevert(ICampaign.GoalAlreadyReached.selector);
        campaign.contribute{value: 3 ether}(); // would push 11 past the 10-ether goal

        vm.deal(donor2, 2 ether);
        vm.prank(donor2);
        campaign.contribute{value: 2 ether}(); // exactly reaching the goal is fine
        vm.deal(donor3, 1 ether);
        vm.prank(donor3);
        vm.expectRevert(ICampaign.GoalAlreadyReached.selector);
        campaign.contribute{value: 1 ether}(); // goal met, window still open
    }
}

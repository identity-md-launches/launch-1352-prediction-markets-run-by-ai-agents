// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {VerdictToken} from "../src/VerdictToken.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";

/// @notice Adversarial boundaries and sequences complementing the basic ERC-20 tests.
/// forge-config: default.fuzz.runs = 1000
contract VerdictTokenEdgeCasesTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    VerdictToken internal token;
    address internal alice = makeAddr("edge-alice");
    address internal bob = makeAddr("edge-bob");
    address internal spender = makeAddr("edge-spender");

    function setUp() public {
        token = new VerdictToken();
    }

    function test_zeroTransferFromNeedsNeitherBalanceNorAllowanceAndEmits() public {
        bytes32 beforeState = _stateDigest();
        vm.expectEmit(true, true, true, true, address(token));
        emit IERC20.Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(_stateDigest(), beforeState);
    }

    function test_zeroTransfersStillRejectZeroReceiver() public {
        bytes32 beforeState = _stateDigest();
        vm.expectRevert(abi.encodeWithSelector(VerdictToken.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(VerdictToken.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(alice, address(0), 0);
        assertEq(_stateDigest(), beforeState);
    }

    function test_zeroApprovalStillRejectsZeroSpender() public {
        testFuzz_zeroSpenderApprovalIsAtomic(0);
    }

    function test_maximumApprovalStillRejectsZeroSpender() public {
        testFuzz_zeroSpenderApprovalIsAtomic(type(uint256).max);
    }

    function test_oneWeiDelegatedSelfTransferConsumesAllowance() public {
        _delegatedSelfTransfer(1, false);
    }

    function test_fullSupplyDelegatedSelfTransferConsumesAllowance() public {
        _delegatedSelfTransfer(SUPPLY, false);
    }

    function test_fullSupplyDelegatedSelfTransferKeepsUnlimitedAllowance() public {
        _delegatedSelfTransfer(SUPPLY, true);
    }

    function test_selfTransferDoesNotBypassBalanceOrAllowanceChecks() public {
        token.transfer(alice, 1);
        vm.prank(alice);
        token.approve(spender, 2);
        bytes32 beforeState = _stateDigest();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(VerdictToken.ERC20InsufficientBalance.selector, alice, 1, 2));
        token.transfer(alice, 2);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(VerdictToken.ERC20InsufficientBalance.selector, alice, 1, 2));
        token.transferFrom(alice, alice, 2);
        assertEq(_stateDigest(), beforeState);

        vm.prank(alice);
        token.approve(spender, 0);
        beforeState = _stateDigest();
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(VerdictToken.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(alice, alice, 1);
        assertEq(_stateDigest(), beforeState);
    }

    function test_maximumTransferAmountRevertsWithoutOverflowOrSpendingApproval() public {
        token.approve(spender, type(uint256).max);
        bytes32 beforeState = _stateDigest();
        bytes memory expectedError = abi.encodeWithSelector(
            VerdictToken.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
        );

        vm.expectRevert(expectedError);
        token.transfer(alice, type(uint256).max);
        vm.prank(spender);
        vm.expectRevert(expectedError);
        token.transferFrom(address(this), alice, type(uint256).max);
        assertEq(_stateDigest(), beforeState);
    }

    function test_maximumMinusOneAllowanceIsFinite() public {
        token.approve(spender, type(uint256).max - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 1 - SUPPLY);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function test_unlimitedApprovalCanBeRevokedAndReplacedWithFiniteApproval() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        token.approve(spender, 0);
        bytes32 beforeState = _stateDigest();
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(VerdictToken.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(address(this), alice, 1);
        assertEq(_stateDigest(), beforeState);

        token.approve(spender, type(uint256).max);
        token.approve(spender, 2);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 2));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), 3);
        assertEq(token.balanceOf(address(this)), SUPPLY - 3);
    }

    function test_anotherSpenderCannotUseAnExistingApproval() public {
        token.approve(spender, SUPPLY);
        bytes32 beforeState = _stateDigest();
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(VerdictToken.ERC20InsufficientAllowance.selector, bob, 0, 1));
        token.transferFrom(address(this), bob, 1);
        assertEq(_stateDigest(), beforeState);
    }

    function test_multipleApprovalsDoNotPromiseMoreThanTheOwnersBalance() public {
        token.transfer(alice, 10);
        vm.startPrank(alice);
        token.approve(spender, 10);
        token.approve(bob, 10);
        vm.stopPrank();

        vm.prank(spender);
        assertTrue(token.transferFrom(alice, spender, 10));
        bytes32 beforeState = _stateDigest();
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(VerdictToken.ERC20InsufficientBalance.selector, alice, 0, 10));
        token.transferFrom(alice, bob, 10);
        assertEq(_stateDigest(), beforeState);

        // A failed spend preserves Bob's approval; receiving new funds makes that approval usable.
        token.transfer(alice, 10);
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, bob, 10));
        assertEq(token.allowance(alice, bob), 0);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 10);
        assertEq(token.balanceOf(spender), 10);
    }

    function test_receivingMoreTokensDoesNotRestoreSpentAllowance() public {
        token.transfer(alice, 1);
        vm.prank(alice);
        token.approve(spender, 1);
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        token.transfer(alice, 1);

        bytes32 beforeState = _stateDigest();
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(VerdictToken.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(alice, bob, 1);
        assertEq(_stateDigest(), beforeState);
    }

    function test_allTokenActionsRejectEtherAndPreserveState() public {
        vm.deal(address(this), 3);
        token.approve(address(this), 1);
        bytes32 beforeState = _stateDigest();
        bytes[3] memory calls = [
            abi.encodeCall(token.transfer, (alice, 1)),
            abi.encodeCall(token.approve, (spender, 1)),
            abi.encodeCall(token.transferFrom, (address(this), alice, 1))
        ];
        for (uint256 i; i < calls.length; ++i) {
            (bool success,) = address(token).call{value: 1}(calls[i]);
            assertFalse(success, "nonpayable token action accepted ether");
            assertEq(_stateDigest(), beforeState);
        }
        assertEq(address(token).balance, 0);
        assertEq(address(this).balance, 3);
    }

    function testFuzz_zeroSpenderApprovalIsAtomic(uint256 amount) public {
        token.approve(spender, 123);
        bytes32 beforeState = _stateDigest();
        vm.expectRevert(abi.encodeWithSelector(VerdictToken.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), amount);
        assertEq(_stateDigest(), beforeState);
    }

    function testFuzz_zeroReceiverFailurePreservesFiniteOrUnlimitedAllowance(uint256 amount, bool unlimited) public {
        amount = bound(amount, 0, SUPPLY);
        token.approve(spender, unlimited ? type(uint256).max : amount);
        bytes32 beforeState = _stateDigest();
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(VerdictToken.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(address(this), address(0), amount);
        assertEq(_stateDigest(), beforeState);
    }

    function testFuzz_balanceFailurePreservesFiniteAllowance(uint256 held, uint256 attempted, uint256 approved) public {
        held = bound(held, 0, SUPPLY);
        attempted = bound(attempted, held + 1, type(uint256).max - 1);
        approved = bound(approved, attempted, type(uint256).max - 1);
        token.transfer(alice, held);
        vm.prank(alice);
        token.approve(spender, approved);
        bytes32 beforeState = _stateDigest();

        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(VerdictToken.ERC20InsufficientBalance.selector, alice, held, attempted));
        token.transferFrom(alice, bob, attempted);
        assertEq(_stateDigest(), beforeState);

        // The same approval still pays out the entire actual balance after the rejection.
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, held));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), held);
        assertEq(token.allowance(alice, spender), approved - held);
    }

    function testFuzz_allowanceFailureIsAtomicWithSufficientBalance(uint256 requested, uint256 approved) public {
        requested = bound(requested, 1, SUPPLY);
        approved = bound(approved, 0, requested - 1);
        token.approve(spender, approved);
        bytes32 beforeState = _stateDigest();
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(VerdictToken.ERC20InsufficientAllowance.selector, spender, approved, requested)
        );
        token.transferFrom(address(this), alice, requested);
        assertEq(_stateDigest(), beforeState);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, approved));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY - approved);
    }

    function testFuzz_splitSpendingExhaustsApprovalExactlyOnce(uint256 total, uint256 first) public {
        total = bound(total, 1, SUPPLY);
        first = bound(first, 0, total);
        token.approve(spender, total);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, first));
        assertEq(token.allowance(address(this), spender), total - first);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, total - first));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), first);
        assertEq(token.balanceOf(bob), total - first);
        assertEq(token.balanceOf(address(this)), SUPPLY - total);

        bytes32 beforeState = _stateDigest();
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(VerdictToken.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(address(this), alice, 1);
        assertEq(_stateDigest(), beforeState);
    }

    function testFuzz_approvalOverwriteIsIdempotentAndIsolated(uint256 oldApproval, uint256 newApproval) public {
        token.transfer(alice, 100);
        token.transfer(bob, 200);
        token.approve(spender, 11);
        vm.prank(bob);
        token.approve(spender, 22);
        vm.startPrank(alice);
        token.approve(bob, 33);
        token.approve(spender, oldApproval);
        vm.expectEmit(true, true, true, true, address(token));
        emit IERC20.Approval(alice, spender, newApproval);
        assertTrue(token.approve(spender, newApproval));
        vm.stopPrank();

        assertEq(token.allowance(alice, spender), newApproval);
        assertEq(token.allowance(address(this), spender), 11);
        assertEq(token.allowance(bob, spender), 22);
        assertEq(token.allowance(alice, bob), 33);
        assertEq(token.allowance(spender, alice), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 300);
        assertEq(token.balanceOf(alice), 100);
        assertEq(token.balanceOf(bob), 200);
        assertEq(token.balanceOf(spender), 0);

        bytes32 afterFirstApproval = _stateDigest();
        vm.prank(alice);
        assertTrue(token.approve(spender, newApproval));
        assertEq(_stateDigest(), afterFirstApproval);
    }

    function testFuzz_transferRoundTripRestoresBalancesAndPreservesApprovals(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        token.approve(spender, 42);
        vm.prank(alice);
        token.approve(spender, type(uint256).max);
        bytes32 beforeState = _stateDigest();
        assertTrue(token.transfer(alice, amount));
        vm.prank(alice);
        assertTrue(token.transfer(address(this), amount));
        assertEq(_stateDigest(), beforeState);
    }

    function testFuzz_directSelfTransferIsAnIdentity(uint256 held, uint256 amount) public {
        held = bound(held, 0, SUPPLY);
        amount = bound(amount, 0, held);
        token.transfer(alice, held);
        vm.prank(alice);
        token.approve(spender, type(uint256).max - 1);
        bytes32 beforeState = _stateDigest();
        vm.expectEmit(true, true, true, true, address(token));
        emit IERC20.Transfer(alice, alice, amount);
        vm.prank(alice);
        assertTrue(token.transfer(alice, amount));
        assertEq(_stateDigest(), beforeState);
    }

    function testFuzz_transferFromWithAliasedParticipants(uint256 amount, uint8 mode, bool unlimited) public {
        amount = bound(amount, 0, SUPPLY);
        mode %= 4;
        address caller = mode < 2 ? bob : alice;
        address recipient = mode % 2 == 0 ? bob : alice;
        token.transfer(alice, SUPPLY);
        vm.prank(alice);
        token.approve(caller, unlimited ? type(uint256).max : amount);

        vm.expectEmit(true, true, true, true, address(token));
        emit IERC20.Transfer(alice, recipient, amount);
        vm.prank(caller);
        assertTrue(token.transferFrom(alice, recipient, amount));
        assertEq(token.balanceOf(alice), recipient == alice ? SUPPLY : SUPPLY - amount);
        assertEq(token.balanceOf(bob), recipient == bob ? amount : 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.allowance(alice, caller), unlimited ? type(uint256).max : 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _delegatedSelfTransfer(uint256 amount, bool unlimited) internal {
        token.approve(spender, unlimited ? type(uint256).max : amount);
        vm.expectEmit(true, true, true, true, address(token));
        emit IERC20.Transfer(address(this), address(this), amount);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.allowance(address(this), spender), unlimited ? type(uint256).max : 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// @dev Snapshot the observable ledger, including every owner/spender pairing and the token's
    ///      own address. Failed operations must be atomic across all of it, not just the receiver.
    function _stateDigest() internal view returns (bytes32 digest) {
        address[6] memory accounts = [address(this), alice, bob, spender, address(0), address(token)];
        digest = keccak256(abi.encode(token.totalSupply()));
        for (uint256 i; i < accounts.length; ++i) {
            digest = keccak256(abi.encode(digest, token.balanceOf(accounts[i])));
            for (uint256 j; j < accounts.length; ++j) {
                digest = keccak256(abi.encode(digest, token.allowance(accounts[i], accounts[j])));
            }
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {VerdictToken} from "../src/VerdictToken.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";

/// @notice Behaviour of the token as an ERC-20: metadata, the one-time mint, transfers, approvals,
///         and every documented failure.
contract VerdictTokenTest is Test {
    uint256 constant SUPPLY = 1_000_000_000 * 10 ** 18;

    VerdictToken token;
    address deployer;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address spender = makeAddr("spender");

    function setUp() public {
        deployer = address(this);
        token = new VerdictToken();
    }

    // ------------------------------------------------------------------------------------------
    // Metadata and the constructor mint
    // ------------------------------------------------------------------------------------------

    function test_metadata() public view {
        assertEq(token.name(), "Prediction Markets Run by AI Agents");
        assertEq(token.symbol(), "VERDICT");
        assertEq(token.decimals(), 18);
    }

    function test_supplyIsOneBillionWithEighteenDecimals() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.totalSupply(), 1e27);
    }

    function test_constructorMintsWholeSupplyToDeployer() public view {
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_constructorEmitsMintTransferFromZeroToDeployer() public {
        address fresh = makeAddr("fresh-deployer");
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(address(0), fresh, SUPPLY);
        vm.prank(fresh);
        VerdictToken minted = new VerdictToken();
        assertEq(minted.balanceOf(fresh), SUPPLY);
        assertEq(minted.balanceOf(address(this)), 0);
    }

    function test_mintsToWhoeverDeploysNotToAFixedAddress() public {
        vm.prank(alice);
        VerdictToken byAlice = new VerdictToken();
        vm.prank(bob);
        VerdictToken byBob = new VerdictToken();
        assertEq(byAlice.balanceOf(alice), SUPPLY);
        assertEq(byAlice.balanceOf(bob), 0);
        assertEq(byBob.balanceOf(bob), SUPPLY);
        assertEq(byBob.balanceOf(alice), 0);
    }

    function test_freshAccountsHoldNothingAndAllowNothing() public view {
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(alice, bob), 0);
        assertEq(token.allowance(deployer, alice), 0);
    }

    // ------------------------------------------------------------------------------------------
    // transfer
    // ------------------------------------------------------------------------------------------

    function test_transferMovesExactAmountAndEmits() public {
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(deployer, alice, 1_000e18);
        assertTrue(token.transfer(alice, 1_000e18));
        assertEq(token.balanceOf(alice), 1_000e18);
        assertEq(token.balanceOf(deployer), SUPPLY - 1_000e18);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferWholeBalance() public {
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
    }

    function test_transferZeroAmountSucceedsAndEmits() public {
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferToSelfKeepsBalance() public {
        token.transfer(alice, 5e18);
        vm.prank(alice);
        assertTrue(token.transfer(alice, 5e18));
        assertEq(token.balanceOf(alice), 5e18);
    }

    function test_transferChainDeliversWhole() public {
        token.transfer(alice, 10e18);
        vm.prank(alice);
        token.transfer(bob, 10e18);
        vm.prank(bob);
        token.transfer(spender, 10e18);
        assertEq(token.balanceOf(spender), 10e18);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_RevertWhen_transferExceedsBalance() public {
        token.transfer(alice, 100);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(VerdictToken.ERC20InsufficientBalance.selector, alice, 100, 101));
        token.transfer(bob, 101);
        assertEq(token.balanceOf(alice), 100);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_RevertWhen_transferFromEmptyAccount() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(VerdictToken.ERC20InsufficientBalance.selector, alice, 0, 1));
        token.transfer(bob, 1);
    }

    function test_RevertWhen_transferToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(VerdictToken.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    // ------------------------------------------------------------------------------------------
    // approve / allowance
    // ------------------------------------------------------------------------------------------

    function test_approveSetsAllowanceAndEmits() public {
        vm.expectEmit(true, true, true, true);
        emit IERC20.Approval(deployer, spender, 42);
        assertTrue(token.approve(spender, 42));
        assertEq(token.allowance(deployer, spender), 42);
    }

    function test_approveOverwritesRatherThanAdds() public {
        token.approve(spender, 42);
        token.approve(spender, 7);
        assertEq(token.allowance(deployer, spender), 7);
        token.approve(spender, 0);
        assertEq(token.allowance(deployer, spender), 0);
    }

    function test_approveDoesNotRequireBalance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, SUPPLY));
        assertEq(token.allowance(alice, spender), SUPPLY);
    }

    function test_RevertWhen_approvingZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(VerdictToken.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    // ------------------------------------------------------------------------------------------
    // transferFrom
    // ------------------------------------------------------------------------------------------

    function test_transferFromSpendsAllowanceAndEmits() public {
        token.approve(spender, 100);
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(deployer, alice, 60);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, 60));
        assertEq(token.balanceOf(alice), 60);
        assertEq(token.balanceOf(deployer), SUPPLY - 60);
        assertEq(token.allowance(deployer, spender), 40);
    }

    function test_transferFromExactAllowanceLeavesZero() public {
        token.approve(spender, 100);
        vm.prank(spender);
        token.transferFrom(deployer, alice, 100);
        assertEq(token.allowance(deployer, spender), 0);
    }

    function test_transferFromUnlimitedAllowanceIsNotDecremented() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        token.transferFrom(deployer, alice, 1_000e18);
        assertEq(token.allowance(deployer, spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 1_000e18);
    }

    function test_transferFromByOwnerStillNeedsAllowance() public {
        // The owner is not implicitly their own spender.
        vm.expectRevert(abi.encodeWithSelector(VerdictToken.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        token.transferFrom(deployer, alice, 1);
    }

    function test_RevertWhen_transferFromExceedsAllowance() public {
        token.approve(spender, 50);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(VerdictToken.ERC20InsufficientAllowance.selector, spender, 50, 51));
        token.transferFrom(deployer, alice, 51);
        assertEq(token.allowance(deployer, spender), 50);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_RevertWhen_transferFromWithoutAnyAllowance() public {
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(VerdictToken.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(deployer, alice, 1);
    }

    function test_RevertWhen_transferFromExceedsBalanceEvenWithAllowance() public {
        token.transfer(alice, 10);
        vm.prank(alice);
        token.approve(spender, 1_000);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(VerdictToken.ERC20InsufficientBalance.selector, alice, 10, 11));
        token.transferFrom(alice, bob, 11);
        // A failed transfer leaves the allowance untouched.
        assertEq(token.allowance(alice, spender), 1_000);
    }

    function test_RevertWhen_transferFromToZeroAddress() public {
        token.approve(spender, 10);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(VerdictToken.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(deployer, address(0), 10);
        assertEq(token.allowance(deployer, spender), 10);
    }

    // ------------------------------------------------------------------------------------------
    // Fuzz: conservation
    // ------------------------------------------------------------------------------------------

    function testFuzz_transferConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0) && to != deployer);
        amount = bound(amount, 0, SUPPLY);
        token.transfer(to, amount);
        assertEq(token.balanceOf(to), amount);
        assertEq(token.balanceOf(deployer) + token.balanceOf(to), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromConservesSupplyAndAllowance(uint256 allowanceAmount, uint256 amount) public {
        allowanceAmount = bound(allowanceAmount, 0, type(uint256).max - 1);
        amount = bound(amount, 0, SUPPLY);
        token.approve(spender, allowanceAmount);
        vm.prank(spender);
        if (amount > allowanceAmount) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    VerdictToken.ERC20InsufficientAllowance.selector, spender, allowanceAmount, amount
                )
            );
            token.transferFrom(deployer, alice, amount);
            assertEq(token.balanceOf(alice), 0);
            assertEq(token.allowance(deployer, spender), allowanceAmount);
        } else {
            token.transferFrom(deployer, alice, amount);
            assertEq(token.balanceOf(alice), amount);
            assertEq(token.allowance(deployer, spender), allowanceAmount - amount);
        }
        assertEq(token.balanceOf(deployer) + token.balanceOf(alice), SUPPLY);
    }

    function testFuzz_transferMoreThanHeldAlwaysReverts(uint256 held, uint256 excess) public {
        held = bound(held, 0, SUPPLY - 1);
        excess = bound(excess, 1, SUPPLY - held);
        token.transfer(alice, held);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(VerdictToken.ERC20InsufficientBalance.selector, alice, held, held + excess)
        );
        token.transfer(bob, held + excess);
    }
}

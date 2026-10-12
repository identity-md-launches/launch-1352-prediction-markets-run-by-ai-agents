// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {VerdictToken} from "../src/VerdictToken.sol";

/// @notice What the token must never do: grow its supply, let a privileged hand move or freeze a
///         holder, or carry an opcode that lets its code be swapped or destroyed. These mirror the
///         launch floor the token is admitted against.
contract VerdictTokenSafetyTest is Test {
    uint256 constant SUPPLY = 1_000_000_000 * 10 ** 18;

    VerdictToken token;
    address deployer;
    address holder = makeAddr("holder");
    address other = makeAddr("other");
    address attacker = makeAddr("attacker");

    function setUp() public {
        deployer = address(this);
        token = new VerdictToken();
    }

    // ------------------------------------------------------------------------------------------
    // No path grows the supply
    // ------------------------------------------------------------------------------------------

    function test_noCommonAdminCallIncreasesSupply() public {
        string[10] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "unpause()",
            "setMinter(address)"
        ];
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory data = abi.encodeWithSignature(signatures[i], attacker, type(uint128).max);

            vm.prank(attacker);
            (bool okAttacker,) = address(token).call(data);
            assertFalse(okAttacker, string.concat("unexpected function exists: ", signatures[i]));

            // The deployer is the most plausible trusted address, and it has no more power than anyone.
            (bool okDeployer,) = address(token).call(data);
            assertFalse(okDeployer, string.concat("unexpected function exists for deployer: ", signatures[i]));

            assertEq(token.totalSupply(), SUPPLY, signatures[i]);
            assertEq(token.balanceOf(attacker), 0, signatures[i]);
        }
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_unknownSelectorsRevert() public {
        (bool ok,) = address(token).call(abi.encodeWithSignature("doesNotExist()"));
        assertFalse(ok);
        (ok,) = address(token).call("");
        assertFalse(ok, "the token accepts plain calls");
    }

    function test_noReceiveOrFallbackSoEtherCannotBeStranded() public {
        vm.deal(attacker, 1 ether);
        vm.prank(attacker);
        (bool ok,) = address(token).call{value: 1 ether}("");
        assertFalse(ok, "the token accepted ether");
        assertEq(address(token).balance, 0);
    }

    // ------------------------------------------------------------------------------------------
    // No privileged hand moves or freezes a holder
    // ------------------------------------------------------------------------------------------

    function test_noPrivilegedHandMovesOrFreezesAHolder() public {
        token.transfer(holder, SUPPLY / 1_000);
        uint256 held = token.balanceOf(holder);
        assertGt(held, 0);

        string[12] memory signatures = [
            "pause()",
            "blacklist(address)",
            "blocklist(address)",
            "freeze(address)",
            "freezeAccount(address)",
            "setBlacklist(address,bool)",
            "setBlocked(address,bool)",
            "lock(address)",
            "disableTransfers()",
            "setTransfersEnabled(bool)",
            "burnFrom(address,uint256)",
            "seize(address)"
        ];
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory data = abi.encodeWithSignature(signatures[i], holder, true);
            // From the deployer, the address a token would most plausibly trust.
            (bool ok,) = address(token).call(data);
            assertFalse(ok, string.concat("unexpected privileged function exists: ", signatures[i]));
        }

        // The deployer cannot pull from a holder without an allowance.
        vm.expectRevert(abi.encodeWithSelector(VerdictToken.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        token.transferFrom(holder, deployer, 1);
        assertEq(token.balanceOf(holder), held, "a privileged call moved the holder's balance");

        // And the holder can still transfer.
        vm.prank(holder);
        assertTrue(token.transfer(other, held / 2), "the holder can no longer transfer");
        assertEq(token.balanceOf(other), held / 2);
        assertEq(token.balanceOf(holder), held - held / 2);
    }

    function test_deployerHasNoSpecialPowersAfterSpendingItsBalance() public {
        token.transfer(holder, SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
        vm.expectRevert(abi.encodeWithSelector(VerdictToken.ERC20InsufficientBalance.selector, deployer, 0, 1));
        token.transfer(other, 1);
    }

    // ------------------------------------------------------------------------------------------
    // Bytecode properties
    // ------------------------------------------------------------------------------------------

    function test_runtimeCodeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0, "the token has no runtime code");
        for (uint256 i = 0; i < runtime.length; i++) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7F) {
                // PUSH1..PUSH32: skip the immediate bytes so data is not read as opcodes.
                i += (op - 0x5F);
                continue;
            }
            assertTrue(op != 0xF4, "runtime code contains DELEGATECALL");
            assertTrue(op != 0xF2, "runtime code contains CALLCODE");
            assertTrue(op != 0xFF, "runtime code contains SELFDESTRUCT");
        }
    }

    function test_runtimeCodeFitsEip170() public view {
        assertLe(address(token).code.length, 24_576, "runtime exceeds EIP-170");
    }

    function test_creationCodeHasNoConstructorArguments() public {
        // Deploying the raw creation code with nothing appended must succeed and mint to the deployer.
        bytes memory code = type(VerdictToken).creationCode;
        address deployed;
        assembly ("memory-safe") {
            deployed := create(0, add(code, 32), mload(code))
        }
        assertTrue(deployed != address(0), "creation code could not be deployed bare");
        assertEq(VerdictToken(deployed).balanceOf(address(this)), SUPPLY);
        assertEq(VerdictToken(deployed).totalSupply(), SUPPLY);
    }
}

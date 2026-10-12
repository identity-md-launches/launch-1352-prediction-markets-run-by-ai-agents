// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {VerdictToken} from "../src/VerdictToken.sol";

/// @notice A closed set of actors drives both valid calls and expected failures. Ghost accounting
///         follows requested movements, never balances or allowances read back from the token.
contract TokenHandler is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    VerdictToken public token;
    address[] public actors;
    mapping(address => uint256) public initialBalance;
    mapping(address => uint256) public received;
    mapping(address => uint256) public sent;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    uint256 public transfers;
    uint256 public pulls;

    constructor(VerdictToken token_, address[] memory actors_, uint256[] memory initialBalances_) {
        token = token_;
        actors = actors_;
        for (uint256 i; i < actors_.length; ++i) {
            initialBalance[actors_[i]] = initialBalances_[i];
        }
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function expectedBalance(address actor) public view returns (uint256) {
        return initialBalance[actor] + received[actor] - sent[actor];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance(from));
        vm.prank(from);
        assertTrue(token.transfer(to, amount), "valid transfer returned false");
        _recordMovement(from, to, amount);
        transfers++;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        _approve(owner, spender, _approvalAmount(amount));
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 balance = expectedBalance(owner);
        uint256 cap = allowed < balance ? allowed : balance;
        amount = bound(amount, 0, cap);
        _pull(owner, spender, to, amount);
    }

    /// @dev Correlating approval and spending reaches nonzero delegated transfers even early in a
    ///      sequence. Standalone approve/transferFrom still exercise old and overwritten approvals.
    function approveAndTransferFrom(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 amount,
        bool unlimited
    ) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance(owner);
        amount = bound(amount, balance == 0 ? 0 : 1, balance);
        _approve(owner, spender, unlimited ? type(uint256).max : amount);
        _pull(owner, spender, to, amount);
    }

    function transferTooMuch(uint256 ownerSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance(owner);
        amount = bound(amount, balance + 1, type(uint256).max);
        _mustRevert(
            owner,
            abi.encodeCall(token.transfer, (to, amount)),
            abi.encodeWithSelector(VerdictToken.ERC20InsufficientBalance.selector, owner, balance, amount)
        );
    }

    function transferFromTooMuchBalance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 amount,
        bool unlimited
    ) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance(owner);
        amount = bound(amount, balance + 1, type(uint256).max - 1);
        _approve(owner, spender, unlimited ? type(uint256).max : amount);
        _mustRevert(
            spender,
            abi.encodeCall(token.transferFrom, (owner, to, amount)),
            abi.encodeWithSelector(VerdictToken.ERC20InsufficientBalance.selector, owner, balance, amount)
        );
        // No ghost spending: the approval made above must survive the failed transfer intact.
    }

    function transferFromTooMuchAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 balance = expectedBalance(owner);
        amount = bound(amount, 1, balance == 0 ? 1 : balance);
        _approve(owner, spender, amount - 1);
        _mustRevert(
            spender,
            abi.encodeCall(token.transferFrom, (owner, spender, amount)),
            abi.encodeWithSelector(VerdictToken.ERC20InsufficientAllowance.selector, spender, amount - 1, amount)
        );
    }

    function transferToZero(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool delegated) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = bound(amount, 0, expectedBalance(owner));
        bytes memory errorData = abi.encodeWithSelector(VerdictToken.ERC20InvalidReceiver.selector, address(0));
        if (delegated) {
            _approve(owner, spender, amount);
            _mustRevert(spender, abi.encodeCall(token.transferFrom, (owner, address(0), amount)), errorData);
        } else {
            _mustRevert(owner, abi.encodeCall(token.transfer, (address(0), amount)), errorData);
        }
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        _mustRevert(
            owner,
            abi.encodeCall(token.approve, (address(0), amount)),
            abi.encodeWithSelector(VerdictToken.ERC20InvalidSpender.selector, address(0))
        );
    }

    function revokeAndTrySpend(uint256 ownerSeed, uint256 spenderSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        _approve(owner, spender, 0);
        _mustRevert(
            spender,
            abi.encodeCall(token.transferFrom, (owner, spender, 1)),
            abi.encodeWithSelector(VerdictToken.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
    }

    function _pull(address owner, address spender, address to, uint256 amount) internal {
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount), "valid transferFrom returned false");
        if (expectedAllowance[owner][spender] != type(uint256).max) {
            expectedAllowance[owner][spender] -= amount;
        }
        _recordMovement(owner, to, amount);
        pulls++;
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount), "valid approval returned false");
        expectedAllowance[owner][spender] = amount;
    }

    function _recordMovement(address from, address to, uint256 amount) internal {
        sent[from] += amount;
        received[to] += amount;
    }

    function _mustRevert(address caller, bytes memory data, bytes memory expectedError) internal {
        vm.prank(caller);
        (bool success, bytes memory result) = address(token).call(data);
        assertFalse(success, "invalid call succeeded");
        assertEq(result, expectedError, "unexpected revert reason");
    }

    function _approvalAmount(uint256 seed) internal pure returns (uint256) {
        uint256 mode = seed % 6;
        if (mode == 0) return 0;
        if (mode == 1) return 1;
        if (mode == 2) return seed % (SUPPLY + 1);
        if (mode == 3) return type(uint256).max - 1;
        if (mode == 4) return type(uint256).max;
        return seed;
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract VerdictTokenInvariantTest is Test {
    uint256 constant SUPPLY = 1_000_000_000 * 10 ** 18;

    VerdictToken token;
    TokenHandler handler;
    address[] actors;

    function setUp() public {
        token = new VerdictToken();
        actors.push(address(this));
        actors.push(makeAddr("actor-1"));
        actors.push(makeAddr("actor-2"));
        actors.push(makeAddr("actor-3"));
        actors.push(makeAddr("actor-4"));

        // Spread some supply so transfers from every actor are reachable from the start.
        uint256[] memory initialBalances = new uint256[](actors.length);
        initialBalances[0] = SUPPLY - (actors.length - 1) * 1_000_000e18;
        for (uint256 i = 1; i < actors.length; i++) {
            token.transfer(actors[i], 1_000_000e18);
            initialBalances[i] = 1_000_000e18;
        }
        handler = new TokenHandler(token, actors, initialBalances);

        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        selectors[3] = TokenHandler.approveAndTransferFrom.selector;
        selectors[4] = TokenHandler.transferTooMuch.selector;
        selectors[5] = TokenHandler.transferFromTooMuchBalance.selector;
        selectors[6] = TokenHandler.transferFromTooMuchAllowance.selector;
        selectors[7] = TokenHandler.transferToZero.selector;
        selectors[8] = TokenHandler.approveZeroSpender.selector;
        selectors[9] = TokenHandler.revokeAndTrySpend.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_totalSupplyNeverChanges() public view {
        assertEq(token.totalSupply(), SUPPLY);
    }

    function invariant_sumOfBalancesEqualsSupply() public view {
        uint256 sum;
        for (uint256 i = 0; i < actors.length; i++) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(sum, SUPPLY, "tokens were created or destroyed");
    }

    function invariant_noBalanceExceedsSupply() public view {
        for (uint256 i = 0; i < actors.length; i++) {
            assertLe(token.balanceOf(actors[i]), SUPPLY);
        }
    }

    function invariant_eachBalanceMatchesAuthorizedMovements() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.balanceOf(actors[i]), handler.expectedBalance(actors[i]), "wrong actor balance");
        }
    }

    function invariant_allowancesMatchApprovalsAndSuccessfulSpending() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(
                    token.allowance(actors[i], actors[j]),
                    handler.expectedAllowance(actors[i], actors[j]),
                    "allowance changed without approval or successful spending"
                );
            }
            assertEq(token.allowance(actors[i], address(0)), 0);
            assertEq(token.allowance(address(0), actors[i]), 0);
        }
    }

    function invariant_zeroAddressNeverReceivesTokens() public view {
        assertEq(token.balanceOf(address(0)), 0);
    }

    /// @dev Every holder can still transfer its entire balance after an arbitrary history, even
    ///      after approvals, revocations, self-transfers and failures. No approvals are needed.
    function afterInvariant() public {
        for (uint256 i = 1; i < actors.length; ++i) {
            handler.transfer(i, 0, handler.expectedBalance(actors[i]));
            assertEq(token.balanceOf(actors[i]), 0);
        }
        assertEq(token.balanceOf(actors[0]), SUPPLY);
        invariant_eachBalanceMatchesAuthorizedMovements();
        invariant_allowancesMatchApprovalsAndSuccessfulSpending();
        invariant_totalSupplyNeverChanges();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "./interfaces/IERC20.sol";

/// @title Prediction Markets Run by AI Agents (VERDICT)
/// @notice A fixed-supply ERC-20. The whole supply of 1,000,000,000 VERDICT (18 decimals) is minted
///         once, in the constructor, to the deployer. There is no owner, no minter, no pause, no
///         blacklist, no fee and no burn: the supply can never change and nobody but a holder (or a
///         spender the holder approved) can move a holder's balance.
/// @dev The contract name is the launch's Solidity identifier and is deliberately short; the long
///      human-readable name is returned by `name()`. The constructor takes no arguments and calls no
///      other contract, so it deploys on an empty chain and from a CREATE2 factory alike.
contract VerdictToken is IERC20 {
    // ---------------------------------------------------------------------------------------------
    // Metadata
    // ---------------------------------------------------------------------------------------------

    /// @notice Human-readable token name.
    string public constant name = "Prediction Markets Run by AI Agents";

    /// @notice Ticker symbol.
    string public constant symbol = "VERDICT";

    /// @notice Number of decimals used for display. One VERDICT is 10 ** 18 minor units.
    uint8 public constant decimals = 18;

    /// @notice Total supply, fixed forever: 1,000,000,000 VERDICT in minor units.
    /// @dev A compile-time constant rather than storage, so no code path can ever change it.
    uint256 public constant totalSupply = 1_000_000_000 * 10 ** 18;

    // ---------------------------------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------------------------------

    /// @notice `sender` holds `balance` but tried to move `needed`.
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);

    /// @notice `spender` was allowed `allowance` by the owner but tried to move `needed`.
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    /// @notice Tokens cannot be sent to the zero address (that would be a burn, which this token has none of).
    error ERC20InvalidReceiver(address receiver);

    /// @notice The zero address cannot be given an allowance.
    error ERC20InvalidSpender(address spender);

    // ---------------------------------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------------------------------

    mapping(address account => uint256 balance) private _balances;

    mapping(address owner => mapping(address spender => uint256 amount)) private _allowances;

    // ---------------------------------------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------------------------------------

    /// @notice Mints the whole supply to the deployer. In the launch, the deployer is the factory,
    ///         which distributes the supply according to the launch manifest.
    constructor() {
        _balances[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
    }

    // ---------------------------------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------------------------------

    /// @inheritdoc IERC20
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    /// @inheritdoc IERC20
    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    // ---------------------------------------------------------------------------------------------
    // Actions
    // ---------------------------------------------------------------------------------------------

    /// @inheritdoc IERC20
    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    /// @inheritdoc IERC20
    /// @dev Setting a non-zero allowance over an existing non-zero allowance is allowed, as the
    ///      ERC-20 standard specifies. Spenders who want to avoid the approve race should rely on
    ///      the owner approving 0 first, or on the owner setting exactly the amount they expect.
    function approve(address spender, uint256 amount) external returns (bool) {
        if (spender == address(0)) revert ERC20InvalidSpender(address(0));
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /// @inheritdoc IERC20
    /// @dev An allowance of `type(uint256).max` is treated as unlimited and is not decremented.
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 current = _allowances[from][msg.sender];
        if (current != type(uint256).max) {
            if (current < amount) revert ERC20InsufficientAllowance(msg.sender, current, amount);
            unchecked {
                _allowances[from][msg.sender] = current - amount;
            }
        }
        _transfer(from, to, amount);
        return true;
    }

    // ---------------------------------------------------------------------------------------------
    // Internals
    // ---------------------------------------------------------------------------------------------

    /// @dev Moves `amount` from `from` to `to`. Every unit leaving `from` arrives at `to`: there is
    ///      no fee, no reflection and no burn, so launch flows and pool swaps move exactly what they say.
    function _transfer(address from, address to, uint256 amount) private {
        if (to == address(0)) revert ERC20InvalidReceiver(address(0));
        uint256 fromBalance = _balances[from];
        if (fromBalance < amount) revert ERC20InsufficientBalance(from, fromBalance, amount);
        unchecked {
            // Cannot underflow: checked above. Cannot overflow: the sum of all balances is the
            // constant total supply, which fits in a uint256 with room to spare.
            _balances[from] = fromBalance - amount;
            _balances[to] += amount;
        }
        emit Transfer(from, to, amount);
    }
}

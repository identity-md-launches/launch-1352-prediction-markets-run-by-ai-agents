// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title ERC-20 token standard interface (EIP-20).
/// @notice Kept in the project so the token depends on no outside library.
interface IERC20 {
    /// @notice Emitted when `value` tokens move from `from` to `to`. A mint has `from == address(0)`.
    event Transfer(address indexed from, address indexed to, uint256 value);

    /// @notice Emitted when `owner` sets `spender`'s allowance to `value`.
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /// @notice Total number of tokens in existence, in minor units.
    function totalSupply() external view returns (uint256);

    /// @notice Number of tokens held by `account`.
    function balanceOf(address account) external view returns (uint256);

    /// @notice Moves `amount` tokens from the caller to `to`. Returns true on success and reverts otherwise.
    function transfer(address to, uint256 amount) external returns (bool);

    /// @notice Remaining number of tokens `spender` may move on behalf of `owner` through `transferFrom`.
    function allowance(address owner, address spender) external view returns (uint256);

    /// @notice Sets `spender`'s allowance over the caller's tokens to `amount`. Returns true on success.
    function approve(address spender, uint256 amount) external returns (bool);

    /// @notice Moves `amount` tokens from `from` to `to` using the caller's allowance. Returns true on
    ///         success and reverts otherwise.
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

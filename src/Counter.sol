// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title Counter
/// @notice A minimal public counter. Anyone may add exactly one to the count; anyone may read it.
/// @dev Deliberately has no owner, no pause, no reset and no way to receive ETH. The count starts at
///      zero when the contract is deployed and can only ever move upward by one per call. Solidity's
///      checked arithmetic makes the count impossible to wrap: once it reaches `type(uint256).max`
///      every further `increment()` reverts with `CounterOverflow`.
contract Counter {
    /// @notice Emitted on every successful increment.
    /// @param caller The account that incremented the counter.
    /// @param newCount The value of the counter after this increment.
    event Incremented(address indexed caller, uint256 newCount);

    /// @notice Raised when the counter is already at its maximum and cannot be incremented again.
    error CounterOverflow();

    /// @dev The current count. Read through `count()`; written only by `increment()`.
    uint256 private _count;

    /// @notice Adds exactly one to the counter.
    /// @dev Reverts with `CounterOverflow` instead of wrapping when the count is at `type(uint256).max`.
    ///      Non-payable, so a call carrying ETH reverts before any state changes.
    /// @return newCount The value of the counter after this increment.
    function increment() external returns (uint256 newCount) {
        uint256 current = _count;
        if (current == type(uint256).max) revert CounterOverflow();
        newCount = current + 1;
        _count = newCount;
        emit Incremented(msg.sender, newCount);
    }

    /// @notice Returns the current count.
    /// @return The number of successful increments since deployment.
    function count() external view returns (uint256) {
        return _count;
    }
}

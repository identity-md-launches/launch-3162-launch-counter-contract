// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Counter} from "../src/Counter.sol";

/// @dev Drives `Counter` through random call sequences and tracks the number of successful increments.
contract CounterHandler is Test {
    Counter public immutable counter;
    uint256 public successfulIncrements;

    constructor(Counter counter_) {
        counter = counter_;
    }

    function increment(address caller) external {
        vm.prank(caller);
        uint256 returned = counter.increment();
        successfulIncrements += 1;
        assertEq(returned, successfulIncrements, "return value must track increments");
    }
}

contract CounterInvariantTest is Test {
    Counter internal counter;
    CounterHandler internal handler;

    function setUp() public {
        counter = new Counter();
        handler = new CounterHandler(counter);
        targetContract(address(handler));
    }

    /// @dev The count equals exactly the number of successful increment calls: nothing else moves it.
    function invariant_CountEqualsSuccessfulIncrements() public view {
        assertEq(counter.count(), handler.successfulIncrements());
    }

    /// @dev The contract can never accumulate ETH.
    function invariant_HoldsNoEth() public view {
        assertEq(address(counter).balance, 0);
    }
}

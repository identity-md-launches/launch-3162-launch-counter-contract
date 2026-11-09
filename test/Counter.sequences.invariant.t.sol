// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Counter} from "../src/Counter.sol";

/// @dev Multi-actor handler mixing successful increments with every way a call can fail, including
///      sequences that reach the overflow boundary. It never reverts itself: failures are asserted.
contract CounterSequenceHandler is Test {
    Counter public immutable counter;

    address[] public actors;
    mapping(address => uint256) public incrementsBy;

    uint256 public expectedCount;
    uint256 public successfulIncrements;
    uint256 public successfulSinceJump;
    uint256 public jumpBase;
    uint256 public overflowReverts;
    uint256 public highestSeen;
    uint256 public jumps;

    constructor(Counter counter_) {
        counter = counter_;
        for (uint256 i; i < 4; ++i) {
            actors.push(makeAddr(string.concat("actor", vm.toString(i))));
        }
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _checkMonotonic() internal {
        uint256 c = counter.count();
        assertGe(c, highestSeen, "count must never decrease");
        highestSeen = c;
    }

    function increment(uint256 actorSeed) external {
        address a = _actor(actorSeed);
        vm.prank(a);
        (bool ok, bytes memory data) = address(counter).call(abi.encodeCall(Counter.increment, ()));
        if (expectedCount == type(uint256).max) {
            assertFalse(ok, "increment at max must revert");
            assertEq(data, abi.encodeWithSelector(Counter.CounterOverflow.selector));
            overflowReverts += 1;
        } else {
            assertTrue(ok, "increment below max must succeed");
            expectedCount += 1;
            successfulIncrements += 1;
            successfulSinceJump += 1;
            incrementsBy[a] += 1;
            assertEq(abi.decode(data, (uint256)), expectedCount, "return value is the new count");
        }
        _checkMonotonic();
    }

    function incrementWithValue(uint256 actorSeed, uint256 value) external {
        address a = _actor(actorSeed);
        value = bound(value, 1, 100 ether);
        vm.deal(a, value);
        vm.prank(a);
        (bool ok,) = address(counter).call{value: value}(abi.encodeCall(Counter.increment, ()));
        assertFalse(ok, "payable increment must fail");
        assertEq(a.balance, value, "value returned");
        _checkMonotonic();
    }

    function sendEth(uint256 actorSeed, uint256 value) external {
        address a = _actor(actorSeed);
        value = bound(value, 1, 100 ether);
        vm.deal(a, value);
        vm.prank(a);
        (bool ok,) = address(counter).call{value: value}("");
        assertFalse(ok, "plain transfer must fail");
        _checkMonotonic();
    }

    function callOther(uint256 actorSeed, bytes4 sel, uint256 arg) external {
        if (sel == Counter.increment.selector || sel == Counter.count.selector) {
            sel = bytes4(keccak256("reset()"));
        }
        vm.prank(_actor(actorSeed));
        (bool ok,) = address(counter).call(abi.encodeWithSelector(sel, arg));
        assertFalse(ok, "unknown selector must fail");
        _checkMonotonic();
    }

    function read() external {
        assertEq(counter.count(), expectedCount);
        _checkMonotonic();
    }

    /// @dev Rarely move the count close to the maximum (as if 2^256 - k calls had happened) so random
    ///      sequences exercise the overflow path. Only ever moves forward, never down.
    function jumpNearMax(uint256 back) external {
        if (jumps >= 1 || back % 4 != 0) return;
        back = bound(back >> 2, 0, 8);
        uint256 target = type(uint256).max - back;
        if (target < expectedCount) return;
        jumps += 1;
        vm.store(address(counter), bytes32(uint256(0)), bytes32(target));
        expectedCount = target;
        jumpBase = target;
        successfulSinceJump = 0;
        _checkMonotonic();
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }
}

contract CounterSequencesInvariantTest is Test {
    Counter internal counter;
    CounterSequenceHandler internal handler;

    function setUp() public {
        counter = new Counter();
        handler = new CounterSequenceHandler(counter);
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 128
    function invariant_CountMatchesModel() public view {
        assertEq(counter.count(), handler.expectedCount());
    }

    /// forge-config: default.invariant.runs = 128
    function invariant_CountIsBasePlusSuccessesSinceJump() public view {
        if (handler.jumps() == 0) {
            assertEq(counter.count(), handler.successfulIncrements());
        } else {
            assertEq(counter.count(), handler.jumpBase() + handler.successfulSinceJump());
        }
    }

    /// forge-config: default.invariant.runs = 128
    function invariant_PerActorIncrementsSumToTotal() public view {
        uint256 sum;
        for (uint256 i; i < handler.actorCount(); ++i) {
            sum += handler.incrementsBy(handler.actors(i));
        }
        assertEq(sum, handler.successfulIncrements());
    }

    /// forge-config: default.invariant.runs = 128
    function invariant_NeverHoldsEth() public view {
        assertEq(address(counter).balance, 0);
    }

    /// forge-config: default.invariant.runs = 128
    function invariant_OverflowOnlyAtMax() public view {
        if (handler.overflowReverts() > 0) {
            assertEq(counter.count(), type(uint256).max, "once overflow is hit the counter stays finished");
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Counter} from "../src/Counter.sol";
import {DeployCounter} from "../script/DeployCounter.s.sol";

contract CounterTest is Test {
    /// @dev Storage slot of `Counter._count`: the only state variable, so slot 0.
    bytes32 internal constant COUNT_SLOT = bytes32(uint256(0));

    Counter internal counter;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    event Incremented(address indexed caller, uint256 newCount);

    function setUp() public {
        counter = new Counter();
    }

    // ---------------------------------------------------------------------------------------------
    // Success paths
    // ---------------------------------------------------------------------------------------------

    function test_StartsAtZero() public view {
        assertEq(counter.count(), 0, "fresh counter must start at zero");
    }

    function test_IncrementAddsExactlyOne() public {
        uint256 returned = counter.increment();
        assertEq(returned, 1, "return value must be the new count");
        assertEq(counter.count(), 1, "getter must reflect the increment");
    }

    function test_IncrementTwiceCountsToTwo() public {
        counter.increment();
        uint256 returned = counter.increment();
        assertEq(returned, 2);
        assertEq(counter.count(), 2);
    }

    function test_AnyoneCanIncrement() public {
        vm.prank(alice);
        counter.increment();
        vm.prank(bob);
        counter.increment();
        assertEq(counter.count(), 2, "increments from different callers must all count");
    }

    function test_IncrementEmitsEvent() public {
        vm.expectEmit(true, false, false, true, address(counter));
        emit Incremented(alice, 1);
        vm.prank(alice);
        counter.increment();

        vm.expectEmit(true, false, false, true, address(counter));
        emit Incremented(bob, 2);
        vm.prank(bob);
        counter.increment();
    }

    function test_GetterIsViewAndDoesNotChangeState() public {
        counter.increment();
        uint256 before = counter.count();
        counter.count();
        counter.count();
        assertEq(counter.count(), before, "reading must not change the count");
    }

    function test_IncrementAtMaxMinusOneReachesMax() public {
        vm.store(address(counter), COUNT_SLOT, bytes32(type(uint256).max - 1));
        uint256 returned = counter.increment();
        assertEq(returned, type(uint256).max);
        assertEq(counter.count(), type(uint256).max);
    }

    function test_DeployScriptProducesFreshCounter() public {
        DeployCounter deployer = new DeployCounter();
        Counter deployed = deployer.deploy();
        assertTrue(address(deployed) != address(0));
        assertTrue(address(deployed) != address(counter));
        assertEq(deployed.count(), 0);
        deployed.increment();
        assertEq(deployed.count(), 1);
        assertEq(counter.count(), 0, "instances must not share state");
    }

    function test_RuntimeFitsEip170() public view {
        assertLe(address(counter).code.length, 24_576);
    }

    // ---------------------------------------------------------------------------------------------
    // Failure paths
    // ---------------------------------------------------------------------------------------------

    function test_RevertWhen_IncrementAtMax() public {
        vm.store(address(counter), COUNT_SLOT, bytes32(type(uint256).max));
        vm.expectRevert(Counter.CounterOverflow.selector);
        counter.increment();
        assertEq(counter.count(), type(uint256).max, "a reverted increment must not change the count");
    }

    function test_RevertWhen_IncrementSentWithValue() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(counter).call{value: 1 wei}(abi.encodeCall(Counter.increment, ()));
        assertFalse(ok, "increment is non-payable");
        assertEq(counter.count(), 0);
        assertEq(address(counter).balance, 0);
    }

    function test_RevertWhen_PlainEthTransfer() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(counter).call{value: 1 wei}("");
        assertFalse(ok, "contract has no receive function");
        assertEq(address(counter).balance, 0);
    }

    function test_RevertWhen_UnknownSelector() public {
        (bool ok,) = address(counter).call(abi.encodeWithSignature("reset()"));
        assertFalse(ok, "there is no reset and no fallback");
        (ok,) = address(counter).call(abi.encodeWithSignature("decrement()"));
        assertFalse(ok, "there is no decrement and no fallback");
        (ok,) = address(counter).call(abi.encodeWithSignature("setCount(uint256)", 42));
        assertFalse(ok, "the count cannot be set directly");
        assertEq(counter.count(), 0);
    }

    // ---------------------------------------------------------------------------------------------
    // Fuzz
    // ---------------------------------------------------------------------------------------------

    /// @dev Each call adds exactly one, whoever the caller is and however many calls precede it.
    function testFuzz_IncrementNTimes(uint8 n, address caller) public {
        for (uint256 i; i < n; ++i) {
            vm.prank(caller);
            uint256 returned = counter.increment();
            assertEq(returned, i + 1);
        }
        assertEq(counter.count(), n);
    }

    /// @dev From any starting value below the maximum, one increment yields exactly start + 1.
    function testFuzz_IncrementFromAnyStart(uint256 start) public {
        start = bound(start, 0, type(uint256).max - 1);
        vm.store(address(counter), COUNT_SLOT, bytes32(start));
        assertEq(counter.count(), start);
        uint256 returned = counter.increment();
        assertEq(returned, start + 1);
        assertEq(counter.count(), start + 1);
    }
}

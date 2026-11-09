// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {Counter} from "../src/Counter.sol";

/// @dev Deploys a Counter and increments it in the same transaction, the way a factory launch would.
contract CounterLauncher {
    function launchAndCount(bytes32 salt, uint256 times) external returns (Counter counter, uint256 last) {
        counter = new Counter{salt: salt}();
        for (uint256 i; i < times; ++i) {
            last = counter.increment();
        }
    }
}

/// @dev Calls back into the counter to check the `Incremented` caller is the immediate caller, not tx.origin.
contract IncrementProxy {
    function poke(Counter counter) external returns (uint256) {
        return counter.increment();
    }
}

/// @notice Edge and failure cases not already covered by `Counter.t.sol`.
contract CounterEdgesTest is Test {
    bytes32 internal constant COUNT_SLOT = bytes32(uint256(0));
    bytes32 internal constant INCREMENTED_TOPIC = keccak256("Incremented(address,uint256)");

    Counter internal counter;
    address internal alice = makeAddr("alice");

    function setUp() public {
        counter = new Counter();
    }

    // ---------------------------------------------------------------- failure paths

    function test_RevertWhen_IncrementAtMax_ExactRevertData() public {
        vm.store(address(counter), COUNT_SLOT, bytes32(type(uint256).max));
        (bool ok, bytes memory data) = address(counter).call(abi.encodeCall(Counter.increment, ()));
        assertFalse(ok);
        assertEq(data, abi.encodeWithSelector(Counter.CounterOverflow.selector), "revert data is exactly the error");
    }

    function test_RevertWhen_IncrementAtMax_RepeatedlyStaysAtMax() public {
        vm.store(address(counter), COUNT_SLOT, bytes32(type(uint256).max - 1));
        assertEq(counter.increment(), type(uint256).max);
        for (uint256 i; i < 5; ++i) {
            vm.expectRevert(Counter.CounterOverflow.selector);
            counter.increment();
        }
        assertEq(counter.count(), type(uint256).max, "a finished counter never wraps or reopens");
    }

    function test_RevertWhen_IncrementAtMax_EmitsNothing() public {
        vm.store(address(counter), COUNT_SLOT, bytes32(type(uint256).max));
        vm.recordLogs();
        (bool ok,) = address(counter).call(abi.encodeCall(Counter.increment, ()));
        assertFalse(ok);
        assertEq(vm.getRecordedLogs().length, 0, "a reverted increment must not emit");
    }

    function test_RevertWhen_IncrementWithValue_RefundsAndEmptyRevert() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok, bytes memory data) = address(counter).call{value: 1 ether}(abi.encodeCall(Counter.increment, ()));
        assertFalse(ok);
        assertEq(data.length, 0, "non-payable check reverts with empty data");
        assertEq(counter.count(), 0);
        assertEq(alice.balance, 1 ether, "value must be returned to the caller");
    }

    function test_RevertWhen_CountCalledWithValue() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(counter).call{value: 1}(abi.encodeCall(Counter.count, ()));
        assertFalse(ok, "count() is view and non-payable");
        assertEq(address(counter).balance, 0);
    }

    function test_RevertWhen_EmptyCalldataNoValue() public {
        (bool ok,) = address(counter).call("");
        assertFalse(ok, "no fallback: empty calldata reverts");
        assertEq(counter.count(), 0);
    }

    function test_RevertWhen_ShortSelector() public {
        // First three bytes of increment() only: must not dispatch to it.
        bytes4 sel = Counter.increment.selector;
        (bool ok,) = address(counter).call(abi.encodePacked(sel[0], sel[1], sel[2]));
        assertFalse(ok, "truncated selector must not dispatch");
        assertEq(counter.count(), 0);
    }

    function test_RevertWhen_IncrementViaStaticcall() public view {
        (bool ok,) = address(counter).staticcall{gas: 100_000}(abi.encodeCall(Counter.increment, ()));
        assertFalse(ok, "increment writes state and must fail under staticcall");
        assertEq(counter.count(), 0);
    }

    /// @dev Any selector other than the two public functions reverts and leaves the count unchanged.
    function testFuzz_RevertWhen_AnyOtherSelector(bytes4 sel, bytes calldata tail) public {
        if (sel == Counter.increment.selector || sel == Counter.count.selector) {
            sel = bytes4(keccak256("notAFunction()"));
        }
        counter.increment();
        (bool ok,) = address(counter).call(abi.encodePacked(sel, tail));
        assertFalse(ok);
        assertEq(counter.count(), 1);
    }

    /// @dev Any non-zero value sent with increment reverts and nothing moves.
    function testFuzz_RevertWhen_IncrementWithAnyValue(uint256 value) public {
        value = bound(value, 1, 1_000_000 ether);
        vm.deal(alice, value);
        vm.prank(alice);
        (bool ok,) = address(counter).call{value: value}(abi.encodeCall(Counter.increment, ()));
        assertFalse(ok);
        assertEq(counter.count(), 0);
        assertEq(alice.balance, value);
        assertEq(address(counter).balance, 0);
    }

    // ---------------------------------------------------------------- success-path details

    function test_IncrementOnlyTouchesCountSlot() public {
        vm.record();
        counter.increment();
        (, bytes32[] memory writes) = vm.accesses(address(counter));
        assertEq(writes.length, 1, "exactly one storage write");
        assertEq(writes[0], COUNT_SLOT);
        assertEq(uint256(vm.load(address(counter), COUNT_SLOT)), 1);
    }

    function test_CountDoesNotWriteStorage() public {
        counter.increment();
        vm.record();
        counter.count();
        (, bytes32[] memory writes) = vm.accesses(address(counter));
        assertEq(writes.length, 0);
    }

    function test_IncrementEmitsExactlyOneLog() public {
        vm.recordLogs();
        vm.prank(alice);
        counter.increment();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(counter));
        assertEq(logs[0].topics.length, 2);
        assertEq(logs[0].topics[0], INCREMENTED_TOPIC);
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(alice))));
        assertEq(abi.decode(logs[0].data, (uint256)), 1);
    }

    function test_EventCallerIsImmediateCallerNotOrigin() public {
        IncrementProxy proxy = new IncrementProxy();
        vm.recordLogs();
        vm.prank(alice, alice);
        proxy.poke(counter);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(address(proxy)))), "caller is msg.sender");
    }

    function test_SameCallerManyTimesCountsEachTime() public {
        for (uint256 i = 1; i <= 10; ++i) {
            vm.prank(alice);
            assertEq(counter.increment(), i);
        }
        assertEq(counter.count(), 10);
    }

    function test_GetterReturnDataIsOneWord() public view {
        (bool ok, bytes memory data) = address(counter).staticcall(abi.encodeCall(Counter.count, ()));
        assertTrue(ok);
        assertEq(data.length, 32);
        assertEq(abi.decode(data, (uint256)), 0);
    }

    function test_IncrementIgnoresTrailingCalldata() public {
        (bool ok, bytes memory data) = address(counter).call(abi.encodePacked(Counter.increment.selector, uint256(123)));
        assertTrue(ok, "extra calldata does not change behaviour");
        assertEq(abi.decode(data, (uint256)), 1, "still adds exactly one");
        assertEq(counter.count(), 1);
    }

    function test_ZeroValueCallToIncrementSucceeds() public {
        (bool ok,) = address(counter).call{value: 0}(abi.encodeCall(Counter.increment, ()));
        assertTrue(ok);
        assertEq(counter.count(), 1);
    }

    // ---------------------------------------------------------------- launch shape

    /// @dev Deploy and count in one transaction through a factory-like helper: constructor needs nothing.
    function test_LaunchAndCountInOneTransaction() public {
        CounterLauncher launcher = new CounterLauncher();
        (Counter launched, uint256 last) = launcher.launchAndCount(bytes32(uint256(1)), 3);
        assertEq(last, 3);
        assertEq(launched.count(), 3);
        assertEq(
            address(launched),
            vm.computeCreate2Address(bytes32(uint256(1)), keccak256(type(Counter).creationCode), address(launcher))
        );
    }

    function test_FreshDeployStartsAtZeroWhoeverDeploys() public {
        vm.prank(alice);
        Counter c = new Counter();
        assertEq(c.count(), 0);
        assertEq(uint256(vm.load(address(c), COUNT_SLOT)), 0);
    }

    function test_RuntimeHasNoForbiddenOpcodes() public view {
        bytes memory code = address(counter).code;
        assertGt(code.length, 0);
        bool reachable = true;
        for (uint256 j; j < code.length; ++j) {
            uint8 op = uint8(code[j]);
            if (op == 0x5b) reachable = true;
            if (op >= 0x60 && op <= 0x7f) {
                j += op - 0x5f;
                continue;
            }
            if (reachable) {
                assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "no DELEGATECALL/CALLCODE/SELFDESTRUCT");
            }
            if (op == 0x00 || op == 0x56 || op == 0xf3 || op == 0xfd || op == 0xfe || op == 0xff) reachable = false;
        }
    }

    // ---------------------------------------------------------------- fuzz near the boundary

    /// @dev From any start, k increments either reach start + k or stop exactly at max with CounterOverflow.
    function testFuzz_IncrementsNearMaxSaturateWithRevert(uint256 back, uint8 k) public {
        back = bound(back, 0, 20);
        uint256 start = type(uint256).max - back;
        vm.store(address(counter), COUNT_SLOT, bytes32(start));
        uint256 expected = start;
        for (uint256 i; i < k; ++i) {
            (bool ok, bytes memory data) = address(counter).call(abi.encodeCall(Counter.increment, ()));
            if (expected == type(uint256).max) {
                assertFalse(ok);
                assertEq(bytes4(data), Counter.CounterOverflow.selector);
            } else {
                assertTrue(ok);
                expected += 1;
                assertEq(abi.decode(data, (uint256)), expected);
            }
            assertEq(counter.count(), expected);
        }
    }
}

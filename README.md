# Counter

A minimal public counter for Base (chain id 8453). Anyone can add exactly one to the count, and
anyone can read it. That is the whole contract.

| Item | Value |
| --- | --- |
| Contract | `Counter` (`src/Counter.sol`) |
| Launch chain | Base, chain id 8453 |
| Constructor arguments | none |
| Owner / admin | none (the contract has no privileged role) |
| Compiler | solc 0.8.26, optimizer on (200 runs), `bytecode_hash = "none"`, EVM `cancun` |

## Interface

| Function | Access | Effect |
| --- | --- | --- |
| `increment() returns (uint256 newCount)` | anyone, non-payable | Adds exactly one to the count, emits `Incremented(caller, newCount)`, returns the new count. Reverts with `CounterOverflow()` if the count is already `type(uint256).max`. |
| `count() returns (uint256)` | anyone, view | Returns the current count. |

Event: `Incremented(address indexed caller, uint256 newCount)`.

Custom error: `CounterOverflow()`.

## Behaviour and assumptions

- The count starts at zero at deployment and only ever moves upward, by exactly one per successful call.
- There is no owner, pause, reset, decrement or setter. Nobody, including the launch owner, can change
  the count other than by calling `increment()` like everyone else.
- The contract cannot receive ETH: it has no `receive` or `fallback`, and `increment()` is non-payable.
  A call that carries value reverts.
- The counter cannot wrap. Solidity 0.8 checked arithmetic would already revert at the maximum; the
  contract checks first and reverts with the explicit `CounterOverflow()` error. Reaching that bound
  needs 2^256 - 1 transactions, so in practice it is unreachable and the check only exists so the
  failure mode is defined and tested.
- "Count to 1+" is read as: every call increments by one, so the first call takes the count from 0
  to 1 and later calls keep counting upward without bound.
- No external contracts, oracles, tokens or libraries are used. The contract has no dependencies at
  runtime. `forge-std` is vendored under `lib/forge-std` for tests only and is not part of the
  deployed bytecode.
- The contract is not upgradeable and uses no `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT`.

## Deployment parameters

`Counter` has no constructor arguments and no post-deployment configuration. The IdentityMD launch
deploys it from the built bytecode through the project factory on Base. Nothing in the constructor
reads `msg.sender` or `tx.origin`, calls another contract, or requires any address to have code, so
it deploys identically on an empty chain and on Base.

Expected manifest entry (written by the manifest step, not by this repository):

```
contract: Counter
constructorArgs: []
```

`script/DeployCounter.s.sol` holds the same deployment as a reviewable Foundry script. Its `deploy()`
function is what the tests call; `run()` only wraps it in a broadcast for anyone who wants to
rehearse on a local node. This repository does not broadcast anything and holds no keys.

## After launch

Nothing to set. There are no owner-settable values and no addresses to configure.

## Operational responsibilities

- **Launch owner (0x047f606fd5b2baa5f5c6c4ab8958e45cb6b054b7):** holds no power over this contract.
  There is nothing to administer, pause or upgrade. The owner's only responsibility is to record and
  publish the deployed address that the launch handoff reports.
- **Users:** pay Base gas for `increment()`. Reads of `count()` are free through any Base RPC, for
  example the public endpoint `https://mainnet.base.org`.
- **Integrators:** index the `Incremented` event or poll `count()`. Because Base is an OP Stack
  rollup, `block.number` and `block.timestamp` follow the L2 sequencer; the contract uses neither.
- **Nobody** can recover a transaction's gas if it reverts, and no funds can ever be locked in the
  contract because it cannot hold ETH or tokens. Tokens sent to it by mistake with a plain ERC-20
  `transfer` would be stuck; there is no sweep function, by design, since the contract has no admin.

## Building and testing

```
forge build
forge test
forge fmt --check
```

The verifier runs the fuzz tests with
`FOUNDRY_FUZZ_SEED=0xb0d9525e80ecd928338af43436ee2b14eb56238279fa14e5eb3a07c4208a3e38`; the suite
passes with that seed and with the default random seed.

### What the tests cover

`test/Counter.t.sol`

- Success: starts at zero; one increment yields 1; two yield 2; any caller can increment; the event
  carries the caller and the new count; the getter does not change state; `max - 1` increments to
  `max`; the deploy script yields a fresh, independent instance; runtime fits EIP-170.
- Failure: increment at `type(uint256).max` reverts with `CounterOverflow()` and leaves the count
  untouched; an increment carrying ETH reverts; a plain ETH transfer reverts; unknown selectors
  (`reset()`, `decrement()`, `setCount(uint256)`) revert and change nothing.
- Fuzz: `n` increments from any caller give exactly `n`; one increment from any starting value below
  the maximum gives exactly `start + 1`.

`test/Counter.invariant.t.sol`

- Across random call sequences the count always equals the number of successful increments, and
  the contract balance is always zero.

Tests read no environment variables and do not depend on which address calls them, so they pass in
any order and in parallel.

## Security notes

Tests passing is not an audit. The contract has a surface of two functions, no value custody, no
privileged roles and no external calls, so the usual classes of defect (reentrancy, access control,
oracle, signature replay, upgrade paths) do not apply. The one arithmetic edge, overflow at the
maximum, is handled explicitly and tested. Slither was not run on this machine; the source uses no
`selfdestruct`, `transferFrom`, initializer, storage pointer, shift or `abi.encodePacked`.

## Layout

```
foundry.toml              compiler and project configuration (solc 0.8.26, bytecode_hash = "none")
remappings.txt            forge-std/ -> lib/forge-std/src/
src/Counter.sol           the contract
script/DeployCounter.s.sol deployment script with a directly testable deploy() function
test/Counter.t.sol        unit, failure and fuzz tests
test/Counter.invariant.t.sol invariant tests
lib/forge-std/            vendored forge-std v1.9.7 (MIT / Apache-2.0), tests only
```

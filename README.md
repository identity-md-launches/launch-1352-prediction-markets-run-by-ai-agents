# Prediction Markets Run by AI Agents (VERDICT)

A fixed-supply ERC-20 token for an IdentityMD custom token launch on Ethereum mainnet.

| Parameter        | Value                                        |
|------------------|----------------------------------------------|
| Solidity contract | `VerdictToken` (`src/VerdictToken.sol`)     |
| `name()`         | `Prediction Markets Run by AI Agents`        |
| `symbol()`       | `VERDICT`                                    |
| `decimals()`     | `18`                                         |
| `totalSupply()`  | `1000000000000000000000000000` (1,000,000,000 VERDICT) |
| Constructor args | none                                         |
| Mint             | once, in the constructor, all to `msg.sender` (the deployer) |
| Owner / admin    | none                                         |

## What the token does

- Implements EIP-20 exactly: `totalSupply`, `balanceOf`, `transfer`, `approve`, `allowance`,
  `transferFrom`, with `Transfer` and `Approval` events.
- Mints the whole supply to the deployer in the constructor and emits the mint as a `Transfer`
  from the zero address.
- Treats an allowance of `type(uint256).max` as unlimited (it is not decremented).
- Reverts with typed errors on failure instead of returning `false`:
  `ERC20InsufficientBalance`, `ERC20InsufficientAllowance`, `ERC20InvalidReceiver` (transfer to the
  zero address), `ERC20InvalidSpender` (approval of the zero address).

## What the token does not do

- No owner, no admin role, no minter, no upgrade path. `totalSupply` is a compile-time constant and
  no function can change it.
- No pause, blacklist, freeze, lock, seize or `burnFrom`. Only a holder, or a spender the holder
  approved, can move a holder's balance.
- No fee, tax, reflection or burn on transfer. Every transfer moves exactly the amount stated, so
  the launch flows (factory to distributor, factory to pool, factory to requester, pool swaps,
  distributor claims) arrive whole.
- No burn at all, so the supply can neither grow nor shrink. Sending to the zero address reverts.
- No `receive` or `fallback`: ether sent to the contract is refused.
- No external calls, no `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT` in the runtime bytecode
  (tested by scanning the deployed code).

## Assumptions

- The launch deploys the token from its built creation code through the project factory, so the
  factory is `msg.sender` in the constructor and receives the whole supply. The constructor takes no
  arguments and calls no other contract, so it deploys on an empty chain and from CREATE2.
- Because the token exempts nobody and taxes nobody, it needs none of the optional launch
  constructor arguments (`$factory`, `$poolManager`, `$launchNumber`) and never calls
  `distributorOf` on the factory.
- The build is compared without a metadata hash: `foundry.toml` sets `bytecode_hash = "none"`,
  pins `solc = "0.8.26"`, `evm_version = "cancun"`, and the optimizer at 200 runs. The verifier
  must build with these same settings for the bytecode to match.
- ERC-20's known approve race (changing a non-zero allowance to another non-zero value) is kept as
  the standard specifies. Holders who care should set the allowance to 0 first.

## Deployment parameters

The launch manifest step writes `launch.json` after this work is accepted. The values it needs
from this project:

- `token.contract`: `VerdictToken`
- `token.name`: `Prediction Markets Run by AI Agents`
- `token.symbol`: `VERDICT`
- `token.decimals`: `18`
- `token.constructorArgs`: `[]`
- `token.totalSupply`: `1000000000000000000000000000`
- `contracts`: `[]` (this launch has no application contracts)

Launch-decided values (not this project's to choose): chain id 1, paired currency IMD at
`0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`, pool fee `12500`, tick spacing `60`, initial price
`79228162514264337593543950336`, and the requester's economics (`poolBps` 8000,
`initialMarketCapWei` 2500000000000000000000, `remainderTo`
`0xd6302976e590b9b947da8774b7f1246164e0ce98`).

Expected supply split performed by the factory at launch, in VERDICT:

| Recipient                      | Share | Amount        |
|--------------------------------|-------|---------------|
| MerkleDistributor (swarm)      | 10%   | 100,000,000   |
| Uniswap v4 pool (single-sided) | 80%   | 800,000,000   |
| `remainderTo`                  | 10%   | 100,000,000   |

### Manual deployment (fork or test network)

`script/DeployVerdictToken.s.sol` deploys the token with no configuration. `deploy()` is a plain
function the tests call directly; `run()` wraps it in a broadcast for `forge script`:

```sh
forge script script/DeployVerdictToken.s.sol:DeployVerdictToken --rpc-url <RPC> --broadcast --sender <ADDRESS> --private-key <KEY>
```

Whoever broadcasts receives the whole supply. This assignment does not deploy, broadcast or hold
keys; the script is for reviewers and for rehearsals on a fork.

## After launch

Nothing. The token has no owner-settable values, no setters and no post-deployment configuration.

## Operational responsibilities

- **Holders** are solely responsible for their balances and allowances. There is no recovery,
  freeze or seize function, and tokens sent to a wrong address cannot be retrieved.
- **The factory** (at launch) is responsible for distributing the supply exactly as the manifest
  says. The token enforces none of the split; it only guarantees each transfer arrives whole.
- **The requester** receives the remainder at `remainderTo` and is responsible for that wallet.
- **Explorer verification** of the deployed contract (`forge verify-contract` with the pinned
  compiler settings) belongs to the launch's deployer after deployment.
- **Independent review**: tests passing is not an audit. Work that will hold other people's funds
  needs a separate adversarial review before release. This token holds no funds and has no
  privileged roles, which keeps that review small.

## Repository layout

```
foundry.toml                     compiler pins and build settings (solc 0.8.26, bytecode_hash none)
remappings.txt                   forge-std/ -> lib/forge-std/src/
src/VerdictToken.sol             the token
src/interfaces/IERC20.sol        the ERC-20 interface the token implements
script/DeployVerdictToken.s.sol  deploy script (deploy() for tests, run() for forge script)
test/VerdictToken.t.sol          ERC-20 behaviour: success and failure paths, fuzz conservation
test/VerdictTokenSafety.t.sol    no mint, no privileged hand, no delegatecall/selfdestruct, EIP-170
test/LaunchFlow.t.sol            CREATE2 deployment from a factory stand-in and the launch payouts
test/VerdictTokenInvariant.t.sol invariant: sum of balances equals the constant supply
lib/forge-std/                   forge-std 1.9.7, vendored as plain files
```

## Dependencies

`lib/forge-std` is forge-std 1.9.7 (Apache-2.0 OR MIT), vendored as ordinary files rather than a
git submodule so the project builds with no network. It is used by tests and the script only; the
token itself imports nothing outside `src/`.

## Checks

```sh
forge build
forge test
forge fmt --check
```

All three were run locally with Foundry 1.8.3 and solc 0.8.26: 46 tests pass (29 behaviour, 8
safety, 8 launch flow, 1 invariant suite with 3 invariants over 64 runs of depth 32). Tests read no
environment variables and do not depend on the calling address, so they pass in any order and in
parallel. No static analyser (Slither, Mythril) was available in this environment and none ran.

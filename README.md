# tap2stacks contracts

Smart contracts for **tap2stacks**, a tap-to-predict game on live stock prices, built on Base.

Gameplay runs off-chain for speed. These contracts hold the money and the proofs: players deposit into a vault, withdraw with a permit signed by the game server, and every batch of settled taps is anchored as a Merkle root that anyone can check.

| Repo | Role |
|---|---|
| [tap2stacks-web](https://github.com/Tap2Stacks/tap2stacks-web) | Player app (React, wallets, live board) |
| [tap2stacks-backend](https://github.com/Tap2Stacks/tap2stacks-backend) | Accounts, taps, settlement, proofs, on-chain money flows |
| [tap2stacks-engine](https://github.com/Tap2Stacks/tap2stacks-engine) | Price feed, odds model, quote stream |
| **tap2stacks-contracts** | Vault, test USDC and proof anchor (this repo) |

## Contracts

| Contract | Purpose |
|---|---|
| `TestUSDC` | 6-decimal test token for the testnet game, with a rate-limited `faucet()` and owner `mint` |
| `Tap2StacksVault` | Holds player deposits and house liquidity. `deposit(amount)`; `withdraw(amount, deadline, signature)` takes an EIP-712 permit from the withdraw signer, with a nonce per player; the owner can seed house liquidity, rotate the signer and pause. |
| `ProofAnchor` | The relayer posts `postRoot(tapsRoot, priceLogHash, fromMs, toMs)` for each batch of settled taps. Every root is indexed and emitted as an event, so a tap can be verified with its Merkle path. |

Built on OpenZeppelin 5 (`ERC20`, `EIP712`, `Ownable`, `Pausable`).

## Deployments: Base Sepolia (chain 84532)

| Contract | Address |
|---|---|
| TestUSDC | [`0xb91410a49868827FF592f2d90E11eD85240E468e`](https://base-sepolia.blockscout.com/address/0xb91410a49868827FF592f2d90E11eD85240E468e?tab=contract) |
| Tap2StacksVault | [`0xa491f306B41Ecee5EC38dFb21D0708Ac8933F216`](https://base-sepolia.blockscout.com/address/0xa491f306B41Ecee5EC38dFb21D0708Ac8933F216?tab=contract) |
| ProofAnchor | [`0xad7ec69738307E9797bF63530b2dAb0E17aaC194`](https://base-sepolia.blockscout.com/address/0xad7ec69738307E9797bF63530b2dAb0E17aaC194?tab=contract) |

All three are verified on Blockscout, deployed from block 62476617. The full manifest, with roles and deployment transactions, is in [`deployments/base-sepolia.json`](deployments/base-sepolia.json).

## Build and test

[Foundry](https://book.getfoundry.sh/).

```sh
forge build
forge test
forge script script/Deploy.s.sol --rpc-url <base-sepolia-rpc> --broadcast --sender <deployer>
scripts/export-abi.sh      # ABIs for the web app and backend
```

## Repository rules

Commits use the project identity and are checked by hooks and CI. See [`AGENTS.md`](AGENTS.md).

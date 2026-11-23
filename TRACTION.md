# tap2stacks: Base Sepolia traction

## One-time setup for the owner

1. In [Base Dashboard](https://dashboard.base.org/), register the tap2stacks
   project and its real app URL. Copy the **Builder Code** as a plain `bc_…`
   string from Settings → Project Settings → Builder Code. Set
   `VITE_BASE_BUILDER_CODE` in the Vercel build environment and
   `BASE_BUILDER_CODE` for the Fly backend proof publisher. Leave them unset
   until there is a real code. When approved to release, rebuild the frontend
   and roll the backend so the new values take effect. No registration, release
   or transaction is part of this handoff.
2. Confirm the existing **Base Sepolia** (84532) deployment's token, vault,
   proof anchor, withdrawal signer, and relayer against the deployment
   receipts. Save the values in `deployments/base-sepolia.json` (use the
   `.example.json` as a shape guide, or augment Foundry's generated manifest).
   Set `deployBlock` to the earliest of the three actual contract creation
   receipt block numbers, not a simulated block, and add `deployer` from the
   creation receipts. If they name different deployers, label the others as
   `team` in the labels CSV. Keep prior and rotated signers/relayers labelled
   as team as well. The deployment addresses were not available in the
   checked-in repo; do not use placeholder addresses or target mainnet.
3. Before onboarding AI/test traffic, set the backend's existing
   `BOT_WALLETS` to the real public player-wallet addresses used by automation.
   Use the same comma-separated roster when running the tracker. Maintain
   [the labels CSV](deployments/base-sepolia-wallet-labels.csv):
   `ai_player` for AI players, `bot` for other automation, `team` for
   staff/test/admin wallets, `contract` for non-player infrastructure, and
   `human` only when there's affirmative evidence (such as a manually
   reviewed tester roster). Record a non-sensitive audit reference in
   `source`; don't store names, emails or keys. Only label the actual player
   address emitted by the vault, not the owner EOA of a separate smart
   account. The snapshot automatically labels the deployment's three contract
   addresses and team roles. Addresses in `BOT_WALLETS` default to `bot`
   unless explicitly labelled `ai_player`; conflicts (including a known bot
   marked human) stop the run. Retain archived/historical bot addresses in the
   labels file even if you rotate the runtime roster.
4. After approval, verify an ordinary wallet write and a sponsored batch on
   **Base Sepolia**, and a normal proof-anchor post if publishing is enabled.
   Check the input for EOAs and the individual UserOperation's `callData`
   for smart accounts using [Base's verification
   guide](https://docs.base.org/specifications/builder-codes/for-app-developers#verify-attribution).
   Sponsored calls request the optional ERC-8021 capability without
   disturbing the paymaster. A wallet that does not implement it may omit
   attribution; chart numbers from the contract logs do not depend on it.
5. Schedule the read-only job on a machine you control, e.g. daily at 02:00
   UTC after UTC midnight has finalized. Archive date-stamped snapshots,
   evidence CSVs, the exact input manifest and labels, and the effective bot
   roster with the commit SHA. Every run should include the launch date
   through the latest fully finalized UTC day so earlier D1/D7 columns fill
   in as those dates mature. For long histories, backfill in bounded date
   ranges (the script automatically reads up to seven extra days for
   retention). Check failures and unlabelled wallet counts before submitting
   any data.

## Run locally

This uses Python 3's standard library and the public Base Sepolia RPC. No
wallet, token, provider account, paid query or signing is needed.

```sh
# From tap2stacks-contracts; set LAUNCH_UTC and BOT_WALLETS to the real values first.
python3 scripts/traction_snapshot.py \
  --start "$LAUNCH_UTC" --evidence tap2stacks-events.csv > tap2stacks-daily.csv
```

Use `--end YYYY-MM-DD` for a bounded rerun and `--chunk-size 1000` if your
RPC rejects the default 5,000-block log requests. `BASE_SEPOLIA_RPC_URL`
can select a different read-only Base Sepolia endpoint. The script rejects
wrong-chain endpoints, missing contract code, vault/token mismatches, and
incomplete UTC days. Publish/archive only on exit code zero. Chain, from/to
blocks (including retention look-ahead), finalized hash and input digests
are included in the daily rows. The evidence file lists the matching
Base Sepolia tx hashes and log indexes, player wallet and base-unit amount;
for example inspect `https://sepolia.basescan.org/tx/<tx_hash>`.

## What counts

| Column or term | Definition |
| --- | --- |
| Active wallet | A distinct player address in a successful `Deposited` or `Withdrawn` event from the one configured vault that UTC day. |
| Human wallet/transactions/volume | Only addresses labelled `human`. An address is not proof of a unique person; this is a conservative count of positively labelled wallets. Neither missing labels nor Builder Code imply human. |
| Player transactions | Distinct (player wallet, chain transaction hash) pairs; multiple events from one wallet in a batch count once for that wallet. `distinct_chain_transactions` instead counts unique outer hashes, which may bundle multiple wallets. |
| Volume | Sum of the deposit and withdrawal amounts, including repeated activity; integer tUSDC base units (divide by 1,000,000). This is gross testnet vault flow, not off-chain tap/order volume, revenue, or dollars. |
| D1/D7 | Of the labelled human wallets active on day D, the fraction also active on exactly D+1 or D+7. This is daily active-cohort retention, not first-ever signup retention. Blank share means not observable yet or no cohort; a zero means an observable cohort with no returns. |
| Bot/team share | `ai_player` + `bot` + `team` divided by all observed vault wallets or all player transactions as applicable. The unlabelled and contract counts are separate; the measured share is not an estimate of unlabeled bots. |
| Proof transactions | Distinct hashes emitting `RootPosted` on the configured proof anchor. Operational only and not part of player counts, volumes, retention or bot/team share. |

Approvals, faucet claims, transfers, house seeding and failed transactions
are not counted as player traction. The backend's existing `/metrics` is
an application counter based on stored signup bot flags; it is not the
audited onchain report and must not be substituted for the daily CSV.

Run the synthetic regression test with
`python3 -B -m unittest discover -s scripts -p 'test_traction_snapshot.py'`.
`deployments/traction-example.synthetic.csv` is an output of that fixture,
not tap2stacks usage or a claim about any deployed contracts.

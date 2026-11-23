#!/usr/bin/env python3
import argparse
import csv
import hashlib
import io
import json
import os
import re
import sys
import time
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


CHAIN_ID = 84532
RPC_URL = "https://sepolia.base.org"
DAY = timedelta(days=1)
ZERO_ADDRESS = "0x" + "0" * 40
DEPOSITED = "0x2da466a7b24304f47e87fa2e1e5a81b9831ce54fec19055ce277ca2f39ba42c4"
WITHDRAWN = "0x92ccf450a286a957af52509bc1c9939d1a6a481783e142e41e2499f0bb66ebc6"
ROOT_POSTED = "0xa17d0dedfdb0dbbeb200a98364e1689a78e07e7177b7b2f779ead72ed4300537"
CLASSES = ("human", "ai_player", "bot", "team", "contract", "unlabelled")
NON_HUMAN_SHARE = {"ai_player", "bot", "team"}


def address(value):
    if not isinstance(value, str) or not re.fullmatch(r"0x[0-9a-fA-F]{40}", value):
        raise ValueError(f"Invalid wallet or contract address: {value!r}")
    value = value.lower()
    if value == ZERO_ADDRESS:
        raise ValueError("Zero address cannot be used as a wallet or contract")
    return value


def load_labels(raw_labels, deployment, bot_wallets):
    labels = {}

    def register(wallet, label):
        wallet = address(wallet)
        if label not in CLASSES[:-1]:
            raise ValueError(f"Invalid label: {label!r}")
        if wallet in labels and labels[wallet] != label:
            raise ValueError(f"Conflicting labels for {wallet}: {labels[wallet]} vs {label}")
        labels[wallet] = label

    reader = csv.DictReader(io.StringIO(raw_labels))
    if reader.fieldnames != ["address", "label", "source"]:
        raise ValueError("Labels CSV must have address,label,source columns")
    for row in reader:
        if None in row or not row["source"] or not row["source"].strip():
            raise ValueError("Each label needs an audit source")
        register(row["address"].strip(), row["label"].strip())
    for key in ("testUSDC", "vault", "proofAnchor"):
        register(deployment[key], "contract")
    for key in ("deployer", "relayer", "withdrawSigner"):
        register(deployment[key], "team")
    for wallet in filter(None, (part.strip() for part in bot_wallets.split(","))):
        if labels.get(address(wallet)) != "ai_player":
            register(wallet, "bot")
    return labels


class Rpc:
    def __init__(self, url):
        self.url = url
        self.blocks = {}

    def call(self, method, params):
        request = Request(
            self.url,
            data=json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode(),
            headers={"Content-Type": "application/json", "User-Agent": "tap2stacks-traction/1"},
        )
        for attempt in range(3):
            try:
                with urlopen(request, timeout=30) as response:
                    result = json.load(response)
                break
            except HTTPError as error:
                if error.code not in {429, 500, 502, 503, 504} or attempt == 2:
                    raise
                time.sleep(2 ** attempt)
        if "error" in result or result.get("result") is None:
            error = result.get("error", {})
            raise ValueError(f"{method} failed: {error.get('code')} {error.get('message', 'missing result')}")
        return result["result"]

    def block(self, number):
        if number not in self.blocks:
            self.blocks[number] = self.call("eth_getBlockByNumber", [hex(number), False])
        return self.blocks[number]

    def logs(self, start, end, contract, topics, chunk_size):
        for left in range(start, end + 1, chunk_size):
            right = min(left + chunk_size - 1, end)
            yield from self.call(
                "eth_getLogs",
                [{"fromBlock": hex(left), "toBlock": hex(right), "address": contract, "topics": [topics]}],
            )


def utc_day(block):
    return datetime.fromtimestamp(int(block["timestamp"], 16), timezone.utc).date()


def first_block(rpc, target, floor, ceiling):
    while floor < ceiling:
        mid = (floor + ceiling) // 2
        if utc_day(rpc.block(mid)) < target:
            floor = mid + 1
        else:
            ceiling = mid
    return floor


def collate(vault_logs, proof_logs, rpc, labels):
    days = defaultdict(dict)
    proofs = defaultdict(set)
    evidence = {}
    for logs, is_proof in ((vault_logs, False), (proof_logs, True)):
        for log in logs:
            number = int(log["blockNumber"], 16)
            block = rpc.block(number)
            if log.get("removed") or log["blockHash"] != block["hash"]:
                raise ValueError("RPC returned a log outside the canonical block")
            day = utc_day(block)
            tx = log["transactionHash"]
            key = (tx, int(log["logIndex"], 16))
            if key in evidence:
                continue
            if is_proof:
                proofs[day].add(tx)
                evidence[key] = (day, number, block["hash"], tx, key[1], "proof_root", "", "", "")
                continue
            topic = log["topics"][0]
            if topic not in (DEPOSITED, WITHDRAWN):
                raise ValueError(f"Unexpected vault topic: {topic}")
            kind = "deposit" if topic == DEPOSITED else "withdrawal"
            wallet = address("0x" + log["topics"][1][-40:])
            amount = int(log["data"][2:66], 16)
            amounts = days[day].setdefault((wallet, tx), [0, 0])
            amounts[kind == "withdrawal"] += amount
            evidence[key] = (
                day, number, block["hash"], tx, key[1], kind, wallet,
                labels.get(wallet, "unlabelled"), amount,
            )
    return days, proofs, sorted(evidence.values(), key=lambda row: (row[1], row[4]))


def share(part, total):
    return f"{part / total:.6f}" if total else ""


def snapshot_rows(days, proofs, labels, start, end, complete_through, metadata):
    def human_wallets(day):
        return {wallet for wallet, _ in days.get(day, {}) if labels.get(wallet) == "human"}

    for offset in range((end - start).days + 1):
        day = start + offset * DAY
        txs_by_class = {label: set() for label in CLASSES}
        wallets_by_class = {label: set() for label in CLASSES}
        deposits = withdrawals = human_deposits = human_withdrawals = 0
        for (wallet, tx), (deposited, withdrawn) in days.get(day, {}).items():
            label = labels.get(wallet, "unlabelled")
            txs_by_class[label].add((wallet, tx))
            wallets_by_class[label].add(wallet)
            deposits += deposited
            withdrawals += withdrawn
            if label == "human":
                human_deposits += deposited
                human_withdrawals += withdrawn

        cohort = wallets_by_class["human"]
        wallet_count = sum(map(len, wallets_by_class.values()))
        tx_count = sum(map(len, txs_by_class.values()))
        row = {
            "date_utc": day,
            "chain_id": CHAIN_ID,
            **metadata,
            "unique_wallets": wallet_count,
            "player_transactions": tx_count,
            "distinct_chain_transactions": len({tx for _, tx in days.get(day, {})}),
            "proof_anchor_transactions": len(proofs.get(day, ())),
            "deposits_tusdc_base_units": deposits,
            "withdrawals_tusdc_base_units": withdrawals,
            "gross_volume_tusdc_base_units": deposits + withdrawals,
            "human_deposits_tusdc_base_units": human_deposits,
            "human_withdrawals_tusdc_base_units": human_withdrawals,
            "human_gross_volume_tusdc_base_units": human_deposits + human_withdrawals,
            "bot_team_wallet_share": share(sum(len(wallets_by_class[k]) for k in NON_HUMAN_SHARE), wallet_count),
            "bot_team_transaction_share": share(sum(len(txs_by_class[k]) for k in NON_HUMAN_SHARE), tx_count),
        }
        for label in CLASSES:
            row[f"{label}_wallets"] = len(wallets_by_class[label])
            row[f"{label}_transactions"] = len(txs_by_class[label])
        for lag in (1, 7):
            target = day + lag * DAY
            count = len(cohort & human_wallets(target)) if target <= complete_through else None
            row[f"d{lag}_returned_human_wallets"] = count
            row[f"d{lag}_human_retention"] = share(count, len(cohort)) if count is not None else ""
        yield row


def snapshot(args):
    manifest_bytes = args.deployment.read_bytes()
    deployment = json.loads(manifest_bytes)
    if deployment["chainId"] != CHAIN_ID:
        raise ValueError("Deployment must be for Base Sepolia (84532)")
    deploy_block = deployment["deployBlock"]
    if type(deploy_block) is not int or deploy_block <= 0:
        raise ValueError("deployBlock must be a positive integer")
    raw_labels = args.labels.read_bytes()
    labels = load_labels(raw_labels.decode("utf-8"), deployment, args.bot_wallets)

    rpc = Rpc(args.rpc)
    if int(rpc.call("eth_chainId", []), 16) != CHAIN_ID:
        raise ValueError("RPC must be on Base Sepolia (84532)")
    finalized = rpc.call("eth_getBlockByNumber", ["finalized", False])
    head = int(finalized["number"], 16)
    rpc.blocks[head] = finalized
    if deploy_block > head:
        raise ValueError("Deployment is newer than the finalized block")
    contracts = {key: address(deployment[key]) for key in ("vault", "proofAnchor", "testUSDC")}
    if len(set(contracts.values())) != len(contracts):
        raise ValueError("Vault, token and proof anchor must be distinct contracts")
    for contract in contracts.values():
        if rpc.call("eth_getCode", [contract, hex(head)]) == "0x":
            raise ValueError(f"No code at {contract} at finalized block {head}")
    token = rpc.call("eth_call", [{"to": contracts["vault"], "data": "0xfc0c546a"}, hex(head)])
    if token != "0x" + "0" * 24 + contracts["testUSDC"][2:]:
        raise ValueError("Vault token() does not match deployment testUSDC")

    complete_through = utc_day(finalized) - DAY
    end = args.end or complete_through
    if not (args.start <= end <= complete_through):
        raise ValueError(f"Require start ≤ end ≤ latest complete finalized UTC day ({complete_through})")
    if args.start < utc_day(rpc.block(deploy_block)):
        raise ValueError("Start date is before the deployment UTC date")
    start_block = first_block(rpc, args.start, deploy_block, head)
    observed_through = min(end + 7 * DAY, complete_through)
    end_block = first_block(rpc, observed_through + DAY, start_block, head) - 1
    days, proofs, evidence = collate(
        rpc.logs(start_block, end_block, contracts["vault"], [DEPOSITED, WITHDRAWN], args.chunk_size),
        rpc.logs(start_block, end_block, contracts["proofAnchor"], ROOT_POSTED, args.chunk_size),
        rpc, labels,
    )
    metadata = {
        "vault": contracts["vault"],
        "proof_anchor": contracts["proofAnchor"],
        "from_block": start_block,
        "to_block": end_block,
        "finalized_block": head,
        "finalized_block_hash": finalized["hash"],
        "observed_through_utc": observed_through,
        "deployment_sha256": hashlib.sha256(manifest_bytes).hexdigest(),
        "labels_sha256": hashlib.sha256(raw_labels).hexdigest(),
        "effective_labels_sha256": hashlib.sha256(json.dumps(labels, sort_keys=True).encode()).hexdigest(),
    }
    rows = list(snapshot_rows(days, proofs, labels, args.start, end, observed_through, metadata))
    if args.evidence:
        with args.evidence.open("w", newline="") as stream:
            writer = csv.writer(stream, lineterminator="\n")
            writer.writerow(("date_utc", "block_number", "block_hash", "tx_hash", "log_index", "event", "wallet", "label", "amount_base_units"))
            writer.writerows(evidence)
    writer = csv.DictWriter(sys.stdout, fieldnames=rows[0].keys(), lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)


def main():
    parser = argparse.ArgumentParser(description="Read-only Base Sepolia tap2stacks daily traction CSV")
    root = Path(__file__).resolve().parents[1]
    parser.add_argument("--deployment", type=Path, default=root / "deployments/base-sepolia.json")
    parser.add_argument("--labels", type=Path, default=root / "deployments/base-sepolia-wallet-labels.csv")
    parser.add_argument("--start", type=date.fromisoformat, required=True, help="First UTC date, inclusive")
    parser.add_argument("--end", type=date.fromisoformat, help="Last UTC date, inclusive (default: latest complete finalized day)")
    parser.add_argument("--evidence", type=Path, help="Write a second CSV of source logs")
    parser.add_argument("--rpc", default=os.getenv("BASE_SEPOLIA_RPC_URL") or RPC_URL)
    parser.add_argument("--chunk-size", type=int, default=5000, help="Maximum blocks per eth_getLogs request")
    parser.add_argument("--bot-wallets", default=os.getenv("BOT_WALLETS", ""), help="Same comma-separated public addresses as the backend BOT_WALLETS")
    args = parser.parse_args()
    if args.chunk_size <= 0:
        parser.error("--chunk-size must be positive")
    try:
        snapshot(args)
    except (KeyError, OSError, ValueError, URLError) as error:
        parser.exit(1, f"Snapshot failed: {error}\n")


if __name__ == "__main__":
    main()

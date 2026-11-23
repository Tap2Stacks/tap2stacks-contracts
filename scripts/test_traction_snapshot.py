import io
import json
import tempfile
import unittest
from argparse import Namespace
from contextlib import redirect_stdout
from datetime import date, datetime, timezone
from pathlib import Path
from unittest.mock import patch

import traction_snapshot as traction


def wallet(number):
    return f"0x{number:040x}"


HUMAN, AI, UNKNOWN, BOT = map(wallet, range(1, 5))
DEPLOYMENT = {
    "chainId": 84532,
    "deployBlock": 1,
    "vault": wallet(11),
    "testUSDC": wallet(12),
    "proofAnchor": wallet(13),
    "deployer": wallet(14),
    "relayer": wallet(15),
    "withdrawSigner": wallet(16),
}
LABELS = f"address,label,source\n{HUMAN},human,fixture\n{AI},ai_player,fixture\n"


def log(topic, player, amount, number, tx, index=0):
    return {
        "blockNumber": hex(number),
        "blockHash": f"0x{number:064x}",
        "transactionHash": f"0x{tx:064x}",
        "logIndex": hex(index),
        "topics": [topic, f"0x{int(player, 16):064x}"],
        "data": f"0x{amount:064x}",
    }


class FixtureRpc:
    latest = 9  # One block per UTC day; day 9 is incomplete.

    def __init__(self, _url):
        self.blocks = {}

    def call(self, method, params):
        if method == "eth_chainId":
            return hex(84532)
        if method == "eth_getBlockByNumber" and params[0] == "finalized":
            return self.block(self.latest)
        if method == "eth_getCode":
            return "0x60"
        if method == "eth_call":
            return f"0x{int(DEPLOYMENT['testUSDC'], 16):064x}"
        raise AssertionError((method, params))

    def block(self, number):
        return {
            "number": hex(number),
            "hash": f"0x{number:064x}",
            "timestamp": hex(int(datetime(2026, 1, number, tzinfo=timezone.utc).timestamp())),
        }

    def logs(self, start, end, contract, topics, _chunk_size):
        if contract == DEPLOYMENT["vault"]:
            assert topics == [traction.DEPOSITED, traction.WITHDRAWN]
            events = [
                log(traction.DEPOSITED, HUMAN, 5_000_000, 1, 101),
                log(traction.WITHDRAWN, HUMAN, 1_000_000, 1, 101, 1),
                log(traction.DEPOSITED, AI, 8_000_000, 1, 101, 2),
                log(traction.DEPOSITED, BOT, 9_000_000, 1, 102),
                log(traction.DEPOSITED, UNKNOWN, 10_000_000, 1, 103),
                log(traction.DEPOSITED, DEPLOYMENT["deployer"], 4_000_000, 1, 104),
                log(traction.DEPOSITED, HUMAN, 1_000_000, 2, 105),
                log(traction.DEPOSITED, HUMAN, 1_000_000, 8, 106),
            ]
        else:
            assert topics == traction.ROOT_POSTED
            events = [log(traction.ROOT_POSTED, DEPLOYMENT["relayer"], 0, 1, 107)]
        return [event for event in events if start <= int(event["blockNumber"], 16) <= end]


def synthetic_snapshot():
    with tempfile.TemporaryDirectory() as directory:
        deployment = Path(directory) / "deployment.json"
        deployment.write_text(json.dumps(DEPLOYMENT))
        labels = Path(directory) / "labels.csv"
        labels.write_text(LABELS)
        evidence = Path(directory) / "evidence.csv"
        args = Namespace(
            deployment=deployment, labels=labels, bot_wallets=f"{AI},{BOT}", rpc="synthetic",
            start=date(2026, 1, 1), end=date(2026, 1, 3), evidence=evidence, chunk_size=5000,
        )
        output = io.StringIO()
        with patch.object(traction, "Rpc", FixtureRpc), redirect_stdout(output):
            traction.snapshot(args)
        return output.getvalue(), evidence.read_text()


class SnapshotTests(unittest.TestCase):
    def test_finalized_cohorts_label_exclusions_and_bundled_transactions(self):
        output, evidence = synthetic_snapshot()
        first, second, empty = list(traction.csv.DictReader(io.StringIO(output)))
        self.assertEqual(first["human_wallets"], "1")
        self.assertEqual(first["human_transactions"], "1")
        self.assertEqual(first["human_gross_volume_tusdc_base_units"], "6000000")
        self.assertEqual(first["player_transactions"], "5")
        self.assertEqual(first["distinct_chain_transactions"], "4")
        self.assertEqual(first["proof_anchor_transactions"], "1")
        self.assertEqual(first["ai_player_wallets"], "1")
        self.assertEqual(first["bot_wallets"], "1")
        self.assertEqual(first["team_wallets"], "1")
        self.assertEqual(first["unlabelled_wallets"], "1")
        self.assertEqual(first["bot_team_wallet_share"], "0.600000")
        self.assertEqual(first["bot_team_transaction_share"], "0.600000")
        self.assertEqual(first["d1_human_retention"], "1.000000")
        self.assertEqual(first["d7_human_retention"], "1.000000")
        self.assertEqual(second["d1_human_retention"], "0.000000")
        self.assertEqual(second["d7_human_retention"], "")
        self.assertEqual(empty["human_wallets"], "0")
        self.assertEqual(empty["d1_human_retention"], "")
        source = list(traction.csv.DictReader(io.StringIO(evidence)))
        self.assertEqual(len(source), 9)
        self.assertEqual(source[-1]["date_utc"], "2026-01-08")

    def test_rejects_a_human_label_for_a_known_bot_or_deployer(self):
        with self.assertRaisesRegex(ValueError, "Conflicting labels"):
            traction.load_labels(LABELS, DEPLOYMENT, HUMAN)
        with self.assertRaisesRegex(ValueError, "Conflicting labels"):
            traction.load_labels(LABELS + f"{DEPLOYMENT['deployer']},human,bad\n", DEPLOYMENT, "")

    def test_rejects_wrong_chain_before_fetching_activity(self):
        class WrongChain(FixtureRpc):
            def call(self, method, params):
                assert method == "eth_chainId"
                return "0x1"

        with patch.object(traction, "Rpc", WrongChain), self.assertRaisesRegex(ValueError, "Base Sepolia"):
            with tempfile.TemporaryDirectory() as directory:
                manifest = Path(directory) / "deployment.json"
                manifest.write_text(json.dumps(DEPLOYMENT))
                labels = Path(directory) / "labels.csv"
                labels.write_text(LABELS)
                traction.snapshot(Namespace(deployment=manifest, labels=labels, bot_wallets="", rpc="synthetic"))


if __name__ == "__main__":
    unittest.main()

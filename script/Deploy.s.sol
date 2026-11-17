// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TestUSDC} from "../src/TestUSDC.sol";
import {Tap2StacksVault} from "../src/Tap2StacksVault.sol";
import {ProofAnchor} from "../src/ProofAnchor.sol";

/// @title Deploy
/// @notice Deploys TestUSDC, Tap2StacksVault, and ProofAnchor, seeds the vault, and writes deployment metadata.
contract Deploy is Script {
    uint256 public constant HOUSE_SEED = 1_000_000e6;

    /// @notice Deploys and wires all contracts, minting and seeding `HOUSE_SEED` into the vault.
    function deploy(address withdrawSigner, address relayer)
        public
        returns (TestUSDC token, Tap2StacksVault vault, ProofAnchor anchor)
    {
        address owner = msg.sender;
        token = new TestUSDC(owner);
        vault = new Tap2StacksVault(IERC20(address(token)), owner, withdrawSigner);
        anchor = new ProofAnchor(owner, relayer);

        token.mint(owner, HOUSE_SEED);
        token.approve(address(vault), HOUSE_SEED);
        vault.seedHouse(HOUSE_SEED);
    }

    /// @notice Entrypoint for `forge script`: reads signers from env, broadcasts deployment, and writes JSON.
    function run() external {
        address withdrawSigner = vm.envAddress("WITHDRAW_SIGNER");
        address relayer = vm.envAddress("RELAYER");

        vm.startBroadcast();
        (TestUSDC token, Tap2StacksVault vault, ProofAnchor anchor) = deploy(withdrawSigner, relayer);
        vm.stopBroadcast();

        string memory obj = "deployment";
        vm.serializeUint(obj, "chainId", block.chainid);
        vm.serializeAddress(obj, "testUSDC", address(token));
        vm.serializeAddress(obj, "vault", address(vault));
        vm.serializeAddress(obj, "proofAnchor", address(anchor));
        vm.serializeAddress(obj, "withdrawSigner", withdrawSigner);
        vm.serializeAddress(obj, "relayer", relayer);
        string memory json = vm.serializeUint(obj, "deployBlock", block.number);
        vm.writeJson(json, "./deployments/base-sepolia.json");
    }
}

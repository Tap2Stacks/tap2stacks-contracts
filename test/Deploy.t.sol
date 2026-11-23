// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";
import {Deploy} from "../script/Deploy.s.sol";
import {TestUSDC} from "../src/TestUSDC.sol";
import {Tap2StacksVault} from "../src/Tap2StacksVault.sol";
import {ProofAnchor} from "../src/ProofAnchor.sol";

contract DeployTest is Test, Deploy {
    address internal withdrawSigner = address(0x1111);
    address internal relayer = address(0x2222);

    function test_deployWiresEverything() public {
        (TestUSDC token, Tap2StacksVault vault, ProofAnchor anchor) = this.deploy(withdrawSigner, relayer);

        assertEq(address(vault.token()), address(token));
        assertEq(vault.withdrawSigner(), withdrawSigner);
        assertEq(token.balanceOf(address(vault)), 1_000_000e6);
        assertEq(anchor.relayer(), relayer);

        assertEq(token.owner(), address(this));
        assertEq(vault.owner(), address(this));
        assertEq(anchor.owner(), address(this));
    }

    function test_deploymentOutputPreservesVerifiedManifest() public {
        string memory manifestPath = "./deployments/base-sepolia.json";
        string memory verifiedManifest = vm.readFile(manifestPath);
        string memory outputPath = "./out/base-sepolia.latest.json";
        bool outputExisted = vm.exists(outputPath);
        string memory priorOutput = outputExisted ? vm.readFile(outputPath) : "";
        (TestUSDC token, Tap2StacksVault vault, ProofAnchor anchor) = this.deploy(withdrawSigner, relayer);

        writeDeploymentOutput(address(token), address(vault), address(anchor), withdrawSigner, relayer);

        string memory generated = vm.readFile(outputPath);
        if (outputExisted) vm.writeFile(outputPath, priorOutput);
        else vm.removeFile(outputPath);

        assertEq(vm.readFile(manifestPath), verifiedManifest);
        assertEq(vm.parseJsonUint(generated, ".chainId"), block.chainid);
        assertEq(vm.parseJsonUint(generated, ".deployBlock"), block.number);
        assertEq(vm.parseJsonAddress(generated, ".withdrawSigner"), withdrawSigner);
        assertEq(vm.parseJsonAddress(generated, ".relayer"), relayer);
        assertEq(vm.parseJsonAddress(generated, ".testUSDC"), address(token));
        assertEq(vm.parseJsonAddress(generated, ".vault"), address(vault));
        assertEq(vm.parseJsonAddress(generated, ".proofAnchor"), address(anchor));
    }
}

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
}

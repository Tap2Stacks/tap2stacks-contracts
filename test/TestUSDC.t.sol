// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";
import {TestUSDC} from "../src/TestUSDC.sol";

contract TestUSDCTest is Test {
    TestUSDC internal token;
    address internal owner = address(0x1);
    address internal alice = address(0xA11CE);

    function setUp() public {
        token = new TestUSDC(owner);
    }

    function test_metadata() public view {
        assertEq(token.name(), "tap2stacks Test USD");
        assertEq(token.symbol(), "tUSDC");
        assertEq(token.FAUCET_AMOUNT(), 100e6);
        assertEq(token.FAUCET_COOLDOWN(), 1 days);
        assertEq(token.nextClaimAt(alice), 0);
    }

    function test_decimalsIsSix() public view {
        assertEq(token.decimals(), 6);
    }

    function test_faucetMints100() public {
        vm.prank(alice);
        token.faucet();
        assertEq(token.balanceOf(alice), 100e6);
        assertEq(token.nextClaimAt(alice), block.timestamp + 1 days);
    }

    function test_faucetCooldownReverts() public {
        vm.prank(alice);
        token.faucet();
        vm.expectRevert(abi.encodeWithSelector(TestUSDC.FaucetCooldown.selector, block.timestamp + 1 days));
        vm.prank(alice);
        token.faucet();
    }

    function test_faucetAgainAfter24h() public {
        vm.prank(alice);
        token.faucet();
        vm.warp(block.timestamp + 1 days);
        vm.prank(alice);
        token.faucet();
        assertEq(token.balanceOf(alice), 200e6);
    }

    function test_onlyOwnerMints() public {
        vm.prank(alice);
        vm.expectRevert();
        token.mint(alice, 1);

        vm.prank(owner);
        token.mint(alice, 500e6);
        assertEq(token.balanceOf(alice), 500e6);
    }
}

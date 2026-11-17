// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";
import {ProofAnchor} from "../src/ProofAnchor.sol";

contract ProofAnchorTest is Test {
    ProofAnchor internal anchor;

    address internal owner = address(0x1);
    address internal relayer = address(0xBEEF);
    address internal alice = address(0xA11CE);

    function setUp() public {
        anchor = new ProofAnchor(owner, relayer);
    }

    function test_relayerPostsRoot() public {
        bytes32 tapsRoot = bytes32("t");
        bytes32 priceLogHash = bytes32("p");

        vm.expectEmit(true, false, false, true);
        emit ProofAnchor.RootPosted(0, tapsRoot, priceLogHash, 1000, 301000);
        vm.prank(relayer);
        anchor.postRoot(tapsRoot, priceLogHash, 1000, 301000);

        assertEq(anchor.count(), 1);
        assertEq(anchor.lastToMs(), 301000);

        (bytes32 storedTaps, bytes32 storedPrice, uint64 fromMs, uint64 toMs) = anchor.anchors(0);
        assertEq(storedTaps, tapsRoot);
        assertEq(storedPrice, priceLogHash);
        assertEq(fromMs, 1000);
        assertEq(toMs, 301000);
    }

    function test_nonRelayerReverts() public {
        vm.prank(alice);
        vm.expectRevert(ProofAnchor.NotRelayer.selector);
        anchor.postRoot(0, 0, 1, 2);
    }

    function test_emptyRangeReverts() public {
        vm.prank(relayer);
        vm.expectRevert(ProofAnchor.BadRange.selector);
        anchor.postRoot(0, 0, 5, 5);
    }

    function test_backwardsRangeReverts() public {
        vm.prank(relayer);
        vm.expectRevert(ProofAnchor.BadRange.selector);
        anchor.postRoot(0, 0, 10, 5);
    }

    function test_overlapReverts() public {
        vm.startPrank(relayer);
        anchor.postRoot(0, 0, 1000, 2000);
        vm.expectRevert(ProofAnchor.BadRange.selector);
        anchor.postRoot(0, 0, 1999, 3000);
        vm.stopPrank();
    }

    function test_gapAllowed() public {
        vm.startPrank(relayer);
        anchor.postRoot(0, 0, 1000, 2000);
        anchor.postRoot(0, 0, 5000, 6000);
        vm.stopPrank();

        assertEq(anchor.count(), 2);
        assertEq(anchor.lastToMs(), 6000);
    }

    function test_contiguousAllowed() public {
        vm.startPrank(relayer);
        anchor.postRoot(0, 0, 1000, 2000);
        anchor.postRoot(0, 0, 2000, 3000);
        vm.stopPrank();

        assertEq(anchor.count(), 2);
        assertEq(anchor.lastToMs(), 3000);
    }

    function test_onlyOwnerSetsRelayer() public {
        vm.prank(alice);
        vm.expectRevert();
        anchor.setRelayer(alice);

        vm.prank(owner);
        anchor.setRelayer(alice);
        assertEq(anchor.relayer(), alice);

        vm.prank(relayer);
        vm.expectRevert(ProofAnchor.NotRelayer.selector);
        anchor.postRoot(0, 0, 10, 20);

        vm.prank(alice);
        anchor.postRoot(0, 0, 10, 20);
        assertEq(anchor.count(), 1);
    }
}

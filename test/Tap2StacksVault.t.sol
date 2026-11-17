// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TestUSDC} from "../src/TestUSDC.sol";
import {Tap2StacksVault} from "../src/Tap2StacksVault.sol";

contract Tap2StacksVaultTest is Test {
    TestUSDC internal token;
    Tap2StacksVault internal vault;

    address internal owner = address(0x1);
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    uint256 internal constant SIGNER_PK = 0xA11CE;
    address internal signer;

    uint256 internal constant HOUSE = 1_000_000e6;

    function setUp() public {
        signer = vm.addr(SIGNER_PK);
        token = new TestUSDC(owner);
        vault = new Tap2StacksVault(IERC20(address(token)), owner, signer);

        vm.startPrank(owner);
        token.mint(owner, HOUSE);
        token.approve(address(vault), HOUSE);
        vault.seedHouse(HOUSE);
        vm.stopPrank();

        vm.prank(alice);
        token.faucet();
    }

    function sign(address player, uint256 amount, uint256 nonce, uint256 deadline)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = vault.hashWithdraw(player, amount, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PK, digest);
        return abi.encodePacked(r, s, v);
    }

    function test_depositPullsTokensAndEmits() public {
        vm.startPrank(alice);
        token.approve(address(vault), 50e6);
        vm.expectEmit(true, false, false, true);
        emit Tap2StacksVault.Deposited(alice, 50e6);
        vault.deposit(50e6);
        vm.stopPrank();

        assertEq(token.balanceOf(address(vault)), HOUSE + 50e6);
        assertEq(token.balanceOf(alice), 50e6);
    }

    function test_depositZeroReverts() public {
        vm.prank(alice);
        vm.expectRevert(Tap2StacksVault.InvalidAmount.selector);
        vault.deposit(0);
    }

    function test_withdrawWithValidPermit() public {
        uint256 deadline = block.timestamp + 300;
        bytes memory sig = sign(alice, 30e6, 0, deadline);

        vm.expectEmit(true, false, false, true);
        emit Tap2StacksVault.Withdrawn(alice, 30e6, 0);
        vm.prank(alice);
        vault.withdraw(30e6, deadline, sig);

        assertEq(vault.nonces(alice), 1);
        assertEq(token.balanceOf(alice), 130e6);
        assertEq(token.balanceOf(address(vault)), HOUSE - 30e6);
    }

    function test_withdrawZeroReverts() public {
        uint256 deadline = block.timestamp + 300;
        bytes memory sig = sign(alice, 0, 0, deadline);
        vm.prank(alice);
        vm.expectRevert(Tap2StacksVault.InvalidAmount.selector);
        vault.withdraw(0, deadline, sig);
    }

    function test_withdrawReplayReverts() public {
        uint256 deadline = block.timestamp + 300;
        bytes memory sig = sign(alice, 30e6, 0, deadline);

        vm.prank(alice);
        vault.withdraw(30e6, deadline, sig);

        vm.prank(alice);
        vm.expectRevert(Tap2StacksVault.BadSignature.selector);
        vault.withdraw(30e6, deadline, sig);
    }

    function test_withdrawExpiredReverts() public {
        uint256 deadline = block.timestamp + 300;
        bytes memory sig = sign(alice, 30e6, 0, deadline);
        vm.warp(deadline + 1);

        vm.prank(alice);
        vm.expectRevert(Tap2StacksVault.Expired.selector);
        vault.withdraw(30e6, deadline, sig);
    }

    function test_permitForAliceCannotPayBob() public {
        uint256 deadline = block.timestamp + 300;
        bytes memory sig = sign(alice, 30e6, 0, deadline);

        vm.prank(bob);
        vm.expectRevert(Tap2StacksVault.BadSignature.selector);
        vault.withdraw(30e6, deadline, sig);
    }

    function test_wrongSignerReverts() public {
        uint256 deadline = block.timestamp + 300;
        bytes32 digest = vault.hashWithdraw(alice, 30e6, 0, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xB0B, digest);
        bytes memory badSig = abi.encodePacked(r, s, v);

        vm.prank(alice);
        vm.expectRevert(Tap2StacksVault.BadSignature.selector);
        vault.withdraw(30e6, deadline, badSig);
    }

    function test_withdrawMoreThanVaultHoldsReverts() public {
        uint256 deadline = block.timestamp + 300;
        uint256 tooMuch = HOUSE + 1e12;
        bytes memory sig = sign(alice, tooMuch, 0, deadline);

        vm.prank(alice);
        vm.expectRevert(Tap2StacksVault.InsufficientVaultBalance.selector);
        vault.withdraw(tooMuch, deadline, sig);
    }

    function test_pausedBlocksDepositAndWithdraw() public {
        vm.prank(owner);
        vault.pause();

        vm.startPrank(alice);
        token.approve(address(vault), 10e6);
        vm.expectRevert();
        vault.deposit(10e6);
        vm.stopPrank();

        uint256 deadline = block.timestamp + 300;
        bytes memory sig = sign(alice, 10e6, 0, deadline);
        vm.prank(alice);
        vm.expectRevert();
        vault.withdraw(10e6, deadline, sig);

        vm.prank(owner);
        vault.unpause();

        vm.prank(alice);
        vault.withdraw(10e6, deadline, sig);
        assertEq(vault.nonces(alice), 1);
    }

    function test_onlyOwnerSeedsAndSetsSigner() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.seedHouse(1e6);

        vm.prank(alice);
        vm.expectRevert();
        vault.setWithdrawSigner(alice);

        vm.prank(alice);
        vm.expectRevert();
        vault.pause();

        address newSigner = address(0x9999);
        vm.expectEmit(false, false, false, true);
        emit Tap2StacksVault.WithdrawSignerChanged(newSigner);
        vm.prank(owner);
        vault.setWithdrawSigner(newSigner);
        assertEq(vault.withdrawSigner(), newSigner);
    }
}

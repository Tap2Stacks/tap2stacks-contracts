// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title Tap2StacksVault
/// @notice Escrow vault for tUSDC deposits and EIP-712 permit-authorized withdrawals.
contract Tap2StacksVault is EIP712, Ownable, Pausable {
    using SafeERC20 for IERC20;

    bytes32 public constant WITHDRAW_TYPEHASH =
        keccak256("Withdraw(address player,uint256 amount,uint256 nonce,uint256 deadline)");

    IERC20 public immutable token;
    address public withdrawSigner;
    mapping(address => uint256) public nonces;

    event Deposited(address indexed player, uint256 amount);
    event Withdrawn(address indexed player, uint256 amount, uint256 nonce);
    event HouseSeeded(uint256 amount);
    event WithdrawSignerChanged(address newSigner);

    error InvalidAmount();
    error Expired();
    error BadSignature();
    error InsufficientVaultBalance();

    constructor(IERC20 token_, address owner_, address withdrawSigner_)
        EIP712("Tap2StacksVault", "1")
        Ownable(owner_)
    {
        token = token_;
        withdrawSigner = withdrawSigner_;
    }

    /// @notice Computes the full EIP-712 digest for a withdrawal permit.
    function hashWithdraw(address player, uint256 amount, uint256 nonce, uint256 deadline)
        public
        view
        returns (bytes32)
    {
        return _hashTypedDataV4(keccak256(abi.encode(WITHDRAW_TYPEHASH, player, amount, nonce, deadline)));
    }

    /// @notice Deposits `amount` of `token` from the caller into the vault.
    function deposit(uint256 amount) external whenNotPaused {
        if (amount == 0) revert InvalidAmount();
        token.safeTransferFrom(msg.sender, address(this), amount);
        emit Deposited(msg.sender, amount);
    }

    /// @notice Withdraws `amount` to `msg.sender` using an EIP-712 permit signed by `withdrawSigner`.
    function withdraw(uint256 amount, uint256 deadline, bytes calldata signature) external whenNotPaused {
        if (amount == 0) revert InvalidAmount();
        if (block.timestamp > deadline) revert Expired();

        uint256 nonce = nonces[msg.sender];
        bytes32 digest = hashWithdraw(msg.sender, amount, nonce, deadline);
        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecoverCalldata(digest, signature);
        if (err != ECDSA.RecoverError.NoError || recovered == address(0) || recovered != withdrawSigner) {
            revert BadSignature();
        }

        if (token.balanceOf(address(this)) < amount) revert InsufficientVaultBalance();

        nonces[msg.sender] = nonce + 1;
        token.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount, nonce);
    }

    /// @notice Seeds the house liquidity in the vault from the owner's balance.
    function seedHouse(uint256 amount) external onlyOwner {
        if (amount == 0) revert InvalidAmount();
        token.safeTransferFrom(msg.sender, address(this), amount);
        emit HouseSeeded(amount);
    }

    /// @notice Updates the authorized EIP-712 withdrawal signer.
    function setWithdrawSigner(address newSigner) external onlyOwner {
        withdrawSigner = newSigner;
        emit WithdrawSignerChanged(newSigner);
    }

    /// @notice Pauses deposits and withdrawals.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses deposits and withdrawals.
    function unpause() external onlyOwner {
        _unpause();
    }
}

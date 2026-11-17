// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title TestUSDC
/// @notice 6-decimal test USD token with a rate-limited daily faucet and owner minting.
contract TestUSDC is ERC20, Ownable {
    uint256 public constant FAUCET_AMOUNT = 100e6;
    uint256 public constant FAUCET_COOLDOWN = 1 days;

    error FaucetCooldown(uint256 nextAt);

    mapping(address => uint256) private _lastClaim;

    constructor(address owner) ERC20("tap2stacks Test USD", "tUSDC") Ownable(owner) {}

    /// @notice Returns 6 decimals to match USDC.
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /// @notice Returns the earliest timestamp `account` may call `faucet()` again, or 0 if never claimed.
    function nextClaimAt(address account) public view returns (uint256) {
        uint256 last = _lastClaim[account];
        return last == 0 ? 0 : last + FAUCET_COOLDOWN;
    }

    /// @notice Mints `FAUCET_AMOUNT` to the caller once per `FAUCET_COOLDOWN`.
    function faucet() external {
        uint256 nextAt = nextClaimAt(msg.sender);
        if (nextAt != 0 && block.timestamp < nextAt) {
            revert FaucetCooldown(nextAt);
        }
        _lastClaim[msg.sender] = block.timestamp;
        _mint(msg.sender, FAUCET_AMOUNT);
    }

    /// @notice Mints arbitrary `amount` to `to`; restricted to the contract owner.
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}

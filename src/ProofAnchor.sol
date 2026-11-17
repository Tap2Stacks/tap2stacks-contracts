// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title ProofAnchor
/// @notice Anchors monotonic, non-overlapping Merkle roots for settled taps and price logs.
contract ProofAnchor is Ownable {
    struct Anchor {
        bytes32 tapsRoot;
        bytes32 priceLogHash;
        uint64 fromMs;
        uint64 toMs;
    }

    address public relayer;
    uint64 public lastToMs;
    Anchor[] public anchors;

    event RootPosted(uint256 indexed index, bytes32 tapsRoot, bytes32 priceLogHash, uint64 fromMs, uint64 toMs);

    error NotRelayer();
    error BadRange();

    constructor(address owner_, address relayer_) Ownable(owner_) {
        relayer = relayer_;
    }

    /// @notice Posts a settled window proof root; requires `fromMs < toMs` and `fromMs >= lastToMs`.
    function postRoot(bytes32 tapsRoot, bytes32 priceLogHash, uint64 fromMs, uint64 toMs) external {
        if (msg.sender != relayer) revert NotRelayer();
        if (fromMs >= toMs || fromMs < lastToMs) revert BadRange();

        lastToMs = toMs;
        uint256 index = anchors.length;
        anchors.push(Anchor({tapsRoot: tapsRoot, priceLogHash: priceLogHash, fromMs: fromMs, toMs: toMs}));
        emit RootPosted(index, tapsRoot, priceLogHash, fromMs, toMs);
    }

    /// @notice Returns the total number of posted anchors.
    function count() external view returns (uint256) {
        return anchors.length;
    }

    /// @notice Updates the authorized relayer address.
    function setRelayer(address newRelayer) external onlyOwner {
        relayer = newRelayer;
    }
}

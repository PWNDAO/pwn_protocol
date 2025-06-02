// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

/**
 * @title IERC5646
 * @notice Interface of the ERC5646 standard, as defined in the https://eips.ethereum.org/EIPS/eip-5646.
 */
interface IERC5646 {

    /**
     * @notice Function to return current token state fingerprint.
     * @param tokenId Id of a token state in question.
     * @return Current token state fingerprint.
     */
    function getStateFingerprint(uint256 tokenId) external view returns (bytes32);

}

// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

/**
 * @title IStateFingerpringComputer
 * @notice State Fingerprint Computer Interface.
 * @dev Contract can compute state fingerprint of several tokens as long as they share the same state structure.
 */
interface IStateFingerpringComputer {

    /**
     * @notice Compute current token state fingerprint for a given token.
     * @param token Address of a token contract.
     * @param tokenId Token id to compute state fingerprint for.
     * @return Current token state fingerprint.
     */
    function computeStateFingerprint(address token, uint256 tokenId) external view returns (bytes32);

    /**
     * @notice Check if the computer supports a given token address.
     * @param token Address of a token contract.
     * @return True if the computer supports the token address, false otherwise.
     */
    function supportsToken(address token) external view returns (bool);

}

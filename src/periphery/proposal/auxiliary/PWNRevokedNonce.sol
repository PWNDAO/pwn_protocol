// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { PWNHub } from "pwn/core/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/core/hub/PWNHubTags.sol";


/**
 * @title PWN Revoked Nonce
 * @notice Contract holding revoked nonces.
 */
contract PWNRevokedNonce {

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    /**
     * @notice Access tag that needs to be assigned to a caller in PWN Hub
     * to call functions that revoke nonces on behalf of an owner.
     */
    bytes32 public immutable accessTag;

    /**
     * @notice PWN Hub contract.
     * @dev Addresses revoking nonces on behalf of an owner need to have an access tag in PWN Hub.
     */
    PWNHub public immutable hub;

    /** @notice Mapping of revoked nonces by an address. Every address has its own nonce space.*/
    mapping (address => mapping (uint256 => mapping (uint256 => bool))) private _revokedNonce;

    /** @notice Mapping of current nonce space for an address.*/
    mapping (address => uint256) private _nonceSpace;


    /*----------------------------------------------------------*|
    |*  # EVENTS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /** @notice Emitted when a nonce is revoked.*/
    event NonceRevoked(address indexed owner, uint256 indexed nonceSpace, uint256 indexed nonce);
    /** @notice Emitted when a nonce is revoked.*/
    event NonceSpaceRevoked(address indexed owner, uint256 indexed nonceSpace);


    /*----------------------------------------------------------*|
    |*  # ERRORS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /** @notice Thrown when an address is missing a PWN Hub tag.*/
    error AddressMissingHubTag(address addr, bytes32 tag);
    /** @notice Thrown when trying to revoke a nonce that is already revoked.*/
    error NonceAlreadyRevoked(address addr, uint256 nonceSpace, uint256 nonce);

    /**
     * @notice Thrown when nonce is currently not usable.
     * @dev Maybe nonce is revoked or not in the current nonce space.
     */
    error NonceNotUsable(address addr, uint256 nonceSpace, uint256 nonce);


    /*----------------------------------------------------------*|
    |*  # MODIFIERS                                             *|
    |*----------------------------------------------------------*/

    modifier onlyWithHubTag() {
        if (!hub.hasTag(msg.sender, accessTag))
            revert AddressMissingHubTag({ addr: msg.sender, tag: accessTag });
        _;
    }


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(address _hub, bytes32 _accessTag) {
        accessTag = _accessTag;
        hub = PWNHub(_hub);
    }


    /*----------------------------------------------------------*|
    |*  # NONCE                                                 *|
    |*----------------------------------------------------------*/

    /**
     * @notice Revoke callers nonce in the current nonce space.
     * @param nonce Nonce to be revoked.
     */
    function revokeNonce(uint256 nonce) external {
        _revokeNonce(msg.sender, _nonceSpace[msg.sender], nonce);
    }

    /**
     * @notice Revoke multiple caller nonces in the current nonce space.
     * @param nonces List of nonces to be revoked.
     */
    function revokeNonces(uint256[] calldata nonces) external {
        uint256 nonceSpace = _nonceSpace[msg.sender];
        for (uint256 i; i < nonces.length; ++i) {
            _revokeNonce(msg.sender, nonceSpace, nonces[i]);
        }
    }

    /**
     * @notice Revoke caller nonce in a nonce space.
     * @param nonceSpace Nonce space where a nonce will be revoked.
     * @param nonce Nonce to be revoked.
     */
    function revokeNonce(uint256 nonceSpace, uint256 nonce) external {
        _revokeNonce(msg.sender, nonceSpace, nonce);
    }

    /**
     * @notice Revoke a nonce in the current nonce space on behalf of an owner.
     * @dev Only an address with associated access tag in PWN Hub can call this function.
     * @param owner Owner address of a revoking nonce.
     * @param nonce Nonce to be revoked.
     */
    function revokeNonce(address owner, uint256 nonce) external onlyWithHubTag {
        _revokeNonce(owner, _nonceSpace[owner], nonce);
    }

    /**
     * @notice Revoke a nonce in a nonce space on behalf of an owner.
     * @dev Only an address with associated access tag in PWN Hub can call this function.
     * @param owner Owner address of a revoking nonce.
     * @param nonceSpace Nonce space where a nonce will be revoked.
     * @param nonce Nonce to be revoked.
     */
    function revokeNonce(address owner, uint256 nonceSpace, uint256 nonce) external onlyWithHubTag {
        _revokeNonce(owner, nonceSpace, nonce);
    }

    /**
     * @notice Internal function to revoke a nonce in a nonce space.
     */
    function _revokeNonce(address owner, uint256 nonceSpace, uint256 nonce) private {
        if (_revokedNonce[owner][nonceSpace][nonce]) {
            revert NonceAlreadyRevoked({ addr: owner, nonceSpace: nonceSpace, nonce: nonce });
        }
        _revokedNonce[owner][nonceSpace][nonce] = true;
        emit NonceRevoked(owner, nonceSpace, nonce);
    }

    /**
     * @notice Return true if owners nonce is revoked in the given nonce space.
     * @dev Do not use this function to check if nonce is usable.
     *      Use `isNonceUsable` instead, which checks nonce space as well.
     * @param owner Address of a nonce owner.
     * @param nonceSpace Value of a nonce space.
     * @param nonce Value of a nonce.
     * @return True if nonce is revoked.
     */
    function isNonceRevoked(address owner, uint256 nonceSpace, uint256 nonce) external view returns (bool) {
        return _revokedNonce[owner][nonceSpace][nonce];
    }

    /**
     * @notice Return true if owners nonce is usable. Nonce is usable if it is not revoked and in the current nonce space.
     * @param owner Address of a nonce owner.
     * @param nonceSpace Value of a nonce space.
     * @param nonce Value of a nonce.
     * @return True if nonce is usable.
     */
    function isNonceUsable(address owner, uint256 nonceSpace, uint256 nonce) external view returns (bool) {
        if (_nonceSpace[owner] != nonceSpace)
            return false;

        return !_revokedNonce[owner][nonceSpace][nonce];
    }


    /*----------------------------------------------------------*|
    |*  # NONCE SPACE                                           *|
    |*----------------------------------------------------------*/

    /**
     * @notice Revoke all nonces in the current nonce space and increment nonce space.
     * @dev Caller is used as a nonce owner.
     * @return New nonce space.
     */
    function revokeNonceSpace() external returns (uint256) {
        emit NonceSpaceRevoked(msg.sender, _nonceSpace[msg.sender]);
        return ++_nonceSpace[msg.sender];
    }

    /**
     * @notice Return current nonce space for an address.
     * @param owner Address of a nonce owner.
     * @return Current nonce space.
     */
    function currentNonceSpace(address owner) external view returns (uint256) {
        return _nonceSpace[owner];
    }

}

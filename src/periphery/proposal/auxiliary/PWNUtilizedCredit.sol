// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { PWNHub } from "pwn/core/hub/PWNHub.sol";


/**
 * @title PWN Utilized Credit Contract
 * @notice Contract holding utilized credit.
 */
contract PWNUtilizedCredit {

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    /**
     * @notice Access tag that needs to be assigned to a caller in PWN Hub
     * to call functions that update utilized credit.
     */
    bytes32 public immutable accessTag;

    /**
     * @notice PWN Hub contract.
     * @dev Addresses updating utilized credit need to have an access tag in PWN Hub.
     */
    PWNHub public immutable hub;

    /**
     * @notice Mapping of credit utilized by an id with defined available credit limit.
     * (owner => id => utilized credit)
     */
    mapping (address => mapping (bytes32 => uint256)) public utilizedCredit;


    /*----------------------------------------------------------*|
    |*  # ERRORS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /** @notice Thrown when an address is missing a PWN Hub tag.*/
    error AddressMissingHubTag(address addr, bytes32 tag);
    /** @notice Thrown when an id would exceed the available credit limit.*/
    error AvailableCreditLimitExceeded(address owner, bytes32 id, uint256 utilized, uint256 limit);


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
    |*  # UTILIZED CREDIT                                       *|
    |*----------------------------------------------------------*/

    /**
     * @notice Update utilized credit for an owner with an id.
     * @dev Function will revert if utilized credit would exceed the available credit limit.
     * @param owner Owner of the utilized credit.
     * @param id Id of the utilized credit.
     * @param amount Amount to update utilized credit.
     * @param limit Available credit limit.
     */
    function utilizeCredit(address owner, bytes32 id, uint256 amount, uint256 limit) external onlyWithHubTag {
        uint256 extendedAmount = utilizedCredit[owner][id] + amount;
        if (extendedAmount > limit) {
            revert AvailableCreditLimitExceeded({ owner: owner, id: id, utilized: extendedAmount, limit: limit });
        }

        utilizedCredit[owner][id] = extendedAmount;
    }

}

// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

/**
 * @notice Struct defining loan terms.
 * @dev This struct is created by proposal contracts and never stored.
 * @param isProposerLender Indicates if the proposer is the lender.
 * @param proposerSpecHash Hash of a proposer specification.
 * @param collateral Asset used as a loan collateral. For a definition see { MultiToken dependency lib }.
 * @param creditAddress Address of an asset used as credit.
 * @param principal Amount of credit.
 */
struct LoanTerms {
    bool isProposerLender;
    bytes32 proposerSpecHash;
    MultiToken.Asset collateral;
    address creditAddress;
    uint256 principal;
}

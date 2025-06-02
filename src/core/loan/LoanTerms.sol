// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";


/**
 * @notice Struct defining loan terms.
 * @dev This struct is created by proposal contracts and never stored.
 * @param proposalHash Hash of a proposal that created this loan terms.
 * @param lender Address of a lender.
 * @param borrower Address of a borrower.
 * @param proposerSpecHash Hash of a proposer specification.
 * @param duration Loan duration in seconds.
 * @param collateral Asset used as a loan collateral. For a definition see { MultiToken dependency lib }.
 * @param creditAddress Address of an asset used as credit.
 * @param principal Amount of credit.
 * @param interestModule Address of an interest module. It is a contract which defines the interest rate.
 * @param interestModuleProposerData Proposer data passed to an interest module when a loan is created.
 * @param defaultModule Address of a default module. It is a contract which defines the default conditions.
 * @param defaultModuleProposerData Proposer data passed to a default module when a loan is created.
 * @param liquidationModule Address that can call liquidation for defaulted loans.
 * @param liquidationModuleProposerData Proposer data passed to a liquidation module when a loan is created.
 */
struct LoanTerms {
    bytes32 proposalHash;
    address lender;
    address borrower;
    bytes32 proposerSpecHash;
    MultiToken.Asset collateral;
    address creditAddress;
    uint256 principal;
    address interestModule;
    bytes interestModuleProposerData;
    address defaultModule;
    bytes defaultModuleProposerData;
    address liquidationModule;
    bytes liquidationModuleProposerData;
}

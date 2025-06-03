// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { IPWNLiquidationModule, LIQUIDATION_MODULE_INIT_HOOK_RETURN_VALUE } from "pwn/core/loan/module/IPWNLiquidationModule.sol";
import { PWNLoan } from "pwn/core/loan/PWNLoan.sol";


contract PWNClaimLiquidationModule is IPWNLiquidationModule {
    using MultiToken for address;
    using MultiToken for MultiToken.Asset;

    error LiquidatorNotLoanOwner(address owner, address liquidator, address loanContract, uint256 loanId);
    error LiquidationDataNotEmpty();

    function onLoanCreated(uint256 /* loanId */, bytes calldata /* proposerData */) external pure returns (bytes32) {
        return LIQUIDATION_MODULE_INIT_HOOK_RETURN_VALUE;
    }

    /** @dev LOAN owner can claim defaulted loan collateral.*/
    function liquidate(
        uint256 loanId,
        address liquidator,
        uint256 /* debt */,
        address /* creditAddress */,
        MultiToken.Asset calldata collateral,
        bytes calldata data
    ) external returns (uint256) {
        address loanContract = msg.sender;
        address loanOwner = PWNLoan(loanContract).loanToken().ownerOf(loanId);
        if (loanOwner != liquidator) revert LiquidatorNotLoanOwner(loanOwner, liquidator, loanContract, loanId);
        if (data.length != 0) revert LiquidationDataNotEmpty();

        collateral.transferAssetFrom(address(this), loanOwner);

        return 0;
    }

}

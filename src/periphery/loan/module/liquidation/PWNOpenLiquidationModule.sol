// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { IPWNLiquidationModule, LIQUIDATION_MODULE_INIT_HOOK_RETURN_VALUE } from "pwn/core/loan/module/IPWNLiquidationModule.sol";
import { PWNLoan } from "pwn/core/loan/PWNLoan.sol";


contract PWNOpenLiquidationModule is IPWNLiquidationModule {
    using MultiToken for address;
    using MultiToken for MultiToken.Asset;

    error LiquidationDataNotEmpty();

    function onLoanCreated(uint256 /* loanId */, bytes calldata /* proposerData */) external pure returns (bytes32) {
        return LIQUIDATION_MODULE_INIT_HOOK_RETURN_VALUE;
    }

    /** @dev Anyone can liquidate defaulted loan by repaying full debt.*/
    function liquidate(
        uint256 /* loanId */,
        address liquidator,
        uint256 debt,
        address creditAddress,
        MultiToken.Asset calldata collateral,
        bytes calldata data
    ) external returns (uint256) {
        if (data.length != 0) revert LiquidationDataNotEmpty();

        MultiToken.Asset memory credit = creditAddress.ERC20(debt);
        credit.transferAssetFrom(liquidator, address(this));
        credit.approveAsset(msg.sender); // Note: approve loan contract

        collateral.transferAssetFrom(address(this), liquidator);

        return debt;
    }

}

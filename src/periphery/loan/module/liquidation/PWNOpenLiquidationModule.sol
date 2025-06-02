// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { IPWNLiquidationModule, LIQUIDATION_MODULE_INIT_HOOK_RETURN_VALUE } from "pwn/core/loan/module/IPWNLiquidationModule.sol";
import { PWNLoan } from "pwn/core/loan/PWNLoan.sol";


contract PWNOpenLiquidationModule is IPWNLiquidationModule {
    using MultiToken for address;
    using MultiToken for MultiToken.Asset;

    function onLoanCreated(uint256 /* loanId */, bytes calldata /* proposerData */) external pure returns (bytes32) {
        return LIQUIDATION_MODULE_INIT_HOOK_RETURN_VALUE;
    }

    /** @dev Anyone can liquidate defaulted loan by repaying full debt.*/
    function liquidate(address loanContract, uint256 loanId) external {
        PWNLoan.LOAN memory loan = PWNLoan(loanContract).getLOAN(loanId);
        uint256 debt = PWNLoan(loanContract).getLOANDebt(loanId);

        MultiToken.Asset memory credit = loan.creditAddress.ERC20(debt);
        credit.transferAssetFrom(msg.sender, address(this));
        credit.approveAsset(loanContract);
        PWNLoan(loanContract).liquidate(loanId, debt);
        loan.collateral.transferAssetFrom(address(this), msg.sender);
    }

}

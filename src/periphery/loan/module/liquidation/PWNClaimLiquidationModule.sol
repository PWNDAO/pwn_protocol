// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { IPWNLiquidationModule, LIQUIDATION_MODULE_INIT_HOOK_RETURN_VALUE } from "pwn/core/loan/module/IPWNLiquidationModule.sol";
import { PWNLoan } from "pwn/core/loan/PWNLoan.sol";


contract PWNClaimLiquidationModule is IPWNLiquidationModule {
    using MultiToken for address;
    using MultiToken for MultiToken.Asset;

    error CallerNotLoanOwner(address owner, address caller, address loanContract, uint256 loanId);

    function onLoanCreated(uint256 /* loanId */, bytes calldata /* proposerData */) external pure returns (bytes32) {
        return LIQUIDATION_MODULE_INIT_HOOK_RETURN_VALUE;
    }

    /** @dev LOAN owner can claim defaulted loan collateral.*/
    function liquidate(address loanContract, uint256 loanId) external {
        address loanOwner = PWNLoan(loanContract).loanToken().ownerOf(loanId);
        if (loanOwner != msg.sender) {
            revert CallerNotLoanOwner(loanOwner, msg.sender, loanContract, loanId);
        }
        PWNLoan.LOAN memory loan = PWNLoan(loanContract).getLOAN(loanId);

        PWNLoan(loanContract).liquidate(loanId, 0);
        loan.collateral.transferAssetFrom(address(this), msg.sender);
    }

}

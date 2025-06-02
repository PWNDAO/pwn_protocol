// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { IPWNLenderRepaymentHook, LENDER_REPAYMENT_HOOK_RETURN_VALUE } from "pwn/core/loan/hook/IPWNLenderRepaymentHook.sol";
import { IAaveLike } from "pwn/periphery/interfaces/IAaveLike.sol";


contract PWNAaveLenderRepaymentHook is IPWNLenderRepaymentHook {
    using MultiToken for address;
    using MultiToken for MultiToken.Asset;

    IAaveLike public immutable pool;

    error PoolZeroAddress();
    error LenderZeroAddress();
    error CreditZeroAddress();
    error RepaymentZero();
    error DataNotEmpty();


    constructor(IAaveLike _pool) {
        if (address(_pool) == address(0)) revert PoolZeroAddress();
        pool = _pool;
    }


    function onLoanRepaid(
        address lender,
        address creditAddress,
        uint256 repayment,
        bytes calldata lenderData
    ) external returns (bytes32) {
        if (lender == address(0)) revert LenderZeroAddress();
        if (creditAddress == address(0)) revert CreditZeroAddress();
        if (repayment == 0) revert RepaymentZero();
        if (lenderData.length == 0) revert DataNotEmpty();

        // Supply to the pool on behalf of the owner
        creditAddress.ERC20(repayment).approveAsset(address(pool));
        pool.supply(creditAddress, repayment, lender, 0);

        return LENDER_REPAYMENT_HOOK_RETURN_VALUE;
    }

}

// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { PWNHub } from "pwn/core/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/core/hub/PWNHubTags.sol";
import { IPWNBorrowerCreateHook, BORROWER_CREATE_HOOK_RETURN_VALUE } from "pwn/core/loan/hook/IPWNBorrowerCreateHook.sol";
import { PWNLoan } from "pwn/core/loan/PWNLoan.sol";


contract PWNRefinanceBorrowerCreateHook is IPWNBorrowerCreateHook {
    using MultiToken for MultiToken.Asset;
    using MultiToken for address;

    PWNHub public immutable hub;

    struct HookData {
        uint256 refinanceLoanId;
    }

    error HubZeroAddress();
    error CallerNotActiveLoan();
    error BorrowerZeroAddress();
    error CreditZeroAddress();
    error PrincipalZero();
    error CreditMismatch();
    error CollateralMismatch();


    constructor(PWNHub _hub) {
        if (address(_hub) == address(0)) revert HubZeroAddress();
        hub = _hub;
    }


    function onLoanCreated(
        address borrower,
        MultiToken.Asset calldata collateral,
        address creditAddress,
        uint256 principal,
        bytes calldata borrowerData
    ) external returns (bytes32) {
        if (!hub.hasTag(msg.sender, PWNHubTags.ACTIVE_LOAN)) revert CallerNotActiveLoan();

        if (borrower == address(0)) revert BorrowerZeroAddress();
        if (creditAddress == address(0)) revert CreditZeroAddress();
        if (principal == 0) revert PrincipalZero();
        HookData memory data = abi.decode(borrowerData, (HookData));

        uint256 debt = PWNLoan(msg.sender).getLOANDebt(data.refinanceLoanId);
        PWNLoan.LOAN memory loan = PWNLoan(msg.sender).getLOAN(data.refinanceLoanId);

        if (loan.creditAddress != creditAddress) revert CreditMismatch();
        if (!loan.collateral.isSameAs(collateral)) revert CollateralMismatch();

        MultiToken.Asset memory credit = creditAddress.ERC20(debt);
        credit.transferAssetFrom(borrower, address(this));
        credit.approveAsset(msg.sender);
        PWNLoan(msg.sender).repay(data.refinanceLoanId, 0);

        return BORROWER_CREATE_HOOK_RETURN_VALUE;
    }

}

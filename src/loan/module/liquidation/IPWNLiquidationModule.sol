// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { IPWNModuleInitializationHook } from "pwn/loan/module/IPWNModuleInitializationHook.sol";

bytes32 constant LIQUIDATION_MODULE_INIT_HOOK_RETURN_VALUE = keccak256("PWNLiquidationModule.onLoanCreated");

/**
 * @title IPWNLiquidationModule
 * @notice Interface for PWN liquidation modules used by the PWNLoan contract.
 *
 * @dev This module is set per-loan at origination and is immutable for the loan's lifetime.
 * The module has the right to call liquidation on the Loan contract when a loan is in default,
 * as determined by the default module. When liquidation is triggered, the collateral is transferred
 * to the liquidation module, which is then responsible for executing the liquidation process
 * (e.g., auction, direct sale, or other custom logic).
 *
 * The module can define its own function that will be called to execute the liquidation logic.
 * This function is never called by the Loan contract; it is intended to be called by external actors
 * as part of the liquidation process.
 *
 * The module must implement the `onLoanCreated` initialization hook, which is called by PWNLoan
 * at loan origination to configure the module for the specific loan. The hook must return a keccak256 hash
 * of "PWNLiquidationModule.onLoanCreated".
 */
interface IPWNLiquidationModule is IPWNModuleInitializationHook {}

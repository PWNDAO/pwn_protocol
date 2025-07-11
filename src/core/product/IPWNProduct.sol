// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { IPWNProposalModule } from "pwn/core/loan/module/IPWNProposalModule.sol";
import { IPWNInterestModule } from "pwn/core/loan/module/IPWNInterestModule.sol";
import { IPWNDefaultModule } from "pwn/core/loan/module/IPWNDefaultModule.sol";
import { IPWNLiquidationModule } from "pwn/core/loan/module/IPWNLiquidationModule.sol";

/**
 * @title IPWNProduct
 * @notice Interface for PWN products that define the complete lifecycle of a loan.
 *
 * @dev This interface combines proposal, interest, default, and liquidation modules into a single product.
 * Each product can have its own implementation of these modules, allowing for flexible loan terms and conditions.
 * The product is used to create loans with specific terms and conditions defined by the modules it implements.
 */
interface IPWNProduct is IPWNProposalModule, IPWNInterestModule, IPWNDefaultModule, IPWNLiquidationModule {}

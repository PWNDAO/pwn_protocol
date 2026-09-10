// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import {
    PWNCrowdsourceLenderVault, Math, PWNLoan, PWNInstallmentsProduct, IAaveLike
} from "pwn/periphery/crowdsource/PWNCrowdsourceLenderVault.sol";


contract PWNCrowdsourceLenderVaultHarness is PWNCrowdsourceLenderVault {
    using Math for uint256;

    uint256 public convertToSharesRatio; // with 4 decimals
    uint256 public convertToAssetsRatio; // with 4 decimals
    uint256 public convertToCollateralAssetsRatio; // with 4 decimals

    constructor(
        PWNLoan _loan,
        PWNInstallmentsProduct _product,
        IAaveLike _aave,
        string memory _name,
        string memory _symbol,
        Terms memory _terms
    ) PWNCrowdsourceLenderVault(_loan, _product, _aave, _name, _symbol, _terms) {}

    // # Exposed

    function exposed_stage() external view returns (PWNCrowdsourceLenderVault.Stage) {
        return stage();
    }

    function exposed_convertToCollateralAssets(uint256 shares, Math.Rounding rounding) external view returns (uint256) {
        return _convertToCollateralAssets(shares, rounding);
    }

    // # Workarounds

    function workaround_setLoanId(uint256 _loanId) external {
        loanId = _loanId;
    }

    function workaround_setLoanEnded(bool _loanEnded) external {
        loanEnded = _loanEnded;
    }

    function workaround_setConvertToSharesRatio(uint256 _convertToSharesRatio) external {
        convertToSharesRatio = _convertToSharesRatio;
    }

    function workaround_setConvertToAssetsRatio(uint256 _convertToAssetsRatio) external {
        convertToAssetsRatio = _convertToAssetsRatio;
    }

    function workaround_setConvertToCollateralAssetsRatio(uint256 _convertToCollateralAssetsRatio) external {
        convertToCollateralAssetsRatio = _convertToCollateralAssetsRatio;
    }

    // # Overrides

    function _convertToShares(uint256 assets, Math.Rounding rounding) override internal view returns (uint256) {
        if (convertToSharesRatio != 0) {
            return assets.mulDiv(convertToSharesRatio, 1e4, rounding);
        } else {
            return super._convertToShares(assets, rounding);
        }
    }

    function _convertToAssets(uint256 shares, Math.Rounding rounding) override internal view returns (uint256) {
        if (convertToAssetsRatio != 0) {
            return shares.mulDiv(convertToAssetsRatio, 1e4, rounding);
        } else {
            return super._convertToAssets(shares, rounding);
        }
    }

    function _convertToCollateralAssets(uint256 shares, Math.Rounding rounding) override internal view returns (uint256) {
        if (convertToCollateralAssetsRatio != 0) {
            return shares.mulDiv(convertToCollateralAssetsRatio, 1e4, rounding);
        } else {
            return super._convertToCollateralAssets(shares, rounding);
        }
    }

}

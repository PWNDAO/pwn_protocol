// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { ERC4626, ERC20, IERC20, IERC20Metadata, Math, SafeERC20 } from "openzeppelin/token/ERC20/extensions/ERC4626.sol";
import { IERC721Receiver } from "openzeppelin/token/ERC721/IERC721Receiver.sol";

import {
    PWNLoan, LOANStatus, PWNLOAN,
    IPWNLenderCreateHook, LENDER_CREATE_HOOK_RETURN_VALUE,
    IPWNLenderRepaymentHook, LENDER_REPAYMENT_HOOK_RETURN_VALUE
} from "pwn/core/loan/PWNLoan.sol";
import { PWNInstallmentsProduct } from "pwn/periphery/product/PWNInstallmentsProduct.sol";
import { IAaveLike } from "pwn/periphery/interfaces/IAaveLike.sol";


/**
 * @title PWNCrowdsourceLenderVault
 * @notice A vault that pools assets to lend through a PWNLoan contract.
 */
contract PWNCrowdsourceLenderVault is ERC4626, IPWNLenderCreateHook, IPWNLenderRepaymentHook, IERC721Receiver {
    using Math for uint256;

    /** @notice The PWNLoan contract through which the loan is created.*/
    PWNLoan immutable public loanContract;
    /** @notice The proposal contract that creates the loan proposal.*/
    PWNInstallmentsProduct immutable public product;
    /** @notice The Aave lending pool contract.*/
    IAaveLike immutable public aave;
    /**
     * @notice The address of the aToken for the asset, if exists.
     * @dev The aToken is used to earn interest on the assets while they are being pooled.
     */
    address immutable internal aAsset;
    /** @notice The address of the collateral token.*/
    address immutable internal collateralAddr;
    /** @notice The number of decimals of the collateral token.*/
    uint8 immutable internal collateralDecimals;
    /**
     * @notice The hash of the loan proposal.
     * @dev The proposal is made on vault deployment.
     */
    bytes32 immutable internal proposalHash;

    /** @notice The ID of the loan funded by the vault.*/
    uint256 public loanId;
    /**
     * @notice Whether the loan has ended.
     * @dev The loan ends when it is repaid or defaulted.
     */
    bool internal loanEnded;

    /**
     * @notice The stages of the vault.
     * @dev The vault can be in the POOLING, RUNNING, or ENDING stage.
     * POOLING: The vault is pooling assets. Anyone can freely deposit and withdraw. The vault automatically supplies assets to Aave, if possible.
     * RUNNING: The vault has funded a loan and is running. No new deposits are allowed. The vault automatically claims repayments on every withdrawal.
     * ENDING: The funded loan ended. Only redeeming is allowed. The vault automatically claims the remaining loan amount or defaulted collateral.
     */
    enum Stage {
        POOLING, RUNNING, ENDING
    }

    /** @notice The terms of the loan proposal.*/
    struct Terms {
        address collateralAddress;
        address creditAddress;
        address[] feedIntermediaryDenominations;
        bool[] feedInvertFlags;
        uint256 loanToValue;
        uint256 interestAPR;
        uint256 postponement;
        uint256 duration;
        uint256 minCreditAmount;
        uint256 expiration;
        address allowedAcceptor;
    }

    /*** @notice Emitted when collateral is withdrawn.*/
    event WithdrawCollateral(address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);


    constructor(
        PWNLoan _loan,
        PWNInstallmentsProduct _product,
        IAaveLike _aave,
        string memory _name,
        string memory _symbol,
        Terms memory _terms
    ) ERC4626(IERC20(_terms.creditAddress)) ERC20(_name, _symbol) {
        loanContract = _loan;
        product = _product;
        aave = _aave;

        collateralAddr = _terms.collateralAddress;
        (bool success, uint8 decimals) = _tryGetAssetDecimals_child(IERC20(collateralAddr));
        if (!success) {
            revert("PWNCrowdsourceLenderVault: collateral token missing decimals");
        }
        collateralDecimals = decimals;

        // TODO should we check the values here that they are correct?

        // TODO should we check here that the getCollateralAmount on installments product contract returns
        //  positive result (to ensure that the feeds are set up correctly)?

        proposalHash = loanContract.makeProposalAcceptable(product, abi.encode(
            PWNInstallmentsProduct.Proposal({
                collateralAddress: _terms.collateralAddress,
                creditAddress: _terms.creditAddress,
                feedIntermediaryDenominations: _terms.feedIntermediaryDenominations,
                feedInvertFlags: _terms.feedInvertFlags,
                loanToValue: _terms.loanToValue,
                interestAPR: _terms.interestAPR,
                duration: _terms.duration,
                postponement: _terms.postponement,
                minCreditAmount: _terms.minCreditAmount,
                allowedAcceptor: _terms.allowedAcceptor,
                availableCreditLimit: 0,
                utilizedCreditId: bytes32(0),
                nonceSpace: 0,
                nonce: 0,
                expiration: _terms.expiration,
                proposerSpecHash: loanContract.getLenderSpecHash(PWNLoan.LenderSpec({
                    createHook: this, createHookData: "", repaymentHook: this, repaymentHookData: ""
                })),
                isProposerLender: true,
                loanContract: address(loanContract)
            })
        ));

        IERC20(asset()).approve(address(loanContract), type(uint256).max);

        IAaveLike.ReserveData memory reserveData = aave.getReserveData(asset());
        aAsset = reserveData.aTokenAddress;
        if (aAsset != address(0)) {
            IERC20(asset()).approve(address(aave), type(uint256).max);
        }
    }


    /** @notice The stage of the vault.*/
    function stage() internal view returns (Stage) {
        if (loanId == 0) {
            return Stage.POOLING;
        } else if (loanEnded) {
            return Stage.ENDING;
        }
        return Stage.RUNNING;
    }


    /*----------------------------------------------------------*|
    |*  # ERC4626                                               *|
    |*----------------------------------------------------------*/

    /** @inheritdoc ERC4626*/
    function totalAssets() public view override returns (uint256) {
        uint256 additionalAssets;
        // Note: assuming aToken:token ratio is always 1:1
        // aToken balance is always part of total assets (deposits in POOLING, repayments in RUNNING/ENDING)
        if (aAsset != address(0)) {
            additionalAssets = IERC20(aAsset).balanceOf(address(this));
        }
        Stage _stage = stage();
        if (_stage == Stage.RUNNING && loanContract.getLOANStatus(loanId) == LOANStatus.RUNNING) {
            additionalAssets += loanContract.getLOANDebt(loanId);
        }
        return _availableLiquidity() + additionalAssets;
    }

    // # Max

    /** @inheritdoc ERC4626*/
    function maxDeposit(address) public view override returns (uint256) {
        return stage() == Stage.POOLING ? type(uint256).max : 0;
    }

    /** @inheritdoc ERC4626*/
    function maxMint(address) public view override returns (uint256) {
        return stage() == Stage.POOLING ? type(uint256).max : 0;
    }

    /** @inheritdoc ERC4626*/
    function maxWithdraw(address owner) public view override returns (uint256 max) {
        Stage _stage = stage();
        if (_stage == Stage.ENDING) {
            return 0; // no withdraws allowed, use redeem
        }

        max = _convertToAssets(balanceOf(owner), Math.Rounding.Down);
        if (_stage == Stage.RUNNING) {
            max = Math.min(max, _totalAvailableLiquidity());
        }
    }

    /** @inheritdoc ERC4626*/
    function maxRedeem(address owner) public view override returns (uint256 max) {
        max = balanceOf(owner);
        if (stage() == Stage.RUNNING) {
            max = Math.min(max, _convertToShares(_totalAvailableLiquidity(), Math.Rounding.Down));
        }
    }

    // # Preview

    /** @inheritdoc ERC4626*/
    function previewDeposit(uint256 assets) public view override returns (uint256) {
        require(stage() == Stage.POOLING, "PWNCrowdsourceLenderVault: deposit disabled");
        return _convertToShares(assets, Math.Rounding.Down);
    }

    /** @inheritdoc ERC4626*/
    function previewMint(uint256 shares) public view override returns (uint256) {
        require(stage() == Stage.POOLING, "PWNCrowdsourceLenderVault: mint disabled");
        return _convertToAssets(shares, Math.Rounding.Up);
    }

    /** @inheritdoc ERC4626*/
    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        require(stage() != Stage.ENDING, "PWNCrowdsourceLenderVault: withdraw disabled, use redeem");
        return _convertToShares(assets, Math.Rounding.Up);
    }

    /** @inheritdoc ERC4626*/
    function previewRedeem(uint256 shares) public view override returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Down);
    }

    // # Actions

    /** @inheritdoc ERC4626*/
    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        shares = previewDeposit(assets);
        require(assets <= maxDeposit(receiver), "ERC4626: deposit more than max");
        _deposit(_msgSender(), receiver, assets, shares);
    }

    /** @inheritdoc ERC4626*/
    function mint(uint256 shares, address receiver) public override returns (uint256 assets) {
        assets = previewMint(shares);
        require(shares <= maxMint(receiver), "ERC4626: mint more than max");
        _deposit(_msgSender(), receiver, assets, shares);
    }

    /** @inheritdoc ERC4626*/
    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256 shares) {
        _claimLoanIfPossible();
        shares = previewWithdraw(assets);
        require(assets <= maxWithdraw(owner), "ERC4626: withdraw more than max");
        _withdraw(_msgSender(), receiver, owner, assets, shares);
    }

    /** @inheritdoc ERC4626*/
    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256 assets) {
        _claimLoanIfPossible();

        uint256 collAssets;
        if (stage() == Stage.ENDING) {
            // Note: need to calculate collateral assets before calling _withdraw which burns shares and changes totalSupply
            collAssets = _convertToCollateralAssets(shares, Math.Rounding.Down);
        }

        assets = previewRedeem(shares);
        require(shares <= maxRedeem(owner), "ERC4626: redeem more than max");
        _withdraw(_msgSender(), receiver, owner, assets, shares);

        if (collAssets > 0) {
            SafeERC20.safeTransfer(IERC20(collateralAddr), receiver, collAssets);
            emit WithdrawCollateral(msg.sender, receiver, owner, collAssets, shares);
        }
    }

    function _availableLiquidity() internal view returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    function _totalAvailableLiquidity() internal view returns (uint256) {
        uint256 liquidity = _availableLiquidity();
        if (aAsset != address(0)) {
            liquidity += IERC20(aAsset).balanceOf(address(this));
        }
        return liquidity;
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        super._deposit(caller, receiver, assets, shares);
        if (aAsset != address(0)) {
            aave.supply(asset(), assets, address(this), 0);
        }
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares) internal override {
        if (aAsset != address(0)) {
            Stage _stage = stage();
            if (_stage == Stage.POOLING) {
                // During POOLING, all assets are in Aave
                aave.withdraw(asset(), assets, address(this));
            } else if (_stage == Stage.RUNNING || _stage == Stage.ENDING) {
                // During RUNNING/ENDING, repayments and unutilized capital are in Aave.
                // Withdraw from Aave if we don't have enough cash.
                // Use try/catch so withdrawals of available cash still work if Aave is down.
                uint256 availableCash = _availableLiquidity();
                if (availableCash < assets) {
                    try aave.withdraw(asset(), assets - availableCash, address(this)) {} catch {}
                }
            }
        }
        super._withdraw(caller, receiver, owner, assets, shares);
    }

    function _claimLoanIfPossible() internal {
        if (stage() == Stage.RUNNING) {
            uint8 status = loanContract.getLOANStatus(loanId);
            if (status != LOANStatus.RUNNING) {
                loanEnded = true;
            }
            if (status == LOANStatus.DEFAULTED) {
                loanContract.liquidate(loanId, "");
            }
        }
    }


    /*----------------------------------------------------------*|
    |*  # ERC4626-LIKE COLLATERAL FUNCTIONS                     *|
    |*----------------------------------------------------------*/

    /** @notice ERC4626-like function that returns the total amount of the underlying collateral asset that is “managed” by Vault. */
    function totalCollateralAssets() public view returns (uint256) {
        uint256 additionalCollateralAssets;
        if (stage() == Stage.RUNNING) {
            uint8 status = loanContract.getLOANStatus(loanId);
            if (status == LOANStatus.DEFAULTED) {
                additionalCollateralAssets += loanContract.getLOAN(loanId).collateral.amount;
            }
        }
        return IERC20(collateralAddr).balanceOf(address(this)) + additionalCollateralAssets;
    }

    // TODO shall we keep this as `public`, or only as `external` since so far it's not used internally anywhere?
    // TODO same question for:
    //  1) totalAssets
    //  2) deposit
    //  3) mint
    //  4) withdraw
    //  5) redeem
    //  6) previewCollateralRedeem
    /**
     * @notice ERC4626-like function that allows an on-chain or off-chain user to simulate the effects
     * of their collateral redeemption at the current block, given current on-chain conditions.
     */
    function previewCollateralRedeem(uint256 shares) public view returns (uint256) {
        Stage _stage = stage();
        if (_stage == Stage.RUNNING) {
            require(loanContract.getLOANStatus(loanId) == LOANStatus.DEFAULTED, "PWNCrowdsourceLenderVault: collateral redeem disabled");
        } else {
            require(_stage == Stage.ENDING, "PWNCrowdsourceLenderVault: collateral redeem disabled");
        }

        return _convertToCollateralAssets(shares, Math.Rounding.Down);
    }

    function _convertToCollateralAssets(uint256 shares, Math.Rounding rounding) internal view virtual returns (uint256) {
        uint256 _totalCollateralAssets = totalCollateralAssets();
        if (_totalCollateralAssets == 0) return 0;

        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) return 0;

        // Note: increase share decimals if smaller than collateral decimals
        uint256 decimalAdjustment = 10 ** (collateralDecimals - Math.min(collateralDecimals, decimals()));
        return (shares * decimalAdjustment).mulDiv(_totalCollateralAssets, totalSupply() * decimalAdjustment, rounding);
    }


    /*----------------------------------------------------------*|
    |*  # PWN LENDER HOOKS                                      *|
    |*----------------------------------------------------------*/

    /** @inheritdoc IPWNLenderCreateHook*/
    function onLoanCreated(
        uint256 loanId_,
        address lender,
        address creditAddress,
        uint256 principal,
        bytes calldata lenderData
    ) external returns (bytes32) {
        require(msg.sender == address(loanContract));
        require(loanId == 0);

        require(lender == address(this));
        require(creditAddress == asset());
        require(lenderData.length == 0);

        loanId = loanId_;
        if (aAsset != address(0)) {
            // Withdraw only the principal needed for the loan, keep the rest earning yield in Aave
            uint256 availableCash = _availableLiquidity();
            if (availableCash < principal) {
                aave.withdraw(asset(), principal - availableCash, address(this));
            }
        }

        return LENDER_CREATE_HOOK_RETURN_VALUE;
    }

    /** @inheritdoc IPWNLenderRepaymentHook*/
    function onLoanRepaid(
        address /* lender */,
        address creditAddress,
        uint256 repayment,
        bytes calldata /* lenderData */
    ) external returns (bytes32) {
        require(msg.sender == address(loanContract));

        // Deposit repayment to Aave to earn yield while waiting for withdrawals/redemptions.
        // Use try/catch to avoid triggering PWNLoan's unclaimedRepayment fallback if Aave is down.
        // If supply fails, the repayment stays as cash in the vault.
        if (aAsset != address(0)) {
            try aave.supply(creditAddress, repayment, address(this), 0) {} catch {}
        }

        return LENDER_REPAYMENT_HOOK_RETURN_VALUE;
    }


    /*----------------------------------------------------------*|
    |*  # ERC721 ON RECEIVED                                    *|
    |*----------------------------------------------------------*/

    /** @inheritdoc IERC721Receiver*/
    function onERC721Received(
        address operator,
        address from,
        uint256 /* tokenId */,
        bytes calldata /* data */
    ) external view returns (bytes4) {
        require(stage() == Stage.POOLING);
        require(operator == address(loanContract));
        require(from == address(loanContract));

        return IERC721Receiver.onERC721Received.selector;
    }


    /*----------------------------------------------------------*|
    |*  # HELPERS                                               *|
    |*----------------------------------------------------------*/

    function _tryGetAssetDecimals_child(IERC20 asset_) private view returns (bool, uint8) {
        (bool success, bytes memory encodedDecimals) = address(asset_).staticcall(
            abi.encodeWithSelector(IERC20Metadata.decimals.selector)
        );
        if (success && encodedDecimals.length >= 32) {
            uint256 returnedDecimals = abi.decode(encodedDecimals, (uint256));
            if (returnedDecimals <= type(uint8).max) {
                return (true, uint8(returnedDecimals));
            }
        }
        return (false, 0);
    }

}

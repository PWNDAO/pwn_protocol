// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import { IERC4626 } from "openzeppelin/token/ERC20/extensions/ERC4626.sol";
import { IERC721 } from "openzeppelin/token/ERC721/IERC721.sol";

import {
    PWNCrowdsourceLenderVault,
    IAaveLike,
    PWNInstallmentsProduct,
    PWNLoan,
    MultiToken,
    IERC20,
    IERC20Metadata,
    Math,
    LENDER_CREATE_HOOK_RETURN_VALUE, LENDER_REPAYMENT_HOOK_RETURN_VALUE
} from "pwn/periphery/crowdsource/PWNCrowdsourceLenderVault.sol";
import { PWNProposalManager } from "pwn/core/loan/PWNProposalManager.sol";
import { IPWNProduct } from "pwn/core/product/IPWNProduct.sol";

import { PWNCrowdsourceLenderVaultHarness } from "test/harness/PWNCrowdsourceLenderVaultHarness.sol";

using MultiToken for address;

abstract contract PWNCrowdsourceLenderVaultTest is Test {

    bytes32 internal constant BALANCES_SLOT = bytes32(uint256(0)); // `_balances` mapping position (ERC20)
    bytes32 internal constant TOTAL_SUPPLY_SLOT = bytes32(uint256(2)); // `_totalSupply` position (ERC20)

    PWNCrowdsourceLenderVaultHarness crowdsource;
    PWNCrowdsourceLenderVault.Terms terms;
    PWNLoan.LOAN loan;
    IAaveLike.ReserveData aaveReserveData;
    address loanContract = makeAddr("loanContract");
    address product = makeAddr("product");
    address aave = makeAddr("aave");
    bytes32 proposalHash = keccak256("proposalHash");

    address[4] lender;

    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);
    event WithdrawCollateral(address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);


    function setUp() public virtual {
        terms = PWNCrowdsourceLenderVault.Terms({
            collateralAddress: makeAddr("collateral"),
            creditAddress: makeAddr("credit"),
            feedIntermediaryDenominations: new address[](0),
            feedInvertFlags: new bool[](0),
            loanToValue: 7500,
            interestAPR: 1200,
            postponement: 90 days,
            duration: 365 days,
            minCreditAmount: 1 ether,
            expiration: uint40(block.timestamp + 7 days),
            // TODO do we also need to test with non zero address?
            allowedAcceptor: address(0)
        });

        _mockAaveReserveData(aaveReserveData);
        vm.mockCall(aave, abi.encodeWithSelector(IAaveLike.withdraw.selector), abi.encode(0));
        vm.mockCall(aave, abi.encodeWithSelector(IAaveLike.supply.selector), abi.encode(""));
        vm.mockCall(terms.creditAddress, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        vm.mockCall(terms.creditAddress, abi.encodeWithSelector(IERC20.transferFrom.selector), abi.encode(true));
        vm.mockCall(terms.creditAddress, abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));
        vm.mockCall(terms.creditAddress, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(18));
        vm.mockCall(terms.collateralAddress, abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));
        vm.mockCall(terms.collateralAddress, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(18));
        vm.mockCall(loanContract, abi.encodeWithSelector(PWNProposalManager.makeProposalAcceptable.selector), abi.encode(proposalHash));
        vm.mockCall(loanContract, abi.encodeWithSelector(PWNLoan.getLenderSpecHash.selector), abi.encode(keccak256("lenderSpecHash")));

        loan = PWNLoan.LOAN({
            borrower: makeAddr("borrower"),
            lastUpdateTimestamp: 1,
            collateral: terms.collateralAddress.ERC20(200 ether),
            creditAddress: terms.creditAddress,
            principal: 100 ether,
            pastAccruedInterest: 10 ether,
            unclaimedRepayment: 0 ether,
            product: IPWNProduct(product)
        });
        _mockLoan(loan);
        _mockLoanRepaymentAmount(101 ether);

        lender = [makeAddr("lender1"), makeAddr("lender2"), makeAddr("lender3"), makeAddr("lender4")];

        crowdsource = new PWNCrowdsourceLenderVaultHarness(
            PWNLoan(loanContract), PWNInstallmentsProduct(product), IAaveLike(aave), "Crowdsource", "CRWD", terms
        );
    }

    function _mockLoan(PWNLoan.LOAN storage _loan) internal {
        vm.mockCall(loanContract, abi.encodeWithSelector(PWNLoan.getLOAN.selector), abi.encode(_loan));
    }

    function _mockLoanStatus(uint8 _status) internal {
        vm.mockCall(loanContract, abi.encodeWithSelector(PWNLoan.getLOANStatus.selector), abi.encode(_status));
    }

    function _mockLoanRepaymentAmount(uint256 _amount) internal {
        vm.mockCall(loanContract, abi.encodeWithSelector(PWNLoan.getLOANDebt.selector), abi.encode(_amount));
    }

    function _mockStage(PWNCrowdsourceLenderVault.Stage _stage) internal {
        if (_stage == PWNCrowdsourceLenderVault.Stage.POOLING) {
            _storeLoanId(0);
            _storeLoanEnded(false);
        } else if (_stage == PWNCrowdsourceLenderVault.Stage.RUNNING) {
            _storeLoanId(1);
            _storeLoanEnded(false);
        } else if (_stage == PWNCrowdsourceLenderVault.Stage.ENDING) {
            _storeLoanId(1);
            _storeLoanEnded(true);
        }
    }

    function _mockCreditBalance(address _owner, uint256 _balance) internal {
        vm.mockCall(terms.creditAddress, abi.encodeWithSelector(IERC20.balanceOf.selector, _owner), abi.encode(_balance));
    }

    function _mockCollateralBalance(address _owner, uint256 _balance) internal {
        vm.mockCall(terms.collateralAddress, abi.encodeWithSelector(IERC20.balanceOf.selector, _owner), abi.encode(_balance));
    }

    function _mockAaveCreditBalance(address _owner, uint256 _balance) internal {
        vm.mockCall(aaveReserveData.aTokenAddress, abi.encodeWithSelector(IERC20.balanceOf.selector, _owner), abi.encode(_balance));
    }

    function _mockAaveReserveData(IAaveLike.ReserveData storage _reserveData) internal {
        vm.mockCall(aave, abi.encodeWithSelector(IAaveLike.getReserveData.selector), abi.encode(_reserveData));
    }


    function _storeLoanId(uint256 _loanId) internal {
        vm.store(address(crowdsource), bytes32(uint256(5)), bytes32(_loanId));
    }

    function _storeLoanEnded(bool _ended) internal {
        vm.store(address(crowdsource), bytes32(uint256(6)), bytes32(uint256(_ended ? 1 : 0)));
    }

    function _storeReceiptBalance(address _owner, uint256 _balance) internal {
        vm.store(address(crowdsource), keccak256(abi.encode(_owner, BALANCES_SLOT)), bytes32(_balance));
    }

    function _storeReceiptTotalSupply(uint256 _totalSupply) internal {
        vm.store(address(crowdsource), TOTAL_SUPPLY_SLOT, bytes32(_totalSupply));
    }

}


/*----------------------------------------------------------*|
|*  # CONSTRUCTOR                                           *|
|*----------------------------------------------------------*/

contract PWNCrowdsourceLenderVault_Constructor_Test is PWNCrowdsourceLenderVaultTest {

    function test_shouldMakeProposal() public {
        vm.expectCall(loanContract, abi.encodeWithSelector(PWNProposalManager.makeProposalAcceptable.selector));
        new PWNCrowdsourceLenderVaultHarness(
            PWNLoan(loanContract), PWNInstallmentsProduct(product), IAaveLike(aave), "Crowdsource", "CRWD", terms
        );
    }

    function test_shouldApproveLoanContract() external {
        vm.expectCall(terms.creditAddress, abi.encodeWithSelector(IERC20.approve.selector, loanContract, type(uint256).max));
        new PWNCrowdsourceLenderVaultHarness(
            PWNLoan(loanContract), PWNInstallmentsProduct(product), IAaveLike(aave), "Crowdsource", "CRWD", terms
        );
    }

    function test_shouldGetAToken() external {
        vm.expectCall(aave, abi.encodeWithSelector(IAaveLike.getReserveData.selector));
        new PWNCrowdsourceLenderVaultHarness(
            PWNLoan(loanContract), PWNInstallmentsProduct(product), IAaveLike(aave), "Crowdsource", "CRWD", terms
        );
    }

}


/*----------------------------------------------------------*|
|*  # STAGE                                                 *|
|*----------------------------------------------------------*/

contract PWNCrowdsourceLenderVault_Stage_Test is PWNCrowdsourceLenderVaultTest {

    function test_shouldReturnStage() public {
        _storeLoanId(0);
        _storeLoanEnded(false);
        assert(crowdsource.exposed_stage() == PWNCrowdsourceLenderVault.Stage.POOLING);

        _storeLoanId(0);
        _storeLoanEnded(true);
        assert(crowdsource.exposed_stage() == PWNCrowdsourceLenderVault.Stage.POOLING);

        _storeLoanId(1);
        _storeLoanEnded(false);
        assert(crowdsource.exposed_stage() == PWNCrowdsourceLenderVault.Stage.RUNNING);

        _storeLoanId(1);
        _storeLoanEnded(true);
        assert(crowdsource.exposed_stage() == PWNCrowdsourceLenderVault.Stage.ENDING);
    }

}


/*----------------------------------------------------------*|
|*  # TOTAL ASSETS                                          *|
|*----------------------------------------------------------*/

contract PWNCrowdsourceLenderVault_TotalAssets_Test is PWNCrowdsourceLenderVaultTest {

    function setUp() override public virtual {
        super.setUp();

        aaveReserveData.aTokenAddress = makeAddr("aToken");
        _mockAaveReserveData(aaveReserveData);

        crowdsource = new PWNCrowdsourceLenderVaultHarness(
            PWNLoan(loanContract), PWNInstallmentsProduct(product), IAaveLike(aave), "Crowdsource", "CRWD", terms
        );
    }


    function test_shouldReturnAaveAndOwnedBalance_whenPoolingStage() external {
        _mockStage(PWNCrowdsourceLenderVault.Stage.POOLING);

        _mockCreditBalance(address(crowdsource), 120 ether);
        _mockAaveCreditBalance(address(crowdsource), 400 ether);

        vm.expectCall(aaveReserveData.aTokenAddress, abi.encodeWithSelector(IERC20.balanceOf.selector, address(crowdsource)));
        assertEq(crowdsource.totalAssets(), 120 ether + 400 ether);
    }

    function test_shouldReturnLoanAndOwnedBalance_whenRunningStage_whenRunningLoan() external {
        _mockStage(PWNCrowdsourceLenderVault.Stage.RUNNING);

        _mockCreditBalance(address(crowdsource), 120 ether);
        _mockAaveCreditBalance(address(crowdsource), 10 ether); // should not be used
        _mockLoanRepaymentAmount(99 ether);
        _mockLoanStatus(2);

        vm.expectCall(loanContract, abi.encodeWithSelector(PWNLoan.getLOANStatus.selector));
        vm.expectCall(loanContract, abi.encodeWithSelector(PWNLoan.getLOANDebt.selector));
        assertEq(crowdsource.totalAssets(), 120 ether + 99 ether);
    }

    function test_shouldReturnLoanAndOwnedBalance_whenRunningStage_whenDefaultedLoan() external {
        _mockStage(PWNCrowdsourceLenderVault.Stage.RUNNING);

        _mockCreditBalance(address(crowdsource), 120 ether);
        _mockAaveCreditBalance(address(crowdsource), 10 ether); // should not be used
        _mockLoanRepaymentAmount(99 ether); // should not be used
        _mockLoanStatus(4);

        vm.expectCall(loanContract, abi.encodeWithSelector(PWNLoan.getLOANStatus.selector));
        vm.expectCall(loanContract, abi.encodeWithSelector(PWNLoan.getLOANDebt.selector), 0);
        assertEq(crowdsource.totalAssets(), 120 ether);
    }

    function test_shouldReturnLoanAndOwnedBalance_whenRunningStage_whenRepaidLoan() external {
        _mockStage(PWNCrowdsourceLenderVault.Stage.RUNNING);

        _mockCreditBalance(address(crowdsource), 120 ether);
        _mockAaveCreditBalance(address(crowdsource), 10 ether); // should not be used
        _mockLoanRepaymentAmount(99 ether); // should not be used
        _mockLoanStatus(3);

        vm.expectCall(loanContract, abi.encodeWithSelector(PWNLoan.getLOANStatus.selector));
        vm.expectCall(loanContract, abi.encodeWithSelector(PWNLoan.getLOANDebt.selector), 0);
        assertEq(crowdsource.totalAssets(), 120 ether);
    }

    function test_shouldReturnOwnedBalance_whenEnding() external {
        _mockStage(PWNCrowdsourceLenderVault.Stage.ENDING);

        _mockCreditBalance(address(crowdsource), 120 ether);
        _mockAaveCreditBalance(address(crowdsource), 10 ether); // should not be used
        _mockLoanRepaymentAmount(99 ether); // should not be used

        assertEq(crowdsource.totalAssets(), 120 ether);
    }

}


/*----------------------------------------------------------*|
|*  # MAX DEPOSIT                                           *|
|*----------------------------------------------------------*/

contract PWNCrowdsourceLenderVault_MaxDeposit_Test is PWNCrowdsourceLenderVaultTest {

    function test_shouldHaveNoLimit_whenPoolingStage() external {
        _mockStage(PWNCrowdsourceLenderVault.Stage.POOLING);
        assertEq(crowdsource.maxDeposit(lender[0]), type(uint256).max);
    }

    function test_shouldBeZero_whenNotPoolingStage() external {
        _mockStage(PWNCrowdsourceLenderVault.Stage.RUNNING);
        assertEq(crowdsource.maxDeposit(lender[0]), 0);

        _mockStage(PWNCrowdsourceLenderVault.Stage.ENDING);
        assertEq(crowdsource.maxDeposit(lender[0]), 0);
    }

}


/*----------------------------------------------------------*|
|*  # MAX MINT                                              *|
|*----------------------------------------------------------*/

contract PWNCrowdsourceLenderVault_MaxMint_Test is PWNCrowdsourceLenderVaultTest {

    function test_shouldHaveNoLimit_whenPoolingStage() external {
        _mockStage(PWNCrowdsourceLenderVault.Stage.POOLING);
        assertEq(crowdsource.maxMint(lender[0]), type(uint256).max);
    }

    function test_shouldBeZero_whenNotPoolingStage() external {
        _mockStage(PWNCrowdsourceLenderVault.Stage.RUNNING);
        assertEq(crowdsource.maxMint(lender[0]), 0);

        _mockStage(PWNCrowdsourceLenderVault.Stage.ENDING);
        assertEq(crowdsource.maxMint(lender[0]), 0);
    }

}


/*----------------------------------------------------------*|
|*  # MAX WITHDRAW                                          *|
|*----------------------------------------------------------*/

contract PWNCrowdsourceLenderVault_MaxWithdraw_Test is PWNCrowdsourceLenderVaultTest {

    function test_shouldReturnUserLiquidity_whenPoolingStage() external {
        _storeReceiptBalance(lender[0], 1 ether);

        crowdsource.workaround_setConvertToAssetsRatio(12e4);
        _mockStage(PWNCrowdsourceLenderVault.Stage.POOLING);
        assertEq(crowdsource.maxWithdraw(lender[0]), 12 ether);
    }

    function test_shouldReturnUserLiquidity_whenRunningStage_whenLessThanAvailableLiquidity() external {
        _mockStage(PWNCrowdsourceLenderVault.Stage.RUNNING);
        _storeReceiptBalance(lender[0], 4 ether);
        _mockCreditBalance(address(crowdsource), 300 ether);
        crowdsource.workaround_setConvertToAssetsRatio(50e4);

        assertEq(crowdsource.maxWithdraw(lender[0]), 200 ether);
    }

    function test_shouldReturnAvailableLiquidity_whenRunningStage_whenLessThanUserLiquidity() external {
        _mockStage(PWNCrowdsourceLenderVault.Stage.RUNNING);
        _storeReceiptBalance(lender[0], 4 ether);
        _mockCreditBalance(address(crowdsource), 150 ether);
        _mockLoanStatus(2);
        crowdsource.workaround_setConvertToAssetsRatio(50e4);

        assertEq(crowdsource.maxWithdraw(lender[0]), 150 ether);
    }

    function test_shouldBeZero_whenEndingStage() external {
        _mockStage(PWNCrowdsourceLenderVault.Stage.ENDING);
        assertEq(crowdsource.maxWithdraw(lender[0]), 0);
    }

}


/*----------------------------------------------------------*|
|*  # MAX REDEEM                                            *|
|*----------------------------------------------------------*/

contract PWNCrowdsourceLenderVault_MaxRedeem_Test is PWNCrowdsourceLenderVaultTest {

    function test_shouldReturnUserLiquidity_whenNotRunningStage() external {
        _storeReceiptBalance(lender[0], 1 ether);

        _mockStage(PWNCrowdsourceLenderVault.Stage.POOLING);
        assertEq(crowdsource.maxRedeem(lender[0]), 1 ether);

        _mockStage(PWNCrowdsourceLenderVault.Stage.ENDING);
        assertEq(crowdsource.maxRedeem(lender[0]), 1 ether);
    }

    function test_shouldReturnUserLiquidity_whenRunningStage_whenLessThanAvailableLiquidity() external {
        _mockStage(PWNCrowdsourceLenderVault.Stage.RUNNING);
        _storeReceiptBalance(lender[0], 2 ether);
        _mockCreditBalance(address(crowdsource), 300 ether);
        crowdsource.workaround_setConvertToSharesRatio(0.01e4);

        assertEq(crowdsource.maxRedeem(lender[0]), 2 ether);
    }

    function test_shouldReturnAvailableLiquidity_whenRunningStage_whenLessThanUserLiquidity() external {
        _mockStage(PWNCrowdsourceLenderVault.Stage.RUNNING);
        _storeReceiptBalance(lender[0], 4 ether);
        _mockCreditBalance(address(crowdsource), 200 ether);
        _mockLoanStatus(2);
        crowdsource.workaround_setConvertToSharesRatio(0.01e4);

        assertEq(crowdsource.maxRedeem(lender[0]), 2 ether);
    }

}


/*----------------------------------------------------------*|
|*  # PREVIEW DEPOSIT                                       *|
|*----------------------------------------------------------*/

contract PWNCrowdsourceLenderVault_PreviewDeposit_Test is PWNCrowdsourceLenderVaultTest {

    function test_shouldRevert_whenNotPoolingStage() external {
        _mockStage(PWNCrowdsourceLenderVault.Stage.RUNNING);
        vm.expectRevert("PWNCrowdsourceLenderVault: deposit disabled");
        crowdsource.previewDeposit(100 ether);

        _mockStage(PWNCrowdsourceLenderVault.Stage.ENDING);
        vm.expectRevert("PWNCrowdsourceLenderVault: deposit disabled");
        crowdsource.previewDeposit(100 ether);
    }

    function test_shouldReturnShares() external {
        _mockStage(PWNCrowdsourceLenderVault.Stage.POOLING);
        crowdsource.workaround_setConvertToSharesRatio(420e4);
        assertEq(crowdsource.previewDeposit(20 ether), 8400 ether);
    }

}


/*----------------------------------------------------------*|
|*  # PREVIEW MINT                                          *|
|*----------------------------------------------------------*/

contract PWNCrowdsourceLenderVault_PreviewMint_Test is PWNCrowdsourceLenderVaultTest {

    function test_shouldRevert_whenNotPoolingStage() external {
        _mockStage(PWNCrowdsourceLenderVault.Stage.RUNNING);
        vm.expectRevert("PWNCrowdsourceLenderVault: mint disabled");
        crowdsource.previewMint(100 ether);

        _mockStage(PWNCrowdsourceLenderVault.Stage.ENDING);
        vm.expectRevert("PWNCrowdsourceLenderVault: mint disabled");
        crowdsource.previewMint(100 ether);
    }

    function test_shouldReturnAssets() external {
        _mockStage(PWNCrowdsourceLenderVault.Stage.POOLING);
        crowdsource.workaround_setConvertToAssetsRatio(420e4);
        assertEq(crowdsource.previewMint(20 ether), 8400 ether);
    }

}


/*----------------------------------------------------------*|
|*  # PREVIEW WITHDRAW                                      *|
|*----------------------------------------------------------*/

contract PWNCrowdsourceLenderVault_PreviewWithdraw_Test is PWNCrowdsourceLenderVaultTest {

    function test_shouldRevert_whenEndingStage() external {
        _mockStage(PWNCrowdsourceLenderVault.Stage.ENDING);
        vm.expectRevert("PWNCrowdsourceLenderVault: withdraw disabled, use redeem");
        crowdsource.previewWithdraw(100 ether);
    }

    function test_shouldReturnShares() external {
        crowdsource.workaround_setConvertToSharesRatio(420e4);

        _mockStage(PWNCrowdsourceLenderVault.Stage.POOLING);
        assertEq(crowdsource.previewWithdraw(20 ether), 8400 ether);

        _mockStage(PWNCrowdsourceLenderVault.Stage.RUNNING);
        assertEq(crowdsource.previewWithdraw(3 ether), 1260 ether);
    }

}


/*----------------------------------------------------------*|
|*  # PREVIEW REDEEM                                        *|
|*----------------------------------------------------------*/

contract PWNCrowdsourceLenderVault_PreviewRedeem_Test is PWNCrowdsourceLenderVaultTest {

    function test_shouldReturnAssets() external {
        crowdsource.workaround_setConvertToAssetsRatio(420e4);

        _mockStage(PWNCrowdsourceLenderVault.Stage.POOLING);
        assertEq(crowdsource.previewRedeem(20 ether), 8400 ether);

        _mockStage(PWNCrowdsourceLenderVault.Stage.RUNNING);
        assertEq(crowdsource.previewRedeem(10 ether), 4200 ether);

        _mockStage(PWNCrowdsourceLenderVault.Stage.ENDING);
        assertEq(crowdsource.previewRedeem(5 ether), 2100 ether);
    }

}


/*----------------------------------------------------------*|
|*  # DEPOSIT                                               *|
|*----------------------------------------------------------*/

contract PWNCrowdsourceLenderVault_Deposit_Test is PWNCrowdsourceLenderVaultTest {

    function setUp() override public virtual {
        super.setUp();

        aaveReserveData.aTokenAddress = makeAddr("aToken");
        _mockAaveReserveData(aaveReserveData);

        crowdsource = new PWNCrowdsourceLenderVaultHarness(
            PWNLoan(loanContract), PWNInstallmentsProduct(product), IAaveLike(aave), "Crowdsource", "CRWD", terms
        );

        _mockStage(PWNCrowdsourceLenderVault.Stage.POOLING);
        _mockCreditBalance(address(crowdsource), 0);
        _mockAaveCreditBalance(address(crowdsource), 0);
    }


    function test_shouldRevert_whenNotPoolingStage() external {
        _mockStage(PWNCrowdsourceLenderVault.Stage.RUNNING);
        vm.expectRevert("PWNCrowdsourceLenderVault: deposit disabled");
        crowdsource.deposit(100 ether, lender[0]);

        _mockStage(PWNCrowdsourceLenderVault.Stage.ENDING);
        vm.expectRevert("PWNCrowdsourceLenderVault: deposit disabled");
        crowdsource.deposit(100 ether, lender[0]);
    }

    function test_shouldDeposit() external {
        crowdsource.workaround_setConvertToSharesRatio(1.1e4);

        vm.expectCall(terms.creditAddress, abi.encodeWithSelector(IERC20.transferFrom.selector, lender[0], address(crowdsource), 100 ether));

        vm.expectEmit();
        emit Deposit(lender[0], lender[0], 100 ether, 110 ether);

        vm.prank(lender[0]);
        crowdsource.deposit(100 ether, lender[0]);
        assertEq(crowdsource.balanceOf(lender[0]), 110 ether);
    }

    function test_shouldSupplyToAave() external {
        vm.expectCall(aave, abi.encodeWithSelector(IAaveLike.supply.selector, terms.creditAddress, 100 ether, address(crowdsource), 0));

        vm.prank(lender[0]);
        crowdsource.deposit(100 ether, lender[0]);
    }

}


/*----------------------------------------------------------*|
|*  # MINT                                                  *|
|*----------------------------------------------------------*/

contract PWNCrowdsourceLenderVault_Mint_Test is PWNCrowdsourceLenderVaultTest {

    function setUp() override public virtual {
        super.setUp();

        aaveReserveData.aTokenAddress = makeAddr("aToken");
        _mockAaveReserveData(aaveReserveData);

        crowdsource = new PWNCrowdsourceLenderVaultHarness(
            PWNLoan(loanContract), PWNInstallmentsProduct(product), IAaveLike(aave), "Crowdsource", "CRWD", terms
        );

        _mockStage(PWNCrowdsourceLenderVault.Stage.POOLING);
        _mockCreditBalance(address(crowdsource), 0);
        _mockAaveCreditBalance(address(crowdsource), 0);
    }


    function test_shouldRevert_whenNotPoolingStage() external {
        _mockStage(PWNCrowdsourceLenderVault.Stage.RUNNING);
        vm.expectRevert("PWNCrowdsourceLenderVault: mint disabled");
        crowdsource.mint(100 ether, lender[0]);

        _mockStage(PWNCrowdsourceLenderVault.Stage.ENDING);
        vm.expectRevert("PWNCrowdsourceLenderVault: mint disabled");
        crowdsource.mint(100 ether, lender[0]);
    }

    function test_shouldMint() external {
        crowdsource.workaround_setConvertToAssetsRatio(2e4);

        vm.expectCall(terms.creditAddress, abi.encodeWithSelector(IERC20.transferFrom.selector, lender[0], address(crowdsource), 200 ether));

        vm.expectEmit();
        emit Deposit(lender[0], lender[0], 200 ether, 100 ether);

        vm.prank(lender[0]);
        crowdsource.mint(100 ether, lender[0]);
        assertEq(crowdsource.balanceOf(lender[0]), 100 ether);
    }

    function test_shouldSupplyToAave() external {
        crowdsource.workaround_setConvertToAssetsRatio(2e4);

        vm.expectCall(aave, abi.encodeWithSelector(IAaveLike.supply.selector, terms.creditAddress, 200 ether, address(crowdsource), 0));

        vm.prank(lender[0]);
        crowdsource.mint(100 ether, lender[0]);
    }

}


/*----------------------------------------------------------*|
|*  # WITHDRAW                                              *|
|*----------------------------------------------------------*/

contract PWNCrowdsourceLenderVault_Withdraw_Test is PWNCrowdsourceLenderVaultTest {

    function setUp() override public virtual {
        super.setUp();

        _mockCreditBalance(address(crowdsource), 1000 ether);
        _storeReceiptBalance(lender[0], 100 ether);
        crowdsource.workaround_setConvertToAssetsRatio(2e4);
        crowdsource.workaround_setConvertToSharesRatio(0.5e4);
    }


    function test_shouldRevert_whenEndingStage() external {
        _mockStage(PWNCrowdsourceLenderVault.Stage.ENDING);
        vm.expectRevert("PWNCrowdsourceLenderVault: withdraw disabled, use redeem");
        crowdsource.withdraw(100 ether, lender[0], lender[0]);
    }

    function test_shouldWithdrawFromAave_whenPoolingStage() external {
        aaveReserveData.aTokenAddress = makeAddr("aToken");
        _mockAaveReserveData(aaveReserveData);
        crowdsource = new PWNCrowdsourceLenderVaultHarness(
            PWNLoan(loanContract), PWNInstallmentsProduct(product), IAaveLike(aave), "Crowdsource", "CRWD", terms
        );

        _mockStage(PWNCrowdsourceLenderVault.Stage.POOLING);
        crowdsource.workaround_setConvertToAssetsRatio(2e4);
        crowdsource.workaround_setConvertToSharesRatio(0.5e4);
        _mockAaveCreditBalance(address(crowdsource), 100 ether);
        _mockCreditBalance(address(crowdsource), 0 ether);
        _storeReceiptBalance(lender[0], 50 ether);

        vm.expectCall(aave, abi.encodeWithSelector(IAaveLike.withdraw.selector, terms.creditAddress, 100 ether, address(crowdsource)));

        vm.prank(lender[0]);
        crowdsource.withdraw(100 ether, lender[0], lender[0]);
    }

    function test_shouldRevert_whenLoanRepaid_whenRunningStage() external {
        _mockStage(PWNCrowdsourceLenderVault.Stage.RUNNING);
        _mockLoanStatus(3);

        vm.expectRevert("PWNCrowdsourceLenderVault: withdraw disabled, use redeem");
        vm.prank(lender[0]);
        crowdsource.withdraw(100 ether, lender[0], lender[0]);
    }

    function test_shouldRevert_whenLoanDefaulted_whenRunningStage() external {
        _mockStage(PWNCrowdsourceLenderVault.Stage.RUNNING);
        _mockLoanStatus(4);

        vm.expectRevert("PWNCrowdsourceLenderVault: withdraw disabled, use redeem");
        vm.prank(lender[0]);
        crowdsource.withdraw(100 ether, lender[0], lender[0]);
    }

    function test_shouldWithdraw() external {
        _mockStage(PWNCrowdsourceLenderVault.Stage.RUNNING);
        _mockLoanStatus(2);

        vm.expectCall(terms.creditAddress, abi.encodeWithSelector(IERC20.transfer.selector, lender[0], 100 ether));

        vm.expectEmit();
        emit Withdraw(lender[0], lender[0], lender[0], 100 ether, 50 ether);

        vm.prank(lender[0]);
        crowdsource.withdraw(100 ether, lender[0], lender[0]);
        assertEq(crowdsource.balanceOf(lender[0]), 50 ether);
    }

}


/*----------------------------------------------------------*|
|*  # REDEEM                                                *|
|*----------------------------------------------------------*/

contract PWNCrowdsourceLenderVault_Redeem_Test is PWNCrowdsourceLenderVaultTest {

    function setUp() override public virtual {
        super.setUp();

        _mockCreditBalance(address(crowdsource), 1000 ether);
        _mockCollateralBalance(address(crowdsource), 0);
        _storeReceiptBalance(lender[0], 100 ether);
        crowdsource.workaround_setConvertToAssetsRatio(2e4);
        crowdsource.workaround_setConvertToSharesRatio(0.5e4);
    }


    function test_shouldWithdrawFromAave_whenPoolingStage() external {
        aaveReserveData.aTokenAddress = makeAddr("aToken");
        _mockAaveReserveData(aaveReserveData);
        crowdsource = new PWNCrowdsourceLenderVaultHarness(
            PWNLoan(loanContract), PWNInstallmentsProduct(product), IAaveLike(aave), "Crowdsource", "CRWD", terms
        );

        _mockStage(PWNCrowdsourceLenderVault.Stage.POOLING);
        crowdsource.workaround_setConvertToAssetsRatio(2e4);
        crowdsource.workaround_setConvertToSharesRatio(0.5e4);
        _mockAaveCreditBalance(address(crowdsource), 200 ether);
        _mockCreditBalance(address(crowdsource), 0 ether);
        _storeReceiptBalance(lender[0], 100 ether);

        vm.expectCall(aave, abi.encodeWithSelector(IAaveLike.withdraw.selector, terms.creditAddress, 200 ether, address(crowdsource)));

        vm.prank(lender[0]);
        crowdsource.redeem(100 ether, lender[0], lender[0]);
    }

    function test_shouldLiquidateLoan_whenLoanDefaulted_whenRunningStage() external {
        _mockStage(PWNCrowdsourceLenderVault.Stage.RUNNING);
        _mockLoanStatus(4);

        vm.expectCall(loanContract, abi.encodeWithSelector(PWNLoan.liquidate.selector));

        vm.prank(lender[0]);
        crowdsource.redeem(100 ether, lender[0], lender[0]);
    }

    function test_shouldRedeem() external {
        _mockStage(PWNCrowdsourceLenderVault.Stage.RUNNING);
        _mockLoanStatus(2);

        vm.expectCall(terms.creditAddress, abi.encodeWithSelector(IERC20.transfer.selector, lender[0], 80 ether));

        vm.expectEmit();
        emit Withdraw(lender[0], lender[0], lender[0], 80 ether, 40 ether);

        vm.prank(lender[0]);
        crowdsource.redeem(40 ether, lender[0], lender[0]);
        assertEq(crowdsource.balanceOf(lender[0]), 60 ether);
    }

    function test_shouldRedeemCollateral_whenLoandefaulted_whenEndingStage() external {
        _mockStage(PWNCrowdsourceLenderVault.Stage.ENDING);
        crowdsource.workaround_setConvertToCollateralAssetsRatio(10e4);
        _mockCollateralBalance(address(crowdsource), 2000 ether);

        vm.expectCall(terms.collateralAddress, abi.encodeWithSelector(IERC20.transfer.selector, lender[0], 400 ether));

        vm.expectEmit();
        emit WithdrawCollateral(lender[0], lender[0], lender[0], 400 ether, 40 ether);

        vm.prank(lender[0]);
        crowdsource.redeem(40 ether, lender[0], lender[0]);
        assertEq(crowdsource.balanceOf(lender[0]), 60 ether);
    }

}


/*----------------------------------------------------------*|
|*  # TOTAL COLLATERAL ASSETS                               *|
|*----------------------------------------------------------*/

contract PWNCrowdsourceLenderVault_TotalCollateralAssets_Test is PWNCrowdsourceLenderVaultTest {

    function setUp() override virtual public {
        super.setUp();

        _mockCollateralBalance(address(crowdsource), 10 ether);
    }


    function test_shouldReturnCollateralBalance_whenPoolingStage() external {
        _mockStage(PWNCrowdsourceLenderVault.Stage.POOLING);
        assertEq(crowdsource.totalCollateralAssets(), 10 ether);
    }

    function test_shouldReturnCollateralBalance_whenRunningStage() external {
        _mockStage(PWNCrowdsourceLenderVault.Stage.RUNNING);
        _mockLoanStatus(2);

        assertEq(crowdsource.totalCollateralAssets(), 10 ether);
    }

    function test_shouldReturnCollateralBalance_whenLoanRepaid_whenRunningStage() external {
        _mockStage(PWNCrowdsourceLenderVault.Stage.RUNNING);
        _mockLoanStatus(3);

        assertEq(crowdsource.totalCollateralAssets(), 10 ether);
    }

    function test_shouldReturnPotentialCollateralBalance_whenLoanDefaulted_whenRunningStage() external {
        _mockStage(PWNCrowdsourceLenderVault.Stage.RUNNING);
        _mockLoanStatus(4);

        assertEq(crowdsource.totalCollateralAssets(), 10 ether + loan.collateral.amount);
    }

    function test_shouldReturnCollateralBalance_whenEndingStage() external {
        _mockStage(PWNCrowdsourceLenderVault.Stage.ENDING);

        assertEq(crowdsource.totalCollateralAssets(), 10 ether);
    }

}


/*----------------------------------------------------------*|
|*  # PREVIEW COLLATERAL REDEEM                             *|
|*----------------------------------------------------------*/

contract PWNCrowdsourceLenderVault_PreviewCollateralRedeem_Test is PWNCrowdsourceLenderVaultTest {

    function setUp() override public virtual {
        super.setUp();

        _mockCollateralBalance(address(crowdsource), 100 ether);
    }

    function test_shouldRevert_whenNotEndingStage() external {
        _mockStage(PWNCrowdsourceLenderVault.Stage.POOLING);
        vm.expectRevert("PWNCrowdsourceLenderVault: collateral redeem disabled");
        crowdsource.previewCollateralRedeem(100 ether);

        _mockStage(PWNCrowdsourceLenderVault.Stage.RUNNING);
        _mockLoanStatus(2);
        vm.expectRevert("PWNCrowdsourceLenderVault: collateral redeem disabled");
        crowdsource.previewCollateralRedeem(100 ether);
    }

    function test_shouldPass_whenRunningStage_whenLoanDefaulted() external {
        _mockStage(PWNCrowdsourceLenderVault.Stage.RUNNING);
        _mockLoanStatus(4);

        crowdsource.previewCollateralRedeem(100 ether);
    }

    function test_shouldReturnAssets() external {
        crowdsource.workaround_setConvertToCollateralAssetsRatio(420e4);

        _mockStage(PWNCrowdsourceLenderVault.Stage.ENDING);
        assertEq(crowdsource.previewCollateralRedeem(5 ether), 2100 ether);
    }

}


/*----------------------------------------------------------*|
|*  # ON LOAN CREATED                                       *|
|*----------------------------------------------------------*/

contract PWNCrowdsourceLenderVault_OnLoanCreated_Test is PWNCrowdsourceLenderVaultTest {

    function setUp() override public virtual {
        super.setUp();

        _mockStage(PWNCrowdsourceLenderVault.Stage.POOLING);
    }


    function test_shouldRevert_whenSenderNotLoanContract() external {
        vm.expectRevert();
        crowdsource.onLoanCreated(1, address(crowdsource), loan.creditAddress, loan.principal, "");
    }

    function test_shouldRevert_whenLenderNotThis() external {
        vm.expectRevert();
        vm.prank(address(loanContract));
        crowdsource.onLoanCreated(2, makeAddr("not this"), loan.creditAddress, loan.principal, "");
    }

    function test_shouldRevert_whenCreditAddressMismatch() external {
        vm.expectRevert();
        vm.prank(address(loanContract));
        crowdsource.onLoanCreated(1, address(crowdsource), makeAddr("diff creditAddr"), loan.principal, "");
    }

    function test_shouldRevert_whenLenderHookParamsNotEmpty() external {
        vm.expectRevert();
        vm.prank(address(loanContract));
        crowdsource.onLoanCreated(1, address(crowdsource), loan.creditAddress, loan.principal, "non-empty params");
    }

    function test_shouldRevert_whenNotPoolingStage() external {
        _mockStage(PWNCrowdsourceLenderVault.Stage.RUNNING);
        vm.expectRevert();
        vm.prank(address(loanContract));
        crowdsource.onLoanCreated(1, address(crowdsource), loan.creditAddress, loan.principal, "");

        _mockStage(PWNCrowdsourceLenderVault.Stage.ENDING);
        vm.expectRevert();
        vm.prank(address(loanContract));
        crowdsource.onLoanCreated(1, address(crowdsource), loan.creditAddress, loan.principal, "");
    }

    function test_shouldSetLoanId() external {
        assertEq(crowdsource.loanId(), 0);

        vm.prank(address(loanContract));
        crowdsource.onLoanCreated(1, address(crowdsource), loan.creditAddress, loan.principal, "");

        assertEq(crowdsource.loanId(), 1);
    }

    function test_shouldWithdrawFromAave() external {
        aaveReserveData.aTokenAddress = makeAddr("aToken");
        _mockAaveReserveData(aaveReserveData);
        crowdsource = new PWNCrowdsourceLenderVaultHarness(
            PWNLoan(loanContract), PWNInstallmentsProduct(product), IAaveLike(aave), "Crowdsource", "CRWD", terms
        );

        _mockStage(PWNCrowdsourceLenderVault.Stage.POOLING);

        vm.expectCall(aave, abi.encodeWithSelector(IAaveLike.withdraw.selector, loan.creditAddress, type(uint256).max, address(crowdsource)));

        vm.prank(address(loanContract));
        crowdsource.onLoanCreated(1, address(crowdsource), loan.creditAddress, loan.principal, "");
    }

    function test_shouldReturnCorrectValue() external {
        vm.prank(address(loanContract));
        bytes32 returnValue = crowdsource.onLoanCreated(1, address(crowdsource), loan.creditAddress, loan.principal, "");
        assertEq(returnValue, LENDER_CREATE_HOOK_RETURN_VALUE);
    }

}

/*----------------------------------------------------------*|
|*  # ON LOAN REPAID                                        *|
|*----------------------------------------------------------*/

contract PWNCrowdsourceLenderVault_OnLoanRepaid_Test is PWNCrowdsourceLenderVaultTest {

    function test_shouldReturnCorrectValue() external {
        bytes32 returnValue = crowdsource.onLoanRepaid(address(0), address(0), 0, "");
        assertEq(returnValue, LENDER_REPAYMENT_HOOK_RETURN_VALUE);
    }

}

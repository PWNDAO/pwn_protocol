// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken, ICryptoKitties, IERC20, IERC721 } from "MultiToken/MultiToken.sol";

import { PWNVault } from "pwn/core/loan/PWNVault.sol";

import { T20 } from "test/helper/T20.sol";
import { T721 } from "test/helper/T721.sol";
import {
    DeploymentTest,
    PWNLoan,
    PWNSimpleProposal
} from "test/DeploymentTest.t.sol";


abstract contract UseCasesTest is DeploymentTest {

    // Token mainnet addresses
    address ZRX = 0xE41d2489571d322189246DaFA5ebDe1F4699F498; // no revert on failed
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // no revert on fallback
    address CULT = 0xf0f9D895aCa5c8678f706FB8216fa22957685A13; // tax token
    address CK = 0x06012c8cf97BEaD5deAe237070F9587f8E7A266d; // CryptoKitties
    address USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // no bool return on transfer(From)
    address BNB = 0xB8c77482e45F1F44dE1745F52C74426C631bDD52; // bool return only on transfer
    address DOODLE = 0x8a90CAb2b38dba80c64b7734e58Ee1dB38B8992e;

    T20 credit;

    PWNLoan.LenderSpec lenderSpec;
    PWNLoan.BorrowerSpec borrowerSpec;
    PWNSimpleProposal.Proposal proposal;


    function setUp() public override virtual {
        vm.createSelectFork("mainnet");

        super.setUp();

        credit = new T20();
        credit.mint(lender, 100e18);
        credit.mint(borrower, 100e18);

        vm.prank(lender);
        credit.approve(address(__d.loan), type(uint256).max);

        vm.prank(borrower);
        credit.approve(address(__d.loan), type(uint256).max);

        proposal = PWNSimpleProposal.Proposal({
            collateralCategory: MultiToken.Category.ERC20,
            collateralAddress: address(credit),
            collateralId: 0,
            collateralAmount: 10e18,
            creditAddress: address(credit),
            creditAmount: 1e18,
            interestAPR: 0,
            duration: 1 days,
            availableCreditLimit: 0,
            utilizedCreditId: 0,
            nonceSpace: 0,
            nonce: 0,
            expiration: uint40(block.timestamp + 7 days),
            proposer: lender,
            proposerSpecHash: bytes32(0),
            isProposerLender: true,
            loanContract: address(__d.loan)
        });
    }


    function _createLoan() internal returns (uint256) {
        return _createLoanRevertWith("");
    }

    function _createLoanRevertWith(bytes memory revertData) internal returns (uint256) {
        bytes memory signature = _sign(lenderPK, __d.simpleProposal.getProposalHash(proposal));
        bytes memory proposalData = __d.simpleProposal.encodeProposalData(proposal);

        // Create a loan
        if (revertData.length > 0) {
            vm.expectRevert(revertData);
        }
        vm.prank(borrower);
        return __d.loan.create({
            proposalSpec: PWNLoan.ProposalSpec({
                proposalContract: address(__d.simpleProposal),
                proposalData: proposalData,
                proposalInclusionProof: new bytes32[](0),
                signature: signature
            }),
            lenderSpec: lenderSpec,
            borrowerSpec: borrowerSpec,
            extra: ""
        });
    }

}


contract InvalidCollateralAssetCategoryTest is UseCasesTest {

    // “No Revert on Failure” tokens can be used to steal from lender
    function testUseCase_shouldFail_when20CollateralPassedWith721Category() external {
        // Borrower has not ZRX tokens

        // Define proposal
        proposal.collateralCategory = MultiToken.Category.ERC721;
        proposal.collateralAddress = ZRX;
        proposal.collateralId = 10e18;
        proposal.collateralAmount = 0;

        // Create loan
        _createLoanRevertWith(abi.encodeWithSelector(PWNLoan.InvalidMultiTokenAsset.selector, 1, ZRX, 10e18, 0));
    }

    // Borrower can steal lender’s assets by using WETH as collateral
    function testUseCase_shouldFail_when20CollateralPassedWith1155Category() external {
        // Borrower has not WETH tokens

        // Define proposal
        proposal.collateralCategory = MultiToken.Category.ERC1155;
        proposal.collateralAddress = WETH;
        proposal.collateralId = 0;
        proposal.collateralAmount = 10e18;

        // Create loan
        _createLoanRevertWith(abi.encodeWithSelector(PWNLoan.InvalidMultiTokenAsset.selector, 2, WETH, 0, 10e18));
    }

    // CryptoKitties token is locked when using it as ERC721 type collateral
    function testUseCase_shouldFail_whenCryptoKittiesCollateralPassedWith721Category() external {
        uint256 ckId = 42;

        // Mock CK
        address originalCkOwner = ICryptoKitties(CK).ownerOf(ckId);
        vm.prank(originalCkOwner);
        ICryptoKitties(CK).transfer(borrower, ckId);

        vm.prank(borrower);
        ICryptoKitties(CK).approve(address(__d.loan), ckId);

        // Define proposal
        proposal.collateralCategory = MultiToken.Category.ERC721;
        proposal.collateralAddress = CK;
        proposal.collateralId = ckId;
        proposal.collateralAmount = 0;

        // Create loan
        _createLoanRevertWith(abi.encodeWithSelector(PWNLoan.InvalidMultiTokenAsset.selector, 1, CK, ckId, 0));
    }

}


contract InvalidCreditTest is UseCasesTest {

    function testUseCase_shouldFail_whenUsingERC721AsCredit() external {
        uint256 doodleId = 42;

        // Mock DOODLE
        address originalDoodleOwner = IERC721(DOODLE).ownerOf(doodleId);
        vm.prank(originalDoodleOwner);
        IERC721(DOODLE).transferFrom(originalDoodleOwner, lender, doodleId);

        vm.prank(lender);
        IERC721(DOODLE).approve(address(__d.loan), doodleId);

        // Define proposal
        proposal.creditAddress = DOODLE;
        proposal.creditAmount = doodleId;

        // Create loan
        _createLoanRevertWith(abi.encodeWithSelector(PWNLoan.InvalidMultiTokenAsset.selector, 0, DOODLE, 0, doodleId));
    }

    function testUseCase_shouldFail_whenUsingCryptoKittiesAsCredit() external {
        uint256 ckId = 42;

        // Mock CK
        address originalCkOwner = ICryptoKitties(CK).ownerOf(ckId);
        vm.prank(originalCkOwner);
        ICryptoKitties(CK).transfer(lender, ckId);

        vm.prank(lender);
        ICryptoKitties(CK).approve(address(__d.loan), ckId);

        // Define proposal
        proposal.creditAddress = CK;
        proposal.creditAmount = ckId;

        // Create loan
        _createLoanRevertWith(abi.encodeWithSelector(PWNLoan.InvalidMultiTokenAsset.selector, 0, CK, 0, ckId));
    }

}


contract TaxTokensTest is UseCasesTest {

    // Fee-on-transfer tokens can be locked in the vault
    function testUseCase_shouldFail_whenUsingTaxTokenAsCollateral() external {
        // Transfer CULT to borrower
        vm.prank(CULT);
        T20(CULT).transfer(borrower, 20e18);

        vm.prank(borrower);
        T20(CULT).approve(address(__d.loan), type(uint256).max);

        // Define proposal
        proposal.collateralCategory = MultiToken.Category.ERC20;
        proposal.collateralAddress = CULT;
        proposal.collateralId = 0;
        proposal.collateralAmount = 10e18;

        // Create loan
        _createLoanRevertWith(abi.encodeWithSelector(PWNVault.IncompleteTransfer.selector));
    }

    // Fee-on-transfer tokens can be locked in the vault
    function testUseCase_shouldFail_whenUsingTaxTokenAsCredit() external {
        // Transfer CULT to lender
        vm.prank(CULT);
        T20(CULT).transfer(lender, 20e18);

        vm.prank(lender);
        T20(CULT).approve(address(__d.loan), type(uint256).max);

        // Define proposal
        proposal.creditAddress = CULT;
        proposal.creditAmount = 10e18;

        // Create loan
        _createLoanRevertWith(abi.encodeWithSelector(PWNVault.IncompleteTransfer.selector));
    }

}


contract IncompleteERC20TokensTest is UseCasesTest {

    function testUseCase_shouldPass_when20TokenTransferNotReturnsBool_whenUsedAsCollateral() external {
        address TetherTreasury = 0x5754284f345afc66a98fbB0a0Afe71e0F007B949;

        // Transfer USDT to borrower
        bool success;
        vm.prank(TetherTreasury);
        (success, ) = USDT.call(abi.encodeWithSignature("transfer(address,uint256)", borrower, 10e6));
        require(success);

        vm.prank(borrower);
        (success, ) = USDT.call(abi.encodeWithSignature("approve(address,uint256)", address(__d.loan), type(uint256).max));
        require(success);

        // Define proposal
        proposal.collateralCategory = MultiToken.Category.ERC20;
        proposal.collateralAddress = USDT;
        proposal.collateralId = 0;
        proposal.collateralAmount = 10e6; // USDT has 6 decimals

        // Check balance
        assertEq(T20(USDT).balanceOf(borrower), 10e6);
        assertEq(T20(USDT).balanceOf(address(__d.loan)), 0);

        // Create loan
        uint256 loanId = _createLoan();

        // Check balance
        assertEq(T20(USDT).balanceOf(borrower), 0);
        assertEq(T20(USDT).balanceOf(address(__d.loan)), 10e6);

        // Repay loan
        vm.prank(borrower);
        __d.loan.repay(loanId, 0);

        // Check balance
        assertEq(T20(USDT).balanceOf(borrower), 10e6);
        assertEq(T20(USDT).balanceOf(address(__d.loan)), 0);
    }

    function testUseCase_shouldPass_when20TokenTransferNotReturnsBool_whenUsedAsCredit() external {
        address TetherTreasury = 0x5754284f345afc66a98fbB0a0Afe71e0F007B949;

        // Transfer USDT to lender
        bool success;
        vm.prank(TetherTreasury);
        (success, ) = USDT.call(abi.encodeWithSignature("transfer(address,uint256)", lender, 10e6));
        require(success);

        vm.prank(lender);
        (success, ) = USDT.call(abi.encodeWithSignature("approve(address,uint256)", address(__d.loan), type(uint256).max));
        require(success);

        vm.prank(borrower);
        (success, ) = USDT.call(abi.encodeWithSignature("approve(address,uint256)", address(__d.loan), type(uint256).max));
        require(success);

        // Define proposal
        proposal.creditAddress = USDT;
        proposal.creditAmount = 10e6; // USDT has 6 decimals

        // Check balance
        assertEq(T20(USDT).balanceOf(lender), 10e6);
        assertEq(T20(USDT).balanceOf(borrower), 0);

        // Create loan
        uint256 loanId = _createLoan();

        // Check balance
        assertEq(T20(USDT).balanceOf(lender), 0);
        assertEq(T20(USDT).balanceOf(borrower), 10e6);

        // Repay loan
        vm.prank(borrower);
        __d.loan.repay(loanId, 0);

        // Check balance
        assertEq(T20(USDT).balanceOf(borrower), 0);
        assertEq(T20(USDT).balanceOf(address(__d.loan)), 10e6);
    }

}


contract CategoryRegistryForIncompleteERCTokensTest is UseCasesTest {

    function test_shouldPass_whenInvalidERC165Support() external {
        address catCoinBank = 0xdeDf88899D7c9025F19C6c9F188DEb98D49CD760;

        // Register category
        vm.prank(__e.protocolTimelock);
        __d.categoryRegistry.registerCategoryValue(catCoinBank, uint8(MultiToken.Category.ERC721));

        // Prepare collateral
        uint256 collId = 2;
        address originalOwner = IERC721(catCoinBank).ownerOf(collId);
        vm.prank(originalOwner);
        IERC721(catCoinBank).transferFrom(originalOwner, borrower, collId);

        vm.prank(borrower);
        IERC721(catCoinBank).setApprovalForAll(address(__d.loan), true);

        // Update proposal
        proposal.collateralCategory = MultiToken.Category.ERC721;
        proposal.collateralAddress = catCoinBank;
        proposal.collateralId = collId;
        proposal.collateralAmount = 0;

        // Create loan
        _createLoan();

        // Check balance
        assertEq(IERC721(catCoinBank).ownerOf(collId), address(__d.loan));
    }

}

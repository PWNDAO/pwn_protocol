// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import { PWNHubTags } from "pwn/core/hub/PWNHubTags.sol";
import {
    PWNElasticProposal,
    Terms,
    PWNBaseProposal,
    MultiToken
} from "pwn/periphery/proposal/PWNElasticProposal.sol";

import { PWNElasticProposalHarness } from "test/harness/PWNElasticProposalHarness.sol";


abstract contract PWNElasticProposalTest is Test {

    address hub = makeAddr("hub");
    address revokedNonce = makeAddr("revokedNonce");
    address config = makeAddr("config");
    address utilizedCredit = makeAddr("utilizedCredit");
    address interestModule = makeAddr("interestModule");
    address defaultModule = makeAddr("defaultModule");
    address liquidationModule = makeAddr("liquidationModule");
    address loanContract = makeAddr("loanContract");
    uint256 proposerPK = 73661723;
    address proposer = vm.addr(proposerPK);
    address acceptor = makeAddr("acecptor");
    address token = makeAddr("token");

    PWNElasticProposalHarness proposalContract;
    PWNElasticProposal.Proposal proposal;
    PWNElasticProposal.AcceptorValues acceptorValues;

    event ProposalMade(bytes32 indexed proposalHash, address indexed proposer, PWNElasticProposal.Proposal proposal);

    function setUp() virtual public {
        proposalContract = new PWNElasticProposalHarness(hub, revokedNonce, config, utilizedCredit, interestModule, defaultModule, liquidationModule);

        proposal = PWNElasticProposal.Proposal({
            collateralCategory: MultiToken.Category.ERC1155,
            collateralAddress: token,
            collateralId: 0,
            creditAddress: token,
            creditPerCollateralUnit: 10 ** proposalContract.CREDIT_PER_COLLATERAL_UNIT_DECIMALS(),
            interestAPR: 0,
            duration: 1 days,
            minCreditAmount: 1 ether,
            availableCreditLimit: 0,
            utilizedCreditId: 0,
            nonceSpace: 0,
            nonce: 0,
            expiration: block.timestamp + 1 days,
            proposer: proposer,
            proposerSpecHash: keccak256("proposer spec"),
            isProposerLender: true,
            loanContract: loanContract
        });

        acceptorValues = PWNElasticProposal.AcceptorValues({
            creditAmount: 10 ether
        });

        vm.mockCall(hub, abi.encodeWithSignature("hasTag(address,bytes32)"), abi.encode(false));
        vm.mockCall(hub, abi.encodeWithSignature("hasTag(address,bytes32)", loanContract, PWNHubTags.ACTIVE_LOAN), abi.encode(true));

        vm.mockCall(revokedNonce, abi.encodeWithSignature("isNonceRevoked(uint256,uint256)", proposal.nonceSpace, proposal.nonce), abi.encode(false));
    }


    function _proposalHash(PWNElasticProposal.Proposal memory _proposal) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            hex"1901",
            keccak256(abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("PWNElasticProposal"),
                keccak256("1.5"),
                block.chainid,
                address(proposalContract)
            )),
            keccak256(abi.encodePacked(
                keccak256("Proposal(uint8 collateralCategory,address collateralAddress,uint256 collateralId,address creditAddress,uint256 creditPerCollateralUnit,uint256 interestAPR,uint256 duration,uint256 minCreditAmount,uint256 availableCreditLimit,bytes32 utilizedCreditId,uint256 nonceSpace,uint256 nonce,uint256 expiration,address proposer,bytes32 proposerSpecHash,bool isProposerLender,address loanContract)"),
                proposalContract.exposed_erc712EncodeProposal(_proposal)
            ))
        ));
    }

    function _sign(uint256 pk, bytes32 proposalHash) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, proposalHash);
        return abi.encodePacked(r, s, v);
    }

}


/*----------------------------------------------------------*|
|*  # GET PROPOSAL HASH                                     *|
|*----------------------------------------------------------*/

contract PWNElasticProposal_GetProposalHash_Test is PWNElasticProposalTest {

    function test_shouldReturnProposalHash() external {
        assertEq(_proposalHash(proposal), proposalContract.getProposalHash(proposal));
    }

}


/*----------------------------------------------------------*|
|*  # MAKE PROPOSAL                                         *|
|*----------------------------------------------------------*/

contract PWNElasticProposal_MakeProposal_Test is PWNElasticProposalTest {

    function testFuzz_shouldFail_whenCallerIsNotProposer(address caller) external {
        vm.assume(caller != proposal.proposer);

        vm.expectRevert(abi.encodeWithSelector(PWNBaseProposal.CallerIsNotStatedProposer.selector, proposal.proposer));
        vm.prank(caller);
        proposalContract.makeProposal(proposal);
    }

    function test_shouldEmit_ProposalMade() external {
        vm.expectEmit();
        emit ProposalMade(_proposalHash(proposal), proposal.proposer, proposal);

        vm.prank(proposal.proposer);
        proposalContract.makeProposal(proposal);
    }

    function test_shouldMakeProposal() external {
        vm.prank(proposal.proposer);
        proposalContract.makeProposal(proposal);

        assertTrue(proposalContract.proposalsMade(_proposalHash(proposal)));
    }

    function test_shouldReturnProposalHash() external {
        vm.prank(proposal.proposer);
        assertEq(proposalContract.makeProposal(proposal), _proposalHash(proposal));
    }

}


/*----------------------------------------------------------*|
|*  # ENCODE DECODE PROPOSAL DATA                           *|
|*----------------------------------------------------------*/

contract PWNElasticProposal_EncodeDecodeProposalData_Test is PWNElasticProposalTest {

    function test_shouldEncodeDecodedProposalData() external {
        (
            PWNElasticProposal.Proposal memory _proposal,
            PWNElasticProposal.AcceptorValues memory _acceptorValues
        ) = proposalContract.decodeProposalData(proposalContract.encodeProposalData(proposal, acceptorValues));

        assertEq(uint8(proposal.collateralCategory), uint8(_proposal.collateralCategory));
        assertEq(proposal.collateralAddress, _proposal.collateralAddress);
        assertEq(proposal.collateralId, _proposal.collateralId);
        assertEq(proposal.creditAddress, _proposal.creditAddress);
        assertEq(proposal.creditPerCollateralUnit, _proposal.creditPerCollateralUnit);
        assertEq(proposal.interestAPR, _proposal.interestAPR);
        assertEq(proposal.duration, _proposal.duration);
        assertEq(proposal.minCreditAmount, _proposal.minCreditAmount);
        assertEq(proposal.availableCreditLimit, _proposal.availableCreditLimit);
        assertEq(proposal.utilizedCreditId, _proposal.utilizedCreditId);
        assertEq(proposal.nonceSpace, _proposal.nonceSpace);
        assertEq(proposal.nonce, _proposal.nonce);
        assertEq(proposal.expiration, _proposal.expiration);
        assertEq(proposal.proposer, _proposal.proposer);
        assertEq(proposal.proposerSpecHash, _proposal.proposerSpecHash);
        assertEq(proposal.isProposerLender, _proposal.isProposerLender);
        assertEq(proposal.loanContract, _proposal.loanContract);

        assertEq(acceptorValues.creditAmount, _acceptorValues.creditAmount);
    }

}


/*----------------------------------------------------------*|
|*  # GET COLLATERAL AMOUNT                                 *|
|*----------------------------------------------------------*/

contract PWNElasticProposal_GetCollateralAmount_Test is PWNElasticProposalTest {

    function test_shouldFail_whenZeroCreditPerCollateralUnit() external {
        vm.expectRevert(abi.encodeWithSelector(PWNElasticProposal.ZeroCreditPerCollateralUnit.selector));
        proposalContract.getCollateralAmount(100e18, 0);
    }

    function test_shouldReturnCollateralAmount() external {
        uint256 decimals = proposalContract.CREDIT_PER_COLLATERAL_UNIT_DECIMALS();

        assertEq(
            proposalContract.getCollateralAmount(100e18, 100 * (10 ** decimals)),
            1e18
        );
        assertEq(
            proposalContract.getCollateralAmount(50, 25 * (10 ** decimals)),
            2
        );
        assertEq(
            proposalContract.getCollateralAmount(1033220e18, 10e18 * (10 ** decimals)),
            103322
        );
        assertEq(
            proposalContract.getCollateralAmount(5e50, 1e30 * (10 ** decimals)),
            5e20
        );
        assertEq(
            proposalContract.getCollateralAmount(0, 1e30 * (10 ** decimals)),
            0
        );
    }

}


/*----------------------------------------------------------*|
|*  # ACCEPT PROPOSAL                                       *|
|*----------------------------------------------------------*/

contract PWNElasticProposal_AcceptProposal_Test is PWNElasticProposalTest {

    function test_shouldFail_whenZeroMinCreditAmount() external {
        proposal.minCreditAmount = 0;

        bytes memory proposalData = proposalContract.encodeProposalData(proposal, acceptorValues);
        bytes32 proposalHash = _proposalHash(proposal);

        vm.expectRevert(abi.encodeWithSelector(PWNElasticProposal.MinCreditAmountNotSet.selector));
        vm.prank(loanContract);
        proposalContract.acceptProposal({
            acceptor: acceptor,
            proposalData: proposalData,
            proposalInclusionProof: new bytes32[](0),
            signature: _sign(proposerPK, proposalHash)
        });
    }

    function testFuzz_shouldFail_whenCreditAmountLessThanMinCreditAmount(uint256 creditAmount) external {
        acceptorValues.creditAmount = bound(creditAmount, 1, proposal.minCreditAmount - 1);

        bytes memory proposalData = proposalContract.encodeProposalData(proposal, acceptorValues);
        bytes32 proposalHash = _proposalHash(proposal);

        vm.expectRevert(
            abi.encodeWithSelector(
                PWNElasticProposal.InsufficientCreditAmount.selector,
                acceptorValues.creditAmount,
                proposal.minCreditAmount
            )
        );
        vm.prank(loanContract);
        proposalContract.acceptProposal({
            acceptor: acceptor,
            proposalData: proposalData,
            proposalInclusionProof: new bytes32[](0),
            signature: _sign(proposerPK, proposalHash)
        });
    }

    function test_shouldFail_whenZeroCreditPerCollateralUnit() external {
        proposal.creditPerCollateralUnit = 0;

        bytes memory proposalData = proposalContract.encodeProposalData(proposal, acceptorValues);
        bytes32 proposalHash = _proposalHash(proposal);

        vm.expectRevert(abi.encodeWithSelector(PWNElasticProposal.ZeroCreditPerCollateralUnit.selector));
        vm.prank(loanContract);
        proposalContract.acceptProposal({
            acceptor: acceptor,
            proposalData: proposalData,
            proposalInclusionProof: new bytes32[](0),
            signature: _sign(proposerPK, proposalHash)
        });
    }

    function testFuzz_shouldCallLoanContractWithLoanTerms(uint256 creditAmount, bool isProposerLender) external {
        acceptorValues.creditAmount = bound(creditAmount, proposal.minCreditAmount, 1_000_000 ether);
        proposal.isProposerLender = isProposerLender;

        bytes memory proposalData = proposalContract.encodeProposalData(proposal, acceptorValues);
        bytes32 proposalHash = _proposalHash(proposal);

        vm.prank(loanContract);
        Terms memory terms = proposalContract.acceptProposal({
            acceptor: acceptor,
            proposalData: proposalData,
            proposalInclusionProof: new bytes32[](0),
            signature: _sign(proposerPK, proposalHash)
        });

        assertEq(terms.proposalHash, proposalHash);
        assertEq(terms.lender, isProposerLender ? proposal.proposer : acceptor);
        assertEq(terms.borrower, isProposerLender ? acceptor : proposal.proposer);
        assertEq(terms.proposerSpecHash, proposal.proposerSpecHash);
        assertEq(uint8(terms.collateral.category), uint8(proposal.collateralCategory));
        assertEq(terms.collateral.assetAddress, proposal.collateralAddress);
        assertEq(terms.collateral.id, proposal.collateralId);
        assertEq(terms.collateral.amount, proposalContract.getCollateralAmount(acceptorValues.creditAmount, proposal.creditPerCollateralUnit));
        assertEq(terms.creditAddress, proposal.creditAddress);
        assertEq(terms.principal, acceptorValues.creditAmount);
        assertEq(address(terms.interestModule), address(interestModule));
        assertEq(terms.interestModuleProposerData.length, 32);
        assertEq(keccak256(terms.interestModuleProposerData), keccak256(abi.encode(proposal.interestAPR)));
        assertEq(address(terms.defaultModule), address(defaultModule));
        assertEq(terms.defaultModuleProposerData.length, 32);
        assertEq(keccak256(terms.defaultModuleProposerData), keccak256(abi.encode(proposal.duration)));
        assertEq(address(terms.liquidationModule), address(liquidationModule));
        assertEq(terms.liquidationModuleProposerData.length, 0);
    }

}

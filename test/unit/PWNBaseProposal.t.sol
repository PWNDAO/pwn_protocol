// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import {
    PWNBaseProposal,
    PWNHubTags,
    PWNSignatureChecker,
    PWNRevokedNonce,
    PWNUtilizedCredit
} from "pwn/periphery/proposal/PWNBaseProposal.sol";

import { PWNBaseProposalHarness } from "test/harness/PWNBaseProposalHarness.sol";


abstract contract PWNBaseProposalTest is Test {

    bytes32 constant PROPOSALS_MADE_SLOT = bytes32(uint256(0)); // `proposalsMade` mapping position

    address hub = makeAddr("hub");
    address revokedNonce = makeAddr("revokedNonce");
    address config = makeAddr("config");
    address utilizedCredit = makeAddr("utilizedCredit");
    address loanContract = makeAddr("loanContract");
    uint256 proposerPK = 73661723;
    address proposer = vm.addr(proposerPK);
    address acceptor = makeAddr("acecptor");

    string name = "PWNBaseProposal";
    string version = "1.0";

    PWNBaseProposalHarness proposal;


    function setUp() virtual public {
        proposal = new PWNBaseProposalHarness(hub, revokedNonce, config, utilizedCredit, name, version);
    }


    function _sign(uint256 pk, bytes32 proposalHash) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, proposalHash);
        return abi.encodePacked(r, s, v);
    }

    function _hashMerkleTreeNodes(bytes32 node1, bytes32 node2) internal pure returns (bytes32) {
        return keccak256(uint256(node1) < uint256(node2) ? abi.encode(node1, node2) : abi.encode(node2, node1));
    }

}


/*----------------------------------------------------------*|
|*  # GET MULTIPROPOSAL HASH                                *|
|*----------------------------------------------------------*/

contract PWNBaseProposal_GetMultiproposalHash_Test is PWNBaseProposalTest {

    function testFuzz_shouldReturnMultiproposalHash(bytes32 root) external {
        PWNBaseProposal.Multiproposal memory multiproposal = PWNBaseProposal.Multiproposal(root);

        bytes32 expectedHash = keccak256(abi.encodePacked(
            hex"1901",
            keccak256(abi.encode(
                keccak256("EIP712Domain(string name)"),
                keccak256("PWNMultiproposal")
            )),
            keccak256(abi.encodePacked(
                keccak256("Multiproposal(bytes32 multiproposalMerkleRoot)"),
                abi.encode(multiproposal)
            ))
        ));

        assertEq(proposal.getMultiproposalHash(multiproposal), expectedHash);
    }

}


/*----------------------------------------------------------*|
|*  # GET PROPOSAL HASH                                     *|
|*----------------------------------------------------------*/

contract PWNBaseProposal_GetProposalHash_Test is PWNBaseProposalTest {

    function testFuzz_shouldReturnProposalHash(bytes32 proposalTypehash) external {
        bytes memory encodedProposal = abi.encode("proposal data");

        bytes32 expectedHash = keccak256(abi.encodePacked(
            hex"1901",
            keccak256(abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(abi.encodePacked(name)),
                keccak256(abi.encodePacked(version)),
                block.chainid,
                address(proposal)
            )),
            keccak256(abi.encodePacked(
                proposalTypehash,
                encodedProposal
            ))
        ));

        assertEq(proposal.exposed_getProposalHash(proposalTypehash, encodedProposal), expectedHash);
    }

}


/*----------------------------------------------------------*|
|*  # MAKE PROPOSAL                                         *|
|*----------------------------------------------------------*/

contract PWNBaseProposal_MakeProposal_Test is PWNBaseProposalTest {

    function testFuzz_shouldFail_whenProposerNotCaller(address proposer) external {
        vm.assume(proposer != address(this));

        vm.expectRevert(abi.encodeWithSelector(PWNBaseProposal.CallerIsNotStatedProposer.selector, proposer));
        proposal.exposed_makeProposal(keccak256("proposal hash"), proposer);
    }

    function testFuzz_shouldMakerProposalAsMade(bytes32 proposalHash) external {
        assertFalse(proposal.proposalsMade(proposalHash));

        proposal.exposed_makeProposal(proposalHash, address(this));

        assertTrue(proposal.proposalsMade(proposalHash));
    }

}


/*----------------------------------------------------------*|
|*  # CHECK PROPOSAL                                        *|
|*----------------------------------------------------------*/

contract PWNBaseProposal_CheckProposal_Test is PWNBaseProposalTest {

    PWNBaseProposal.CheckInputs params;

    function setUp() public override {
        super.setUp();

        params = PWNBaseProposal.CheckInputs({
            proposalHash: keccak256("proposal hash"),
            acceptor: acceptor,
            creditAmount: 10 ether,
            availableCreditLimit: 0,
            utilizedCreditId: bytes32(0),
            nonceSpace: 0,
            nonce: 0,
            expiration: block.timestamp + 20 minutes,
            proposer: proposer,
            loanContract: loanContract
        });

        vm.mockCall(revokedNonce, abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)"), abi.encode(true));

        vm.mockCall(hub, abi.encodeWithSignature("hasTag(address,bytes32)"), abi.encode(false));
        vm.mockCall(
            hub,
            abi.encodeWithSignature("hasTag(address,bytes32)", loanContract, PWNHubTags.ACTIVE_LOAN),
            abi.encode(true)
        );
    }


    function testFuzz_shouldFail_whenCallerIsNotProposedLoanContract(address caller) external {
        vm.assume(caller != loanContract);

        vm.expectRevert(
            abi.encodeWithSelector(PWNBaseProposal.CallerNotLoanContract.selector, caller, loanContract)
        );
        vm.prank(caller);
        proposal.exposed_checkProposal(params, new bytes32[](0), "");
    }

    function test_shouldFail_whenCallerNotTagged_ACTIVE_LOAN() external {
        vm.mockCall(
            hub,
            abi.encodeWithSignature("hasTag(address,bytes32)", loanContract, PWNHubTags.ACTIVE_LOAN),
            abi.encode(false)
        );

        vm.expectRevert(
            abi.encodeWithSelector(PWNBaseProposal.AddressMissingHubTag.selector, loanContract, PWNHubTags.ACTIVE_LOAN)
        );
        vm.prank(loanContract);
        proposal.exposed_checkProposal(params, new bytes32[](0), "");
    }

    function testFuzz_shouldFail_whenInvalidSignature_whenEOA(uint256 randomPK) external {
        randomPK = boundPrivateKey(randomPK);
        vm.assume(randomPK != proposerPK);

        vm.expectRevert(
            abi.encodeWithSelector(PWNSignatureChecker.InvalidSignature.selector, proposer, params.proposalHash)
        );
        vm.prank(loanContract);
        proposal.exposed_checkProposal(params, new bytes32[](0), _sign(randomPK, params.proposalHash));
    }

    function test_shouldFail_whenInvalidSignature_whenContractAccount() external {
        vm.etch(proposer, bytes("data"));

        vm.expectRevert(
            abi.encodeWithSelector(PWNSignatureChecker.InvalidSignature.selector, proposer, params.proposalHash)
        );
        vm.prank(loanContract);
        proposal.exposed_checkProposal(params, new bytes32[](0), "");
    }

    function testFuzz_shouldFail_withInvalidSignature_whenEOA_whenMultiproposal(uint256 randomPK) external {
        randomPK = boundPrivateKey(randomPK);
        vm.assume(randomPK != proposerPK);

        bytes32[] memory proposalInclusionProof = new bytes32[](1);
        proposalInclusionProof[0] = keccak256("leaf1");
        bytes32 root = _hashMerkleTreeNodes(params.proposalHash, proposalInclusionProof[0]);
        bytes32 multiproposalHash = proposal.getMultiproposalHash(PWNBaseProposal.Multiproposal(root));

        vm.expectRevert(abi.encodeWithSelector(PWNSignatureChecker.InvalidSignature.selector, proposer, multiproposalHash));
        vm.prank(loanContract);
        proposal.exposed_checkProposal(params, proposalInclusionProof, _sign(randomPK, multiproposalHash));
    }

    function test_shouldFail_whenInvalidSignature_whenContractAccount_whenMultiproposal() external {
        vm.etch(proposer, bytes("data"));

        bytes32[] memory proposalInclusionProof = new bytes32[](1);
        proposalInclusionProof[0] = keccak256("leaf1");
        bytes32 root = _hashMerkleTreeNodes(params.proposalHash, proposalInclusionProof[0]);
        bytes32 multiproposalHash = proposal.getMultiproposalHash(PWNBaseProposal.Multiproposal(root));

        vm.expectRevert(abi.encodeWithSelector(PWNSignatureChecker.InvalidSignature.selector, proposer, multiproposalHash));
        vm.prank(loanContract);
        proposal.exposed_checkProposal(params, proposalInclusionProof, "");
    }

    function test_shouldFail_withInvalidInclusionProof() external {
        bytes32[] memory proposalInclusionProof = new bytes32[](1);
        proposalInclusionProof[0] = keccak256("other leaf1");
        bytes32 leaf = keccak256("leaf1");
        bytes32 root = _hashMerkleTreeNodes(params.proposalHash, leaf);
        bytes32 multiproposalHash = proposal.getMultiproposalHash(PWNBaseProposal.Multiproposal(root));

        bytes32 actualRoot = _hashMerkleTreeNodes(params.proposalHash, proposalInclusionProof[0]);
        bytes32 actualMultiproposalHash = proposal.getMultiproposalHash(PWNBaseProposal.Multiproposal(actualRoot));
        vm.expectRevert(
            abi.encodeWithSelector(PWNSignatureChecker.InvalidSignature.selector, proposer, actualMultiproposalHash)
        );
        vm.prank(loanContract);
        proposal.exposed_checkProposal(params, proposalInclusionProof, _sign(proposerPK, multiproposalHash));
    }

    function test_shouldPass_whenProposalMadeOnchain() external {
        vm.store(
            address(proposal),
            keccak256(abi.encode(params.proposalHash, PROPOSALS_MADE_SLOT)),
            bytes32(uint256(1))
        );

        vm.prank(loanContract);
        proposal.exposed_checkProposal(params, new bytes32[](0), "");
    }

    function test_shouldPass_withValidSignature_whenEOA_whenStandardSignature() external {
        vm.prank(loanContract);
        proposal.exposed_checkProposal(params, new bytes32[](0), _sign(proposerPK, params.proposalHash));
    }

    function test_shouldPass_whenValidSignature_whenContractAccount() external {
        vm.etch(proposer, bytes("data"));
        bytes memory signature = "some signature";

        vm.mockCall(
            proposer,
            abi.encodeWithSignature("isValidSignature(bytes32,bytes)", params.proposalHash, signature),
            abi.encode(bytes4(0x1626ba7e))
        );

        vm.prank(loanContract);
        proposal.exposed_checkProposal(params, new bytes32[](0), signature);
    }

    function test_shouldPass_withValidSignature_whenEOA_whenStandardSignature_whenMultiproposal() external {
        bytes32[] memory proposalInclusionProof = new bytes32[](1);
        proposalInclusionProof[0] = keccak256("leaf1");

        bytes32 root = _hashMerkleTreeNodes(params.proposalHash, proposalInclusionProof[0]);
        bytes32 multiproposalHash = proposal.getMultiproposalHash(PWNBaseProposal.Multiproposal(root));

        vm.prank(loanContract);
        proposal.exposed_checkProposal(params, proposalInclusionProof, _sign(proposerPK, multiproposalHash));
    }

    function test_shouldPass_whenValidSignature_whenContractAccount_whenMultiproposal() external {
        vm.etch(proposer, bytes("data"));

        bytes32[] memory proposalInclusionProof = new bytes32[](1);
        proposalInclusionProof[0] = keccak256("leaf1");
        bytes32 root = _hashMerkleTreeNodes(params.proposalHash, proposalInclusionProof[0]);

        bytes32 multiproposalHash = proposal.getMultiproposalHash(PWNBaseProposal.Multiproposal(root));
        bytes memory signature = "some random string";

        vm.mockCall(
            proposer,
            abi.encodeWithSignature("isValidSignature(bytes32,bytes)", multiproposalHash, signature),
            abi.encode(bytes4(0x1626ba7e))
        );

        vm.prank(loanContract);
        proposal.exposed_checkProposal(params, proposalInclusionProof, signature);
    }

    function test_shouldFail_whenProposerIsSameAsAcceptor() external {
        params.acceptor = proposer;

        vm.expectRevert(abi.encodeWithSelector(PWNBaseProposal.AcceptorIsProposer.selector, proposer));
        vm.prank(loanContract);
        proposal.exposed_checkProposal(params, new bytes32[](0), _sign(proposerPK, params.proposalHash));
    }

    function testFuzz_shouldFail_whenProposalExpired(uint256 timestamp) external {
        timestamp = bound(timestamp, params.expiration, type(uint256).max);
        vm.warp(timestamp);

        vm.expectRevert(abi.encodeWithSelector(PWNBaseProposal.Expired.selector, timestamp, params.expiration));
        vm.prank(loanContract);
        proposal.exposed_checkProposal(params, new bytes32[](0), _sign(proposerPK, params.proposalHash));
    }

    function testFuzz_shouldFail_whenNonceNotUsable(uint256 nonceSpace, uint256 nonce) external {
        params.nonceSpace = nonceSpace;
        params.nonce = nonce;

        vm.mockCall(
            revokedNonce,
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)"),
            abi.encode(false)
        );
        vm.expectCall(
            revokedNonce,
            abi.encodeWithSignature("isNonceUsable(address,uint256,uint256)", proposer, nonceSpace, nonce)
        );

        vm.expectRevert(abi.encodeWithSelector(PWNRevokedNonce.NonceNotUsable.selector, proposer, nonceSpace, nonce));
        vm.prank(loanContract);
        proposal.exposed_checkProposal(params, new bytes32[](0), _sign(proposerPK, params.proposalHash));
    }

    function test_shouldRevokeNonce_whenAvailableCreditLimitEqualToZero(uint256 nonceSpace, uint256 nonce) external {
        params.availableCreditLimit = 0;
        params.nonceSpace = nonceSpace;
        params.nonce = nonce;

        vm.expectCall(
            revokedNonce,
            abi.encodeWithSignature("revokeNonce(address,uint256,uint256)", proposer, nonceSpace, nonce)
        );

        vm.prank(loanContract);
        proposal.exposed_checkProposal(params, new bytes32[](0), _sign(proposerPK, params.proposalHash));
    }

    function testFuzz_shouldUtilizeCredit(bytes32 id, uint256 creditAmount, uint256 limit) external {
        params.creditAmount = bound(creditAmount, 1, type(uint256).max);
        params.availableCreditLimit = bound(limit, 1, type(uint256).max);
        params.utilizedCreditId = id;

        vm.mockCall(
            utilizedCredit,
            abi.encodeWithSelector(PWNUtilizedCredit.utilizeCredit.selector),
            abi.encode("")
        );

        vm.expectCall(
            utilizedCredit,
            abi.encodeWithSelector(
                PWNUtilizedCredit.utilizeCredit.selector,
                proposer, params.utilizedCreditId, params.creditAmount, params.availableCreditLimit
            )
        );

        vm.prank(loanContract);
        proposal.exposed_checkProposal(params, new bytes32[](0), _sign(proposerPK, params.proposalHash));
    }

}

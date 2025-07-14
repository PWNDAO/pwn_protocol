// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import {
    PWNProposalManager,
    IPWNProposalModule,
    PWNSignatureChecker
} from "pwn/core/loan/PWNProposalManager.sol";

import { PWNProposalManagerHarness } from "test/harness/PWNProposalManagerHarness.sol";


abstract contract PWNProposalManagerTest is Test {

    IPWNProposalModule proposalModule = IPWNProposalModule(makeAddr("proposalModule"));
    bytes proposalData = "0x1234567890abcdef";
    bytes32 typedDataHash = keccak256("typedDataHash");
    address caller = makeAddr("caller");
    PWNProposalManager.Multiproposal multiproposal = PWNProposalManager.Multiproposal(keccak256("multiproposalMerkleRoot"));

    PWNProposalManagerHarness manager;

    event ProposalAcceptable(bytes32 indexed proposalHash, address indexed proposer, address indexed proposalModule, bytes proposal);
    event ProposalUnacceptable(bytes32 indexed proposalHash);
    event MultiproposalAcceptable(bytes32 indexed multiproposalHash, address indexed proposer, bytes32 multiproposalMerkleRoot);
    event MultiproposalUnacceptable(bytes32 indexed multiproposalHash);

    function setUp() public virtual {
        manager = new PWNProposalManagerHarness();

        vm.mockCall(
            address(proposalModule),
            abi.encodeWithSelector(IPWNProposalModule.nameAndVersion.selector),
            abi.encode("ProposalModule", "1")
        );
        vm.mockCall(
            address(proposalModule),
            abi.encodeWithSelector(IPWNProposalModule.hashProposalTypedData.selector),
            abi.encode(typedDataHash)
        );
    }

}


/*----------------------------------------------------------*|
|*  # MAKE PROPOSAL ACCEPTABLE                              *|
|*----------------------------------------------------------*/

contract PWNProposalManager_makeProposalAcceptable_Test is PWNProposalManagerTest {

    function test_shouldHashProposal() external {
        vm.expectCall(address(proposalModule), abi.encodeWithSelector(IPWNProposalModule.nameAndVersion.selector));
        vm.expectCall(address(proposalModule), abi.encodeWithSelector(IPWNProposalModule.hashProposalTypedData.selector, proposalData));

        manager.makeProposalAcceptable(proposalModule, proposalData);
    }

    function test_shouldMarkProposalAcceptable() external {
        bytes32 proposalHash = manager.hashProposal(proposalModule, proposalData);

        assertFalse(manager.isProposalAcceptable(caller, proposalHash));

        vm.prank(caller);
        manager.makeProposalAcceptable(proposalModule, proposalData);

        assertTrue(manager.isProposalAcceptable(caller, proposalHash));
    }

    function test_shouldPass_whenProposalAlreadyAcceptable() external {
        bytes32 proposalHash = manager.makeProposalAcceptable(proposalModule, proposalData);
        manager.makeProposalAcceptable(proposalModule, proposalData);

        assertTrue(manager.isProposalAcceptable(address(this), proposalHash));
    }

    function test_shouldEmit_ProposalAcceptable() external {
        bytes32 proposalHash = manager.hashProposal(proposalModule, proposalData);

        vm.expectEmit();
        emit ProposalAcceptable(proposalHash, caller, address(proposalModule), proposalData);

        vm.prank(caller);
        manager.makeProposalAcceptable(proposalModule, proposalData);
    }

    function test_shouldReturnProposalHash() external {
        bytes32 proposalHash = manager.hashProposal(proposalModule, proposalData);

        assertEq(manager.makeProposalAcceptable(proposalModule, proposalData), proposalHash);
    }

}


/*----------------------------------------------------------*|
|*  # MAKE PROPOSAL UNACCEPTABLE                            *|
|*----------------------------------------------------------*/

contract PWNProposalManager_makeProposalUnacceptable_Test is PWNProposalManagerTest {

    bytes32 proposalHash;

    function setUp() public override virtual {
        super.setUp();

        vm.prank(caller);
        proposalHash = manager.makeProposalAcceptable(proposalModule, proposalData);
    }


    function test_shouldMarkProposalUnacceptable() external {
        assertTrue(manager.isProposalAcceptable(caller, proposalHash));

        vm.prank(caller);
        manager.makeProposalUnacceptable(proposalHash);

        assertFalse(manager.isProposalAcceptable(caller, proposalHash));
    }

    function test_shouldEmit_ProposalUnacceptable() external {
        vm.expectEmit();
        emit ProposalUnacceptable(proposalHash);

        vm.prank(caller);
        manager.makeProposalUnacceptable(proposalHash);
    }

    function test_shouldPass_whenProposalAlreadyUncceptable() external {
        proposalHash = keccak256("random proposal");

        assertFalse(manager.isProposalAcceptable(caller, proposalHash));

        manager.makeProposalUnacceptable(proposalHash);

        assertFalse(manager.isProposalAcceptable(caller, proposalHash));
    }

}


/*----------------------------------------------------------*|
|*  # MAKE MULTIPROPOSAL ACCEPTABLE                         *|
|*----------------------------------------------------------*/

contract PWNProposalManager_makeMultiproposalAcceptable_Test is PWNProposalManagerTest {

    function test_shouldMarkMultiproposalAcceptable() external {
        bytes32 multiproposalHash = manager.hashMultiproposal(multiproposal);

        assertFalse(manager.isMultiproposalAcceptable(caller, multiproposalHash));

        vm.prank(caller);
        manager.makeMultiproposalAcceptable(multiproposal);

        assertTrue(manager.isMultiproposalAcceptable(caller, multiproposalHash));
    }

    function test_shouldPass_whenMultiproposalAlreadyAcceptable() external {
        bytes32 multiproposalHash = manager.makeMultiproposalAcceptable(multiproposal);
        manager.makeMultiproposalAcceptable(multiproposal);

        assertTrue(manager.isMultiproposalAcceptable(address(this), multiproposalHash));
    }

    function test_shouldEmit_MultiproposalAcceptable() external {
        bytes32 multiproposalHash = manager.hashMultiproposal(multiproposal);

        vm.expectEmit();
        emit MultiproposalAcceptable(multiproposalHash, caller, multiproposal.multiproposalMerkleRoot);

        vm.prank(caller);
        manager.makeMultiproposalAcceptable(multiproposal);
    }

    function test_shouldReturnMultiproposalHash() external {
        bytes32 multiproposalHash = manager.hashMultiproposal(multiproposal);

        assertEq(manager.makeMultiproposalAcceptable(multiproposal), multiproposalHash);
    }

}


/*----------------------------------------------------------*|
|*  # MAKE MULTIPROPOSAL UNACCEPTABLE                       *|
|*----------------------------------------------------------*/

contract PWNProposalManager_makeMultiproposalUnacceptable_Test is PWNProposalManagerTest {

    bytes32 multiproposalHash;

    function setUp() public override virtual {
        super.setUp();

        vm.prank(caller);
        multiproposalHash = manager.makeMultiproposalAcceptable(multiproposal);
    }


    function test_shouldMarkMultiproposalUnacceptable() external {
        assertTrue(manager.isMultiproposalAcceptable(caller, multiproposalHash));

        vm.prank(caller);
        manager.makeMultiproposalUnacceptable(multiproposalHash);

        assertFalse(manager.isMultiproposalAcceptable(caller, multiproposalHash));
    }

    function test_shouldEmit_MultiproposalUnacceptable() external {
        vm.expectEmit();
        emit MultiproposalUnacceptable(multiproposalHash);

        vm.prank(caller);
        manager.makeMultiproposalUnacceptable(multiproposalHash);
    }

    function test_shouldPass_whenMultiproposalAlreadyUncceptable() external {
        multiproposalHash = keccak256("random proposal");

        assertFalse(manager.isMultiproposalAcceptable(caller, multiproposalHash));

        manager.makeMultiproposalUnacceptable(multiproposalHash);

        assertFalse(manager.isMultiproposalAcceptable(caller, multiproposalHash));
    }

}


/*----------------------------------------------------------*|
|*  # HASH PROPOSAL                                         *|
|*----------------------------------------------------------*/

contract PWNProposalManager_hashProposal_Test is PWNProposalManagerTest {

    function test_shouldFetchNameAndVersion() external {
        vm.expectCall(address(proposalModule), abi.encodeWithSelector(IPWNProposalModule.nameAndVersion.selector));
        manager.hashProposal(proposalModule, proposalData);
    }

    function test_shouldHashTypedData() external {
        vm.expectCall(address(proposalModule), abi.encodeWithSelector(IPWNProposalModule.hashProposalTypedData.selector, proposalData));
        manager.hashProposal(proposalModule, proposalData);
    }

    function test_shouldHashProposal() external {
        bytes32 proposalHash = manager.hashProposal(proposalModule, proposalData);

        assertEq(proposalHash, keccak256(abi.encodePacked(
            hex"1901",
            keccak256(abi.encode(
                manager.EIP712DOMAIN_TYPEHASH(),
                keccak256(abi.encodePacked("ProposalModule")),
                keccak256(abi.encodePacked("1")),
                block.chainid,
                address(proposalModule)
            )),
            typedDataHash
        )));
    }

}


/*----------------------------------------------------------*|
|*  # HASH MULTIPROPOSAL                                    *|
|*----------------------------------------------------------*/

contract PWNProposalManager_hashMultiproposal_Test is PWNProposalManagerTest {

    function test_shouldHashMultiproposal() external {
        bytes32 multiproposalHash = manager.hashMultiproposal(multiproposal);

        assertEq(multiproposalHash, keccak256(abi.encodePacked(
            hex"1901",
            manager.MULTIPROPOSAL_DOMAIN_SEPARATOR(),
            keccak256(abi.encodePacked(
                manager.MULTIPROPOSAL_TYPEHASH(),
                abi.encode(multiproposal)
            ))
        )));
    }

}


/*----------------------------------------------------------*|
|*  # CHECK PROPOSAL SIGNATURE                              *|
|*----------------------------------------------------------*/

contract PWNProposalManager_exposed_checkProposalSignature_Test is PWNProposalManagerTest {

    address proposer;
    uint256 proposerPK;
    bytes32 proposalHash = keccak256("proposalHash");
    bytes32[] proposalInclusionProof = new bytes32[](0);
    bytes signature;

    function setUp() public override virtual {
        super.setUp();

        (proposer, proposerPK) = makeAddrAndKey("proposer");
    }

    function _sign(uint256 _pk, bytes32 _proposalHash) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_pk, _proposalHash);
        return abi.encodePacked(r, s, v);
    }

    function _hashMerkleTreeNodes(bytes32 node1, bytes32 node2) internal pure returns (bytes32) {
        return keccak256(uint256(node1) < uint256(node2) ? abi.encode(node1, node2) : abi.encode(node2, node1));
    }


    function testFuzz_shouldFail_whenInvalidSignature_whenProposal(uint256 randomPK) external {
        randomPK = boundPrivateKey(randomPK);
        vm.assume(randomPK != proposerPK);

        signature = _sign(randomPK, proposalHash);

        vm.expectRevert(abi.encodeWithSelector(PWNSignatureChecker.InvalidSignature.selector, proposer, proposalHash));
        manager.exposed_checkProposalSignature(proposer, proposalHash, proposalInclusionProof, signature);
    }

    function testFuzz_shouldFail_withInvalidSignature_whenMultiproposal(uint256 randomPK) external {
        randomPK = boundPrivateKey(randomPK);
        vm.assume(randomPK != proposerPK);

        proposalInclusionProof = new bytes32[](1);
        proposalInclusionProof[0] = keccak256("leaf1");
        bytes32 root = _hashMerkleTreeNodes(proposalHash, proposalInclusionProof[0]);
        bytes32 multiproposalHash = manager.hashMultiproposal(PWNProposalManager.Multiproposal(root));
        signature = _sign(randomPK, multiproposalHash);

        vm.expectRevert(abi.encodeWithSelector(PWNSignatureChecker.InvalidSignature.selector, proposer, multiproposalHash));
        manager.exposed_checkProposalSignature(proposer, proposalHash, proposalInclusionProof, signature);
    }

    function test_shouldFail_withInvalidInclusionProof() external {
        proposalInclusionProof = new bytes32[](1);
        proposalInclusionProof[0] = keccak256("other leaf1");
        bytes32 leaf = keccak256("leaf1");
        bytes32 root = _hashMerkleTreeNodes(proposalHash, leaf);
        bytes32 multiproposalHash = manager.hashMultiproposal(PWNProposalManager.Multiproposal(root));
        signature = _sign(proposerPK, multiproposalHash);

        bytes32 actualRoot = _hashMerkleTreeNodes(proposalHash, proposalInclusionProof[0]);
        bytes32 actualMultiproposalHash = manager.hashMultiproposal(PWNProposalManager.Multiproposal(actualRoot));
        vm.expectRevert(
            abi.encodeWithSelector(PWNSignatureChecker.InvalidSignature.selector, proposer, actualMultiproposalHash)
        );
        manager.exposed_checkProposalSignature(proposer, proposalHash, proposalInclusionProof, signature);
    }

    function test_shouldPass_whenProposalMadeOnchain() external {
        vm.prank(proposer);
        proposalHash = manager.makeProposalAcceptable(proposalModule, proposalData);

        manager.exposed_checkProposalSignature(proposer, proposalHash, proposalInclusionProof, "");
    }

    function test_shouldPass_withValidSignature_whenProposal() external {
        signature = _sign(proposerPK, proposalHash);
        manager.exposed_checkProposalSignature(proposer, proposalHash, proposalInclusionProof, signature);
    }

    function test_shouldPass_whenMultiproposalMadeOnchain() external {
        proposalInclusionProof = new bytes32[](1);
        proposalInclusionProof[0] = keccak256("leaf1");
        bytes32 root = _hashMerkleTreeNodes(proposalHash, proposalInclusionProof[0]);

        vm.prank(proposer);
        manager.makeMultiproposalAcceptable(PWNProposalManager.Multiproposal(root));

        manager.exposed_checkProposalSignature(proposer, proposalHash, proposalInclusionProof, "");
    }

    function test_shouldPass_withValidSignature_whenMultiproposal() external {
        proposalInclusionProof = new bytes32[](1);
        proposalInclusionProof[0] = keccak256("leaf1");

        bytes32 root = _hashMerkleTreeNodes(proposalHash, proposalInclusionProof[0]);
        bytes32 multiproposalHash = manager.hashMultiproposal(PWNProposalManager.Multiproposal(root));
        signature = _sign(proposerPK, multiproposalHash);

        manager.exposed_checkProposalSignature(proposer, proposalHash, proposalInclusionProof, signature);
    }

}

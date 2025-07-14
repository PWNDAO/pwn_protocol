// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MerkleProof } from "openzeppelin/utils/cryptography/MerkleProof.sol";

import { IPWNProposalModule } from "pwn/core/loan/module/IPWNProposalModule.sol";
import { PWNSignatureChecker } from "pwn/core/lib/PWNSignatureChecker.sol";


/**
 * @title PWNProposalManager
 * @notice Manages proposal and multiproposal verification for PWN protocol.
 */
contract PWNProposalManager {

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    bytes32 public constant MULTIPROPOSAL_DOMAIN_SEPARATOR = keccak256(abi.encode(keccak256("EIP712Domain(string name)"), keccak256("PWNMultiproposal")));
    bytes32 public constant MULTIPROPOSAL_TYPEHASH = keccak256("Multiproposal(bytes32 multiproposalMerkleRoot)");
    bytes32 public constant EIP712DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)");

    /**
     * @notice Struct representing a multiproposal, identified by its Merkle root.
     * @param multiproposalMerkleRoot Merkle root of the multiproposal tree.
     */
    struct Multiproposal {
        bytes32 multiproposalMerkleRoot;
    }

    /** @notice Mapping to track if a proposal is acceptable for a given proposer.*/
    mapping (address => mapping (bytes32 => bool)) public isProposalAcceptable;
    /** @notice Mapping to track if a multiproposal is acceptable for a given proposer.*/
    mapping (address => mapping (bytes32 => bool)) public isMultiproposalAcceptable;


    /*----------------------------------------------------------*|
    |*  # EVENTS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /** @notice Emitted when a proposal is marked as acceptable.*/
    event ProposalAcceptable(bytes32 indexed proposalHash, address indexed proposer, address indexed proposalModule, bytes proposal);
    /** @notice Emitted when a proposal is marked as unacceptable.*/
    event ProposalUnacceptable(bytes32 indexed proposalHash);
    /** @notice Emitted when a multiproposal is marked as acceptable.*/
    event MultiproposalAcceptable(bytes32 indexed multiproposalHash, address indexed proposer, bytes32 multiproposalMerkleRoot);
    /** @notice Emitted when a multiproposal is marked as unacceptable.*/
    event MultiproposalUnacceptable(bytes32 indexed multiproposalHash);


    /*----------------------------------------------------------*|
    |*  # ON-CHAIN PROPOSAL                                     *|
    |*----------------------------------------------------------*/

    /**
     * @notice Mark a proposal as acceptable for the sender.
     * @param proposalModule The proposal module contract.
     * @param proposalData Raw proposal data.
     * @return proposalHash Hash of the proposal marked as acceptable.
     */
    function makeProposalAcceptable(
        IPWNProposalModule proposalModule,
        bytes calldata proposalData
    ) external returns (bytes32 proposalHash) {
        proposalHash = hashProposal(proposalModule, proposalData);
        isProposalAcceptable[msg.sender][proposalHash] = true;
        emit ProposalAcceptable(proposalHash, msg.sender, address(proposalModule), proposalData);
    }

    /**
     * @notice Mark a proposal as unacceptable for the sender.
     * @param proposalHash Hash of the proposal to mark as unacceptable.
     */
    function makeProposalUnacceptable(bytes32 proposalHash) external {
        isProposalAcceptable[msg.sender][proposalHash] = false;
        emit ProposalUnacceptable(proposalHash);
    }

    /**
     * @notice Mark a multiproposal as acceptable for the sender.
     * @param multiproposal The multiproposal struct to mark as acceptable.
     * @return multiproposalHash Hash of the multiproposal marked as acceptable.
     */
    function makeMultiproposalAcceptable(Multiproposal memory multiproposal) external returns (bytes32 multiproposalHash) {
        multiproposalHash = hashMultiproposal(multiproposal);
        isMultiproposalAcceptable[msg.sender][multiproposalHash] = true;
        emit MultiproposalAcceptable(multiproposalHash, msg.sender, multiproposal.multiproposalMerkleRoot);
    }

    /**
     * @notice Mark a multiproposal as unacceptable for the sender.
     * @param multiproposalHash Hash of the multiproposal to mark as unacceptable.
     */
    function makeMultiproposalUnacceptable(bytes32 multiproposalHash) external {
        isMultiproposalAcceptable[msg.sender][multiproposalHash] = false;
        emit MultiproposalUnacceptable(multiproposalHash);
    }


    /*----------------------------------------------------------*|
    |*  # PROPOSAL HASHING                                      *|
    |*----------------------------------------------------------*/

    /**
     * @notice Compute the EIP-712 hash for a proposal using its module and data.
     * @param proposalModule The proposal module contract.
     * @param proposalData Raw proposal data.
     * @return proposalHash Hash of the proposal.
     */
    function hashProposal(
        IPWNProposalModule proposalModule,
        bytes calldata proposalData
    ) public view returns (bytes32 proposalHash) {
        (string memory name, string memory version) = proposalModule.nameAndVersion();
        proposalHash = keccak256(abi.encodePacked(
            hex"1901",
            keccak256(abi.encode(
                EIP712DOMAIN_TYPEHASH,
                keccak256(abi.encodePacked(name)),
                keccak256(abi.encodePacked(version)),
                block.chainid,
                address(proposalModule)
            )),
            proposalModule.hashProposalTypedData(proposalData)
        ));
    }

    /**
     * @notice Compute the EIP-712 hash for a multiproposal struct.
     * @param multiproposal The multiproposal struct to hash.
     * @return Hash of the multiproposal.
     */
    function hashMultiproposal(Multiproposal memory multiproposal) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            hex"1901", MULTIPROPOSAL_DOMAIN_SEPARATOR, keccak256(abi.encodePacked(
                MULTIPROPOSAL_TYPEHASH, abi.encode(multiproposal)
            ))
        ));
    }


    /*----------------------------------------------------------*|
    |*  # PROPOSAL SIGNATURE CHECKING                           *|
    |*----------------------------------------------------------*/

    /**
     * @notice Internal function to check the validity of a proposal or multiproposal signature.
     * @dev Reverts if the signature is invalid or the proposal/multiproposal is not marked as acceptable.
     * @param proposer Address of the proposer.
     * @param proposalHash Hash of the proposal.
     * @param proposalInclusionProof Merkle proof for multiproposal inclusion (empty for single proposal).
     * @param signature Signature to verify.
     */
    function _checkProposalSignature(
        address proposer,
        bytes32 proposalHash,
        bytes32[] calldata proposalInclusionProof,
        bytes calldata signature
    ) internal view {
        // Check proposal signature or that it was made on-chain
        if (proposalInclusionProof.length == 0) {
            // Single proposal signature
            if (!isProposalAcceptable[proposer][proposalHash]) {
                if (!PWNSignatureChecker.isValidSignatureNow(proposer, proposalHash, signature)) {
                    revert PWNSignatureChecker.InvalidSignature({ signer: proposer, digest: proposalHash });
                }
            }
        } else {
            // Multiproposal signature
            bytes32 multiproposalHash = hashMultiproposal(
                Multiproposal({
                    multiproposalMerkleRoot: MerkleProof.processProofCalldata({
                        proof: proposalInclusionProof,
                        leaf: proposalHash
                    })
                })
            );
            if (!isMultiproposalAcceptable[proposer][multiproposalHash]) {
                if (!PWNSignatureChecker.isValidSignatureNow(proposer, multiproposalHash, signature)) {
                    revert PWNSignatureChecker.InvalidSignature({ signer: proposer, digest: multiproposalHash });
                }
            }
        }
    }

}

// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MerkleProof } from "openzeppelin/utils/cryptography/MerkleProof.sol";

import { PWNConfig } from "pwn/core/config/PWNConfig.sol";
import { PWNHub } from "pwn/core/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/core/hub/PWNHubTags.sol";
import { LoanTerms as Terms } from "pwn/core/loan/LoanTerms.sol";
import { IPWNProposal } from "pwn/core/proposal/IPWNProposal.sol";
import { PWNSignatureChecker } from "pwn/periphery/lib/PWNSignatureChecker.sol";
import { PWNRevokedNonce } from "pwn/periphery/proposal/auxiliary/PWNRevokedNonce.sol";
import { PWNUtilizedCredit } from "pwn/periphery/proposal/auxiliary/PWNUtilizedCredit.sol";


/**
 * @title PWN Proposal Base Contract
 * @notice Base contract of loan proposals that builds a simple loan terms.
 */
abstract contract PWNBaseProposal is IPWNProposal {

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    bytes32 public immutable DOMAIN_SEPARATOR;
    bytes32 public immutable MULTIPROPOSAL_DOMAIN_SEPARATOR;

    PWNHub public immutable hub;
    PWNRevokedNonce public immutable revokedNonce;
    PWNConfig public immutable config;
    PWNUtilizedCredit public immutable utilizedCredit;

    bytes32 public constant MULTIPROPOSAL_TYPEHASH = keccak256("Multiproposal(bytes32 multiproposalMerkleRoot)");

    struct Multiproposal {
        bytes32 multiproposalMerkleRoot;
    }

    struct CheckInputs {
        bytes32 proposalHash;
        address acceptor;
        uint256 creditAmount;
        uint256 availableCreditLimit;
        bytes32 utilizedCreditId;
        uint256 nonceSpace;
        uint256 nonce;
        uint256 expiration;
        address proposer;
        address loanContract;
    }

    /**
     * @dev Mapping of proposals made via on-chain transactions.
     * Could be used by contract wallets instead of EIP-1271.
     * (proposal hash => is made)
     */
    mapping (bytes32 => bool) public proposalsMade;


    /*----------------------------------------------------------*|
    |*  # ERRORS DEFINITIONS                                    *|
    |*----------------------------------------------------------*/

    /** @notice Thrown when an address is missing a PWN Hub tag.*/
    error AddressMissingHubTag(address addr, bytes32 tag);
    /** @notice Thrown when a proposal is expired.*/
    error Expired(uint256 current, uint256 expiration);
    /** @notice Thrown when a caller is missing a required hub tag.*/
    error CallerNotLoanContract(address caller, address loanContract);
    /** @notice Thrown when a caller is not a stated proposer.*/
    error CallerIsNotStatedProposer(address addr);
    /** @notice Thrown when proposal acceptor and proposer are the same.*/
    error AcceptorIsProposer(address addr);
    /** @notice Thrown when a default date is in the past.*/
    error DefaultDateInPast(uint256 defaultDate, uint256 current);


    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR                                           *|
    |*----------------------------------------------------------*/

    constructor(
        address _hub,
        address _revokedNonce,
        address _config,
        address _utilizedCredit,
        string memory name,
        string memory version
    ) {
        hub = PWNHub(_hub);
        revokedNonce = PWNRevokedNonce(_revokedNonce);
        config = PWNConfig(_config);
        utilizedCredit = PWNUtilizedCredit(_utilizedCredit);

        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(abi.encodePacked(name)),
            keccak256(abi.encodePacked(version)),
            block.chainid,
            address(this)
        ));

        MULTIPROPOSAL_DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name)"),
            keccak256("PWNMultiproposal")
        ));
    }


    /*----------------------------------------------------------*|
    |*  # EXTERNALS                                             *|
    |*----------------------------------------------------------*/

    /**
     * @notice Get a multiproposal hash according to EIP-712.
     * @param multiproposal Multiproposal struct.
     * @return Multiproposal hash.
     */
    function getMultiproposalHash(Multiproposal memory multiproposal) public view returns (bytes32) {
        return keccak256(abi.encodePacked(
            hex"1901", MULTIPROPOSAL_DOMAIN_SEPARATOR, keccak256(abi.encodePacked(
                MULTIPROPOSAL_TYPEHASH, abi.encode(multiproposal)
            ))
        ));
    }


    /*----------------------------------------------------------*|
    |*  # INTERNALS                                             *|
    |*----------------------------------------------------------*/

    /**
     * @notice Get a proposal hash according to EIP-712.
     * @param encodedProposal Encoded proposal struct.
     * @return Struct hash.
     */
    function _getProposalHash(
        bytes32 proposalTypehash,
        bytes memory encodedProposal
    ) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            hex"1901", DOMAIN_SEPARATOR, keccak256(abi.encodePacked(
                proposalTypehash, encodedProposal
            ))
        ));
    }

    /**
     * @notice Make an on-chain proposal.
     * @dev Function will mark a proposal hash as proposed.
     * @param proposalHash Proposal hash.
     * @param proposer Address of a proposal proposer.
     */
    function _makeProposal(bytes32 proposalHash, address proposer) internal {
        if (msg.sender != proposer) revert CallerIsNotStatedProposer({ addr: proposer });
        proposalsMade[proposalHash] = true;
    }

    /**
     * @notice Check proposal validity.
     * @param inputs Struct containing all needed proposal data.
     * @param proposalInclusionProof Multiproposal inclusion proof. Empty if single proposal.
     * @param signature Signature of a proposal.
     */
    function _checkProposal(
        CheckInputs memory inputs,
        bytes32[] calldata proposalInclusionProof,
        bytes calldata signature
    ) internal {
        // Check loan contract
        if (msg.sender != inputs.loanContract) {
            revert CallerNotLoanContract({ caller: msg.sender, loanContract: inputs.loanContract });
        }
        if (!hub.hasTag(inputs.loanContract, PWNHubTags.ACTIVE_LOAN)) {
            revert AddressMissingHubTag({ addr: inputs.loanContract, tag: PWNHubTags.ACTIVE_LOAN });
        }

        // Check proposal signature or that it was made on-chain
        if (proposalInclusionProof.length == 0) {
            // Single proposal signature
            if (!proposalsMade[inputs.proposalHash]) {
                if (!PWNSignatureChecker.isValidSignatureNow(inputs.proposer, inputs.proposalHash, signature)) {
                    revert PWNSignatureChecker.InvalidSignature({ signer: inputs.proposer, digest: inputs.proposalHash });
                }
            }
        } else {
            // Multiproposal signature
            bytes32 multiproposalHash = getMultiproposalHash(
                Multiproposal({
                    multiproposalMerkleRoot: MerkleProof.processProofCalldata({
                        proof: proposalInclusionProof,
                        leaf: inputs.proposalHash
                    })
                })
            );
            if (!PWNSignatureChecker.isValidSignatureNow(inputs.proposer, multiproposalHash, signature)) {
                revert PWNSignatureChecker.InvalidSignature({ signer: inputs.proposer, digest: multiproposalHash });
            }
        }

        // Check proposer is not acceptor
        if (inputs.proposer == inputs.acceptor) {
            revert AcceptorIsProposer({ addr: inputs.acceptor});
        }

        // Check proposal is not expired
        if (block.timestamp >= inputs.expiration) {
            revert Expired({ current: block.timestamp, expiration: inputs.expiration });
        }

        // Check proposal is not revoked
        if (!revokedNonce.isNonceUsable(inputs.proposer, inputs.nonceSpace, inputs.nonce)) {
            revert PWNRevokedNonce.NonceNotUsable({
                addr: inputs.proposer,
                nonceSpace: inputs.nonceSpace,
                nonce: inputs.nonce
            });
        }

        if (inputs.availableCreditLimit == 0) {
            // Revoke nonce if credit limit is 0, proposal can be accepted only once
            revokedNonce.revokeNonce(inputs.proposer, inputs.nonceSpace, inputs.nonce);
        } else {
            // Update utilized credit
            // Note: This will revert if utilized credit would exceed the available credit limit
            utilizedCredit.utilizeCredit(
                inputs.proposer, inputs.utilizedCreditId, inputs.creditAmount, inputs.availableCreditLimit
            );
        }
    }

}

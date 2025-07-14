// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import { PWNUtilizedCredit } from "pwn/periphery/auxiliary/PWNUtilizedCredit.sol";


abstract contract PWNUtilizedCreditTest is Test {

    bytes32 internal constant UTILIZED_CREDIT_SLOT = bytes32(uint256(0)); // `utilizedCredit` mapping position

    PWNUtilizedCredit utilizedCredit;
    bytes32 accessTag = keccak256("Some nice pwn tag");
    address hub = makeAddr("hub");
    address accessEnabledAddress = makeAddr("accessEnabledAddress");
    address owner = makeAddr("owner");
    bytes32 id = keccak256("id");
    uint256 amount = 420;
    uint256 limit = 1000;


    function setUp() public virtual {
        utilizedCredit = new PWNUtilizedCredit(hub, accessTag);

        vm.mockCall(hub, abi.encodeWithSignature("hasTag(address,bytes32)"), abi.encode(false));
        vm.mockCall(hub, abi.encodeWithSignature("hasTag(address,bytes32)", accessEnabledAddress, accessTag), abi.encode(true));
    }


    function _utilizedCreditSlot(address _owner, bytes32 _id) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            _id, keccak256(abi.encode(
                _owner, UTILIZED_CREDIT_SLOT
            ))
        ));
    }

}


/*----------------------------------------------------------*|
|*  # UTILIZED CREDIT                                       *|
|*----------------------------------------------------------*/

contract PWNUtilizedCredit_UtilizedCredit_Test is PWNUtilizedCreditTest {

    function testFuzz_shouldReturnStoredValue(uint256 alreadyUtilizedCredit) external {
        vm.store(address(utilizedCredit), _utilizedCreditSlot(owner, id), bytes32(alreadyUtilizedCredit));

        assertEq(utilizedCredit.utilizedCredit(owner, id), alreadyUtilizedCredit);
    }

}


/*----------------------------------------------------------*|
|*  # UTILIZE CREDIT                                        *|
|*----------------------------------------------------------*/

contract PWNUtilizedCredit_UtilizeCredit_Test is PWNUtilizedCreditTest {

    function test_shouldFail_whenCallerWithoutHubTag() external {
        address caller = makeAddr("prank");

        vm.expectRevert(abi.encodeWithSelector(
            PWNUtilizedCredit.AddressMissingHubTag.selector, caller, utilizedCredit.accessTag())
        );
        vm.prank(caller);
        utilizedCredit.utilizeCredit(owner, id, amount, limit);
    }

    function testFuzz_shouldRevert_whenUtilizedCreditExceedsLimit_whenNoUtilizedCredit(
        uint256 amount, uint256 limit
    ) external {
        limit = bound(limit, 1, type(uint256).max - 1);
        amount = bound(amount, limit + 1, type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(PWNUtilizedCredit.AvailableCreditLimitExceeded.selector, owner, id, amount, limit)
        );
        vm.prank(accessEnabledAddress);
        utilizedCredit.utilizeCredit(owner, id, amount, limit);
    }

    function testFuzz_shouldRevert_whenUtilizedCreditExceedsLimit_whenAlreadyUtilizedCredit(
        uint256 amount, uint256 limit, uint256 alreadyUtilizedCredit
    ) external {
        alreadyUtilizedCredit = bound(alreadyUtilizedCredit, 1, type(uint256).max - 1);
        limit = bound(limit, alreadyUtilizedCredit, type(uint256).max - 1);
        amount = bound(amount, limit - alreadyUtilizedCredit + 1, type(uint256).max - alreadyUtilizedCredit);

        vm.store(address(utilizedCredit), _utilizedCreditSlot(owner, id), bytes32(alreadyUtilizedCredit));

        vm.expectRevert(
            abi.encodeWithSelector(
                PWNUtilizedCredit.AvailableCreditLimitExceeded.selector,
                owner, id, alreadyUtilizedCredit + amount, limit
            )
        );
        vm.prank(accessEnabledAddress);
        utilizedCredit.utilizeCredit(owner, id, amount, limit);
    }

    function testFuzz_shouldIncrementUtilizedCredit(uint256 amount, uint256 alreadyUtilizedCredit) external {
        amount = bound(amount, 1, type(uint256).max / 2);
        alreadyUtilizedCredit = bound(alreadyUtilizedCredit, 0, type(uint256).max / 2);

        vm.store(address(utilizedCredit), _utilizedCreditSlot(owner, id), bytes32(alreadyUtilizedCredit));

        vm.prank(accessEnabledAddress);
        utilizedCredit.utilizeCredit(owner, id, amount, type(uint256).max);

        assertEq(utilizedCredit.utilizedCredit(owner, id), alreadyUtilizedCredit + amount);
    }

}

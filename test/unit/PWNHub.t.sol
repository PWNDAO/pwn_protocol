// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import { PWNHub } from "pwn/core/hub/PWNHub.sol";


abstract contract PWNHubTest is Test {

    bytes32 internal constant TAGS_SLOT = bytes32(uint256(2)); // `tags` mapping position

    PWNHub hub;
    address owner = address(0x1001);
    address addr = address(0x01);
    bytes32 tag = keccak256("tag_1");

    event TagSet(address indexed _address, bytes32 indexed tag, bool hasTag);

    function setUp() external {
        vm.prank(owner);
        hub = new PWNHub();
    }


    function _addressTagSlot(address _address, bytes32 _tag) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            _tag,
            keccak256(abi.encode(
                _address,
                TAGS_SLOT
            ))
        ));
    }

}


/*----------------------------------------------------------*|
|*  # CONSTRUCTOR                                           *|
|*----------------------------------------------------------*/

contract PWNHub_Constructor_Test is PWNHubTest {

    function test_shouldSetHubOwner() external {
        address otherOwner = address(0x4321);

        vm.prank(otherOwner);
        hub = new PWNHub();

        assertTrue(hub.owner() == otherOwner);
    }

}


/*----------------------------------------------------------*|
|*  # SET TAG                                               *|
|*----------------------------------------------------------*/

contract PWNHub_SetTag_Test is PWNHubTest {

    function test_shouldFail_whenCallerIsNotOwner() external {
        address other = address(0x123);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(other);
        hub.setTag(addr, tag, true);
    }

    function test_shouldAddTagToAddress() external {
        vm.prank(owner);
        hub.setTag(addr, tag, true);

        bytes32 hasTagValue = vm.load(
            address(hub),
            _addressTagSlot(addr, tag)
        );
        assertTrue(uint256(hasTagValue) == 1);
    }

    function test_shouldRemoveTagFromAddress() external {
        vm.store(
            address(hub),
            _addressTagSlot(addr, tag),
            bytes32(uint256(1))
        );

        vm.prank(owner);
        hub.setTag(addr, tag, false);

        bytes32 hasTagValue = vm.load(
            address(hub),
            _addressTagSlot(addr, tag)
        );
        assertTrue(uint256(hasTagValue) == 0);
    }

    function test_shouldEmitEvent_TagSet() external {
        vm.expectEmit(true, true, false, true);
        emit TagSet(addr, tag, true);

        vm.prank(owner);
        hub.setTag(addr, tag, true);
    }

}


/*----------------------------------------------------------*|
|*  # SET TAGS                                              *|
|*----------------------------------------------------------*/

contract PWNHub_SetTags_Test is PWNHubTest {

    address[] addrs;
    bytes32[] tags;

    constructor() {
        addrs = new address[](2);
        addrs[0] = address(0x1001);
        addrs[1] = address(0x1002);

        tags = new bytes32[](2);
        tags[0] = keccak256("tags_0");
        tags[1] = keccak256("tags_1");
    }

    function test_shouldFail_whenCallerIsNotOwner() external {
        address other = address(0x123);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(other);
        hub.setTags(addrs, tags, true);
    }

    function test_shouldFail_whenDiffInputLengths() external {
        address[] memory addrs_ = new address[](3);

        vm.expectRevert(abi.encodeWithSelector(PWNHub.InvalidInputData.selector));
        vm.prank(owner);
        hub.setTags(addrs_, tags, true);
    }

    function test_shouldNotFail_whenEmptyList() external {
        address[] memory emptyAddrs;
        bytes32[] memory emptyTags;

        vm.prank(owner);
        hub.setTags(emptyAddrs, emptyTags, true);
    }

    function test_shouldAddTagsToAddress() external {
        vm.prank(owner);
        hub.setTags(addrs, tags, true);

        for (uint256 i; i < tags.length; ++i) {
            bytes32 hasTagValue = vm.load(
                address(hub),
                _addressTagSlot(addrs[i], tags[i])
            );
            assertTrue(uint256(hasTagValue) == 1);
        }
    }

    function test_shouldRemoveTagsFromAddress() external {
        for (uint256 i; i < tags.length; ++i) {
            vm.store(
                address(hub),
                _addressTagSlot(addrs[i], tags[i]),
                bytes32(uint256(1))
            );
        }

        vm.prank(owner);
        hub.setTags(addrs, tags, false);

        for (uint256 i; i < tags.length; ++i) {
            bytes32 hasTagValue = vm.load(
                address(hub),
                _addressTagSlot(addrs[i], tags[i])
            );
            assertTrue(uint256(hasTagValue) == 0);
        }
    }

    function test_shouldEmitEvent_TagSet_forEverySet() external {
        for (uint256 i; i < tags.length; ++i) {
            vm.expectEmit(true, true, false, true);
            emit TagSet(addrs[i], tags[i], true);
        }

        vm.prank(owner);
        hub.setTags(addrs, tags, true);
    }

}


/*----------------------------------------------------------*|
|*  # HAS TAG                                               *|
|*----------------------------------------------------------*/

contract PWNHub_HasTag_Test is PWNHubTest {

    function test_shouldReturnFalse_whenAddressDoesNotHaveTag() external {
        vm.store(
            address(hub),
            _addressTagSlot(addr, tag),
            bytes32(uint256(0))
        );

        assertFalse(hub.hasTag(addr, tag));
    }

    function test_shouldReturnTrue_whenAddressDoesHaveTag() external {
        vm.store(
            address(hub),
            _addressTagSlot(addr, tag),
            bytes32(uint256(1))
        );

        assertTrue(hub.hasTag(addr, tag));
    }

}

// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import { PWNConfig } from "pwn/core/config/PWNConfig.sol";


abstract contract PWNConfigTest is Test {

    bytes32 internal constant INITIALIZED_SLOT = bytes32(uint256(0)); // `_initialized` property position
    bytes32 internal constant OWNER_SLOT = bytes32(uint256(51)); // `_owner` property position
    bytes32 internal constant PENDING_OWNER_SLOT = bytes32(uint256(101)); // `_pendingOwner` property position
    bytes32 internal constant FEE_SLOT = bytes32(uint256(151)); // `fee` property position
    bytes32 internal constant FEE_COLLECTOR_SLOT = bytes32(uint256(151)); // `feeCollector` property position
    bytes32 internal constant LOAN_METADATA_URI_SLOT = bytes32(uint256(152)); // `loanMetadataUri` mapping position
    bytes32 internal constant SFC_REGISTRY_SLOT = bytes32(uint256(153)); // `_sfComputerRegistry` mapping position
    bytes32 internal constant POOL_ADAPTER_REGISTRY_SLOT = bytes32(uint256(154)); // `_poolAdapterRegistry` mapping position

    PWNConfig config;
    address owner = makeAddr("owner");
    address feeCollector = makeAddr("feeCollector");

    event FeeUpdated(uint16 oldFee, uint16 newFee);
    event FeeCollectorUpdated(address oldFeeCollector, address newFeeCollector);
    event LOANMetadataUriUpdated(address indexed loanContract, string newUri);
    event DefaultLOANMetadataUriUpdated(string newUri);

    function setUp() virtual public {
        config = new PWNConfig();
    }

    function _initialize() internal {
        // initialize owner to `owner`, fee to 0 and feeCollector to `feeCollector`
        vm.store(address(config), OWNER_SLOT, bytes32(uint256(uint160(owner))));
        vm.store(address(config), FEE_COLLECTOR_SLOT, bytes32(uint256(uint160(feeCollector))) << 16);
    }

    function _mockSupportsToken(address computer, address token, bool result) internal {
        vm.mockCall(
            computer,
            abi.encodeWithSignature("supportsToken(address)", token),
            abi.encode(result)
        );
    }

}


/*----------------------------------------------------------*|
|*  # CONSTRUCTOR                                           *|
|*----------------------------------------------------------*/

contract PWNConfig_Constructor_Test is PWNConfigTest {

    function test_shouldInitializeWithZeroValues() external {
        bytes32 ownerValue = vm.load(address(config), OWNER_SLOT);
        assertEq(address(uint160(uint256(ownerValue))), address(0));

        bytes32 initializedSlotValue = vm.load(address(config), INITIALIZED_SLOT);
        assertEq(uint16(uint256(initializedSlotValue << 248 >> 248)), 255); // disable initializers

        bytes32 feeSlotValue = vm.load(address(config), FEE_SLOT);
        assertEq(uint16(uint256(feeSlotValue << 240 >> 240)), 0);

        bytes32 feeCollectorValue = vm.load(address(config), FEE_COLLECTOR_SLOT);
        assertEq(address(uint160(uint256(feeCollectorValue >> 16))), address(0));
    }

}


/*----------------------------------------------------------*|
|*  # INITIALIZE                                            *|
|*----------------------------------------------------------*/

contract PWNConfig_Initialize_Test is PWNConfigTest {

    uint16 fee = 32;

    function setUp() override public {
        super.setUp();

        // mock that contract is not initialized
        vm.store(address(config), INITIALIZED_SLOT, bytes32(0));
    }

    function test_shouldSetValues() external {
        config.initialize(owner, fee, feeCollector);

        bytes32 ownerValue = vm.load(address(config), OWNER_SLOT);
        assertEq(address(uint160(uint256(ownerValue))), owner);

        bytes32 feeSlotValue = vm.load(address(config), FEE_SLOT);
        assertEq(uint16(uint256(feeSlotValue << 240 >> 240)), fee);

        bytes32 feeCollectorValue = vm.load(address(config), FEE_COLLECTOR_SLOT);
        assertEq(address(uint160(uint256(feeCollectorValue >> 16))), feeCollector);
    }

    function test_shouldFail_whenCalledSecondTime() external {
        config.initialize(owner, fee, feeCollector);

        vm.expectRevert("Initializable: contract is already initialized");
        config.initialize(owner, fee, feeCollector);
    }

    function test_shouldFail_whenOwnerIsZeroAddress() external {
        vm.expectRevert("Owner is zero address");
        config.initialize(address(0), fee, feeCollector);
    }

    function test_shouldFail_whenFeeCollectorIsZeroAddress() external {
        vm.expectRevert(abi.encodeWithSelector(PWNConfig.ZeroFeeCollector.selector));
        config.initialize(owner, fee, address(0));
    }

}


/*----------------------------------------------------------*|
|*  # SET FEE                                               *|
|*----------------------------------------------------------*/

contract PWNConfig_SetFee_Test is PWNConfigTest {

    function setUp() override public {
        super.setUp();

        _initialize();
    }


    function test_shouldFail_whenCallerIsNotOwner() external {
        vm.expectRevert("Ownable: caller is not the owner");
        config.setFee(9);
    }

    function testFuzz_shouldFail_whenNewValueBiggerThanMaxFee(uint16 fee) external {
        uint16 maxFee = config.MAX_FEE();
        fee = uint16(bound(fee, maxFee + 1, type(uint16).max));

        vm.expectRevert(abi.encodeWithSelector(PWNConfig.InvalidFeeValue.selector, fee, maxFee));
        vm.prank(owner);
        config.setFee(fee);
    }

    function test_shouldSetFeeValue() external {
        uint16 fee = 9;

        vm.prank(owner);
        config.setFee(fee);

        bytes32 feeSlotValue = vm.load(address(config), FEE_SLOT);
        assertEq(uint16(uint256(feeSlotValue << 240 >> 240)), fee);
    }

    function test_shouldEmitEvent_FeeUpdated() external {
        vm.expectEmit(true, true, false, false);
        emit FeeUpdated(0, 9);

        vm.prank(owner);
        config.setFee(9);
    }

}


/*----------------------------------------------------------*|
|*  # SET FEE COLLECTOR                                     *|
|*----------------------------------------------------------*/

contract PWNConfig_SetFeeCollector_Test is PWNConfigTest {

    address newFeeCollector = address(0xfee);

    function setUp() override public {
        super.setUp();

        _initialize();
    }


    function test_shouldFail_whenCallerIsNotOwner() external {
        vm.expectRevert("Ownable: caller is not the owner");
        config.setFeeCollector(newFeeCollector);
    }

    function test_shouldFail_whenSettingZeroAddress() external {
        vm.expectRevert(abi.encodeWithSelector(PWNConfig.ZeroFeeCollector.selector));
        vm.prank(owner);
        config.setFeeCollector(address(0));
    }

    function test_shouldSetFeeCollectorAddress() external {
        vm.prank(owner);
        config.setFeeCollector(newFeeCollector);

        bytes32 feeCollectorValue = vm.load(address(config), FEE_COLLECTOR_SLOT);
        assertEq(uint160(uint256(feeCollectorValue >> 16)), uint160(newFeeCollector));
    }

    function test_shouldEmitEvent_FeeCollectorUpdated() external {
        vm.expectEmit(true, true, false, false);
        emit FeeCollectorUpdated(feeCollector, newFeeCollector);

        vm.prank(owner);
        config.setFeeCollector(newFeeCollector);
    }

}


/*----------------------------------------------------------*|
|*  # SET LOAN METADATA URI                                 *|
|*----------------------------------------------------------*/

contract PWNConfig_SetLOANMetadataUri_Test is PWNConfigTest {

    string tokenUri = "test.token.uri";
    address loanContract = address(0x63);

    function setUp() override public {
        super.setUp();

        _initialize();
    }


    function test_shouldFail_whenCallerIsNotOwner() external {
        vm.expectRevert("Ownable: caller is not the owner");
        config.setLOANMetadataUri(loanContract, tokenUri);
    }

    function test_shouldFail_whenZeroLoanContract() external {
        vm.expectRevert(abi.encodeWithSelector(PWNConfig.ZeroLoanContract.selector));
        vm.prank(owner);
        config.setLOANMetadataUri(address(0), tokenUri);
    }

    function testFuzz_shouldStoreLoanMetadataUriToLoanContract(address _loanContract) external {
        vm.assume(_loanContract != address(0));
        loanContract = _loanContract;

        vm.prank(owner);
        config.setLOANMetadataUri(loanContract, tokenUri);

        bytes32 tokenUriValue = vm.load(
            address(config),
            keccak256(abi.encode(loanContract, LOAN_METADATA_URI_SLOT))
        );
        bytes memory memoryTokenUri = bytes(tokenUri);
        bytes32 _tokenUri;
        assembly {
            _tokenUri := mload(add(memoryTokenUri, 0x20))
        }
        // Remove string length
        assertEq(keccak256(abi.encodePacked(tokenUriValue >> 8)), keccak256(abi.encodePacked(_tokenUri >> 8)));
    }

    function test_shouldEmitEvent_LOANMetadataUriUpdated() external {
        vm.expectEmit(true, true, true, true);
        emit LOANMetadataUriUpdated(loanContract, tokenUri);

        vm.prank(owner);
        config.setLOANMetadataUri(loanContract, tokenUri);
    }

}


/*----------------------------------------------------------*|
|*  # SET DEFAULT LOAN METADATA URI                         *|
|*----------------------------------------------------------*/

contract PWNConfig_SetDefaultLOANMetadataUri_Test is PWNConfigTest {

    string tokenUri = "test.token.uri";

    function setUp() override public {
        super.setUp();

        _initialize();
    }


    function test_shouldFail_whenCallerIsNotOwner() external {
        vm.expectRevert("Ownable: caller is not the owner");
        config.setDefaultLOANMetadataUri(tokenUri);
    }

    function test_shouldStoreDefaultLoanMetadataUri() external {
        vm.prank(owner);
        config.setDefaultLOANMetadataUri(tokenUri);

        bytes32 tokenUriValue = vm.load(
            address(config),
            keccak256(abi.encode(address(0), LOAN_METADATA_URI_SLOT))
        );
        bytes memory memoryTokenUri = bytes(tokenUri);
        bytes32 _tokenUri;
        assembly {
            _tokenUri := mload(add(memoryTokenUri, 0x20))
        }
        // Remove string length
        assertEq(keccak256(abi.encodePacked(tokenUriValue >> 8)), keccak256(abi.encodePacked(_tokenUri >> 8)));
    }

    function test_shouldEmitEvent_DefaultLOANMetadataUriUpdated() external {
        vm.expectEmit(true, true, true, true);
        emit DefaultLOANMetadataUriUpdated(tokenUri);

        vm.prank(owner);
        config.setDefaultLOANMetadataUri(tokenUri);
    }

}


/*----------------------------------------------------------*|
|*  # LOAN METADATA URI                                     *|
|*----------------------------------------------------------*/

contract PWNConfig_LoanMetadataUri_Test is PWNConfigTest {

    function setUp() override public {
        super.setUp();

        _initialize();
    }


    function testFuzz_shouldReturnDefaultLoanMetadataUri_whenNoStoreValueForLoanContract(address loanContract) external {
        string memory defaultUri = "default.token.uri";

        vm.prank(owner);
        config.setDefaultLOANMetadataUri(defaultUri);

        string memory uri = config.loanMetadataUri(loanContract);
        assertEq(uri, defaultUri);
    }

    function testFuzz_shouldReturnLoanMetadataUri_whenStoredValueForLoanContract(address loanContract) external {
        vm.assume(loanContract != address(0));
        string memory tokenUri = "test.token.uri";

        vm.prank(owner);
        config.setLOANMetadataUri(loanContract, tokenUri);

        string memory uri = config.loanMetadataUri(loanContract);
        assertEq(uri, tokenUri);
    }

}


/*----------------------------------------------------------*|
|*  # GET STATE FINGERPRINT COMPUTER                        *|
|*----------------------------------------------------------*/

contract PWNConfig_GetStateFingerprintComputer_Test is PWNConfigTest {

    function setUp() override public {
        super.setUp();

        _initialize();
    }


    function testFuzz_shouldReturnStoredComputer_whenIsRegistered(address asset, address computer) external {
        bytes32 assetSlot = keccak256(abi.encode(asset, SFC_REGISTRY_SLOT));
        vm.store(address(config), assetSlot, bytes32(uint256(uint160(computer))));

        assertEq(address(config.getStateFingerprintComputer(asset)), computer);
    }

}


/*----------------------------------------------------------*|
|*  # REGISTER STATE FINGERPRINT COMPUTER                   *|
|*----------------------------------------------------------*/

contract PWNConfig_RegisterStateFingerprintComputer_Test is PWNConfigTest {

    function setUp() override public {
        super.setUp();

        _initialize();
    }


    function testFuzz_shouldFail_whenCallerIsNotOwner(address caller) external {
        vm.assume(caller != owner);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(caller);
        config.registerStateFingerprintComputer(address(0), address(0));
    }

    function testFuzz_shouldUnregisterComputer_whenComputerIsZeroAddress(address asset) external {
        address computer = makeAddr("computer");
        bytes32 assetSlot = keccak256(abi.encode(asset, SFC_REGISTRY_SLOT));
        vm.store(address(config), assetSlot, bytes32(uint256(uint160(computer))));

        vm.prank(owner);
        config.registerStateFingerprintComputer(asset, address(0));

        assertEq(address(config.getStateFingerprintComputer(asset)), address(0));
    }

    function testFuzz_shouldFail_whenComputerDoesNotSupportToken(address asset, address computer) external {
        assumeAddressIsNot(computer, AddressType.ForgeAddress, AddressType.Precompile, AddressType.ZeroAddress);
        _mockSupportsToken(computer, asset, false);

        vm.expectRevert(abi.encodeWithSelector(PWNConfig.InvalidComputerContract.selector, computer, asset));
        vm.prank(owner);
        config.registerStateFingerprintComputer(asset, computer);
    }

    function testFuzz_shouldRegisterComputer(address asset, address computer) external {
        assumeAddressIsNot(computer, AddressType.ForgeAddress, AddressType.Precompile, AddressType.ZeroAddress);
        _mockSupportsToken(computer, asset, true);

        vm.prank(owner);
        config.registerStateFingerprintComputer(asset, computer);

        assertEq(address(config.getStateFingerprintComputer(asset)), computer);
    }

}


/*----------------------------------------------------------*|
|*  # GET POOL ADAPTER                                      *|
|*----------------------------------------------------------*/

contract PWNConfig_GetPoolAdapter_Test is PWNConfigTest {

    function setUp() override public {
        super.setUp();

        _initialize();
    }


    function testFuzz_shouldReturnStoredAdapter_whenIsRegistered(address pool, address adapter) external {
        bytes32 poolSlot = keccak256(abi.encode(pool, POOL_ADAPTER_REGISTRY_SLOT));
        vm.store(address(config), poolSlot, bytes32(uint256(uint160(adapter))));

        assertEq(address(config.getPoolAdapter(pool)), adapter);
    }

}


/*----------------------------------------------------------*|
|*  # REGISTER POOL ADAPTER                                 *|
|*----------------------------------------------------------*/

contract PWNConfig_RegisterPoolAdapter_Test is PWNConfigTest {

    function setUp() override public {
        super.setUp();

        _initialize();
    }


    function testFuzz_shouldFail_whenCallerIsNotOwner(address caller) external {
        vm.assume(caller != owner);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(caller);
        config.registerPoolAdapter(address(0), address(0));
    }

    function testFuzz_shouldStoreAdapter(address pool, address adapter) external {
        vm.prank(owner);
        config.registerPoolAdapter(pool, adapter);

        assertEq(address(config.getPoolAdapter(pool)), adapter);
    }

}

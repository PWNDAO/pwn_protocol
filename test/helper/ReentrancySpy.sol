// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;


contract ReentrancySpy {

    address private addr_;
    bytes private calldata_;

    function reenter(address _addr, bytes calldata _calldata) external {
        addr_ = _addr;
        calldata_ = _calldata;
    }

    fallback() external {
        (bool success, bytes memory err) = addr_.call(calldata_);
        if (!success && err.length > 0) {
            assembly {
                revert(add(err, 0x20), mload(err))
            }
        }
    }

}

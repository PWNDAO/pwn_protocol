// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

library LOANStatus {
    uint8 constant DEAD = 0;
    uint8 constant RUNNING = 2;
    uint8 constant REPAID = 3;
    uint8 constant DEFAULTED = 4;
}

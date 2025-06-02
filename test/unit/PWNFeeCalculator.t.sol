// // SPDX-License-Identifier: GPL-3.0-only
// pragma solidity 0.8.16;

// import { Test } from "forge-std/Test.sol";

// import { PWNFeeCalculator } from "pwn/lib/PWNFeeCalculator.sol";


// contract PWNFeeCalculator_CalculateFeeAmount_Test is Test {

//     function test_shouldReturnCorrectValue_forZeroFee() external {
//         (uint256 feeAmount, uint256 newLoanAmount) = PWNFeeCalculator.calculateFeeAmount(0, 5400);

//         assertEq(feeAmount, 0);
//         assertEq(newLoanAmount, 5400);
//     }

//     function test_shouldReturnCorrectValue_forNonZeroFee() external {
//         (uint256 feeAmount, uint256 newLoanAmount) = PWNFeeCalculator.calculateFeeAmount(100, 5400);

//         assertEq(feeAmount, 54);
//         assertEq(newLoanAmount, 5346);
//     }

//     function test_shouldHandleZeroAmount() external {
//         (uint256 feeAmount, uint256 newLoanAmount) = PWNFeeCalculator.calculateFeeAmount(0, 0);

//         assertEq(feeAmount, 0);
//         assertEq(newLoanAmount, 0);
//     }

//     function test_shouldHandleSmallAmount() external {
//         (uint256 feeAmount, uint256 newLoanAmount) = PWNFeeCalculator.calculateFeeAmount(100, 10);

//         assertEq(feeAmount, 0);
//         assertEq(newLoanAmount, 10);
//     }

//     function testFuzz_feeAndNewLoanAmountAreEqToOriginalLoanAmount(uint16 fee, uint256 loanAmount) external {
//         fee = fee % 10001;

//         (uint256 feeAmount, uint256 newLoanAmount) = PWNFeeCalculator.calculateFeeAmount(fee, loanAmount);
//         assertEq(loanAmount, feeAmount + newLoanAmount);
//     }

// }

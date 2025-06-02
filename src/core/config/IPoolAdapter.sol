// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

/**
 * @title IPoolAdapter
 * @notice Interface for pool adapters used to withdraw and supply assets to the pool.
 */
interface IPoolAdapter {

    /**
     * @notice Withdraw an asset from the pool on behalf of the owner.
     * @dev Withdrawn asset remains in the owner. Caller must have the ACTIVE_LOAN tag in the hub.
     * @param pool The address of the pool from which the asset is withdrawn.
     * @param owner The address of the owner from whom the asset is withdrawn.
     * @param asset The address of the asset to withdraw.
     * @param amount The amount of the asset to withdraw.
     */
    function withdraw(address pool, address owner, address asset, uint256 amount) external;

    /**
     * @notice Supply an asset to the pool on behalf of the owner.
     * @dev Need to transfer the asset to the adapter before calling this function.
     * @param pool The address of the pool to which the asset is supplied.
     * @param owner The address of the owner on whose behalf the asset is supplied.
     * @param asset The address of the asset to supply.
     * @param amount The amount of the asset to supply.
     */
    function supply(address pool, address owner, address asset, uint256 amount) external;

}

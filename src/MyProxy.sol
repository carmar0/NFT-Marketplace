// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title MyProxy contract
 * @dev Main point of interaction with NFTMarketplace contract
 * @author carmar0
 */
contract MyProxy is ERC1967Proxy {

    constructor(address implementation, bytes memory data) 
    ERC1967Proxy(implementation, data) {}

    /**
     * @notice Returns the implementation/contract address the proxy is pointing
     * @return Implementation address
     */
    function getImplementation() external view returns (address) {
        return _implementation();
    }
}
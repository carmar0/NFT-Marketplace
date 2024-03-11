// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title MyProxy contract
 * @dev Main point of interaction with NFTMarketplace contract
 * @author carmar0
 */
contract MyProxy is ERC1967Proxy {

    uint256 public sellOfferIdCounter;
    uint256 public buyOfferIdCounter;
    address public contractOwner;
    string public marketplaceName;

    mapping(uint256 => Offer) public sellOffers;
    mapping(uint256 => Offer) public buyOffers;

    struct Offer {
        uint128 price;
        uint128 deadline;
        uint64 tokenId;
        address nftAddress;
        bool isEnded;
        address offerer;
    }

    constructor(address implementation, bytes memory data) 
    ERC1967Proxy(implementation, data) {}

    /**
     * @notice Returns the implementation address the proxy is pointing
     * @return Implementation address
     */
    function getImplementation() external view returns (address) {
        return _implementation();
    }
}
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/**
 * @title NFTMarketplace contract
 * @author carmar0
 */

contract NFTMarketplace is UUPSUpgradeable, Initializable {

    event SellOfferCreated(uint256 offer);
    event SellOfferAccepted(uint256 offer);
    event SellOfferCancelled(uint256 offer);
    event BuyOfferCreated(uint256 offer);
    error NoOwner();
    error WrongDeadline();
    error WrongPrice();
    error OfferEnded();
    error WrongEthAmount();
    error ErrorEtherTransfer();
    error OfferNotEnded();

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

    /**
     * @notice Revert if not called by the NFT owner
     * @param nftAddress Address of the NFT collection
     * @param tokenId NFT Id
     */
    modifier onlyNFTOwner(address nftAddress, uint64 tokenId) {
        if (IERC721(nftAddress).ownerOf(tokenId) != msg.sender) {
            revert NoOwner();
        }
        _;
    }

    /**
     * @dev Function is invoked by the proxy contract when it is deployed.
     * It sets the contract owner and the NFT marketplace name
     * @param _marketplaceName Name of the NFT marketplace
     */
    function initialize(string memory _marketplaceName) external initializer() {
        contractOwner = msg.sender;
        marketplaceName = _marketplaceName;
    }

    /**
     * @notice Creates an offer to sell an NFT by specifying the NFT contract address,
     * the NFT token ID, the NFT price and the deadline date for the sale.
     * Emits a SellOfferCreated() event when the sale is created.
     * @param _nftAddress NFT collection contract address
     * @param _tokenId NFT Id
     * @param _price NFT price in Ether
     * @param _deadline Deadline in Wei until the sale is open
     */
    function createSellOffer(
        address _nftAddress, 
        uint64 _tokenId, 
        uint128 _price,
        uint128 _deadline) public onlyNFTOwner(_nftAddress, _tokenId) {
            
            if (_deadline <= block.timestamp) revert WrongDeadline();
            if (_price == 0) revert WrongPrice();

            sellOffers[sellOfferIdCounter].nftAddress = _nftAddress;
            sellOffers[sellOfferIdCounter].tokenId = _tokenId;
            sellOffers[sellOfferIdCounter].offerer = msg.sender;
            sellOffers[sellOfferIdCounter].price = _price;
            sellOffers[sellOfferIdCounter].deadline = _deadline;
            sellOfferIdCounter++;

            IERC721(_nftAddress).safeTransferFrom(msg.sender, address(this), _tokenId);

            emit SellOfferCreated(sellOfferIdCounter - 1);
    }

    /**
     * @notice Accepts the NFT sell offer. The Ether is transferred to the
     * creator of the offer and the NFT is transferred to the buyer.
     * Emits a SellOfferAccepted() event when the offer is accepted.
     * @param sellOfferId Identifier of the sell offer
     */
    function acceptSellOffer(uint256 sellOfferId) public payable {

        if (sellOffers[sellOfferId].isEnded) revert OfferEnded();
        if (block.timestamp > sellOffers[sellOfferId].deadline) revert OfferEnded();
        if (msg.value != sellOffers[sellOfferId].price) revert WrongEthAmount();

        sellOffers[sellOfferId].isEnded = true;

        IERC721(sellOffers[sellOfferId].nftAddress).safeTransferFrom(
            address(this), msg.sender, sellOffers[sellOfferId].tokenId);

        (bool ok, ) = (sellOffers[sellOfferId].offerer).call{value: msg.value}("");
        if (!ok) revert ErrorEtherTransfer();

        emit SellOfferAccepted(sellOfferId);
    }

    /**
     * @notice Cancels the NFT sell offer and returns the NFT to the owner.
     * Emits a SellOfferCancelled() event when the offer is cancelled
     * @param sellOfferId Identifier of the sell offer
     */
    function cancelSellOffer(uint256 sellOfferId) public {
        
        if (sellOffers[sellOfferId].isEnded) revert OfferEnded();
        if (sellOffers[sellOfferId].offerer != msg.sender) revert NoOwner();
        if (block.timestamp < sellOffers[sellOfferId].deadline) revert OfferNotEnded();

        sellOffers[sellOfferId].isEnded = true;

        IERC721(sellOffers[sellOfferId].nftAddress).safeTransferFrom(
            address(this), msg.sender, sellOffers[sellOfferId].tokenId);

        emit SellOfferCancelled(sellOfferId);
    }

    /**
     * @notice Creates an offer to buy a NFT by specifying the NFT contract address,
     * the NFT token ID and the deadline date for the sale. The Ether is sent to this
     * contract.
     * Emits a BuyOfferCreated() event.
     * @param _nftAddress NFT collection contract address
     * @param _tokenId NFT Id
     * @param _deadline Deadline in Wei until the sale is open
     */
    function createBuyOffer(
        address _nftAddress, 
        uint64 _tokenId, 
        uint128 _deadline) public payable {
            
            if (_deadline <= block.timestamp) revert WrongDeadline();
            if (msg.value == 0) revert WrongPrice();

            buyOffers[buyOfferIdCounter].nftAddress = _nftAddress;
            buyOffers[buyOfferIdCounter].tokenId = _tokenId;
            buyOffers[buyOfferIdCounter].offerer = msg.sender;
            buyOffers[buyOfferIdCounter].price = uint128(msg.value);
            buyOffers[buyOfferIdCounter].deadline = _deadline;
            buyOfferIdCounter++;

            emit BuyOfferCreated(buyOfferIdCounter - 1);
    }

    /**
     * @dev Function required so that this contract can receive NFT
     * @return 4 bytes that belong to onERC721Received(address,address,uint256,bytes) selector
     */
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /**
     * @notice Revert if not called by the contract owner
     * @dev Function required for access restriction to the upgrade mechanism
     * @param newImplementation Address of the new contract it is desired the proxy points
     */
    function _authorizeUpgrade(address newImplementation) internal override view {
        if (msg.sender != contractOwner) revert NoOwner();
    }


}

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

    event SellOfferCreated(uint256 indexed offer);
    event SellOfferAccepted(uint256 indexed offer);
    event SellOfferCancelled(uint256 indexed offer);
    event BuyOfferCreated(uint256 indexed offer);
    event BuyOfferAccepted(uint256 indexed offer);
    event BuyOfferCancelled(uint256 indexed offer);
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
     * @param nftAddress NFTs collection contract address
     * @param tokenId NFT Identifier
     */
    modifier onlyNFTOwner(address nftAddress, uint64 tokenId) {
        if (IERC721(nftAddress).ownerOf(tokenId) != msg.sender) {
            revert NoOwner();
        }
        _;
    }

    /**
     * @dev This function is invoked by the proxy contract when it is deployed.
     * It sets the contract owner and the NFT marketplace name
     * @param _marketplaceName Name of the NFT marketplace
     */
    function initialize(string memory _marketplaceName) external initializer() {
        contractOwner = msg.sender;
        marketplaceName = _marketplaceName;
    }

    /**
     * @notice Creates a sell offer for a NFT by specifying the NFT contract address,
     * the NFT token identifier, the NFT price and the deadline date for the sale.
     * Emits a SellOfferCreated() event
     * @param _nftAddress NFTs collection contract address
     * @param _tokenId NFT identifier
     * @param _price NFT price in Wei
     * @param _deadline Deadline in Wei until the sale is finished
     */
    function createSellOffer(
        address _nftAddress, 
        uint64 _tokenId, 
        uint128 _price,
        uint128 _deadline) public onlyNFTOwner(_nftAddress, _tokenId) {
            
            if (_deadline <= block.timestamp) revert WrongDeadline();
            if (_price == 0) revert WrongPrice();

            Offer storage offer = sellOffers[sellOfferIdCounter];
            offer.nftAddress = _nftAddress;
            offer.tokenId = _tokenId;
            offer.offerer = msg.sender;
            offer.price = _price;
            offer.deadline = _deadline;

            sellOfferIdCounter++;

            IERC721(_nftAddress).safeTransferFrom(msg.sender, address(this), _tokenId);

            emit SellOfferCreated(sellOfferIdCounter - 1);
    }

    /**
     * @notice Accepts the NFT sell offer. The Ether is transferred to the
     * creator of the offer and the NFT is transferred to the buyer.
     * Emits a SellOfferAccepted() event
     * @param sellOfferId Identifier of the sell offer
     */
    function acceptSellOffer(uint256 sellOfferId) public payable {

        if (sellOffers[sellOfferId].isEnded) revert OfferEnded();
        if (block.timestamp > sellOffers[sellOfferId].deadline) revert OfferEnded();
        if (msg.value != sellOffers[sellOfferId].price) revert WrongEthAmount();

        sellOffers[sellOfferId].isEnded = true;

        /// NFT transfer to the buyer
        IERC721(sellOffers[sellOfferId].nftAddress).safeTransferFrom(
            address(this), msg.sender, sellOffers[sellOfferId].tokenId);

        /// Ether transfer to the offer creator
        (bool ok, ) = (sellOffers[sellOfferId].offerer).call{value: msg.value}("");
        if (!ok) revert ErrorEtherTransfer();

        emit SellOfferAccepted(sellOfferId);
    }

    /**
     * @notice Cancels the NFT sell offer and returns the NFT to the owner.
     * Emits a SellOfferCancelled() event
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
     * the NFT identifier and the deadline date for the purchase. The Ether is sent to this
     * contract.
     * Emits a BuyOfferCreated() event
     * @param _nftAddress NFT collection contract address
     * @param _tokenId NFT identifier
     * @param _deadline Deadline in Wei until the offer is finished
     */
    function createBuyOffer(
        address _nftAddress, 
        uint64 _tokenId, 
        uint128 _deadline) public payable {
            
            if (_deadline <= block.timestamp) revert WrongDeadline();
            if (msg.value == 0) revert WrongPrice();

            Offer storage offer = buyOffers[buyOfferIdCounter];
            offer.nftAddress = _nftAddress;
            offer.tokenId = _tokenId;
            offer.offerer = msg.sender;
            offer.price = uint128(msg.value);
            offer.deadline = _deadline;

            buyOfferIdCounter++;

            emit BuyOfferCreated(buyOfferIdCounter - 1);
    }

/**
     * @notice Accepts the NFT buy offer. Firstly the user must approve this contract to move
     * his NFT. The Ether is transferred to the NFT owner and the NFT is transferred to the 
     * offer creator.
     * Emits a BuyOfferAccepted() event
     * @param buyOfferId Identifier of the buy offer
     */
    function acceptBuyOffer(uint256 buyOfferId) public {

        if (msg.sender != IERC721(buyOffers[buyOfferId].nftAddress).ownerOf(
            buyOffers[buyOfferId].tokenId)) revert NoOwner();

        if (buyOffers[buyOfferId].isEnded) revert OfferEnded();
        if (block.timestamp > buyOffers[buyOfferId].deadline) revert OfferEnded();

        buyOffers[buyOfferId].isEnded = true;

        /// NFT transfer to the buyer
        IERC721(buyOffers[buyOfferId].nftAddress).safeTransferFrom(
            msg.sender, buyOffers[buyOfferId].offerer, buyOffers[buyOfferId].tokenId);

        /// Ether transfer to NFT owner
        (bool ok, ) = (msg.sender).call{value: buyOffers[buyOfferId].price}("");
        if (!ok) revert ErrorEtherTransfer();

        emit BuyOfferAccepted(buyOfferId);
    }

    /**
     * @notice Cancels the NFT buy offer and returns the Ether to the offer creator.
     * Emits a BuyOfferCancelled() event
     * @param buyOfferId Identifier of the buy offer
     */
    function cancelBuyOffer(uint256 buyOfferId) public {

        if (buyOffers[buyOfferId].isEnded) revert OfferEnded();
        if (buyOffers[buyOfferId].offerer != msg.sender) revert NoOwner();
        if (block.timestamp < buyOffers[buyOfferId].deadline) revert OfferNotEnded();

        /// cancel the offer
        buyOffers[buyOfferId].isEnded = true;

        /// return the Ether to the offer creator
        (bool ok, ) = (msg.sender).call{value: buyOffers[buyOfferId].price}("");
        if (!ok) revert ErrorEtherTransfer();

        emit BuyOfferCancelled(buyOfferId);
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

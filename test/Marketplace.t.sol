// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../src/NFTMarketplace.sol";
import "../src/MyProxy.sol";

contract NFTMarketplaceTest is Test {
    
    event SellOfferCreated(uint256 offer);
    event SellOfferAccepted(uint256 offer);
    
    /// load to next string the url that is saved in the file ".env"
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    NFTMarketplace public market;
    MyProxy public proxy;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    /// Bored Ape Yacht Club NFT collection address deployed on Mainnet
    address baycNFT = 0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D;

    struct Offer {
        uint128 price;
        uint128 deadline;
        uint64 tokenId;
        address nftAddress;
        bool isEnded;
        address offerer;
    }

    function setUp() public {
        /// Mainnet fork is created and selected to be used from next line
        vm.createSelectFork(MAINNET_RPC_URL);
        /// Marketplace.sol deployment
        market = new NFTMarketplace();
        /// MyProxy.sol deployment
        proxy = new MyProxy(address(market), 
        abi.encodeWithSignature("initialize(string)", "NFT Market"));
    }

    function testInitialize() public {
        assertEq(proxy.contractOwner(), address(this));
        assertEq(proxy.marketplaceName(), "NFT Market");
    }

    function testGetImplementation() public {
        assertEq(proxy.getImplementation(), address(market));
    }

    function testAuthorizeUpgrades() public {
        /// alice tries to upgrade the implementation but she is not the owner
        vm.prank(alice);
        vm.expectRevert(bytes4(keccak256("NoOwner()")));
        (bool ok, ) = address(proxy).call(
            abi.encodeWithSignature("upgradeToAndCall(address,bytes)", address(market), ""));
        require (ok, "Upgrade has failed");
        /// NFTMarketplaceTest.sol (it is the contract owner) upgrades it
        (bool ok2, ) = address(proxy).call(
            abi.encodeWithSignature("upgradeToAndCall(address,bytes)", address(market), ""));
        require (ok2, "Upgrade has failed");

    }

    function testCreateSellOffer() public {
        /// ERROR CHECKING
        /// MarketplaceTest.sol tries to create a sell Offer for NFT Token
        /// Id 2150 from Bored Ape Yacht CLub NFT collection
        vm.expectRevert(bytes4(keccak256("NoOwner()")));
        market.createSellOffer(baycNFT, 2150, 24 ether, uint128(block.timestamp) + 1);

        /// The owner of the NFT Token Id 2150 sends his NFT to alice
        address ownerToken2150 = IERC721(baycNFT).ownerOf(2150);
        vm.prank(ownerToken2150);
        IERC721(baycNFT).safeTransferFrom(ownerToken2150, alice, 2150);
        assertEq(IERC721(baycNFT).ownerOf(2150), alice);
        
        /// alice creates a sell Offer with wrong deadline
        vm.startPrank(alice);
        vm.expectRevert(bytes4(keccak256("WrongDeadline()")));
        market.createSellOffer(baycNFT, 2150, 20 ether, uint128(block.timestamp));
        
        /// alice creates a sell Offer with wrong price
        vm.expectRevert(bytes4(keccak256("WrongPrice()")));
        market.createSellOffer(baycNFT, 2150, 0, uint128(block.timestamp) + 1);

        /// SELL OFFER CREATION CHECKING
        /// alice creates a sell offer (she first approves marketpalce.sol
        /// to move her NFT)
        IERC721(baycNFT).approve(address(market), 2150);
        vm.expectEmit(true, false, false, false);
        emit SellOfferCreated(0);
        market.createSellOffer(baycNFT, 2150, 20 ether, uint128(block.timestamp) + 1000000);
        
        (uint128 price,
        uint128 deadline,
        uint64 tokenId,
        address nftAddress,
        bool isEnded,
        address offerer) = market.sellOffers(0);

        assertEq(price, 20 ether); 
        assertEq(deadline, block.timestamp + 1000000); 
        assertEq(tokenId, 2150); 
        assertEq(nftAddress, baycNFT); 
        assertEq(isEnded, false);
        assertEq(offerer, alice); 

        assertEq(market.sellOfferIdCounter(), 1);

        /// NFT TRANSFER CHECKING
        assertEq(IERC721(baycNFT).ownerOf(2150), address(market));
    }

    function testOnERC721Received() public {
        testCreateSellOffer();
        assertEq(IERC721(baycNFT).balanceOf(address(alice)), 0);
        assertEq(IERC721(baycNFT).balanceOf(address(market)), 1);
    }

    function testAcceptSellOffer() public {
        /// alice creates the sell offer with id 0
        testCreateSellOffer();

        /// ERROR CHECKING
        /// bob accepts the sell offer with less Ether
        vm.deal(bob, 50 ether);
        vm.startPrank(bob);
        vm.expectRevert(bytes4(keccak256("WrongEthAmount()")));
        market.acceptSellOffer{value: 18 ether}(0);
        /// bob accepts it out of deadline
        vm.warp(uint128(block.timestamp) + 1000000 + 1);
        vm.expectRevert(bytes4(keccak256("OfferEnded()")));
        market.acceptSellOffer{value: 20 ether}(0);

        /// bob accepts the offer
        vm.warp(uint128(block.timestamp) - 1000000 - 1);
        vm.expectEmit(true, false, false, false);
        emit SellOfferAccepted(0);
        market.acceptSellOffer{value: 20 ether}(0);
        
        ( , , , , bool isEnded, ) = market.sellOffers(0);
        assertEq(isEnded, true);
        assertEq(IERC721(baycNFT).ownerOf(2150), bob);
        assertEq(alice.balance, 20 ether);
        vm.stopPrank();

        /// Markus tries to accept the same offer
        address markus = makeAddr("markus");
        vm.deal(markus, 50 ether);
        vm.prank(markus);
        vm.expectRevert(bytes4(keccak256("OfferEnded()")));
        market.acceptSellOffer{value: 20 ether}(0);
    }

}

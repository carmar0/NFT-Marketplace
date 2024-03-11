// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../src/NFTMarketplace.sol";
import "../src/MyProxy.sol";

contract NFTMarketplaceTest is Test {
    
    event SellOfferCreated(uint256 offer);
    event SellOfferAccepted(uint256 offer);
    event SellOfferCancelled(uint256 offer);
    
    /// load to next string the url that is saved in the file ".env"
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    NFTMarketplace public market;
    MyProxy public proxy;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public karl = makeAddr("karl");
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
        /////////////////////////// ERROR CHECKING ///////////////////////////
        /// MarketplaceTest.sol tries to create a sell Offer for NFT Token
        /// Id 2150 from Bored Ape Yacht CLub NFT collection
        vm.expectRevert(bytes4(keccak256("NoOwner()")));
        (bool ok, ) = address(proxy).call(abi.encodeWithSignature(
            "createSellOffer(address,uint64,uint128,uint128)",
             baycNFT, 2150, 24 ether, uint128(block.timestamp) + 1, ""));
        require (ok, "Call has failed"); 

        /// The owner of the NFT Token Id 2150 sends his NFT to alice
        address ownerToken2150 = IERC721(baycNFT).ownerOf(2150);
        vm.prank(ownerToken2150);
        IERC721(baycNFT).safeTransferFrom(ownerToken2150, alice, 2150);
        assertEq(IERC721(baycNFT).ownerOf(2150), alice);
        
        // /// alice creates a sell Offer with wrong deadline
        vm.startPrank(alice);
        vm.expectRevert(bytes4(keccak256("WrongDeadline()")));
        (bool ok2, ) = address(proxy).call(abi.encodeWithSignature(
            "createSellOffer(address,uint64,uint128,uint128)",
             baycNFT, 2150, 20 ether, uint128(block.timestamp), ""));
        require (ok2, "Call has failed");      
        
        /// alice creates a sell Offer with wrong price
        vm.expectRevert(bytes4(keccak256("WrongPrice()")));
        (bool ok3, ) = address(proxy).call(abi.encodeWithSignature(
            "createSellOffer(address,uint64,uint128,uint128)",
             baycNFT, 2150, 0, uint128(block.timestamp) + 1, ""));
        require (ok3, "Call has failed"); 

        /////////////////////////// SELL OFFER CREATION CHECKING ///////////////////////////
        /// alice creates a sell offer (she first approves the proxy to move her NFT)
        IERC721(baycNFT).approve(address(proxy), 2150);
        vm.expectEmit(true, false, false, false);
        emit SellOfferCreated(0);
        (bool ok4, ) = address(proxy).call(abi.encodeWithSignature(
            "createSellOffer(address,uint64,uint128,uint128)",
             baycNFT, 2150, 20 ether, uint128(block.timestamp) + 1000000, ""));
        require (ok4, "Call has failed"); 
        
        (uint128 price,
        uint128 deadline,
        uint64 tokenId,
        address nftAddress,
        bool isEnded,
        address offerer) = proxy.sellOffers(0);

        assertEq(price, 20 ether); 
        assertEq(deadline, block.timestamp + 1000000); 
        assertEq(tokenId, 2150); 
        assertEq(nftAddress, baycNFT); 
        assertEq(isEnded, false);
        assertEq(offerer, alice); 

        assertEq(proxy.sellOfferIdCounter(), 1);

        /////////////////////////// NFT TRANSFER CHECKING ///////////////////////////
        assertEq(IERC721(baycNFT).ownerOf(2150), address(proxy));
        vm.stopPrank();
    }

    function testOnERC721Received() public {
        testCreateSellOffer();
        assertEq(IERC721(baycNFT).balanceOf(address(alice)), 0);
        assertEq(IERC721(baycNFT).balanceOf(address(proxy)), 1);
    }

    function testAcceptSellOffer() public {
        /// alice creates the sell offer with id 0
        testCreateSellOffer();

        /////////////////////////// ERROR CHECKING ///////////////////////////
        /// bob accepts the sell offer with less Ether
        vm.deal(bob, 50 ether);
        vm.startPrank(bob);
        vm.expectRevert(bytes4(keccak256("WrongEthAmount()")));
        (bool ok, ) = address(proxy).call{value: 18 ether}(abi.encodeWithSignature(
            "acceptSellOffer(uint256)", 0));
        require (ok, "Call has failed"); 

        /// bob accepts it out of deadline
        vm.warp(uint128(block.timestamp) + 1000000 + 1);
        vm.expectRevert(bytes4(keccak256("OfferEnded()")));
        (bool ok2, ) = address(proxy).call{value: 20 ether}(abi.encodeWithSignature(
            "acceptSellOffer(uint256)", 0));
        require (ok2, "Call has failed"); 

        /////////////////////////// SELL OFFER ACCEPT ///////////////////////////
        /// bob accepts the offer
        vm.warp(uint128(block.timestamp) - 1000000 - 1);
        vm.expectEmit(true, false, false, false);
        emit SellOfferAccepted(0);
        (bool ok3, ) = address(proxy).call{value: 20 ether}(abi.encodeWithSignature(
            "acceptSellOffer(uint256)", 0));
        require (ok3, "Call has failed"); 
        
        ( , , , , bool isEnded, ) = proxy.sellOffers(0);
        assertEq(isEnded, true);
        assertEq(IERC721(baycNFT).ownerOf(2150), bob);
        assertEq(alice.balance, 20 ether);
        vm.stopPrank();

        /////////////////////////// ERROR CHECKING ///////////////////////////
        /// karl tries to accept the same offer
        vm.deal(karl, 50 ether);
        vm.prank(karl);
        vm.expectRevert(bytes4(keccak256("OfferEnded()")));
        (bool ok4, ) = address(proxy).call{value: 20 ether}(abi.encodeWithSignature(
            "acceptSellOffer(uint256)", 0));
        require (ok4, "Call has failed"); 
    }

    function testCancelSellOffer() public {
        /// alice creates the sell offer with id 0
        testCreateSellOffer();

        /////////////////////////// ERROR CHECKING ///////////////////////////
        /// bob tries to cancel it
        vm.prank(bob);
        vm.expectRevert(bytes4(keccak256("NoOwner()")));
        (bool ok, ) = address(proxy).call(abi.encodeWithSignature(
            "cancelSellOffer(uint256)", 0));
        require (ok, "Call has failed");
        /// alice tries to cancel it when it is not ended
        vm.startPrank(alice);
        vm.expectRevert(bytes4(keccak256("OfferNotEnded()")));
        (bool ok2, ) = address(proxy).call(abi.encodeWithSignature(
            "cancelSellOffer(uint256)", 0));
        require (ok2, "Call has failed");  

        /////////////////////////// CANCEL CHECKING ///////////////////////////
        /// alice cancels the sell offer
        vm.warp(uint128(block.timestamp) + 1000000 + 1);
        vm.expectEmit(true, false, false, false);
        emit SellOfferCancelled(0);
        (bool ok3, ) = address(proxy).call(abi.encodeWithSignature(
            "cancelSellOffer(uint256)", 0));
        require (ok3, "Call has failed");  

        ( , , , , bool isEnded, ) = proxy.sellOffers(0);
        assertEq(isEnded, true);
        assertEq(IERC721(baycNFT).ownerOf(2150), alice);

        /////////////////////////// ERROR CHECKING ///////////////////////////
        /// alice tries to cancel it again
        vm.expectRevert(bytes4(keccak256("OfferEnded()")));
        (bool ok4, ) = address(proxy).call(abi.encodeWithSignature(
            "cancelSellOffer(uint256)", 0));
        require (ok4, "Call has failed");  
    }
}

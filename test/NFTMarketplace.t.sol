// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../src/NFTMarketplace.sol";
import "../src/MyProxy.sol";

contract NFTMarketplaceTest is Test {
    
    event SellOfferCreated(uint256 indexed offer);
    event SellOfferAccepted(uint256 indexed offer);
    event SellOfferCancelled(uint256 indexed offer);
    event BuyOfferCreated(uint256 indexed offer);
    event BuyOfferAccepted(uint256 indexed offer);
    event BuyOfferCancelled(uint256 indexed offer);
    
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
        abi.encodeWithSignature("initialize(string)", "NFT Marketplace"));

        (bool ok, bytes memory answer) = address(proxy).call(abi.encodeWithSignature(
            "contractOwner()"));
        require (ok, "Call failed");
        address contractOwner =  abi.decode(answer, (address));
        assertEq(contractOwner, address(this));

        (bool ok2, bytes memory answer2) = address(proxy).call(abi.encodeWithSignature(
            "marketplaceName()"));
        require (ok2, "Call failed");
        string memory marketplaceName =  abi.decode(answer2, (string));
        assertEq(marketplaceName, "NFT Marketplace");

        /// The owner of the NFT Token Id 2150 sends his NFT to alice
        address ownerToken2150 = IERC721(baycNFT).ownerOf(2150);
        vm.prank(ownerToken2150);
        IERC721(baycNFT).safeTransferFrom(ownerToken2150, alice, 2150);
        assertEq(IERC721(baycNFT).ownerOf(2150), alice);
    }

    function testInitialize() public {
        /// NFTMarketplaceTest.sol tries to initialize NFTMarketplace.sol again
        vm.expectRevert();
        (bool ok, ) = address(proxy).call(
            abi.encodeWithSignature("initialize(string)", "NFT Market"));
        require (ok, "Call failed");
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
        require (ok, "Upgrade failed");
        /// NFTMarketplaceTest.sol (it is the contract owner) upgrades it
        (bool ok2, ) = address(proxy).call(
            abi.encodeWithSignature("upgradeToAndCall(address,bytes)", address(market), ""));
        require (ok2, "Upgrade failed");

    }

    function testCreateSellOffer() public {
        /////////////////////////// ERROR CHECKING ///////////////////////////
        /// MarketplaceTest.sol tries to create a sell Offer for NFT Token
        /// Id 2150 from Bored Ape Yacht CLub NFT collection
        vm.expectRevert(bytes4(keccak256("NoOwner()")));
        (bool ok, ) = address(proxy).call(abi.encodeWithSignature(
            "createSellOffer(address,uint64,uint128,uint128)",
             baycNFT, 2150, 24 ether, uint128(block.timestamp) + 1));
        require (ok, "Call failed"); 
        
        // /// alice creates a sell Offer with wrong deadline
        vm.startPrank(alice);
        vm.expectRevert(bytes4(keccak256("WrongDeadline()")));
        (bool ok2, ) = address(proxy).call(abi.encodeWithSignature(
            "createSellOffer(address,uint64,uint128,uint128)",
             baycNFT, 2150, 20 ether, uint128(block.timestamp)));
        require (ok2, "Call failed");      
        
        /// alice creates a sell Offer with wrong price
        vm.expectRevert(bytes4(keccak256("WrongPrice()")));
        (bool ok3, ) = address(proxy).call(abi.encodeWithSignature(
            "createSellOffer(address,uint64,uint128,uint128)",
             baycNFT, 2150, 0, uint128(block.timestamp) + 1));
        require (ok3, "Call failed"); 

        /////////////////////////// SELL OFFER CREATION CHECKING ///////////////////////////
        /// alice creates a sell offer (she first approves the proxy to move her NFT)
        IERC721(baycNFT).approve(address(proxy), 2150);
        vm.expectEmit(true, false, false, false);
        emit SellOfferCreated(0);

        (bool ok4, ) = address(proxy).call(abi.encodeWithSignature(
            "createSellOffer(address,uint64,uint128,uint128)",
             baycNFT, 2150, 20 ether, uint128(block.timestamp) + 1000000));
        require (ok4, "Call failed");

        (bool ok5, bytes memory answer) = address(proxy).call(abi.encodeWithSignature(
            "sellOffers(uint256)", 0));
        require (ok5, "Call failed");  
        
        Offer memory offer =  abi.decode(answer, (Offer));

        assertEq(offer.price, 20 ether); 
        assertEq(offer.deadline, block.timestamp + 1000000); 
        assertEq(offer.tokenId, 2150); 
        assertEq(offer.nftAddress, baycNFT); 
        assertEq(offer.isEnded, false);
        assertEq(offer.offerer, alice); 

        (bool ok6, bytes memory answer2) = address(proxy).call(abi.encodeWithSignature(
            "sellOfferIdCounter()"));
        require (ok6, "Call failed"); 

        uint256 offerIdCounter =  abi.decode(answer2, (uint256)); 
        assertEq(offerIdCounter, 1);

        // /////////////////////////// NFT TRANSFER CHECKING ///////////////////////////
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
        require (ok, "Call failed"); 

        /// bob accepts it out of deadline
        vm.warp(uint128(block.timestamp) + 1000000 + 1);
        vm.expectRevert(bytes4(keccak256("OfferEnded()")));
        (bool ok2, ) = address(proxy).call{value: 20 ether}(abi.encodeWithSignature(
            "acceptSellOffer(uint256)", 0));
        require (ok2, "Call failed"); 

        /////////////////////////// SELL OFFER ACCEPT ///////////////////////////
        /// bob accepts the offer
        vm.warp(uint128(block.timestamp) - 1000000 - 1);
        vm.expectEmit(true, false, false, false);
        emit SellOfferAccepted(0);
        (bool ok3, ) = address(proxy).call{value: 20 ether}(abi.encodeWithSignature(
            "acceptSellOffer(uint256)", 0));
        require (ok3, "Call failed");

        (bool ok4, bytes memory answer) = address(proxy).call(abi.encodeWithSignature(
            "sellOffers(uint256)", 0));
        require (ok4, "Call failed");  
        Offer memory offer =  abi.decode(answer, (Offer));
        assertEq(offer.isEnded, true);
        assertEq(IERC721(baycNFT).ownerOf(2150), bob);
        assertEq(alice.balance, 20 ether);
        vm.stopPrank();

        /////////////////////////// ERROR CHECKING ///////////////////////////
        /// karl tries to accept the same offer
        vm.deal(karl, 50 ether);
        vm.prank(karl);
        vm.expectRevert(bytes4(keccak256("OfferEnded()")));
        (bool ok5, ) = address(proxy).call{value: 20 ether}(abi.encodeWithSignature(
            "acceptSellOffer(uint256)", 0));
        require (ok5, "Call failed"); 
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
        require (ok, "Call failed");

        /// alice tries to cancel it when it is not ended
        vm.startPrank(alice);
        vm.expectRevert(bytes4(keccak256("OfferNotEnded()")));
        (bool ok2, ) = address(proxy).call(abi.encodeWithSignature(
            "cancelSellOffer(uint256)", 0));
        require (ok2, "Call failed");  

        /////////////////////////// CANCEL CHECKING ///////////////////////////
        /// alice cancels the sell offer
        vm.warp(uint128(block.timestamp) + 1000000 + 1);
        vm.expectEmit(true, false, false, false);
        emit SellOfferCancelled(0);
        (bool ok3, ) = address(proxy).call(abi.encodeWithSignature(
            "cancelSellOffer(uint256)", 0));
        require (ok3, "Call failed");

        (bool ok4, bytes memory answer) = address(proxy).call(abi.encodeWithSignature(
            "sellOffers(uint256)", 0));
        require (ok4, "Call failed");  
        Offer memory offer =  abi.decode(answer, (Offer));
        assertEq(offer.isEnded, true);  
        assertEq(IERC721(baycNFT).ownerOf(2150), alice);

        /////////////////////////// ERROR CHECKING ///////////////////////////
        /// alice tries to cancel it again
        vm.expectRevert(bytes4(keccak256("OfferEnded()")));
        (bool ok5, ) = address(proxy).call(abi.encodeWithSignature(
            "cancelSellOffer(uint256)", 0));
        require (ok5, "Call failed");
        vm.stopPrank(); 
    }

    function testCreateBuyOffer() public {
        /////////////////////////// ERROR CHECKING ///////////////////////////
        /// bob creates a buy offer with wrong deadline
        vm.deal(bob, 50 ether);
        vm.startPrank(bob);
        vm.expectRevert(bytes4(keccak256("WrongDeadline()")));
        (bool ok, ) = address(proxy).call{value: 10 ether}(
            abi.encodeWithSignature("createBuyOffer(address,uint64,uint128)",
            baycNFT, 2150, uint128(block.timestamp)));
        require (ok, "Call failed");

        /// bob creates a buy offer with wrong price
        vm.expectRevert(bytes4(keccak256("WrongPrice()")));
        (bool ok2, ) = address(proxy).call{value: 0}(
            abi.encodeWithSignature("createBuyOffer(address,uint64,uint128)",
            baycNFT, 2150, uint128(block.timestamp) + 10000));
        require (ok2, "Call failed");    

        /////////////////////////// BUY OFFER CHECKING ///////////////////////////
        vm.expectEmit(true, false, false, false);
        emit BuyOfferCreated(0);
        (bool ok3, ) = address(proxy).call{value: 20 ether}(
            abi.encodeWithSignature("createBuyOffer(address,uint64,uint128)",
            baycNFT, 2150, uint128(block.timestamp) + 10000));
        require (ok3, "Call failed");

        (bool ok4, bytes memory answer) = address(proxy).call(abi.encodeWithSignature(
            "buyOffers(uint256)", 0));
        require (ok4, "Call failed");  
        Offer memory offer =  abi.decode(answer, (Offer));
        assertEq(offer.price, 20 ether); 
        assertEq(offer.deadline, block.timestamp + 10000); 
        assertEq(offer.tokenId, 2150); 
        assertEq(offer.nftAddress, baycNFT); 
        assertEq(offer.isEnded, false);
        assertEq(offer.offerer, bob); 

        (bool ok5, bytes memory answer2) = address(proxy).call(abi.encodeWithSignature(
            "buyOfferIdCounter()"));
        require (ok5, "Call failed");
        uint256 offerIdCounter =  abi.decode(answer2, (uint256)); 
        assertEq(offerIdCounter, 1);
        assertEq(bob.balance, 30 ether);
        assertEq(address(proxy).balance, 20 ether);

        /// bob creates another Offer
        (bool ok6, ) = address(proxy).call{value: 15 ether}(
            abi.encodeWithSignature("createBuyOffer(address,uint64,uint128)",
            baycNFT, 2000, uint128(block.timestamp) + 10000));
        require (ok6, "Call failed");

        assertEq(bob.balance, 15 ether);
        assertEq(address(proxy).balance, 35 ether);

        (bool ok7, bytes memory answer3) = address(proxy).call(abi.encodeWithSignature(
            "buyOfferIdCounter()"));
        require (ok7, "Call failed");
        uint256 offerIdCounter2 =  abi.decode(answer3, (uint256)); 
        assertEq(offerIdCounter2, 2); 
        vm.stopPrank();
    }

    function testAcceptBuyOffer() public {
        /// bob creates a buy offer for token 2150 from Bored Ape Yacht Club
        /// for 20 ether. The NFT belongs to alice
        testCreateBuyOffer();

        /////////////////////////// ERROR CHECKING ///////////////////////////
        /// karl tries to accept it
        vm.prank(karl);
        vm.expectRevert(bytes4(keccak256("NoOwner()")));
        (bool ok, ) = address(proxy).call(abi.encodeWithSignature(
            "acceptBuyOffer(uint256)", 0));
        require (ok, "Call failed");

        /// alice tries to accept it with wrong deadline
        vm.warp(uint128(block.timestamp) + 100000);
        vm.startPrank(alice);
        vm.expectRevert(bytes4(keccak256("OfferEnded()")));
        (bool ok2, ) = address(proxy).call(abi.encodeWithSignature(
            "acceptBuyOffer(uint256)", 0));
        require (ok2, "Call failed");  
        vm.warp(uint128(block.timestamp) - 100000);

        /////////////////////////// ACCEPT BUY OFFER CHECKING ///////////////////////////
        /// Alice first approves the proxy to move her NFT
        IERC721(baycNFT).approve(address(proxy), 2150);
        vm.expectEmit(true, false, false, false);
        emit BuyOfferAccepted(0);
        (bool ok3, ) = address(proxy).call(abi.encodeWithSignature(
            "acceptBuyOffer(uint256)", 0));
        require (ok3, "Call failed");

        (bool ok4, bytes memory answer) = address(proxy).call(abi.encodeWithSignature(
            "buyOffers(uint256)", 0));
        require (ok4, "Call failed");  
        Offer memory offer =  abi.decode(answer, (Offer));
        assertEq(offer.isEnded, true);
        assertEq(IERC721(baycNFT).ownerOf(2150), bob);
        assertEq(alice.balance, 20 ether);
        vm.stopPrank();

        /////////////////////////// ERROR CHECKING ///////////////////////////
        /// bob tries to accept it again
        vm.prank(bob);
        vm.expectRevert(bytes4(keccak256("OfferEnded()")));
        (bool ok5, ) = address(proxy).call(abi.encodeWithSignature(
            "acceptBuyOffer(uint256)", 0));
        require (ok5, "Call failed");  
    }

    function testCancelBuyOffer() public {
        /// bob cretaes buy offers with id=0 (20 ether) and id=1 (15 ether)
        testCreateBuyOffer();
        /// Now bob has 15 ether balance and the proxy 35 ether

        /////////////////////////// ERROR CHECKING ///////////////////////////
        /// alice tries to cancel buy offer with id=0
        vm.prank(alice);
        vm.expectRevert(bytes4(keccak256("NoOwner()")));
        (bool ok, ) = address(proxy).call(abi.encodeWithSignature(
            "cancelBuyOffer(uint256)", 0));
        require (ok, "Call failed");

        /// bob tries to cancel it when it is not ended
        vm.startPrank(bob);
        vm.expectRevert(bytes4(keccak256("OfferNotEnded()")));
        (bool ok2, ) = address(proxy).call(abi.encodeWithSignature(
            "cancelBuyOffer(uint256)", 0));
        require (ok2, "Call failed");  

        /////////////////////////// CANCELLATION CHECKING ///////////////////////////
        /// bob cancels the buy offer with id=0
        vm.warp(uint128(block.timestamp) + 1000000000);
        vm.expectEmit(true, false, false, false);
        emit BuyOfferCancelled(0);
        (bool ok3, ) = address(proxy).call(abi.encodeWithSignature(
            "cancelBuyOffer(uint256)", 0));
        require (ok3, "Call failed");

        (bool ok4, bytes memory answer) = address(proxy).call(abi.encodeWithSignature(
            "buyOffers(uint256)", 0));
        require (ok4, "Call failed");     
        Offer memory offer =  abi.decode(answer, (Offer));
        assertEq(offer.isEnded, true);
        assertEq(bob.balance, 35 ether);
        assertEq(address(proxy).balance, 15 ether);

        /// bob cancels the buy offer with id=1
        vm.expectEmit(true, false, false, false);
        emit BuyOfferCancelled(1);
        (bool ok5, ) = address(proxy).call(abi.encodeWithSignature(
            "cancelBuyOffer(uint256)", 1));
        require (ok5, "Call failed");
        
        (bool ok6, bytes memory answer2) = address(proxy).call(abi.encodeWithSignature(
            "buyOffers(uint256)", 0));
        require (ok6, "Call failed");
        Offer memory offer2 =  abi.decode(answer2, (Offer));
        assertEq(offer2.isEnded, true);
        assertEq(bob.balance, 50 ether);
        assertEq(address(proxy).balance, 0);

        /////////////////////////// ERROR CHECKING ///////////////////////////
        /// bob tries to cancel again the buy offer with id=0
        vm.expectRevert(bytes4(keccak256("OfferEnded()")));
        (bool ok7, ) = address(proxy).call(abi.encodeWithSignature(
            "cancelBuyOffer(uint256)", 0));
        require (ok7, "Call failed");  
    }
}
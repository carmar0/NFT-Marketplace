# NFT Marketplace

This is a smart contract to allow users to place orders to buy and sell NFTs.

NFT owners/sellers can:
  - Create an offer for the sale of an NFT by specifying the NFT contract address,
    the NFT token Id, the NFT price in Ether and the deadline date for the sale.
  - Cancel a sale offer.
  - Accept a NFT buy offer. The Ether is transferred to the NFT owner and the NFT
    is transferred to the offer creator.
    
Users/buyers can:
  - Accept NFT sale offers. The Ether is transferred to the creator of the offer
    and the NFT is transferred to the buyer.
  - Create an offer to buy a NFT by specifying the NFT contract address, the NFT
    token Id and the deadline date for the purchase.
  - Cancel buy offers.
  
![](https://github.com/carmar0/NFT-Marketplace/blob/main/NFTMarketplace.JPG)
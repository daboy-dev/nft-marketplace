// SPDX-License-Identifier: MIT

pragma solidity ^0.8.34;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract NFTMarketplace is Ownable, ReentrancyGuard {
    struct Listing {
        address nftAddress;
        address seller;
        uint256 tokenId;
        uint256 price;
    }

    mapping(address => mapping(uint256 => Listing)) listings;

    event NFTListed(address indexed seller, address indexed nftAddress, uint256 indexed tokenId, uint256 price);
    event NFTUnlisted(address indexed seller, address indexed nftAddress, uint256 indexed tokenId);
    event NFTSold(address indexed buyer, address indexed seller, address indexed nftAddress, uint256 tokenId, uint256 price);

    error NFTMarketplace__PriceZero();
    error NFTMarketplace__NotTokenOwner();
    error NFTMarketplace__OnlySellerCanCancel();
    error NFTMarketplace__ListingNotExists();
    error NFTMarketplace__PriceNotValid();
    error NFTMarketplace__TransferFailed();

    constructor() Ownable(msg.sender) {}

    function listNFT(address nftAddress_, uint256 tokenId_, uint256 price_) external {
        if (price_ == 0) revert NFTMarketplace__PriceZero();
        address owner = IERC721(nftAddress_).ownerOf(tokenId_);
        if (owner != msg.sender) revert NFTMarketplace__NotTokenOwner();

        listings[nftAddress_][tokenId_] = Listing({
            nftAddress: nftAddress_,
            seller: msg.sender,
            tokenId: tokenId_,
            price: price_
        });

        emit NFTListed(msg.sender, nftAddress_, tokenId_, price_);
    }

    function unlistNFT(address nftAddress_, uint256 tokenId_) external {
        if (listings[nftAddress_][tokenId_].seller != msg.sender) revert NFTMarketplace__OnlySellerCanCancel();

        delete listings[nftAddress_][tokenId_];

        emit NFTUnlisted(msg.sender, nftAddress_, tokenId_);
    }

    function buyNFT(address nftAddress_, uint256 tokenId_) external payable nonReentrant {
        Listing memory listing_ = listings[nftAddress_][tokenId_];

        if (listing_.price == 0) revert NFTMarketplace__ListingNotExists();
        if (listing_.price != msg.value) revert NFTMarketplace__PriceNotValid();

        delete listings[nftAddress_][tokenId_];

        IERC721(nftAddress_).safeTransferFrom(listing_.seller, msg.sender, tokenId_);

        (bool success,) = listing_.seller.call{value: listing_.price}("");
        if (!success) revert NFTMarketplace__TransferFailed();
    }
}
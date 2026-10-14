// SPDX-License-Identifier: MIT

pragma solidity ^0.8.34;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title NFTMarketplace
/// @notice Marketplace where users can list, unlist and buy ERC721 tokens for ETH.
contract NFTMarketplace is Ownable, ReentrancyGuard {
    /// @notice Sale information of a listed NFT.
    /// @param nftAddress Address of the ERC721 contract.
    /// @param seller Address that listed the NFT and receives the payment.
    /// @param tokenId ID of the token within the ERC721 contract.
    /// @param price Sale price in wei.
    struct Listing {
        address nftAddress;
        address seller;
        uint256 tokenId;
        uint256 price;
    }

    /// @dev NFT contract address => token ID => listing.
    mapping(address => mapping(uint256 => Listing)) listings;

    /// @notice Emitted when an NFT is listed for sale.
    event NFTListed(address indexed seller, address indexed nftAddress, uint256 indexed tokenId, uint256 price);
    /// @notice Emitted when a listing is cancelled by its seller.
    event NFTUnlisted(address indexed seller, address indexed nftAddress, uint256 indexed tokenId);
    /// @notice Emitted when a listed NFT is bought.
    event NFTSold(address indexed buyer, address indexed seller, address indexed nftAddress, uint256 tokenId, uint256 price);

    /// @dev The listing price is zero.
    error NFTMarketplace__PriceZero();
    /// @dev The caller does not own the token.
    error NFTMarketplace__NotTokenOwner();
    /// @dev The caller is not the seller of the listing.
    error NFTMarketplace__OnlySellerCanCancel();
    /// @dev There is no active listing for the given NFT.
    error NFTMarketplace__ListingNotExists();
    /// @dev The ETH sent does not match the listing price.
    error NFTMarketplace__PriceNotValid();
    /// @dev The ETH transfer to the seller failed.
    error NFTMarketplace__TransferFailed();

    constructor() Ownable(msg.sender) {}

    /// @notice Lists an NFT for sale at a fixed price.
    /// @dev Overwrites any previous listing of the same token. The marketplace must be approved
    /// by the caller for the purchase to succeed; approval is not checked here.
    /// @param nftAddress_ Address of the ERC721 contract.
    /// @param tokenId_ ID of the token to list.
    /// @param price_ Sale price in wei. Must be greater than zero.
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

    /// @notice Cancels an active listing.
    /// @dev Reverts if the caller is not the seller (this also covers non-existent listings).
    /// @param nftAddress_ Address of the ERC721 contract.
    /// @param tokenId_ ID of the listed token.
    function unlistNFT(address nftAddress_, uint256 tokenId_) external {
        if (listings[nftAddress_][tokenId_].seller != msg.sender) revert NFTMarketplace__OnlySellerCanCancel();

        delete listings[nftAddress_][tokenId_];

        emit NFTUnlisted(msg.sender, nftAddress_, tokenId_);
    }

    /// @notice Buys a listed NFT by sending the exact listing price in ETH.
    /// @dev Follows checks-effects-interactions: the listing is deleted before the NFT and ETH
    /// are transferred. Protected against reentrancy.
    /// @param nftAddress_ Address of the ERC721 contract.
    /// @param tokenId_ ID of the token to buy.
    function buyNFT(address nftAddress_, uint256 tokenId_) external payable nonReentrant {
        Listing memory listing_ = listings[nftAddress_][tokenId_];

        if (listing_.price == 0) revert NFTMarketplace__ListingNotExists();
        if (listing_.price != msg.value) revert NFTMarketplace__PriceNotValid();

        delete listings[nftAddress_][tokenId_];

        IERC721(nftAddress_).safeTransferFrom(listing_.seller, msg.sender, tokenId_);

        (bool success,) = listing_.seller.call{value: listing_.price}("");
        if (!success) revert NFTMarketplace__TransferFailed();

        emit NFTSold(msg.sender, listing_.seller, nftAddress_, tokenId_, listing_.price);
    }
}

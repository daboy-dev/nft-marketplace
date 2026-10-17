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
    mapping(address => mapping(uint256 => Listing)) public listings;

    /// @notice Maximum fee the owner can set, in basis points (500 = 5%).
    uint256 public constant MAX_FEE_BPS = 500;
    uint256 private constant BPS_DENOMINATOR = 10_000;

    /// @notice Marketplace fee in basis points (50 = 0.5%), charged to the seller on each sale.
    uint256 public feeBps = 50;

    /// @notice Fees collected from sales and not yet withdrawn by the owner, in wei.
    uint256 public accumulatedFees;

    /// @notice Emitted when an NFT is listed for sale.
    event NFTListed(address indexed seller, address indexed nftAddress, uint256 indexed tokenId, uint256 price);
    /// @notice Emitted when a listing is cancelled by its seller.
    event NFTUnlisted(address indexed seller, address indexed nftAddress, uint256 indexed tokenId);
    /// @notice Emitted when a listed NFT is bought.
    event NFTSold(
        address indexed buyer,
        address indexed seller,
        address indexed nftAddress,
        uint256 tokenId,
        uint256 price,
        uint256 fee
    );
    /// @notice Emitted when the owner updates the marketplace fee.
    event FeeUpdated(uint256 oldFeeBps, uint256 newFeeBps);
    /// @notice Emitted when the owner withdraws the accumulated fees.
    event FeesWithdrawn(address indexed to, uint256 amount);

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
    /// @dev The requested fee exceeds MAX_FEE_BPS.
    error NFTMarketplace__FeeTooHigh();
    /// @dev There are no accumulated fees to withdraw.
    error NFTMarketplace__NoFeesToWithdraw();

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

        listings[nftAddress_][tokenId_] =
            Listing({nftAddress: nftAddress_, seller: msg.sender, tokenId: tokenId_, price: price_});

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
    /// @dev Follows checks-effects-interactions: the listing is deleted and the fee accounted for
    /// before the NFT and ETH are transferred. The fee (feeBps) is deducted from the seller's
    /// proceeds, so the buyer always pays exactly the listing price. Protected against reentrancy.
    /// @param nftAddress_ Address of the ERC721 contract.
    /// @param tokenId_ ID of the token to buy.
    function buyNFT(address nftAddress_, uint256 tokenId_) external payable nonReentrant {
        Listing memory listing_ = listings[nftAddress_][tokenId_];

        if (listing_.price == 0) revert NFTMarketplace__ListingNotExists();
        if (listing_.price != msg.value) revert NFTMarketplace__PriceNotValid();

        uint256 fee = (listing_.price * feeBps) / BPS_DENOMINATOR;

        delete listings[nftAddress_][tokenId_];
        accumulatedFees += fee;

        IERC721(nftAddress_).safeTransferFrom(listing_.seller, msg.sender, tokenId_);

        (bool success,) = listing_.seller.call{value: listing_.price - fee}("");
        if (!success) revert NFTMarketplace__TransferFailed();

        emit NFTSold(msg.sender, listing_.seller, nftAddress_, tokenId_, listing_.price, fee);
    }

    /// @notice Updates the marketplace fee.
    /// @dev Applies to every sale made after the change, including already active listings.
    /// @param newFeeBps_ New fee in basis points. Must not exceed MAX_FEE_BPS.
    function setFee(uint256 newFeeBps_) external onlyOwner {
        if (newFeeBps_ > MAX_FEE_BPS) revert NFTMarketplace__FeeTooHigh();

        emit FeeUpdated(feeBps, newFeeBps_);
        feeBps = newFeeBps_;
    }

    /// @notice Withdraws all accumulated fees to the owner.
    /// @dev Pull pattern: fees are never sent during a purchase, so a failing owner can't block sales.
    function withdrawFees() external onlyOwner nonReentrant {
        uint256 amount = accumulatedFees;
        if (amount == 0) revert NFTMarketplace__NoFeesToWithdraw();

        accumulatedFees = 0;

        (bool success,) = msg.sender.call{value: amount}("");
        if (!success) revert NFTMarketplace__TransferFailed();

        emit FeesWithdrawn(msg.sender, amount);
    }
}

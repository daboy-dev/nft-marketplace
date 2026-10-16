// SPDX-License-Identifier: MIT

pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {NFTMarketplace} from "../src/NFTMarketplace.sol";
import {MockNFT} from "./mocks/MockNFT.sol";

contract NFTMarketplaceTest is Test {
    NFTMarketplace nftMarketplace;
    MockNFT mockedNFT;
    address deployer = vm.addr(1);
    address user = vm.addr(2);
    uint256 tokenId = 0;

    function setUp() public {
        vm.startPrank(deployer);
        nftMarketplace = new NFTMarketplace();
        mockedNFT = new MockNFT();
        vm.stopPrank();

        mockedNFT.mint(user, tokenId);
    }

    function test_SetUp_MintsNFTToUser() public view {
        address currentOwner = mockedNFT.ownerOf(tokenId);
        assertEq(currentOwner, user);
    }

    function test_RevertIf_ListPriceIsZero() public {
        vm.prank(user);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__PriceZero.selector);
        nftMarketplace.listNFT(address(mockedNFT), tokenId, 0);
    }

    function test_RevertIf_TokenNotExists() public {
        uint256 nonexistentTokenId = 50;
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, nonexistentTokenId));
        nftMarketplace.listNFT(address(mockedNFT), nonexistentTokenId, 1);
    }

    function test_RevertIf_ListCallerIsNotTokenOwner() public {
        vm.prank(deployer);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__NotTokenOwner.selector);
        nftMarketplace.listNFT(address(mockedNFT), tokenId, 1);
    }

    function test_ListNFT_EmitsNFTListed() public {
        vm.startPrank(user);

        address nftAddress = address(mockedNFT);
        (,address beforeSeller,,) = nftMarketplace.listings(nftAddress, tokenId);
        assertEq(beforeSeller, address(0));

        vm.expectEmit(true, true, true, true, address(nftMarketplace));
        emit NFTMarketplace.NFTListed(user, nftAddress, tokenId, 1);
        nftMarketplace.listNFT(nftAddress, tokenId, 1);
        (,address afterSeller,,) = nftMarketplace.listings(nftAddress, tokenId);
        assertEq(afterSeller, user);

        vm.stopPrank();
    }

    function test_RevertIf_UnlistCallerIsNotSeller() public {
        address nftAddress = address(mockedNFT);

        vm.prank(user);
        nftMarketplace.listNFT(nftAddress, tokenId, 1);

        vm.prank(deployer);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__OnlySellerCanCancel.selector);
        nftMarketplace.unlistNFT(nftAddress, tokenId);
    }

    function test_UnlistNFT_DeletesListing() public {
        vm.startPrank(user);
        address nftAddress = address(mockedNFT);

        nftMarketplace.listNFT(nftAddress, tokenId, 1);
        (, address sellerBefore,,) = nftMarketplace.listings(nftAddress, tokenId);
        assertEq(sellerBefore, user);

        vm.expectEmit(true, true, true, false);
        emit NFTMarketplace.NFTUnlisted(user, nftAddress, tokenId);
        nftMarketplace.unlistNFT(nftAddress, tokenId);
        (address nftListedAddress,,,) = nftMarketplace.listings(nftAddress, tokenId);
        assertEq(nftListedAddress, address(0));

        vm.stopPrank();
    }

    function test_RevertIf_BuyUnlistedNFT() public {
        address nftAddress = address(mockedNFT);

        vm.expectRevert(NFTMarketplace.NFTMarketplace__ListingNotExists.selector);
        nftMarketplace.buyNFT(nftAddress, tokenId);
    }

    function test_RevertIf_BuyValueDoesNotMatchPrice() public {
        address nftAddress = address(mockedNFT);
        uint256 price = 10;

        vm.prank(user);
        nftMarketplace.listNFT(nftAddress, tokenId, price);

        vm.startPrank(deployer);
        vm.deal(deployer, 10);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__PriceNotValid.selector);
        nftMarketplace.buyNFT{ value: price / 2 }(nftAddress, tokenId);
        vm.stopPrank();
    }

    function test_BuyNFT_IsCorrectlyTransferred() public {
        address nftAddress = address(mockedNFT);
        uint256 price = 10;

        vm.startPrank(user);
        nftMarketplace.listNFT(nftAddress, tokenId, price);
        mockedNFT.approve(address(nftMarketplace), tokenId);
        vm.stopPrank();

        (,address sellerAddress,,) = nftMarketplace.listings(nftAddress, tokenId);
        assertEq(sellerAddress, user);

        vm.startPrank(deployer);

        vm.deal(deployer, price);
        uint256 balanceBefore = address(deployer).balance;
        uint256 expectedFee = (price * nftMarketplace.feeBps()) / 10_000;

        vm.expectEmit(true, true, true, true, address(nftMarketplace));
        emit NFTMarketplace.NFTSold(deployer, user, address(mockedNFT), tokenId, price, expectedFee);

        nftMarketplace.buyNFT{ value: price }(nftAddress, tokenId);
        uint256 balanceAfter = address(deployer).balance;
        assertEq(balanceAfter, balanceBefore - price);

        (address currentAddress,,,) = nftMarketplace.listings(nftAddress, tokenId);
        assertEq(currentAddress, address(0));
        address newOwner = mockedNFT.ownerOf(tokenId);
        assertEq(newOwner, deployer);

        vm.stopPrank();
    }
}
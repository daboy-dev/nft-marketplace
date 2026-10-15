// SPDX-License-Identifier: MIT

pragma solidity ^0.8.34;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Test} from "forge-std/Test.sol";
import {NFTMarketplace} from "../src/NFTMarketplace.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract MockNFT is ERC721 {
    constructor() ERC721("MockNFT", "MNFT") {}

    function mint(address to, uint256 token) external {
        _mint(to, token);
    }
}

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

    /* function test_RevertIf_TokenNotExists() public {
        vm.expectRevert(IERC721Errors.ERC721NonexistentToken.selector);
    } */

    function test_RevertIf_NotOwner() public {
        vm.prank(deployer);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__NotTokenOwner.selector);
        nftMarketplace.listNFT(address(mockedNFT), tokenId, 1);
    }

    function test_ListNFT_EmitsNFTListed() public {
        vm.startPrank(user);

        address nftAddress = address(mockedNFT);
        (,address beforeSeller,,) = nftMarketplace.listings(nftAddress, tokenId);
        assertEq(beforeSeller, address(0));
    
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

        nftMarketplace.unlistNFT(nftAddress, tokenId);
        (address nftListedAddress,,,) = nftMarketplace.listings(nftAddress, tokenId);
        assertEq(nftListedAddress, address(0));

        vm.stopPrank();
    }
}
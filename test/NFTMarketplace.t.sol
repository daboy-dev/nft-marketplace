// SPDX-License-Identifier: MIT

pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {NFTMarketplace} from "../src/NFTMarketplace.sol";
import {MockNFT} from "./mocks/MockNFT.sol";

contract NFTMarketplaceTest is Test {
    NFTMarketplace nftMarketplace;
    MockNFT mockedNFT;
    address deployer = vm.addr(1);
    address user = vm.addr(2);
    uint256 tokenId = 0;
    address buyer = vm.addr(3);
    uint256 constant feeTestsPrice = 1 ether;
    uint256 constant BPS_DENOMINATOR = 10_000;

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

        vm.expectEmit(true, true, true, false, address(nftMarketplace));
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

    function test_FeeBps_DefaultsToHalfPercent() public view {
        assertEq(nftMarketplace.feeBps(), 50);
    }

    function test_SetFee_UpdatesFeeAndEmitsFeeUpdated() public {
        uint256 oldFeeBps = nftMarketplace.feeBps();
        uint256 newFeeBps = 100;

        vm.expectEmit(false, false, false, true, address(nftMarketplace));
        emit NFTMarketplace.FeeUpdated(oldFeeBps, newFeeBps);
        vm.prank(deployer);
        nftMarketplace.setFee(newFeeBps);

        assertEq(nftMarketplace.feeBps(), newFeeBps);
    }

    function test_RevertIf_SetFeeCallerIsNotOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        nftMarketplace.setFee(100);
    }

    function test_RevertIf_SetFeeExceedsMax() public {
        uint256 aboveMaxFeeBps = nftMarketplace.MAX_FEE_BPS() + 1;

        vm.prank(deployer);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__FeeTooHigh.selector);
        nftMarketplace.setFee(aboveMaxFeeBps);
    }

    function test_BuyNFT_SplitsPriceBetweenSellerAndFees() public {
        uint256 expectedFee = (feeTestsPrice * nftMarketplace.feeBps()) / BPS_DENOMINATOR;
        _listAndApprove(tokenId, feeTestsPrice);

        _buy(tokenId, feeTestsPrice);

        assertEq(user.balance, feeTestsPrice - expectedFee);
        assertEq(nftMarketplace.accumulatedFees(), expectedFee);
        assertEq(address(nftMarketplace).balance, expectedFee);
        assertEq(buyer.balance, 0);
    }

    function test_BuyNFT_AppliesUpdatedFee() public {
        uint256 newFeeBps = 200;
        uint256 expectedFee = (feeTestsPrice * newFeeBps) / BPS_DENOMINATOR;
        _listAndApprove(tokenId, feeTestsPrice);

        vm.prank(deployer);
        nftMarketplace.setFee(newFeeBps);
        _buy(tokenId, feeTestsPrice);

        assertEq(nftMarketplace.accumulatedFees(), expectedFee);
        assertEq(user.balance, feeTestsPrice - expectedFee);
    }

    function test_BuyNFT_AccumulatesFeesAcrossSales() public {
        uint256 secondTokenId = 1;
        mockedNFT.mint(user, secondTokenId);
        _listAndApprove(tokenId, feeTestsPrice);
        _listAndApprove(secondTokenId, 2 * feeTestsPrice);
        uint256 expectedFees = (feeTestsPrice * nftMarketplace.feeBps()) / BPS_DENOMINATOR
            + (2 * feeTestsPrice * nftMarketplace.feeBps()) / BPS_DENOMINATOR;

        _buy(tokenId, feeTestsPrice);
        _buy(secondTokenId, 2 * feeTestsPrice);

        assertEq(nftMarketplace.accumulatedFees(), expectedFees);
        assertEq(address(nftMarketplace).balance, expectedFees);
    }

    function testFuzz_BuyNFT_SplitsPriceBetweenSellerAndFees(uint256 price, uint256 feeBps) public {
        price = bound(price, 1, 100 ether);
        feeBps = bound(feeBps, 0, nftMarketplace.MAX_FEE_BPS());
        uint256 expectedFee = (price * feeBps) / BPS_DENOMINATOR;
        vm.prank(deployer);
        nftMarketplace.setFee(feeBps);
        _listAndApprove(tokenId, price);

        _buy(tokenId, price);

        assertEq(nftMarketplace.accumulatedFees(), expectedFee);
        assertEq(user.balance, price - expectedFee);
        assertEq(user.balance + nftMarketplace.accumulatedFees(), price);
    }

    function test_WithdrawFees_TransfersFeesToOwnerAndEmitsFeesWithdrawn() public {
        _listAndApprove(tokenId, feeTestsPrice);
        _buy(tokenId, feeTestsPrice);
        uint256 fees = nftMarketplace.accumulatedFees();

        vm.expectEmit(true, false, false, true, address(nftMarketplace));
        emit NFTMarketplace.FeesWithdrawn(deployer, fees);
        vm.prank(deployer);
        nftMarketplace.withdrawFees();

        assertEq(deployer.balance, fees);
        assertEq(nftMarketplace.accumulatedFees(), 0);
        assertEq(address(nftMarketplace).balance, 0);
    }

    function test_RevertIf_WithdrawFeesCallerIsNotOwner() public {
        _listAndApprove(tokenId, feeTestsPrice);
        _buy(tokenId, feeTestsPrice);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        nftMarketplace.withdrawFees();
    }

    function test_RevertIf_NoFeesToWithdraw() public {
        vm.prank(deployer);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__NoFeesToWithdraw.selector);
        nftMarketplace.withdrawFees();
    }

    function test_RevertIf_WithdrawFeesTransferFails() public {
        _listAndApprove(tokenId, feeTestsPrice);
        _buy(tokenId, feeTestsPrice);

        address ownerRejectingEth = address(mockedNFT);
        vm.prank(deployer);
        nftMarketplace.transferOwnership(ownerRejectingEth);

        vm.prank(ownerRejectingEth);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__TransferFailed.selector);
        nftMarketplace.withdrawFees();
    }

    function _listAndApprove(uint256 id, uint256 price) internal {
        vm.startPrank(user);
        nftMarketplace.listNFT(address(mockedNFT), id, price);
        mockedNFT.approve(address(nftMarketplace), id);
        vm.stopPrank();
    }

    function _buy(uint256 id, uint256 price) internal {
        vm.deal(buyer, price);
        vm.prank(buyer);
        nftMarketplace.buyNFT{value: price}(address(mockedNFT), id);
    }
}
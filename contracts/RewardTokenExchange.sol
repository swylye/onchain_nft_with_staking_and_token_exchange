// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./SVGStaking.sol";
import "./Math.sol";

contract RewardTokenExchange is ERC20, Ownable {
    SVGStaking rewardTokenContract;
    address payable rewardTokenAddress;
    uint256 ownerShareEth = 0;
    uint256 ownerShareToken = 0;

    // Both fee cuts should be in the thousandth (i.e. feeCut of 10 is equivalent to 1% [10/1000])
    uint256 public ownerFeeCut = 2; //0.2%
    uint256 public lpFeeCut = 3; //0.3%

    constructor(address payable _rewardTokenAddress)
        ERC20("SVG NFT reward token <> Eth LP token", "svgNftEthLP")
    {
        rewardTokenAddress = _rewardTokenAddress;
        rewardTokenContract = SVGStaking(rewardTokenAddress);
    }

    function getReserves()
        public
        view
        returns (uint256 ethReserveAmount, uint256 tokenReserveAmount)
    {
        ethReserveAmount = address(this).balance - ownerShareEth;
        tokenReserveAmount =
            rewardTokenContract.balanceOf(address(this)) -
            ownerShareToken;
    }

    function addLiquidity(uint256 tokenAmount)
        external
        payable
        returns (uint256 lpTokenAmount)
    {
        require(
            tokenAmount > 0 && msg.value > 0,
            "Must transfer both token and ether!"
        );
        (uint256 ethBalance, uint256 tokenReserve) = getReserves();
        uint256 _totalSupply = totalSupply();
        if (tokenReserve == 0) {
            rewardTokenContract.transferFrom(
                msg.sender,
                address(this),
                tokenAmount
            );
            lpTokenAmount = Math.sqrt(msg.value * tokenAmount);
        } else {
            uint256 ethReserve = ethBalance - msg.value;
            lpTokenAmount = Math.min(
                (msg.value * _totalSupply) / ethReserve,
                (tokenAmount * _totalSupply) / tokenReserve
            );
            rewardTokenContract.transferFrom(
                msg.sender,
                address(this),
                tokenAmount
            );
        }
        _mint(msg.sender, lpTokenAmount);
    }

    function removeLiquidity(uint256 lpTokenRemoveAmount)
        external
        returns (uint256 ethAmountReturned, uint256 tokenAmountReturned)
    {
        require(
            lpTokenRemoveAmount > 0 &&
                balanceOf(msg.sender) >= lpTokenRemoveAmount,
            "You must have sufficient amount to remove!"
        );
        (uint256 ethReserve, uint256 tokenReserve) = getReserves();
        uint256 _totalSupply = totalSupply();

        ethAmountReturned = (lpTokenRemoveAmount * ethReserve) / _totalSupply;
        tokenAmountReturned =
            (lpTokenRemoveAmount * tokenReserve) /
            _totalSupply;

        _burn(msg.sender, lpTokenRemoveAmount);
        payable(msg.sender).transfer(ethAmountReturned);
        rewardTokenContract.transfer(msg.sender, tokenAmountReturned);
    }

    function getSwapAmount(
        uint256 inputAmount,
        uint256 inputReserves,
        uint256 outputReserves
    ) public view returns (uint256 outputAmount, uint256 ownerCut) {
        uint256 _ownerShare = ownerFeeCut;
        uint256 _lpShare = lpFeeCut;
        uint256 _swapShare = 1000 - _ownerShare - _lpShare;

        uint256 _amount = (inputAmount * outputReserves) / inputReserves;
        outputAmount = (_amount * _swapShare) / 1000;
        ownerCut = (_amount * _ownerShare) / 1000;
    }

    function swapEthForToken(uint256 minTokens) external payable {
        (uint256 ethReserve, uint256 tokenReserve) = getReserves();
        (uint256 tokensBought, uint256 ownerCut) = getSwapAmount(
            msg.value,
            ethReserve - msg.value,
            tokenReserve
        );
        require(tokensBought >= minTokens, "Insufficient output amount!");
        rewardTokenContract.transfer(msg.sender, tokensBought);
        ownerShareToken += ownerCut;
    }

    function swapTokenForEth(uint256 tokenSaleAmount, uint256 minEth) external {
        (uint256 ethReserve, uint256 tokenReserve) = getReserves();
        (uint256 ethBought, uint256 ownerCut) = getSwapAmount(
            tokenSaleAmount,
            tokenReserve,
            ethReserve
        );
        require(ethBought >= minEth, "Insufficient output amount!");
        rewardTokenContract.transferFrom(
            msg.sender,
            address(this),
            tokenSaleAmount
        );
        payable(msg.sender).transfer(ethBought);
        ownerShareEth += ownerCut;
    }

    function setFee(uint256 _ownerCut, uint256 _lpCut) external onlyOwner {
        ownerFeeCut = _ownerCut;
        lpFeeCut = _lpCut;
    }

    function ownerWithdraw() external onlyOwner {
        require(
            ownerShareEth > 0 || ownerShareToken > 0,
            "Nothing to withdraw!"
        );
        uint256 ethAmount = ownerShareEth;
        uint256 tokenAmount = ownerShareToken;
        ownerShareEth = 0;
        ownerShareToken = 0;
        payable(msg.sender).transfer(ethAmount);
        rewardTokenContract.transfer(msg.sender, tokenAmount);
    }
}

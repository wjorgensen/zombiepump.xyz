// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

//Things to still implement:

import {ERC20} from "solady/tokens/ERC20.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

contract ERC20_Bonding is ERC20 {
    using FixedPointMathLib for uint256;

    // Events
    event BondingCurveCompleted();
    event SegmentCompleted(uint256 currentSegment, uint256 newDeadline);

    // Custom Errors
    error ERC20_Bonding__MaxSupplyReached();
    error ERC20_Bonding__ZeroAmount();
    error ERC20_Bonding__TransferFailed();
    error ERC20_Bonding__InsufficientBalance();

    // Private Constants
    uint8 private constant c_DECIMALS = 18;
    uint256 private constant c_TOTAL_SUPPLY = 1_000_000_000 * 1 ** c_DECIMALS; // 1 billion tokens
    uint256 private constant c_MAX_ETH = 15 ether; // 15 ETH maximum
    uint256 private constant c_LIQUIDITY_RESERVE = (c_TOTAL_SUPPLY * 15) / 100; // 15% reserve
    uint256 private constant c_AVAILABLE_SUPPLY = c_TOTAL_SUPPLY - c_LIQUIDITY_RESERVE;
    uint256 private constant c_SEGMENT_SIZE = c_TOTAL_SUPPLY / 20; // 5% segments

    // Private Variables
    uint256 private s_currentSegment; // Tracks which 5% segment we're in
    uint256 private s_deadline; // Block number deadline
    bool private s_isComplete;

    // Private Immutables
    string private i_NAME;
    string private i_SYMBOL;
    string private i_LINK_TO_IMAGE;
    string private i_DESCRIPTION;

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _linkToImage,
        string memory _description
    ) {
        i_NAME = _name;
        i_SYMBOL = _symbol;
        i_LINK_TO_IMAGE = _linkToImage;
        i_DESCRIPTION = _description;
        s_deadline = block.number + 1 weeks;
    }

    function buy() external payable {
        if (msg.value == 0) {
            revert ERC20_Bonding__ZeroAmount();
        }

        if (s_isComplete) {
            revert ERC20_Bonding__MaxSupplyReached();
        }

        uint256 remainingTokens = c_AVAILABLE_SUPPLY - totalSupply();
        uint256 msgValue = msg.value;
        uint256 tokensToMint = calculateTokensToMint(msgValue);

        // If trying to mint more than remaining supply, calculate exact cost for remaining tokens
        if (tokensToMint > remainingTokens) {
            tokensToMint = remainingTokens;
            uint256 ethToUse = calculateEthRequired(remainingTokens);

            // Refund excess ETH
            uint256 refund = msg.value - ethToUse;
            if (refund > 0) {
                (bool success, ) = msg.sender.call{value: refund}("");
                if (!success) {
                    revert ERC20_Bonding__TransferFailed();
                }
            }
        }

        _mint(msg.sender, tokensToMint);

        // Check if we've completed a new segment
        uint256 newSegment = totalSupply() / c_SEGMENT_SIZE;
        if (newSegment > s_currentSegment) {
            s_currentSegment = newSegment;
            s_deadline = block.number + 1 weeks;
            emit SegmentCompleted(newSegment, s_deadline);
        }

        // Check if bonding curve is complete
        if (totalSupply() >= c_AVAILABLE_SUPPLY && !s_isComplete) {
            s_isComplete = true;
            emit BondingCurveCompleted();
        }
    }

    function sell(uint256 tokenAmount) external {
        if (tokenAmount == 0) {
            revert ERC20_Bonding__ZeroAmount();
        }
        if (balanceOf(msg.sender) < tokenAmount) {
            revert ERC20_Bonding__InsufficientBalance();
        }

        // Calculate ETH to return based on current position on curve
        uint256 ethToReturn = calculateEthToReturn(tokenAmount);

        // Burn tokens first (checks-effects-interactions pattern)
        _burn(msg.sender, tokenAmount);

        // Transfer ETH to seller
        (bool success, ) = msg.sender.call{value: ethToReturn}("");
        if (!success) {
            revert ERC20_Bonding__TransferFailed();
        }
    }

    function calculateTokensToMint(
        uint256 ethAmount
    ) public pure returns (uint256) {
        // Linear bonding curve formula: tokens = (ethAmount * TOTAL_SUPPLY) / MAX_ETH
        return ethAmount.mulDiv(c_TOTAL_SUPPLY, c_MAX_ETH);
    }

    function calculateEthRequired(
        uint256 tokenAmount
    ) public pure returns (uint256) {
        // Inverse of bonding curve formula: eth = (tokenAmount * MAX_ETH) / TOTAL_SUPPLY
        return tokenAmount.mulDiv(c_MAX_ETH, c_TOTAL_SUPPLY);
    }

    function calculateEthToReturn(
        uint256 tokenAmount
    ) public view returns (uint256) {
        // Calculate new supply point after burning
        uint256 currentSupply = totalSupply();
        uint256 newSupply = currentSupply - tokenAmount;

        // Calculate ETH based on the average price between new supply and current supply
        // This ensures no immediate arbitrage is possible
        uint256 averagePrice = (newSupply + currentSupply).mulDiv(
            c_MAX_ETH,
            c_TOTAL_SUPPLY * 2
        );
        return tokenAmount.mulDiv(averagePrice, 1e18);
    }

    function getCurrentPrice() public view returns (uint256) {
        // Price increases linearly as supply increases
        // price = MAX_ETH / TOTAL_SUPPLY
        return c_MAX_ETH.mulDiv(1e18, c_TOTAL_SUPPLY);
    }

    // Required for receiving ETH
    receive() external payable {}

    fallback() external payable {}

    function decimals() public view override returns (uint8) {
        return c_DECIMALS;
    }

    function name() public view override returns (string memory) {
        return i_NAME;
    }

    function symbol() public view override returns (string memory) {
        return i_SYMBOL;
    }

    function linkToImage() public view returns (string memory) {
        return i_LINK_TO_IMAGE;
    }

    function description() public view returns (string memory) {
        return i_DESCRIPTION;
    }

    function getMaxSupply() public pure returns (uint256) {
        return c_TOTAL_SUPPLY;
    }

    function getMaxEth() public pure returns (uint256) {
        return c_MAX_ETH;
    }

    function getCurrentSegment() public view returns (uint256) {
        return s_currentSegment;
    }

    function getDeadline() public view returns (uint256) {
        return s_deadline;
    }

    function isComplete() public view returns (bool) {
        return s_isComplete;
    }

    function getAvailableSupply() public pure returns (uint256) {
        return c_AVAILABLE_SUPPLY;
    }

    function getLiquidityReserve() public pure returns (uint256) {
        return c_LIQUIDITY_RESERVE;
    }

    function isZombie() public view returns (bool) {
        return block.number > s_deadline && !s_isComplete;
    }
}

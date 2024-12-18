// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract FraxSwapf is ERC721, Ownable {
    using SafeMath for uint256;

    struct Reserve {
        uint256 reserveA;
        uint256 reserveB;
    }

    mapping(bytes32 => Reserve) public reserves; // Reserves per token pair
    mapping(uint256 => mapping(address => uint256)) public accumulatedRewards; // Accumulated rewards per NFT (tokenId)
    mapping(bytes32 => mapping(address => uint256)) public liquidityProviderContribution; // Liquidity contribution by providers per pair
    mapping(bytes32 => address[]) public liquidityProviders; // List of liquidity providers per pair
    mapping(uint256 => bytes32) public tokenIdToPair; // Mapping tokenId to token pair
    uint256 public tokenIdCounter;
    uint public constant DEFAULT_FEE_RATE = 30; // Default fee rate of 0.3%
    uint public constant MAX_FEE_RATE = 100; // Maximum fee rate of 1%
    address public protocolWallet; // Protocol wallet address to receive fees

    constructor() ERC721("FRAXNFT", "FNFT") Ownable(0xb8BBC9301B0ddF33D4Cb881EA545025D15eF5F1c) {
        protocolWallet = msg.sender; // Set the deployer as the protocol wallet address
    }

    // Helper function to get a unique pair hash
    function getPairHash(address tokenA, address tokenB) public pure returns (bytes32) {
        require(tokenA != tokenB, "Tokens must be different");
        return keccak256(abi.encodePacked(tokenA < tokenB ? tokenA : tokenB, tokenA < tokenB ? tokenB : tokenA));
    }

    // Add liquidity for a token pair
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountA
    ) external {
        require(amountA > 0, "Amount must be greater than zero");

        bytes32 pairHash = getPairHash(tokenA, tokenB);
        Reserve storage pairReserves = reserves[pairHash];

        uint256 amountB;

        if (pairReserves.reserveA == 0 && pairReserves.reserveB == 0) {
            // First-time liquidity: No ratio check, accept amountA and calculate amountB
            amountB = amountA; // Start with a 1:1 ratio for first time
        } else {
            // Calculate the required amount of tokenB based on the current ratio
            amountB = amountA.mul(pairReserves.reserveB).div(pairReserves.reserveA);
        }

        // Transfer tokens to the contract
        IERC20(tokenA).transferFrom(msg.sender, address(this), amountA);
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountB);

        // Update reserves
        pairReserves.reserveA = pairReserves.reserveA.add(amountA);
        pairReserves.reserveB = pairReserves.reserveB.add(amountB);

        uint256 newTokenId = tokenIdCounter;
        _mint(msg.sender, newTokenId);
        tokenIdToPair[newTokenId] = pairHash;

        liquidityProviderContribution[pairHash][msg.sender] = liquidityProviderContribution[pairHash][msg.sender].add(amountA).add(amountB);

        // Track the liquidity provider for this pair
        liquidityProviders[pairHash].push(msg.sender);

        tokenIdCounter++;
    }

    // Swap function (without tokenId requirement)
    function swap(
        address tokenIn,
        uint256 amountIn,
        address tokenOut
    ) external {
        require(amountIn > 0, "Swap amount must be greater than zero");
        require(tokenIn != tokenOut, "Tokens must be different");

        bytes32 pairHash = getPairHash(tokenIn, tokenOut);
        Reserve storage pairReserves = reserves[pairHash];

        require(pairReserves.reserveA > 0 && pairReserves.reserveB > 0, "No liquidity for this pair");

        uint256 reserveIn = tokenIn == address(0) ? pairReserves.reserveA : pairReserves.reserveB;
        uint256 reserveOut = tokenOut == address(0) ? pairReserves.reserveB : pairReserves.reserveA;

        uint256 amountOut = getAmountOut(amountIn, reserveIn, reserveOut);

        // Handle the transfer of tokens
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        pairReserves.reserveA = pairReserves.reserveA.add(amountIn);
        pairReserves.reserveB = pairReserves.reserveB.sub(amountOut);

        // Calculate the fee for liquidity provider (this is accumulated, not transferred yet)
        uint256 fee = (amountIn.mul(DEFAULT_FEE_RATE)).div(10000);

        // Accumulate the fee for the liquidity provider
        liquidityProviderContribution[pairHash][msg.sender] = liquidityProviderContribution[pairHash][msg.sender].add(fee);

        // Find the tokenId associated with the liquidity provider
        uint256 tokenId = getTokenIdForLiquidityProvider(msg.sender, pairHash);

        // Accumulate rewards for the liquidity provider (you may want to accumulate rewards for liquidity provision)
        uint256 reward = fee; // For simplicity, we can use the fee as the reward
        accumulatedRewards[tokenId][tokenOut] = accumulatedRewards[tokenId][tokenOut].add(reward);

        // Send the swapped tokens to the user
        IERC20(tokenOut).transfer(msg.sender, amountOut);
    }

    // Helper function to get the tokenId for a liquidity provider
    function getTokenIdForLiquidityProvider(address provider, bytes32 pairHash) internal view returns (uint256) {
        // Iterate through all token IDs to find the one associated with the provider and pair
        for (uint256 i = 0; i < tokenIdCounter; i++) {
            if (ownerOf(i) == provider && tokenIdToPair[i] == pairHash) {
                return i;
            }
        }
        revert("No tokenId found for this liquidity provider and pair");
    }

    // Calculate amount out
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure returns (uint256) {
        uint256 amountInWithFee = amountIn.mul(10000 - DEFAULT_FEE_RATE);
        uint256 numerator = amountInWithFee.mul(reserveOut);
        uint256 denominator = reserveIn.mul(10000).add(amountInWithFee);
        return numerator.div(denominator);
    }

    // Claim rewards function
    function claimRewards(uint256 tokenId, address tokenOut) external {
        // Retrieve the accumulated rewards for the given tokenId and tokenOut pair
        bytes32 pairHash = tokenIdToPair[tokenId];
        uint256 reward = accumulatedRewards[tokenId][tokenOut];
        require(reward > 0, "No rewards available to claim");

        // Divide total rewards among all LPs
        uint256 totalLPs = liquidityProviders[pairHash].length;
        uint256 rewardPerLP = reward.div(totalLPs);

        // Cut 10% from the reward when claiming
        uint256 lpShare = rewardPerLP.mul(90).div(100); // 90% to the liquidity provider
        uint256 protocolShare = rewardPerLP.sub(lpShare); // 10% to the protocol wallet

        // Reset the accumulated reward for the tokenId and tokenOut pair
        accumulatedRewards[tokenId][tokenOut] = 0;

        // Transfer the rewards: 90% to the liquidity provider and 10% to the protocol wallet
        IERC20(tokenOut).transfer(msg.sender, lpShare);
        IERC20(tokenOut).transfer(protocolWallet, protocolShare);
    }

    // Remove liquidity
    function removeLiquidity(
        uint256 tokenId,
        address tokenA,
        address tokenB
    ) external {
        require(ownerOf(tokenId) == msg.sender, "Not the owner of this liquidity NFT");

        bytes32 pairHash = getPairHash(tokenA, tokenB);
        Reserve storage pairReserves = reserves[pairHash];

        uint256 amountA = pairReserves.reserveA;
        uint256 amountB = pairReserves.reserveB;

        IERC20(tokenA).transfer(msg.sender, amountA);
        IERC20(tokenB).transfer(msg.sender, amountB);

        pairReserves.reserveA = pairReserves.reserveA.sub(amountA);
        pairReserves.reserveB = pairReserves.reserveB.sub(amountB);

        delete liquidityProviderContribution[pairHash][msg.sender];
        delete tokenIdToPair[tokenId];
        _burn(tokenId);

        // Remove provider from the liquidity providers list
        address[] storage providers = liquidityProviders[pairHash];
        for (uint256 i = 0; i < providers.length; i++) {
            if (providers[i] == msg.sender) {
                providers[i] = providers[providers.length - 1];
                providers.pop();
                break;
            }
        }
    }

    // Get current reserves for a pair
    function getReserves(address tokenA, address tokenB) external view returns (uint256, uint256) {
        bytes32 pairHash = getPairHash(tokenA, tokenB);
        Reserve storage pairReserves = reserves[pairHash];
        return (pairReserves.reserveA, pairReserves.reserveB);
    }

    // Update protocol wallet address
    function updateProtocolWallet(address newProtocolWallet) external onlyOwner {
        protocolWallet = newProtocolWallet;
    }
}

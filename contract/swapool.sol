// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function mint(address to, uint256 amount) external;
}

interface IPriceFeed {
    function getLatestPrice() external view returns (uint256);

    function getUSDToINRPrice() external view returns (uint256);
}

contract RcoinSwap is ERC721, Ownable {
    using SafeMath for uint256;
    address public maticTokenAddress;
    address public linkTokenAddress;
    address public rcoinTokenAddress;
    address public maticUsdPriceFeed;
    address public linkUsdPriceFeed;
    address public usdInrPriceFeed;
    struct Reserve {
        uint256 reserveA;
        uint256 reserveB;
    }
    mapping(bytes32 => Reserve) public reserves;
    mapping(uint256 => mapping(address => uint256)) public accumulatedRewards;
    mapping(bytes32 => mapping(address => uint256))
        public liquidityProviderContribution;
    mapping(bytes32 => address[]) public liquidityProviders;
    mapping(uint256 => bytes32) public tokenIdToPair;
    mapping(bytes32 => uint256) public pairTotalSupply;
    uint256 public tokenIdCounter;
    uint256 public constant DEFAULT_FEE_RATE = 30;
    uint256 public constant MAX_FEE_RATE = 100;
    address public protocolWallet;

    constructor(
        address _maticTokenAddress,
        address _linkTokenAddress,
        address _maticUsdPriceFeed,
        address _linkUsdPriceFeed,
        address _usdInrPriceFeed
    ) ERC721("FRAXNFT", "FNFT") Ownable(msg.sender) {
        protocolWallet = msg.sender;
        maticTokenAddress = _maticTokenAddress;
        linkTokenAddress = _linkTokenAddress;
        maticUsdPriceFeed = _maticUsdPriceFeed;
        linkUsdPriceFeed = _linkUsdPriceFeed;
        usdInrPriceFeed = _usdInrPriceFeed;
    }

    function getPairHash(address tokenA, address tokenB)
        public
        pure
        returns (bytes32)
    {
        require(tokenA != tokenB, "Tokens must be different");
        return
            keccak256(
                abi.encodePacked(
                    tokenA < tokenB ? tokenA : tokenB,
                    tokenA < tokenB ? tokenB : tokenA
                )
            );
    }

    function maticInInr() public view returns (uint256) {
        uint256 maticPriceInUsd = IPriceFeed(maticUsdPriceFeed)
            .getLatestPrice();
        uint256 usdToInr = IPriceFeed(usdInrPriceFeed).getUSDToINRPrice();
        return maticPriceInUsd.mul(usdToInr).div(1e18);
    }

    function linkInInr() public view returns (uint256) {
        uint256 linkPriceInUsd = IPriceFeed(linkUsdPriceFeed).getLatestPrice();
        uint256 usdToInr = IPriceFeed(usdInrPriceFeed).getUSDToINRPrice();
        return linkPriceInUsd.mul(usdToInr).div(1e18);
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountA
    ) external {
        require(amountA > 0, "Amount must be greater than zero");
        uint256 amountB;
        uint256 priceAInInr;
        uint256 priceBInInr;
        if (tokenA == maticTokenAddress) {
            priceAInInr = maticInInr();
        } else if (tokenA == linkTokenAddress) {
            priceAInInr = linkInInr();
        } else {
            priceAInInr = 1e18;
        }
        if (tokenB == maticTokenAddress) {
            priceBInInr = maticInInr();
        } else if (tokenB == linkTokenAddress) {
            priceBInInr = linkInInr();
        } else {
            priceBInInr = 1e18;
        }
        if (priceAInInr > 0 && priceBInInr > 0) {
            amountB = amountA.mul(priceAInInr).div(priceBInInr);
        }
        IERC20(tokenA).transferFrom(msg.sender, address(this), amountA);
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountB);
        bytes32 pairHash = getPairHash(tokenA, tokenB);
        reserves[pairHash].reserveA = reserves[pairHash].reserveA.add(amountA);
        reserves[pairHash].reserveB = reserves[pairHash].reserveB.add(amountB);
        uint256 newTokenId = tokenIdCounter;
        _mint(msg.sender, newTokenId);
        tokenIdToPair[newTokenId] = pairHash;
        liquidityProviderContribution[pairHash][
            msg.sender
        ] = liquidityProviderContribution[pairHash][msg.sender]
            .add(amountA)
            .add(amountB);
        liquidityProviders[pairHash].push(msg.sender);
        tokenIdCounter++;
        pairTotalSupply[pairHash] = pairTotalSupply[pairHash].add(1);
    }

    function withdraw(address tokenA, uint256 amount)
        external
        returns (uint256)
    {
        if (tokenA == maticTokenAddress) {
            IERC20(tokenA).transfer(msg.sender, amount);
            return amount;
        } else if (tokenA == linkTokenAddress) {
            IERC20(tokenA).transfer(msg.sender, amount);
            return amount;
        } else if (tokenA == rcoinTokenAddress) {
            IERC20(tokenA).transfer(msg.sender, amount);
            return amount;
        } else {
            return 0;
        }
    }

    function calculateAddLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountA
    ) external view returns (uint256 amountB) {
        bytes32 pairHash = getPairHash(tokenA, tokenB);
        Reserve storage pairReserves = reserves[pairHash];
        if (pairReserves.reserveA == 0 && pairReserves.reserveB == 0) {
            return amountA;
        } else {
            return
                amountA.mul(pairReserves.reserveB).div(pairReserves.reserveA);
        }
    }

    function swap(
        address tokenIn,
        uint256 amountIn,
        address tokenOut
    ) external returns (uint256) {
        require(amountIn > 0, "Swap amount must be greater than zero");
        require(tokenIn != tokenOut, "Tokens must be different");
        bytes32 pairHash = getPairHash(tokenIn, tokenOut);
        Reserve storage pairReserves = reserves[pairHash];
        require(
            pairReserves.reserveA > 0 && pairReserves.reserveB > 0,
            "No liquidity for this pair"
        );
        (uint256 reserveIn, uint256 reserveOut) = getReserves(
            tokenIn,
            pairReserves
        );
        require(reserveIn > 0 && reserveOut > 0, "Invalid reserves");
        uint256 amountOut = calculateAmountOut(amountIn, reserveIn, reserveOut);
        uint256 fee = amountOut.mul(DEFAULT_FEE_RATE).div(1e18);
        uint256 amountOutAfterFee = amountOut.sub(fee);
        require(amountOutAfterFee > 0, "Insufficient output after fees");
        transferTokens(tokenIn, tokenOut, amountIn, amountOutAfterFee, fee);
        updateReserves(pairReserves, tokenIn, amountIn, amountOut);
        return amountOutAfterFee;
    }

    function getReserves(address tokenIn, Reserve storage pairReserves)
        internal
        view
        returns (uint256 reserveIn, uint256 reserveOut)
    {
        if (tokenIn == maticTokenAddress) {
            reserveIn = pairReserves.reserveA;
            reserveOut = pairReserves.reserveB;
        } else if (tokenIn == linkTokenAddress) {
            reserveIn = pairReserves.reserveA;
            reserveOut = pairReserves.reserveB;
        } else {
            reserveIn = pairReserves.reserveB;
            reserveOut = pairReserves.reserveA;
        }
    }

    function calculateAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256) {
        return amountIn.mul(reserveOut).div(reserveIn);
    }

    function transferTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutAfterFee,
        uint256 fee
    ) internal {
        require(
            IERC20(tokenIn).allowance(msg.sender, address(this)) >= amountIn,
            "Insufficient allowance for tokenIn"
        );
        require(
            IERC20(tokenIn).balanceOf(msg.sender) >= amountIn,
            "Insufficient balance for tokenIn"
        );
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).transfer(msg.sender, amountOutAfterFee);
        IERC20(tokenOut).transfer(protocolWallet, fee);
    }

    function updateReserves(
        Reserve storage pairReserves,
        address tokenIn,
        uint256 amountIn,
        uint256 amountOut
    ) internal {
        if (tokenIn == maticTokenAddress) {
            pairReserves.reserveA += amountIn;
            pairReserves.reserveB -= amountOut;
        } else if (tokenIn == linkTokenAddress) {
            pairReserves.reserveA += amountIn;
            pairReserves.reserveB -= amountOut;
        } else {
            pairReserves.reserveB += amountIn;
            pairReserves.reserveA -= amountOut;
        }
    }

    function calculateSwapAmount(
        address tokenIn,
        uint256 amountIn,
        address tokenOut
    ) external view returns (uint256 amountOutAfterFee) {
        require(amountIn > 0, "Swap amount must be greater than zero");
        require(tokenIn != tokenOut, "Tokens must be different");

        bytes32 pairHash = getPairHash(tokenIn, tokenOut);
        Reserve storage pairReserves = reserves[pairHash];

        require(
            pairReserves.reserveA > 0 && pairReserves.reserveB > 0,
            "No liquidity for this pair"
        );

        (uint256 reserveIn, uint256 reserveOut) = getReserves(
            tokenIn,
            pairReserves
        );
        require(reserveIn > 0 && reserveOut > 0, "Invalid reserves");

        uint256 amountOut = calculateAmountOut(amountIn, reserveIn, reserveOut);

        uint256 fee = amountOut.mul(DEFAULT_FEE_RATE).div(1e18);

        amountOutAfterFee = amountOut.sub(fee);

        return amountOutAfterFee;
    }

    function claimRewards(uint256 tokenId, address tokenOut) external {
        bytes32 pairHash = tokenIdToPair[tokenId];
        uint256 reward = accumulatedRewards[tokenId][tokenOut];
        require(reward > 0, "No rewards available to claim");
        uint256 totalLPs = liquidityProviders[pairHash].length;
        uint256 rewardPerLP = reward.div(totalLPs);
        uint256 lpShare = rewardPerLP.mul(90).div(100);
        uint256 protocolShare = rewardPerLP.sub(lpShare);
        accumulatedRewards[tokenId][tokenOut] = 0;
        IERC20(tokenOut).transfer(msg.sender, lpShare);
        IERC20(tokenOut).transfer(protocolWallet, protocolShare);
    }

    function removeLiquidity(
        uint256 tokenId,
        address tokenA,
        address tokenB
    ) external {
        require(
            ownerOf(tokenId) == msg.sender,
            "Not the owner of this liquidity NFT"
        );
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
        address[] storage providers = liquidityProviders[pairHash];
        for (uint256 i = 0; i < providers.length; i++) {
            if (providers[i] == msg.sender) {
                providers[i] = providers[providers.length - 1];
                providers.pop();
                break;
            }
        }
        pairTotalSupply[pairHash] = pairTotalSupply[pairHash].sub(1);
    }

    function calculateRemoveLiquidity(uint256 tokenId)
        external
        view
        returns (uint256 amountA, uint256 amountB)
    {
        bytes32 pairHash = tokenIdToPair[tokenId];
        Reserve storage pairReserves = reserves[pairHash];
        uint256 totalSupply = pairTotalSupply[pairHash];
        uint256 userShare = liquidityProviderContribution[pairHash][msg.sender];
        amountA = pairReserves.reserveA.mul(userShare).div(totalSupply);
        amountB = pairReserves.reserveB.mul(userShare).div(totalSupply);
    }

    function getReserves(address tokenA, address tokenB)
        external
        view
        returns (uint256, uint256)
    {
        bytes32 pairHash = getPairHash(tokenA, tokenB);
        Reserve storage pairReserves = reserves[pairHash];
        return (pairReserves.reserveA, pairReserves.reserveB);
    }

    //Adding two functions one will store the price and the other one will be used to fetch realtime price of rcoin in different pools so we can maintain them properly.  
     
    function getTokenPriceInInr(address token)
        internal
        view
        returns (uint256 priceInInr)
    {
        if (token == maticTokenAddress) {
            priceInInr = maticInInr();
        } else if (token == linkTokenAddress) {
            priceInInr = linkInInr();
        } else {
            priceInInr = 1e18; 
        }
    }

    function getRcoinAmountInPool(address tokenA, address tokenB)
        public
        view
        returns (uint256 rcoinAmount)
    {
        bytes32 pairHash = getPairHash(tokenA, tokenB);
        uint256 reserveA = reserves[pairHash].reserveA;
        uint256 reserveB = reserves[pairHash].reserveB;

        // Ensure reserves are not zero
        require(reserveA > 0 && reserveB > 0, "No liquidity in pool");

        // Get prices for both tokens (in INR)
        uint256 priceAInInr = getTokenPriceInInr(tokenA);
        uint256 priceBInInr = getTokenPriceInInr(tokenB);

        // Ensure prices are valid
        require(priceAInInr > 0 && priceBInInr > 0, "Invalid token price");

        // Calculate the amount of Rcoin in the pool
        rcoinAmount = reserveA.mul(priceAInInr).div(reserveB);
    }
    function updateProtocolWallet(address newProtocolWallet)
        external
        onlyOwner
    {
        protocolWallet = newProtocolWallet;
    }
}

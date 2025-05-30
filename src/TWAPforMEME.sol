// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TWAPforMEME is Ownable {
    // Uniswap V2 Factory 地址
    IUniswapV2Factory public immutable factory;
    // WETH 地址
    address public immutable WETH;
    
    // 价格观察结构体
    struct PriceObservation {
        uint256 timestamp;
        uint256 price0Cumulative;
        uint256 price1Cumulative;
    }
    
    // 存储每个交易对的价格观察数据
    mapping(address => PriceObservation[]) public priceObservations;
    
    // 事件
    event PriceUpdated(address indexed pair, uint256 price0Cumulative, uint256 price1Cumulative, uint256 timestamp);
    
    constructor(address _factory, address _WETH) Ownable() {
        factory = IUniswapV2Factory(_factory);
        WETH = _WETH;
    }
    
    // 更新价格数据
    function updatePrice(address token) external {
        address pair = factory.getPair(token, WETH);
        require(pair != address(0), "Pair does not exist");
        
        IUniswapV2Pair pairContract = IUniswapV2Pair(pair);
        
        // 获取累积价格
        uint256 price0Cumulative = pairContract.price0CumulativeLast();
        uint256 price1Cumulative = pairContract.price1CumulativeLast();
        
        // 存储价格观察数据
        priceObservations[pair].push(PriceObservation({
            timestamp: block.timestamp,
            price0Cumulative: price0Cumulative,
            price1Cumulative: price1Cumulative
        }));
        
        emit PriceUpdated(pair, price0Cumulative, price1Cumulative, block.timestamp);
    }
    
    // 获取 TWAP 价格
    function getTWAP(address token, uint256 period) external view returns (uint256) {
        address pair = factory.getPair(token, WETH);
        require(pair != address(0), "Pair does not exist");
        
        PriceObservation[] storage observations = priceObservations[pair];
        require(observations.length > 1, "Insufficient price data");
        
        // 获取时间窗口内的价格数据
        uint256 endIndex = observations.length - 1;
        uint256 startIndex = 0;
        
        // 找到时间窗口的起始点
        for (uint256 i = endIndex; i > 0; i--) {
            if (observations[i].timestamp - observations[i-1].timestamp >= period) {
                startIndex = i-1;
                break;
            }
        }
        
        // 计算 TWAP
        uint256 timeElapsed = observations[endIndex].timestamp - observations[startIndex].timestamp;
        require(timeElapsed > 0, "Invalid time period");
        
        // 根据代币在交易对中的位置选择正确的价格
        bool isToken0 = IUniswapV2Pair(pair).token0() == token;
        uint256 priceCumulativeDelta = isToken0
            ? observations[endIndex].price1Cumulative - observations[startIndex].price1Cumulative
            : observations[endIndex].price0Cumulative - observations[startIndex].price0Cumulative;
        
        // 计算 TWAP
        return priceCumulativeDelta / timeElapsed;
    }
    
    // 清理旧的价格数据
    function cleanOldObservations(address pair, uint256 maxAge) external onlyOwner {
        PriceObservation[] storage observations = priceObservations[pair];
        uint256 currentTime = block.timestamp;
        
        uint256 i = 0;
        while (i < observations.length && currentTime - observations[i].timestamp > maxAge) {
            i++;
        }
        
        if (i > 0) {
            for (uint256 j = 0; j < observations.length - i; j++) {
                observations[j] = observations[j + i];
            }
            for (uint256 j = 0; j < i; j++) {
                observations.pop();
            }
        }
    }
} 
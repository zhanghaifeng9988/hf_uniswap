// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./MEME_Token.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract MEME_Inscription {
    // 添加owner变量声明
    address public owner;
    
    // immutable 关键字表示这个变量只能在构造函数中设置一次，之后不能修改
    // 存储 MEME 代币的实现合约地址
    address public immutable implementation;

/* IUniswapV2Router02 接口（包含了 IUniswapV2Router01 的功能）主要用于：
添加初始流动性（5%的ETH和对应的Token）
- 添加流动性：
  - addLiquidity ：添加两个ERC20代币的流动性
  - addLiquidityETH ：添加ETH和ERC20代币的流动性
- 移除流动性：
  - removeLiquidity ：移除两个ERC20代币的流动性
  - removeLiquidityETH ：移除ETH和ERC20代币的流动性
- 代币交换：
  - swapExactTokensForTokens ：用确定数量的代币A换取代币B
  - swapExactETHForTokens ：用确定数量的ETH换取代币
  - swapExactTokensForETH ：用确定数量的代币换取ETH
  - 还支持带有转账费用的代币交换（Supporting Fee On Transfer Tokens） */
  
    IUniswapV2Router02 public immutable uniswapV2Router;

/*     IUniswapV2Factory 接口主要用于：通过Factory创建Meme代币和ETH的交易对
- 创建交易对：通过 createPair 函数可以为两个代币创建交易对
- 查询交易对：使用 getPair 函数可以查询两个代币之间的交易对地址
- 管理费用接收地址：通过 feeTo 和 feeToSetter 管理协议费用的接收地址 */
    IUniswapV2Factory public immutable uniswapV2Factory;
    address public immutable WETH;

    // 修改构造函数，接受工厂地址 (IUniswapV2Factory) 和路由器地址 (address) 作为参数
    constructor(IUniswapV2Factory _uniswapV2Factory, address _uniswapV2RouterAddress) {
        implementation = address(new MEME_Token());
        owner = msg.sender;

        uniswapV2Factory = _uniswapV2Factory;
        // 将传入的路由器地址强制转换为 IUniswapV2Router02 接口类型
        uniswapV2Router = IUniswapV2Router02(_uniswapV2RouterAddress);
        WETH = uniswapV2Router.WETH(); // WETH 地址仍然通过路由器获取
    }

    /**
     * @dev MEME 代币的相关信息结构体
     */
    struct MemeInfo {
        uint256 perMint;    // 每次铸造的代币数量
        uint256 price;      // 每个代币的价格（以 wei 为单位）
        address creator;    // 代币创建者地址
    }
    
    // 存储每个代币合约地址对应的 MemeInfo 信息
    mapping(address => MemeInfo) public memeInfos;
    
    // 事件：当新的 MEME 代币被部署时触发
    event MemeDeployed(address indexed token, string symbol, uint256 totalSupply, uint256 perMint, uint256 price);
    // 事件：当 MEME 代币被铸造时触发
    event MemeMinted(address indexed token, address indexed minter, uint256 amount);

    /**
     * @dev 部署新的 MEME 代币
     * @param symbol 代币符号
     * @param totalSupply 代币总供应量
     * @param perMint 每次铸造的数量
     * @param price 每个代币的价格（wei）
     * @return 新部署的代币合约地址
     */
    function deployInscription(
        string memory symbol,
        uint256 totalSupply,
        uint256 perMint,
        uint256 price
    ) external returns (address) {
        // 验证参数的合法性
        require(perMint > 0 && perMint <= totalSupply, "Invalid perMint");
        require(perMint == 10, "perMint must be 10");
        require(price == 0.0001 ether, "Invalid price");  // 每个代币 0.0001 ETH

        // 使用 OpenZeppelin 的 Clones 库创建代理合约
        address proxy = Clones.clone(implementation);
        
        // 初始化代理合约
        MEME_Token(proxy).initialize(symbol, totalSupply, address(this));
        
        // 存储代币相关信息
        memeInfos[proxy] = MemeInfo({
            perMint: perMint,
            price: price,
            creator: msg.sender
        });

        // 触发部署事件
        emit MemeDeployed(proxy, symbol, totalSupply, perMint, price);
        return proxy;
    }

    /**
     * @dev 铸造 MEME 代币
     * @param tokenAddr 要铸造的代币合约地址，是代理合约的地址，
     * 该函数是 payable 的，调用时需要附带足够的 ETH
     */
    function mintInscription(address tokenAddr) external payable {
        MemeInfo storage info = memeInfos[tokenAddr];
        require(info.creator != address(0), "Token not found");
        
        // 获取代币的小数位数
        uint8 decimals = MEME_Token(implementation).decimals();
        uint256 perMintWithDecimals = info.perMint * 10**decimals;
        
        // 检查总供应量
        require(MEME_Token(tokenAddr).minted() + perMintWithDecimals <= MEME_Token(tokenAddr).totalSupply(), "Exceeds total supply");
        
        // 检查铸币费用
        uint256 totalFee = info.price * info.perMint;  // 0.0001 ETH * 10 = 0.001 ETH
        require(msg.value >= totalFee, "Insufficient payment");

        // 计算费用分配
        uint256 platformFee = totalFee / 20;  // 平台收取 5% 费用
        uint256 creatorFee = totalFee - platformFee;  // meme创建者收取 95% 费用

        // 铸造代币给购买者
        MEME_Token(tokenAddr).mint(msg.sender, perMintWithDecimals);

        // 转账费用给创建者
        (bool success2, ) = payable(info.creator).call{value: creatorFee}("");
        require(success2, "Creator fee transfer failed");

        // 检查是否是第一次添加流动性
        address pair = uniswapV2Factory.getPair(tokenAddr, WETH);
        bool isFirstLiquidity = pair == address(0);
        
        if (isFirstLiquidity) {
            // 如果是第一次添加流动性，使用铸币价格计算Token数量
            // 为了保持价格一致，我们需要添加相同数量的代币和ETH
            uint256 tokenAmount = platformFee / info.price;  // 0.00005/0.0001 = 0.5 MEME
            uint256 tokenAmountWithDecimals = tokenAmount * 10**decimals;
            
            // 铸造对应数量的Token给合约
            MEME_Token(tokenAddr).mint(address(this), tokenAmountWithDecimals);
            
            // 授权Router使用Token
            MEME_Token(tokenAddr).approve(address(uniswapV2Router), tokenAmountWithDecimals);
            
            // 添加流动性，确保价格与铸币价格一致
            uniswapV2Router.addLiquidityETH{value: platformFee}(
                tokenAddr,
                tokenAmountWithDecimals,
                0, // 允许滑点
                0, // 允许滑点
                owner, // LP代币接收地址（平台所有者）
                block.timestamp
            );
        } else {
            // 如果不是第一次添加流动性，将平台费用转给owner
            (bool success1, ) = payable(owner).call{value: platformFee}("");
            require(success1, "Platform fee transfer failed");
        }

        emit MemeMinted(tokenAddr, msg.sender, info.perMint);
    }

    /**
     * @dev 添加流动性到Uniswap池子
     * @param tokenAddr MEME代币地址
     * @param tokenAmount 要添加的MEME代币数量
     * @param amountTokenMin 最小添加的代币数量（防止滑点）
     * @param amountETHMin 最小添加的ETH数量（防止滑点）
     */
    function addLiquidity(
        address tokenAddr,
        uint256 tokenAmount,
        uint256 amountTokenMin,
        uint256 amountETHMin
    ) external payable {
        MemeInfo storage info = memeInfos[tokenAddr];
        require(info.creator != address(0), "Token not found");
        require(msg.value > 0, "Must send ETH");
        require(tokenAmount > 0, "Must send tokens");

        // 检查Uniswap上的价格
        address pair = uniswapV2Factory.getPair(tokenAddr, WETH);
        require(pair != address(0), "Liquidity pair not exists");

        // 转移代币到合约
        require(MEME_Token(tokenAddr).transferFrom(msg.sender, address(this), tokenAmount), "Token transfer failed");

        // 授权Router使用代币
        MEME_Token(tokenAddr).approve(address(uniswapV2Router), tokenAmount);

        // 添加流动性
        uniswapV2Router.addLiquidityETH{value: msg.value}(
            tokenAddr,
            tokenAmount,
            amountTokenMin,
            amountETHMin,
            msg.sender, // LP代币给添加流动性的用户
            block.timestamp
        );
    }

    /**
     * @dev 在Uniswap上购买MEME代币
     * @param tokenAddr MEME代币地址
     * @param amountOutMin 最小获得的代币数量（防止滑点）
     */
    function buyMeme(address tokenAddr, uint256 amountOutMin) external payable {
        MemeInfo storage info = memeInfos[tokenAddr];
        require(info.creator != address(0), "Token not found");
        require(msg.value > 0, "Must send ETH");

        // 检查Uniswap上的价格
        address pair = uniswapV2Factory.getPair(tokenAddr, WETH);
        require(pair != address(0), "Liquidity pair not exists");

        // 创建交易路径
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = tokenAddr;

        // 计算平台费用（5%）
        uint256 platformFee = msg.value / 20;
        uint256 swapAmount = msg.value - platformFee;

        // 使用剩余的ETH在Uniswap上购买代币
        uniswapV2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{
            value: swapAmount
        }(
            amountOutMin,
            path,
            msg.sender,
            block.timestamp
        );

        // 将平台费用转给owner
        (bool success, ) = payable(owner).call{value: platformFee}("");
        require(success, "Platform fee transfer failed");
    }
}
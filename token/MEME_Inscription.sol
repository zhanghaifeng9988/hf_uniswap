// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./MEME_Token.sol";
import "../v2/interfaces/IUniswapV2Router02.sol";
import "../v2/interfaces/IUniswapV2Factory.sol";

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

    constructor() {
        implementation = address(new MEME_Token());
        owner = msg.sender;
        
        // 设置Uniswap V2地址（这里使用Sepolia测试网地址）
        uniswapV2Router = IUniswapV2Router02(0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3);
        uniswapV2Factory = IUniswapV2Factory(0xF62c03E08ada871A0bEb309762E260a7a6a880E6);
        WETH = uniswapV2Router.WETH();
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

    // /**
    //  * @dev 构造函数
    //  * 部署一个基础的 MEME_Token 实现合约，作为所有代理合约的模板
    //  */
    // constructor() {
    //     implementation = address(new MEME_Token());
    //     owner = msg.sender;
    // }

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
        require(price == 10000, "Invalid price");

        // 使用最小代理模式部署新的代币合约
        address proxy = createClone(implementation);
        // 初始化代理合约 ，address(this) 是 MEME_Inscription 工厂合约的地址
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
        require(MEME_Token(tokenAddr).minted() + info.perMint <= MEME_Token(tokenAddr).totalSupply(), "Exceeds total supply");
        require(msg.value >= info.price * info.perMint, "Insufficient payment");

        // 计算费用分配
        uint256 totalFee = info.price * info.perMint;
        uint256 platformFee = totalFee / 20;  // 平台收取 5% 费用
        uint256 creatorFee = totalFee - platformFee;

        // 铸造代币给购买者  msg.sender是用户得钱包地址，当前调用这个mintInscription函数
        MEME_Token(tokenAddr).mint(msg.sender, info.perMint);

        // 转账费用给平台和创建者
        (bool success1, ) = payable(owner).call{value: platformFee}("");
        require(success1, "Platform fee transfer failed");
        (bool success2, ) = payable(info.creator).call{value: creatorFee}("");
        require(success2, "Creator fee transfer failed");

        emit MemeMinted(tokenAddr, msg.sender, info.perMint);
    }

    /**
     * @dev 创建最小代理合约
     * @param target 目标实现合约地址
     * @return result 新创建的代理合约地址
     * 使用内联汇编实现 EIP-1167 最小代理模式
     */
    function createClone(address target) internal returns (address result) {
        bytes20 targetBytes = bytes20(target);
        assembly {
            // 加载空闲内存指针
            let clone := mload(0x40)
            // 存储代理合约的字节码
            mstore(clone, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            // 存储目标合约地址
            mstore(add(clone, 0x14), targetBytes)
            // 存储剩余的代理合约字节码
            mstore(add(clone, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            // 创建新的合约
            result := create(0, clone, 0x37)
        }
    }

    // 添加buyMeme函数
    function buyMeme(address tokenAddr, uint256 amountOutMin) external payable {
        MemeInfo storage info = memeInfos[tokenAddr];
        require(info.creator != address(0), "Token not found");

        // 计算平台费用（5%）
        uint256 platformFee = msg.value / 20;
        uint256 swapAmount = msg.value - platformFee;

        // 检查Uniswap上的价格
        address pair = uniswapV2Factory.getPair(tokenAddr, WETH);
        require(pair != address(0), "Liquidity pair not exists");

        // 在Uniswap上购买代币
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = tokenAddr;

        // 使用剩余的ETH在Uniswap上购买代币
        uniswapV2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{
            value: swapAmount
        }(
            amountOutMin,
            path,
            msg.sender,
            block.timestamp
        );

        // 将平台费用的ETH和对应数量的代币添加到流动性池
        uint256 tokenAmount = (MEME_Token(tokenAddr).balanceOf(address(this)) * platformFee) / swapAmount;
        MEME_Token(tokenAddr).approve(address(uniswapV2Router), tokenAmount);

        // 添加流动性
        uniswapV2Router.addLiquidityETH{
            value: platformFee
        }(
            tokenAddr,
            tokenAmount,
            0, // 允许滑点
            0, // 允许滑点
            owner, // LP代币接收地址（平台所有者）
            block.timestamp
        );
    }
}
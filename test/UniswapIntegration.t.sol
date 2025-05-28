// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "lib/v2-periphery/contracts/libraries/UniswapV2Library.sol";
import "lib/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "lib/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
// import "lib/v2-core/contracts/interfaces/IERC20.sol"; // 移除重复的 IERC20 导入
import "../token/MEME_Inscription.sol";
import "../token/MEME_Token.sol";
import "lib/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

// 添加 UQ112x112 库
library UQ112x112 {
    uint224 constant Q112 = 2**112;

    function encode(uint112 y) internal pure returns (uint224 z) {
        z = uint224(y) * Q112;
    }

    function uqdiv(uint224 x, uint112 y) internal pure returns (uint224 z) {
        z = x / uint224(y);
    }
}

// 添加 Math 库
library Math {
    function min(uint x, uint y) internal pure returns (uint z) {
        z = x < y ? x : y;
    }

    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}

// 模拟 ERC20 代币
contract MockERC20 is IERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    uint256 public minted;
    mapping(address => uint256) public _balances;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
        decimals = 18;
    }

    // 添加 receive 函数以接收 ETH
    receive() external payable {}

    function mint(address to, uint256 amount) public {
        _balances[to] += amount;
        totalSupply += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(_balances[msg.sender] >= amount, "Insufficient balance");
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        require(_balances[from] >= amount, "Insufficient balance");
        allowance[from][msg.sender] -= amount;
        _balances[from] -= amount;
        _balances[to] += amount;
        return true;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }
}

// 模拟 Uniswap V2 Pair
contract MockUniswapV2Pair is IUniswapV2Pair {
    address public override token0;
    address public override token1;
    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;
    uint private price0CumulativeLastValue;
    uint private price1CumulativeLastValue;
    uint private kLastValue;
    address private _factory;
    bool private initialized;
    uint private totalSupplyValue;

    uint private constant MINIMUM_LIQUIDITY_VALUE = 1000;

    // 新增 LP token 余额映射
    mapping(address => uint) public override balanceOf;
    
    // 添加 allowance 映射
    mapping(address => mapping(address => uint)) public override allowance;

    constructor(address _token0, address _token1) {
        token0 = _token0;
        token1 = _token1;
        _factory = msg.sender;
    }

    function setReserves(uint112 _reserve0, uint112 _reserve1) external {
        reserve0 = _reserve0;
        reserve1 = _reserve1;
        blockTimestampLast = uint32(block.timestamp);
        kLastValue = uint(reserve0) * uint(reserve1);
    }

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function price0CumulativeLast() external view override returns (uint) {
        return price0CumulativeLastValue;
    }

    function price1CumulativeLast() external view override returns (uint) {
        return price1CumulativeLastValue;
    }

    function MINIMUM_LIQUIDITY() public pure override returns (uint) {
        return MINIMUM_LIQUIDITY_VALUE;
    }

    function kLast() external view override returns (uint) {
        return kLastValue;
    }

    function factory() external view override returns (address) {
        return _factory;
    }

    function sync() external override {
        // 更新价格累积值
        uint32 timeElapsed = uint32(block.timestamp) - blockTimestampLast;
        if (timeElapsed > 0 && reserve0 != 0 && reserve1 != 0) {
            uint224 price0 = UQ112x112.encode(reserve1);
            uint224 price1 = UQ112x112.encode(reserve0);
            price0CumulativeLastValue += uint(UQ112x112.uqdiv(price0, reserve0)) * timeElapsed;
            price1CumulativeLastValue += uint(UQ112x112.uqdiv(price1, reserve1)) * timeElapsed;
        }
        blockTimestampLast = uint32(block.timestamp);
    }

    function initialize(address _token0, address _token1) external override {
        require(!initialized, "UniswapV2: ALREADY_INITIALIZED");
        require(_token0 != address(0) && _token1 != address(0), "UniswapV2: ZERO_ADDRESS");
        require(_token0 != _token1, "UniswapV2: IDENTICAL_ADDRESSES");
        token0 = _token0;
        token1 = _token1;
        initialized = true;
    }

    function mint(address to) external override returns (uint liquidity) {
        require(initialized, "UniswapV2: NOT_INITIALIZED");
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        
        uint _totalSupply = totalSupplyValue;
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(balance0 * balance1) - MINIMUM_LIQUIDITY_VALUE;
            require(liquidity > 0, "UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED");
            totalSupplyValue = MINIMUM_LIQUIDITY_VALUE;
            balanceOf[address(0)] = MINIMUM_LIQUIDITY_VALUE; // 锁定最小流动性
        } else {
            liquidity = Math.min(
                (balance0 * _totalSupply) / reserve0,
                (balance1 * _totalSupply) / reserve1
            );
            require(liquidity > 0, "UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED");
        }
        // 更新 LP token 余额
        balanceOf[to] += liquidity;
        totalSupplyValue += liquidity;

        // 更新储备量
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = uint32(block.timestamp);

        return liquidity;
    }

    function burn(address to) external override returns (uint amount0, uint amount1) {
        require(initialized, "UniswapV2: NOT_INITIALIZED");
        (uint112 _reserve0, uint112 _reserve1,) = this.getReserves();
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        uint liquidity = totalSupplyValue;

        uint _totalSupply = totalSupplyValue;
        amount0 = (liquidity * balance0) / _totalSupply;
        amount1 = (liquidity * balance1) / _totalSupply;
        require(amount0 > 0 && amount1 > 0, "UniswapV2: INSUFFICIENT_LIQUIDITY_BURNED");
        totalSupplyValue = _totalSupply - liquidity;
        return (amount0, amount1);
    }

    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external override {
        require(initialized, "UniswapV2: NOT_INITIALIZED");
        require(amount0Out > 0 || amount1Out > 0, "UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT");
        (uint112 _reserve0, uint112 _reserve1,) = this.getReserves();
        require(amount0Out < _reserve0 && amount1Out < _reserve1, "UniswapV2: INSUFFICIENT_LIQUIDITY");

        uint balance0;
        uint balance1;
        {
            require(to != token0 && to != token1, "UniswapV2: INVALID_TO");
            if (amount0Out > 0) {
                // 给 Router 授权
                IERC20(token0).approve(msg.sender, amount0Out);
                IERC20(token0).transfer(to, amount0Out);
            }
            if (amount1Out > 0) {
                // 给 Router 授权
                IERC20(token1).approve(msg.sender, amount1Out);
                IERC20(token1).transfer(to, amount1Out);
            }
            balance0 = IERC20(token0).balanceOf(address(this));
            balance1 = IERC20(token1).balanceOf(address(this));
        }
        uint amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, "UniswapV2: INSUFFICIENT_INPUT_AMOUNT");
        {
            // 计算新的储备量
            uint newReserve0 = _reserve0 + amount0In - amount0Out;
            uint newReserve1 = _reserve1 + amount1In - amount1Out;
            
            // 检查 k 值
            require(newReserve0 * newReserve1 >= uint(_reserve0) * uint(_reserve1), "UniswapV2: K");
            
            // 更新储备量
            reserve0 = uint112(newReserve0);
            reserve1 = uint112(newReserve1);
        }
        blockTimestampLast = uint32(block.timestamp);
    }

    function skim(address to) external override {
        require(initialized, "UniswapV2: NOT_INITIALIZED");
        (uint112 _reserve0, uint112 _reserve1,) = this.getReserves();
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        if (balance0 > _reserve0) {
            IERC20(token0).transfer(to, balance0 - _reserve0);
        }
        if (balance1 > _reserve1) {
            IERC20(token1).transfer(to, balance1 - _reserve1);
        }
    }

    // 实现其他必需的接口方法
    function name() external pure returns (string memory) { return "Uniswap V2"; }
    function symbol() external pure returns (string memory) { return "UNI-V2"; }
    function decimals() external pure returns (uint8) { return 18; }
    function totalSupply() external view override returns (uint) {
        return totalSupplyValue;
    }
    function approve(address spender, uint amount) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
    function transfer(address to, uint amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient LP balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
    function transferFrom(address from, address to, uint amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient LP balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
    function DOMAIN_SEPARATOR() external pure returns (bytes32) { return bytes32(0); }
    function PERMIT_TYPEHASH() external pure returns (bytes32) { return bytes32(0); }
    function nonces(address) external pure returns (uint) { return 0; }
    function permit(address, address, uint, uint, uint8, bytes32, bytes32) external pure {}
}

// 模拟 Uniswap V2 Factory
contract MockUniswapV2Factory is IUniswapV2Factory {
    mapping(address => mapping(address => address)) public pairs;
    address public immutable WETH;
    address public feeTo;
    address public feeToSetter;
    address[] public allPairsArray;

    constructor(address _WETH) {
        WETH = _WETH;
        feeToSetter = msg.sender;
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, "UniswapV2: IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "UniswapV2: ZERO_ADDRESS");
        require(pairs[token0][token1] == address(0), "UniswapV2: PAIR_EXISTS");

        MockUniswapV2Pair newPair = new MockUniswapV2Pair(token0, token1);
        pair = address(newPair);
        pairs[token0][token1] = pair;
        pairs[token1][token0] = pair;
        allPairsArray.push(pair);
        return pair;
    }

    function getPair(address tokenA, address tokenB) external view override returns (address pair) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return pairs[token0][token1];
    }

    function allPairs(uint index) external view returns (address pair) {
        return allPairsArray[index];
    }

    function allPairsLength() external view returns (uint) {
        return allPairsArray.length;
    }

    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, "UniswapV2: FORBIDDEN");
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, "UniswapV2: FORBIDDEN");
        feeToSetter = _feeToSetter;
    }
}

// 模拟 Uniswap V2 Router
// 移除接口继承并确保所有 override 关键字被移除
contract MockUniswapV2Router {
    IUniswapV2Factory immutable _factory;
    address payable immutable _WETH;
    address public memeInscriptionAddress; // 添加一个变量来存储 MEME_Inscription 地址

    // 添加 ensure 修饰符
    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, "UniswapV2Router: EXPIRED");
        _;
    }

    constructor(IUniswapV2Factory factory_, address WETH_, address _memeInscriptionAddress) {
        _factory = factory_;
        _WETH = payable(WETH_);
        memeInscriptionAddress = _memeInscriptionAddress;
    }

    // 添加一个函数来更新 memeInscriptionAddress
    function setMemeInscriptionAddress(address _memeInscriptionAddress) external {
        memeInscriptionAddress = _memeInscriptionAddress;
    }

    // 实现 MEME_Inscription 需要调用的函数，移除 override
    function WETH() external view returns (address) {
        return address(_WETH);
    }

    function factory() external view returns (address) {
        return address(_factory);
    }

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable ensure(deadline) {
        require(path.length >= 2, "UniswapV2Router: INVALID_PATH");
        require(path[0] == _WETH, "UniswapV2Router: INVALID_PATH");
        
        uint amountIn = msg.value;
        
        // 获取 Pair 合约
        IUniswapV2Pair pair = IUniswapV2Pair(_factory.getPair(path[0], path[1]));
        require(address(pair) != address(0), "UniswapV2Router: NO_PAIR");
        
        // 获取储备量
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint amountOut;
        
        // 计算输出金额
        if (pair.token0() == path[0]) {
            amountOut = (amountIn * reserve1) / (reserve0 + amountIn);
        } else {
            amountOut = (amountIn * reserve0) / (reserve1 + amountIn);
        }
        
        require(amountOut >= amountOutMin, "UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
        
        // 将 ETH 转换为 WETH
        MockERC20(_WETH).mint(address(this), amountIn);
        
        // 将 WETH 转给 Pair 合约
        IERC20(_WETH).transfer(address(pair), amountIn);
        
        // 从 Pair 合约获取代币
        pair.swap(0, amountOut, address(this), "");
        
        // 直接使用 transfer 而不是 transferFrom
        IERC20(path[1]).transfer(to, amountOut);
    }

    function addLiquidityETH(
        address token,
        uint tokenAmount,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity) {
        require(token != _WETH, "MockRouter: INVALID_TOKEN");
        
        IUniswapV2Pair pair = IUniswapV2Pair(_factory.getPair(token, _WETH));
        require(address(pair) != address(0), "MockRouter: NO_PAIR");

        // 将 ETH 转换为 WETH
        MockERC20(_WETH).mint(address(this), msg.value);
        
        // 转 WETH 到 Pair
        IERC20(_WETH).transfer(address(pair), msg.value);
        IERC20(token).transferFrom(msg.sender, address(pair), tokenAmount);

        liquidity = pair.mint(to);

        amountToken = tokenAmount;
        amountETH = msg.value;
    }

    // 实现 UniswapV2Library 可能间接调用的函数，移除 override
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts) {
        amounts = UniswapV2Library.getAmountsOut(address(_factory), amountIn, path);
    }

    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts) {
        amounts = UniswapV2Library.getAmountsIn(address(_factory), amountOut, path);
    }

    function quote(
        uint amountA,
        uint reserveA,
        uint reserveB
    ) external pure returns (uint amountB) {
        return UniswapV2Library.quote(amountA, reserveA, reserveB);
    }

    // 实现 IUniswapV2Router02 接口中的其他函数，可以使用 revert("MockRouter: NOT_IMPLEMENTED"), 移除 override
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity) {
        revert("MockRouter: NOT_IMPLEMENTED");
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB) {
        revert("MockRouter: NOT_IMPLEMENTED");
    }

    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH) {
        revert("MockRouter: NOT_IMPLEMENTED");
    }

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint amountA, uint amountB) {
        revert("MockRouter: NOT_IMPLEMENTED");
    }

    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint amountToken, uint amountETH) {
        revert("MockRouter: NOT_IMPLEMENTED");
    }

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts) {
        revert("MockRouter: NOT_IMPLEMENTED");
    }

    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts) {
        revert("MockRouter: NOT_IMPLEMENTED");
    }

    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts) {
        revert("MockRouter: NOT_IMPLEMENTED");
    }

    function swapTokensForExactETH(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts) {
        revert("MockRouter: NOT_IMPLEMENTED");
    }

    function swapExactTokensForETH(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts) {
        revert("MockRouter: NOT_IMPLEMENTED");
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external {
        revert("MockRouter: NOT_IMPLEMENTED");
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external {
        revert("MockRouter: NOT_IMPLEMENTED");
    }

    function swapETHForExactTokens(
        uint amountOut,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts) {
        revert("MockRouter: NOT_IMPLEMENTED");
    }

    function swapTokensForExactETHSupportingFeeOnTransferTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts) {
        revert("MockRouter: NOT_IMPLEMENTED");
    }

    function swapETHForExactTokensSupportingFeeOnTransferTokens(
        uint amountOut,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts) {
        revert("MockRouter: NOT_IMPLEMENTED");
    }

    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountToken) {
        revert("MockRouter: NOT_IMPLEMENTED");
    }

    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint amountToken) {
        revert("MockRouter: NOT_IMPLEMENTED");
    }
}

contract UniswapIntegrationTest is Test {
    MockUniswapV2Factory factory;
    MockUniswapV2Router router;
    MockERC20 weth;
    MockERC20 meme;
    MockERC20 usdc;
    MockUniswapV2Pair pair;
    MEME_Inscription memeInscription;
    address memeToken;
    address user;
    address tokenAddr;
    MockERC20 mockToken1;
    MockERC20 mockToken2;
    MockUniswapV2Factory mockFactory;
    MockUniswapV2Router mockRouter;

    // 在这里声明 MemeMinted 事件，使其在测试合约中可见
    event MemeMinted(address indexed token, address indexed minter, uint256 amount);

    // 添加 receive 函数，使合约能够接收 ETH
    receive() external payable {}

    function setUp() public {
        // 设置测试用户
        user = makeAddr("user");
        vm.deal(user, 0.1 ether);
        
        // 部署模拟合约
        mockToken1 = new MockERC20("Token1", "TK1");
        mockToken2 = new MockERC20("Token2", "TK2");
        mockFactory = new MockUniswapV2Factory(address(mockToken1)); // 使用 mockToken1 作为 WETH
        mockRouter = new MockUniswapV2Router(IUniswapV2Factory(address(mockFactory)), address(mockToken1), address(0));
        
        // 部署 MEME_Inscription 合约
        memeInscription = new MEME_Inscription(IUniswapV2Factory(address(mockFactory)), address(mockRouter));
        
        // 设置路由器的 MEME_Inscription 地址
        mockRouter.setMemeInscriptionAddress(address(memeInscription));
        
        // 部署测试代币，总供应量设为 1000，每个代币 0.0001 ETH
        tokenAddr = memeInscription.deployInscription("TEST", 1000, 10, 0.0001 ether);

        // 创建交易对
        pair = MockUniswapV2Pair(mockFactory.createPair(address(mockToken1), tokenAddr));
        pair.initialize(address(mockToken1), tokenAddr);

        // 给 mockToken1 (WETH) 充值
        mockToken1.mint(address(mockRouter), 100 ether);  // 给路由器充值
        mockToken1.mint(address(this), 100 ether);        // 给测试合约充值
    }

    function testBasicFlow() public {
        // 第一次铸币和上架流动性
        // 给测试合约一些 ETH
        vm.deal(address(this), 0.2 ether);  // 增加 ETH 数量
        
        // 第一次铸币（10个代币，每个0.0001 ETH，总共0.001 ETH）
        memeInscription.mintInscription{value: 0.001 ether}(tokenAddr);
        
        // 验证第一次铸币结果
        uint256 balance = MEME_Token(tokenAddr).balanceOf(address(this));
        assertEq(balance, 10 * 10**18, "First minting failed");
        
        // 第一次上架流动性：使用铸币价格 0.0001 ETH/MEME
        uint256 firstTokenAmount = 10 * 10**18;  // 10 个代币
        uint256 firstEthAmount = 0.001 ether;    // 0.001 ETH (10 * 0.0001 ETH)
        
        MEME_Token(tokenAddr).approve(address(memeInscription), firstTokenAmount);
        memeInscription.addLiquidity{value: firstEthAmount}(tokenAddr, firstTokenAmount, 0, 0);
        
        // 验证第一次流动性池
        address liquidityPair = mockFactory.getPair(address(mockToken1), tokenAddr);
        assertTrue(liquidityPair != address(0), "First liquidity pair not created");
        
        // 验证第一次添加流动性后的价格
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(liquidityPair).getReserves();
        uint256 initialPrice;
        if (IUniswapV2Pair(liquidityPair).token0() == address(mockToken1)) {
            initialPrice = (uint256(reserve0) * 1e18) / uint256(reserve1);  // ETH/MEME 价格
        } else {
            initialPrice = (uint256(reserve1) * 1e18) / uint256(reserve0);  // ETH/MEME 价格
        }
        assertEq(initialPrice, 0.0001 ether, "Initial price should be 0.0001 ETH/MEME");
        
        // 第二次铸币和上架流动性
        // 给测试合约更多 ETH
        vm.deal(address(this), 0.15 ether);  // 增加 ETH 数量
        
        // 第二次铸币（10个代币，每个0.0001 ETH，总共0.001 ETH）
        memeInscription.mintInscription{value: 0.001 ether}(tokenAddr);
        
        // 验证第二次铸币结果
        balance = MEME_Token(tokenAddr).balanceOf(address(this));
        assertEq(balance, 10 * 10**18, "Second minting failed");
        
        // 第二次上架流动性：10个代币，每个0.00001 ETH
        uint256 secondTokenAmount = 10 * 10**18;  // 10 个代币
        uint256 secondEthAmount = 0.0001 ether;   // 0.0001 ETH
        
        MEME_Token(tokenAddr).approve(address(memeInscription), secondTokenAmount);
        memeInscription.addLiquidity{value: secondEthAmount}(tokenAddr, secondTokenAmount, 0, 0);
        
        // 验证第二次流动性池
        liquidityPair = mockFactory.getPair(address(mockToken1), tokenAddr);
        assertTrue(liquidityPair != address(0), "Second liquidity pair not created");
        
        // 验证第二次添加流动性后的价格
        (reserve0, reserve1,) = IUniswapV2Pair(liquidityPair).getReserves();
        uint256 finalPrice;
        if (IUniswapV2Pair(liquidityPair).token0() == address(mockToken1)) {
            finalPrice = (uint256(reserve0) * 1e18) / uint256(reserve1);  // ETH/MEME 价格
        } else {
            finalPrice = (uint256(reserve1) * 1e18) / uint256(reserve0);  // ETH/MEME 价格
        }
        assertEq(finalPrice, 0.000055 ether, "Final price should be 0.000055 ETH/MEME");
        
        // 验证最终余额
        uint256 finalBalance = MEME_Token(tokenAddr).balanceOf(address(this));
        assertEq(finalBalance, 0, "Should have no tokens left after adding liquidity");

        // 用户购买代币
        vm.prank(user);
        memeInscription.buyMeme{value: 0.05 ether}(tokenAddr, 0);  // 使用 0.05 ETH 购买
        
        // 验证用户收到代币
        uint256 userBalance = MEME_Token(tokenAddr).balanceOf(user);
        assertTrue(userBalance > 0, "User did not receive tokens after buying");
    }
}
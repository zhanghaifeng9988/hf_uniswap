// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract DeflationaryToken is ERC20, ReentrancyGuard {
    using SafeMath for uint256;

    // 常量定义
    uint256 public constant INITIAL_SUPPLY = 100000000 * 10**18; // 1亿
    uint256 public constant PRICE_TARGET = 1 * 10**18; // 1港币
    uint256 public constant PRICE_DEVIATION = 5 * 10**15; // 0.5%
    uint256 public constant REBASE_INTERVAL = 1 hours;
    uint256 public constant YEARLY_DEFLATION_RATE = 100; // 1% (100 basis points)

    // 状态变量
    uint256 public lastRebaseTimestamp;
    uint256 public deployTimestamp;
    uint256 public rebaseIndex;
    mapping(address => uint256) public rawBalances;
    address public oracle;

    // 事件
    event Rebase(uint256 timestamp, uint256 newIndex);
    event BalanceUpdated(address indexed user, uint256 newBalance);
    event DeflationRateChanged(uint256 newRate);

    // 修饰符
    modifier onlyOracle() {
        require(msg.sender == oracle, "Only oracle can call this function");
        _;
    }

    constructor(address _oracle) ERC20("hf_stableCoin", "HFSC") {
        require(_oracle != address(0), "Invalid oracle address");
        oracle = _oracle;
        deployTimestamp = block.timestamp;
        lastRebaseTimestamp = block.timestamp;
        rebaseIndex = 10**18; // 初始rebase系数为1
        
        // 初始化原始余额
        rawBalances[msg.sender] = INITIAL_SUPPLY;
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    // 重写balanceOf函数
    function balanceOf(address account) public view override returns (uint256) {
        return rawBalances[account].mul(rebaseIndex).div(10**18);
    }

    // 重写transfer函数
    function transfer(address to, uint256 amount) public override returns (bool) {
        require(amount > 0, "Transfer amount must be greater than 0");
        require(rawBalances[msg.sender] >= amount, "Insufficient balance");
        
        uint256 rawAmount = amount.mul(10**18).div(rebaseIndex);
        rawBalances[msg.sender] = rawBalances[msg.sender].sub(rawAmount);
        rawBalances[to] = rawBalances[to].add(rawAmount);
        
        emit BalanceUpdated(msg.sender, balanceOf(msg.sender));
        emit BalanceUpdated(to, balanceOf(to));
        
        return super.transfer(to, amount);
    }

    // rebase函数
    function rebase() external onlyOracle nonReentrant {
        require(block.timestamp >= lastRebaseTimestamp.add(REBASE_INTERVAL), "Too early to rebase");
        
        // 计算年度通缩
        uint256 yearsPassed = block.timestamp.sub(deployTimestamp).div(365 days);
        uint256 deflationRate = YEARLY_DEFLATION_RATE.mul(yearsPassed);
        
        // 计算新指数
        uint256 newIndex;
        if (yearsPassed == 0) {
            // 如果时间不足一年，使用固定1%的减少率
            newIndex = rebaseIndex.mul(99).div(100);
        } else {
            // 如果时间超过一年，使用年度通缩率
            newIndex = rebaseIndex.mul(10000 - deflationRate).div(10000);
        }
        
        // 确保新指数小于当前指数
        require(newIndex < rebaseIndex, "New index must be less than current index");
        
        rebaseIndex = newIndex;
        lastRebaseTimestamp = block.timestamp;
        emit Rebase(block.timestamp, rebaseIndex);
    }

    // 设置预言机地址
    function setOracle(address _oracle) external {
        require(msg.sender == oracle, "Only current oracle can change oracle");
        require(_oracle != address(0), "Invalid oracle address");
        oracle = _oracle;
    }
} 
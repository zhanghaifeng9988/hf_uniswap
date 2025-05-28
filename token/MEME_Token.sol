// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/Address.sol";

// 定义 MemeToken 合约
contract MEME_Token is Context, IERC20, IERC20Metadata {
    using Address for address;

    // 状态变量 - 按照存储槽顺序排列
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    uint256 private _minted;
    string private _name;
    string private _symbol;
    uint8 public constant decimals = 18;
    address public inscriptionFactory;
    address public owner;
    bool public initialized;

    // 定义事件
    event MintCalled(address indexed caller, address indexed owner, address indexed to, uint256 amount);

    // 构造函数
    constructor() {
        // 在构造函数中初始化状态变量
        _name = "";
        _symbol = "";
        _totalSupply = 0;
        _minted = 0;
        inscriptionFactory = address(0);
        owner = address(0);
        initialized = false;
    }

    // 初始化函数，由铭文工厂合约调用一次
    function initialize(
        string memory symbol_,
        uint256 totalSupply_,
        address owner_
    ) public {
        // 确保只被初始化一次
        require(!initialized, "Already initialized");
        initialized = true;

        // 设置代币信息
        _name = string(abi.encodePacked("MEME ", symbol_));
        _symbol = symbol_;
        _totalSupply = totalSupply_ * 10**decimals; // 转换为带18位小数的数量
        owner = owner_;
        // 设置 inscriptionFactory 为调用 initialize 的地址 (即 MEME_Inscription 合约)
        inscriptionFactory = _msgSender();

        // 初始时没有代币被铸造
        _minted = 0;
    }

    // ERC20 标准函数
    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), to, amount);
        return true;
    }

    function allowance(address _owner, address spender) public view override returns (uint256) {
        return _allowances[_owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        require(_allowances[from][_msgSender()] >= amount, "ERC20: insufficient allowance");
        require(_balances[from] >= amount, "ERC20: insufficient balance");
        
        _transfer(from, to, amount);
        _approve(from, _msgSender(), _allowances[from][_msgSender()] - amount);
        return true;
    }

    // 内部函数，处理代币转移逻辑
    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        _balances[from] = _balances[from] - amount;
        _balances[to] = _balances[to] + amount;
        emit Transfer(from, to, amount);
    }

    // 内部函数，处理代币授权逻辑
    function _approve(address _owner, address spender, uint256 amount) internal {
        require(_owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[_owner][spender] = amount;
        emit Approval(_owner, spender, amount);
    }

    // 铸造代币
    function mint(address to, uint256 amount) public {
        // 确保只有铭文工厂合约可以调用 mint
        require(_msgSender() == inscriptionFactory, "Only inscription factory can mint");
        
        // 检查是否超过总供应量上限
        require(_minted + amount <= _totalSupply, "Exceeds total supply");

        // 更新已铸造数量
        _minted = _minted + amount;
        // 增加接收者余额
        _balances[to] = _balances[to] + amount;

        emit MintCalled(_msgSender(), owner, to, amount);
        // 触发 Transfer 事件，表示代币从"无"（零地址）转移到接收者
        emit Transfer(address(0), to, amount);
    }

    // 返回已铸造的代币数量
    function minted() public view returns (uint256) {
        return _minted;
    }
} 
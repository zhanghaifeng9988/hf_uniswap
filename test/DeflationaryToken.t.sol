// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/DeflationaryToken.sol";

contract DeflationaryTokenTest is Test {
    DeflationaryToken public token;
    address public owner;
    address public oracle;
    address public user1;
    address public user2;
    address public user3;
    address public user4;
    address public user5;

    function setUp() public {
        // 设置测试账户
        owner = address(this);
        oracle = address(0x1);
        user1 = address(0x2);
        user2 = address(0x3);
        user3 = address(0x4);
        user4 = address(0x5);
        user5 = address(0x6);

        // 部署合约
        token = new DeflationaryToken(oracle);
    }

    function testInitialParameters() public {
        assertEq(token.name(), "hf_stableCoin");
        assertEq(token.symbol(), "HFSC");
        assertEq(token.oracle(), oracle);
        assertEq(token.rebaseIndex(), 1e18);
    }

    function testInitialSupply() public {
        assertEq(token.balanceOf(owner), token.INITIAL_SUPPLY());
    }

    function testTransfer() public {
        uint256 transferAmount = 1000 * 1e18;
        
        // 从owner转账给5个用户
        token.transfer(user1, transferAmount);
        token.transfer(user2, transferAmount);
        token.transfer(user3, transferAmount);
        token.transfer(user4, transferAmount);
        token.transfer(user5, transferAmount);

        // 验证余额
        assertEq(token.balanceOf(user1), transferAmount);
        assertEq(token.balanceOf(user2), transferAmount);
        assertEq(token.balanceOf(user3), transferAmount);
        assertEq(token.balanceOf(user4), transferAmount);
        assertEq(token.balanceOf(user5), transferAmount);
    }

    function testRebasePermissions() public {
        // 测试非预言机账户调用rebase
        vm.prank(user1);
        vm.expectRevert("Only oracle can call this function");
        token.rebase();
    }

    function testRebaseTimeInterval() public {
        // 测试rebase时间间隔
        vm.prank(oracle);
        vm.expectRevert("Too early to rebase");
        token.rebase();
    }

    function testRebaseExecution() public {
        uint256 transferAmount = 1000 * 1e18;
        token.transfer(user1, transferAmount);

        // 增加时间
        vm.warp(block.timestamp + 1 hours + 1);

        // 执行rebase
        vm.prank(oracle);
        token.rebase();

        // 验证rebase后的余额
        uint256 newBalance = token.balanceOf(user1);
        assertTrue(newBalance < transferAmount, "Balance should decrease after rebase");
    }

    function testYearlyDeflation() public {
        uint256 transferAmount = 1000 * 1e18;
        token.transfer(user1, transferAmount);

        // 增加一年时间
        vm.warp(block.timestamp + 365 days);

        // 执行rebase
        vm.prank(oracle);
        token.rebase();

        // 验证余额是否减少了1%
        uint256 newBalance = token.balanceOf(user1);
        uint256 expectedBalance = (transferAmount * 99) / 100;
        assertEq(newBalance, expectedBalance);
    }

    function testMultipleRebases() public {
        uint256 transferAmount = 1000 * 1e18;
        token.transfer(user1, transferAmount);

        uint256 currentTime = block.timestamp;
        // 执行多次rebase
        for(uint i = 0; i < 5; i++) {
            currentTime += 1 hours + 1;
            vm.warp(currentTime);
            vm.prank(oracle);
            token.rebase();
        }

        // 验证余额持续减少
        uint256 newBalance = token.balanceOf(user1);
        assertTrue(newBalance < transferAmount, "Balance should decrease after multiple rebases");
    }
} 
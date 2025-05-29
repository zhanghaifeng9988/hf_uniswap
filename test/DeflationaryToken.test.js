const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("DeflationaryToken", function () {
    let token;
    let owner;
    let oracle;
    let user1;
    let user2;
    let user3;
    let user4;
    let user5;

    beforeEach(async function () {
        // 获取测试账户
        [owner, oracle, user1, user2, user3, user4, user5] = await ethers.getSigners();

        // 部署合约
        const DeflationaryToken = await ethers.getContractFactory("DeflationaryToken");
        token = await DeflationaryToken.deploy(oracle.address);
        await token.deployed();
    });

    describe("部署测试", function () {
        it("应该正确设置初始参数", async function () {
            expect(await token.name()).to.equal("hf_stableCoin");
            expect(await token.symbol()).to.equal("HFSC");
            expect(await token.oracle()).to.equal(oracle.address);
            expect(await token.rebaseIndex()).to.equal(ethers.utils.parseEther("1"));
        });

        it("应该正确铸造初始供应量", async function () {
            const initialSupply = await token.INITIAL_SUPPLY();
            expect(await token.balanceOf(owner.address)).to.equal(initialSupply);
        });
    });

    describe("转账测试", function () {
        it("应该正确处理用户之间的转账", async function () {
            const transferAmount = ethers.utils.parseEther("1000");
            
            // 从owner转账给5个用户
            await token.transfer(user1.address, transferAmount);
            await token.transfer(user2.address, transferAmount);
            await token.transfer(user3.address, transferAmount);
            await token.transfer(user4.address, transferAmount);
            await token.transfer(user5.address, transferAmount);

            // 验证余额
            expect(await token.balanceOf(user1.address)).to.equal(transferAmount);
            expect(await token.balanceOf(user2.address)).to.equal(transferAmount);
            expect(await token.balanceOf(user3.address)).to.equal(transferAmount);
            expect(await token.balanceOf(user4.address)).to.equal(transferAmount);
            expect(await token.balanceOf(user5.address)).to.equal(transferAmount);
        });
    });

    describe("Rebase测试", function () {
        it("只有预言机可以触发rebase", async function () {
            await expect(token.connect(user1).rebase()).to.be.revertedWith("Only oracle can call this function");
        });

        it("rebase间隔必须大于1小时", async function () {
            await expect(token.connect(oracle).rebase()).to.be.revertedWith("Too early to rebase");
        });

        it("应该正确执行rebase并更新余额", async function () {
            // 先进行转账
            const transferAmount = ethers.utils.parseEther("1000");
            await token.transfer(user1.address, transferAmount);

            // 增加时间
            await ethers.provider.send("evm_increaseTime", [3600]); // 增加1小时
            await ethers.provider.send("evm_mine");

            // 执行rebase
            await token.connect(oracle).rebase();

            // 验证rebase后的余额
            const newBalance = await token.balanceOf(user1.address);
            expect(newBalance).to.be.below(transferAmount); // 余额应该减少
        });
    });

    describe("年度通缩测试", function () {
        it("应该正确计算年度通缩", async function () {
            // 先进行转账
            const transferAmount = ethers.utils.parseEther("1000");
            await token.transfer(user1.address, transferAmount);

            // 增加一年时间
            await ethers.provider.send("evm_increaseTime", [365 * 24 * 3600]); // 增加一年
            await ethers.provider.send("evm_mine");

            // 执行rebase
            await token.connect(oracle).rebase();

            // 验证余额是否减少了1%
            const newBalance = await token.balanceOf(user1.address);
            const expectedBalance = transferAmount.mul(99).div(100); // 减少1%
            expect(newBalance).to.equal(expectedBalance);
        });
    });
}); 
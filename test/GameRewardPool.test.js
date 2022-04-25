const { expect, assert } = require("chai");
const { ethers, network } = require("hardhat");
const { BigNumber } = require('ethers');

describe("Game Reward Pool", function () {

    let accounts;
    let GameContract;
    let GameRewardPool;
    let MDVToken;
    const now = parseInt(Date.now()/1000);

    beforeEach('Deploy Token & GameRewardPool Contract', async () => {
        accounts = await ethers.getSigners();
        GameContract = accounts[9];

        const mdvToken = await ethers.getContractFactory("MiddleverseGold");
        MDVToken = await mdvToken.connect(accounts[0]).deploy();
        await MDVToken.connect(accounts[0]).deployed();

        // Deploy Game Reward Pool
        const gameRewardPool = await ethers.getContractFactory('GameRewardPool');
        GameRewardPool = await gameRewardPool.connect(accounts[0]).deploy(MDVToken.address, GameContract.address, now + 120);
        await GameRewardPool.connect(accounts[0]).deployed();
    });

    it('Contract owner should match', async () => { 
        const owner = await GameRewardPool.owner();
        expect(owner).to.be.equal(accounts[0].address);
    });

    it('Game Contract Address Should be match', async () => {
        const address = await GameRewardPool.gameContract();
        expect(address).to.be.equal(GameContract.address);
    });

    it('Time should be match', async () => {
        const gameLaunchTime = await GameRewardPool.gameLaunchTime();
        expect(gameLaunchTime).to.be.equal(now + 120);
    });

    it('Claimed Amount should be Zero at initial', async () => { 
        const claimedAmount = await GameRewardPool.claimedAmount();
        expect(claimedAmount).to.be.equal(BigNumber.from(0));
    });

    describe('withdrawal from GameRewardPool', function () {
        let totalAmount;
        beforeEach('Initially transfer Amount to GameRewardPool', async () => { 
            totalAmount = await GameRewardPool.tokenForGameRewardPool();
            await MDVToken.connect(accounts[0]).transfer(GameRewardPool.address, totalAmount);
        });

        it('transferred amount should be match', async () => {
            let balance = await MDVToken.balanceOf(GameRewardPool.address);
            expect(balance).to.be.equal(totalAmount);
        });

        it('withdraw fail from other account', async () => { 
            await expect(GameRewardPool.connect(accounts[1]).withdraw()).to.be.revertedWith(
                "Ownable: caller is not the owner"
            );
        });

        it('withdrawal fail before game Launch', async () => {
            await expect(GameRewardPool.connect(accounts[0]).withdraw()).to.be.revertedWith(
                "Game is not Launch yet."
            );
        });

        describe('Initial withdrawal', function () {
            let intervalTime = BigNumber.from(4 * 7 * 24 * 60 * 60); // 4 weeks
            let totalTime = BigNumber.from(92 * 7 * 24 * 60 * 60); // 92 weeks

            it('withdraw Amount at Game Launch Time', async () => {
                await network.provider.send('evm_increaseTime', [120]);
                await network.provider.send('evm_mine');
                await GameRewardPool.connect(accounts[0]).withdraw();
                let balance = await MDVToken.balanceOf(GameContract.address);
                let claimedAmount = await GameRewardPool.claimedAmount();
                expect(balance).to.be.equal(totalAmount.mul(intervalTime).div(totalTime));
                expect(balance).to.be.equal(claimedAmount);
            });

            it('withdraw failed after successful withdrawal', async () => { 
                await GameRewardPool.connect(accounts[0]).withdraw();
                await expect(GameRewardPool.connect(accounts[0]).withdraw()).to.be.revertedWith(
                    "There is no amount for withdrawal in current phase."
                );
            });

            describe('First withdrawal', function () {
                const intIntervalTime = parseInt(intervalTime);
                it('Withdraw amount at first interval', async () => {
                    await GameRewardPool.connect(accounts[0]).withdraw();
                    await network.provider.send('evm_increaseTime', [intIntervalTime]);
                    await network.provider.send('evm_mine');
                    await GameRewardPool.connect(accounts[0]).withdraw();
                    let balance = await MDVToken.balanceOf(GameContract.address);
                    let claimedAmount = await GameRewardPool.claimedAmount();
                    expect(balance).to.be.equal(totalAmount.mul(intervalTime).div(totalTime).mul(2));
                    expect(balance).to.be.equal(claimedAmount);
                });

                it('withdraw failed after successful withdrawal', async () => {
                    await GameRewardPool.connect(accounts[0]).withdraw();
                    await expect(GameRewardPool.connect(accounts[0]).withdraw()).to.be.revertedWith("There is no amount for withdrawal in current phase.");
                });

                describe('Second Withdrawal', function () { 
                    it('Withdraw amount at second interval', async () => {
                        await GameRewardPool.connect(accounts[0]).withdraw();
                        await network.provider.send('evm_increaseTime', [intIntervalTime]);
                        await network.provider.send('evm_mine');
                        await GameRewardPool.connect(accounts[0]).withdraw();
                        let balance = await MDVToken.balanceOf(GameContract.address);
                        let claimedAmount = await GameRewardPool.claimedAmount();
                        expect(balance).to.be.equal(totalAmount.mul(intervalTime).div(totalTime).mul(3));
                        expect(balance).to.be.equal(claimedAmount);
                    });

                    it('withdraw failed after successful withdrawal', async () => {
                        await GameRewardPool.connect(accounts[0]).withdraw();
                        await expect(GameRewardPool.connect(accounts[0]).withdraw()).to.be.revertedWith(
                            "There is no amount for withdrawal in current phase."
                        );
                    });

                    describe('Final Withdrawal', function () { 
                        it('Withdraw amount at Last Withdrawal', async () => { 
                            await GameRewardPool.connect(accounts[0]).withdraw();
                            await network.provider.send('evm_increaseTime', [21 * intIntervalTime]);
                            await network.provider.send('evm_mine');;
                            await GameRewardPool.connect(accounts[0]).withdraw();
                            let balance = await MDVToken.balanceOf(GameContract.address);
                            let claimedAmount = await GameRewardPool.claimedAmount();
                            expect(balance).to.be.equal(totalAmount);
                            await expect(balance).to.be.equal(claimedAmount);
                        });

                        it('withdraw failed after successful withdrawal', async () => {
                            await GameRewardPool.connect(accounts[0]).withdraw();
                            await expect(GameRewardPool.connect(accounts[0]).withdraw()).to.be.revertedWith(
                                "You have withdraw all amount."
                            );
                        });
                    });
                });
            });
        });
    });
});
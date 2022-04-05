const { expect, assert } = require("chai");
const { ethers, network } = require("hardhat");
// const { BigNumber } = require('ethers');
const { BigNumber } = require('bignumber.js');
const Web3 = require("web3");


describe("Token Distribution with Vesting", function () {
    it("SeedSale : WhiteListed Account can buy Token with Vesting", async function () {
        const accounts = await ethers.getSigners();

        const MVGToken = await ethers.getContractFactory("MVGToken");
        const mvgToken = await MVGToken.connect(accounts[0]).deploy();
        await mvgToken.connect(accounts[0]).deployed();

        const MVGDistribution = await ethers.getContractFactory("MDVDistribution");
        const mvgDistribution = await MVGDistribution.connect(accounts[1]).deploy(mvgToken.address, 1000);
        await mvgDistribution.connect(accounts[1]).deployed();

        let tokenToSellInSeedSale = await mvgDistribution.tokenToSellInSeedSale();
        // expect(tokenToSellInSeedSale).to.be.equal(BigNumber(10000000000000000000000000));

        // get current Active Sale (0: SeedSale, 1: StrategicSale, 2: PublicSale)
        let currentStage = await mvgDistribution.stage();
        expect(currentStage).to.be.equal(0);

        // approve MVGDistribution smart contract to spend token from MVGToken
        await mvgToken.connect(accounts[0]).transfer(mvgDistribution.address, tokenToSellInSeedSale);

        // add to whitelist
        await mvgDistribution.connect(accounts[1]).setWhiteListForSeedSale(accounts[2].address);
        assert(await mvgDistribution.whiteListInSeedSale(accounts[2].address));

        // buy token with Linear Vesting
        await mvgDistribution.connect(accounts[2]).buyAndVesting({ value: 20 });
        
        let Sale = await mvgDistribution.saleDetail(currentStage);
        Sale = {
            saleStartTime: Sale.saleStartTime.toNumber(),
            cliffTime: Sale.cliffTime.toNumber(),
            intervalTime: Sale.intervalTime.toNumber(),
            releasedTime: Sale.releasedTime.toNumber(),
            percentageOfTGE: Sale.percentageOfTGE.toNumber(),
            rate: Sale.rate.toNumber()
        };

        let bal = await mvgToken.balanceOf(accounts[2].address);
        expect(bal).to.equal((Sale.rate * 20) * Sale.percentageOfTGE / 100);

        // buy token with Linear Vesting
        await mvgDistribution.connect(accounts[2]).buyAndVesting({ value: 30 });
        bal = await mvgToken.balanceOf(accounts[2].address);
        expect(bal).to.equal((Sale.rate * 50) * Sale.percentageOfTGE / 100);

        tokenToSellInSeedSale = await mvgDistribution.tokenToSellInSeedSale();
        console.log(tokenToSellInSeedSale);

        let cliffTime = Sale.cliffTime; // cliffTime
        await network.provider.send('evm_increaseTime', [cliffTime]);
        await network.provider.send('evm_mine');

        let intervalTime = Sale.intervalTime; // Interval
        await network.provider.send('evm_increaseTime', [intervalTime]);
        await network.provider.send('evm_mine');

        let seedPurchase = await mvgDistribution.seedSalePurchase(accounts[2].address);

        let amountPerInterval = parseInt((seedPurchase.totalAmount - seedPurchase.claimedAmount) / (Sale.releasedTime / Sale.intervalTime));

        let claimable_0 = await mvgDistribution.computeClaimableAmount(currentStage, accounts[2].address);
        expect(claimable_0).to.equal(amountPerInterval);
        
        // add One Interval Time
        await network.provider.send('evm_increaseTime', [intervalTime]);
        await network.provider.send('evm_mine');

        claimable_0 = await mvgDistribution.computeClaimableAmount(currentStage, accounts[2].address);
        expect(claimable_0).to.equal(amountPerInterval * 2);

        // wait untill Vesting period is over
        await network.provider.send('evm_increaseTime', [Sale.releasedTime]);
        await network.provider.send('evm_mine');

        claimable_0 = await mvgDistribution.computeClaimableAmount(currentStage, accounts[2].address);
        expect(claimable_0).to.equal(seedPurchase.totalAmount - seedPurchase.claimedAmount);

        // claim Amount by User from particular Sale
        await mvgDistribution.connect(accounts[2]).claimPurchase(currentStage);

        seedPurchase = await mvgDistribution.seedSalePurchase(accounts[2].address);
        bal = await mvgToken.balanceOf(accounts[2].address);
        expect(bal).to.equal(seedPurchase.totalAmount);
        console.log(bal);
        assert(seedPurchase.status);
    });

    it("StrategicSale : WhiteListed Account can buy Token with Vesting", async function () {
        const accounts = await ethers.getSigners();

        const MVGToken = await ethers.getContractFactory("MVGToken");
        const mvgToken = await MVGToken.connect(accounts[0]).deploy();
        await mvgToken.connect(accounts[0]).deployed();

        const MVGDistribution = await ethers.getContractFactory("MDVDistribution");
        const mvgDistribution = await MVGDistribution.connect(accounts[1]).deploy(mvgToken.address, 1000);
        await mvgDistribution.connect(accounts[1]).deployed();

        // Activate Strategic Sale
        await mvgDistribution.activateStage(1, 500);

        // get current Active Sale (0: SeedSale, 1: StrategicSale, 2: PublicSale)
        let currentStage = await mvgDistribution.stage();
        expect(currentStage).to.be.equal(1);

        let tokenToSellInStrategicSale = await mvgDistribution.tokenToSellInStrategicSale();
        console.log(tokenToSellInStrategicSale);

        // approve MVGDistribution smart contract to spend token from MVGToken
        await mvgToken.connect(accounts[0]).transfer(mvgDistribution.address, tokenToSellInStrategicSale);

        // add to whitelist
        await mvgDistribution.connect(accounts[1]).setWhiteListForStrategicSale(accounts[2].address);
        assert(await mvgDistribution.whiteListInStrategicSale(accounts[2].address));

        // buy token with Linear Vesting
        await mvgDistribution.connect(accounts[2]).buyAndVesting({ value: 20 });
        
        let Sale = await mvgDistribution.saleDetail(currentStage);
        Sale = {
            saleStartTime: Sale.saleStartTime.toNumber(),
            cliffTime: Sale.cliffTime.toNumber(),
            intervalTime: Sale.intervalTime.toNumber(),
            releasedTime: Sale.releasedTime.toNumber(),
            percentageOfTGE: Sale.percentageOfTGE.toNumber(),
            rate: Sale.rate.toNumber()
        };

        let bal = await mvgToken.balanceOf(accounts[2].address);
        expect(bal).to.equal((Sale.rate * 20) * Sale.percentageOfTGE / 100);

        tokenToSellInStrategicSale = await mvgDistribution.tokenToSellInStrategicSale();
        console.log(tokenToSellInStrategicSale);

        // buy token with Linear Vesting
        await mvgDistribution.connect(accounts[2]).buyAndVesting({ value: 80 });
        bal = await mvgToken.balanceOf(accounts[2].address);
        expect(bal).to.be.equal((Sale.rate * 100) * Sale.percentageOfTGE / 100);

        let waitTime = Sale.cliffTime; // cliffTime
        await network.provider.send('evm_increaseTime', [waitTime]);
        await network.provider.send('evm_mine');

        let intervalTime = Sale.intervalTime; // Interval
        await network.provider.send('evm_increaseTime', [intervalTime]);
        await network.provider.send('evm_mine');
        
        let strategicPurchase = await mvgDistribution.strategicSalePurchase(accounts[2].address);

        let amountPerInterval = parseInt((strategicPurchase.totalAmount - strategicPurchase.claimedAmount) / (Sale.releasedTime / Sale.intervalTime));

        let claimable_0 = await mvgDistribution.computeClaimableAmount(currentStage, accounts[2].address);
        expect(claimable_0).to.equal(amountPerInterval);
        
        // add One Interval Time
        await network.provider.send('evm_increaseTime', [intervalTime]);
        await network.provider.send('evm_mine');

        claimable_0 = await mvgDistribution.computeClaimableAmount(currentStage, accounts[2].address);
        expect(claimable_0).to.equal(amountPerInterval * 2);

        await network.provider.send('evm_increaseTime', [Sale.releasedTime]);
        await network.provider.send('evm_mine');

        claimable_0 = await mvgDistribution.computeClaimableAmount(currentStage, accounts[2].address);
        expect(claimable_0).to.equal(strategicPurchase.totalAmount - strategicPurchase.claimedAmount);

        // claim Amount by User from particular Sale
        await mvgDistribution.connect(accounts[2]).claimPurchase(currentStage);

        strategicPurchase = await mvgDistribution.strategicSalePurchase(accounts[2].address);
        bal = await mvgToken.balanceOf(accounts[2].address);
        expect(bal).to.equal(strategicPurchase.totalAmount);
        console.log(bal);
        assert(strategicPurchase.status);
    });

    it("PublicSale : WhiteListed Account can buy Token with Vesting", async function () {
        const accounts = await ethers.getSigners();

        const MVGToken = await ethers.getContractFactory("MVGToken");
        const mvgToken = await MVGToken.connect(accounts[0]).deploy();
        await mvgToken.connect(accounts[0]).deployed();

        const MVGDistribution = await ethers.getContractFactory("MDVDistribution");
        const mvgDistribution = await MVGDistribution.connect(accounts[1]).deploy(mvgToken.address, 1000);
        await mvgDistribution.connect(accounts[1]).deployed();

        // Activate Strategic Sale
        await mvgDistribution.activateStage(2, 250);

        // get current Active Sale (0: SeedSale, 1: StrategicSale, 2: PublicSale)
        let currentStage = await mvgDistribution.stage();
        expect(currentStage).to.be.equal(2);

        let tokenToSellInPublicSale = await mvgDistribution.tokenToSellInPublicSale();
        console.log(tokenToSellInPublicSale);

        // approve MVGDistribution smart contract to spend token from MVGToken
        await mvgToken.connect(accounts[0]).transfer(mvgDistribution.address, tokenToSellInPublicSale);

        // buy token with Linear Vesting
        await mvgDistribution.connect(accounts[2]).buyAndVesting({ value: 20 });
        
        let publicSalePurchase = await mvgDistribution.publicSalePurchase(accounts[2].address);

        let Sale = await mvgDistribution.saleDetail(currentStage);
        Sale = {
            saleStartTime: Sale.saleStartTime.toNumber(),
            cliffTime: Sale.cliffTime.toNumber(),
            intervalTime: Sale.intervalTime.toNumber(),
            releasedTime: Sale.releasedTime.toNumber(),
            percentageOfTGE: Sale.percentageOfTGE.toNumber(),
            rate: Sale.rate.toNumber()
        };

        let bal = await mvgToken.balanceOf(accounts[2].address);
        expect(bal).to.equal((Sale.rate * 20) * Sale.percentageOfTGE / 100);

        // buy token with Linear Vesting
        await mvgDistribution.connect(accounts[2]).buyAndVesting({ value: 60 });
        bal = await mvgToken.balanceOf(accounts[2].address);
        expect(bal).to.be.equal((Sale.rate * 80) * Sale.percentageOfTGE / 100);

        tokenToSellInPublicSale = await mvgDistribution.tokenToSellInPublicSale();

        let intervalTime = Sale.intervalTime; // Interval
        await network.provider.send('evm_increaseTime', [intervalTime]);
        await network.provider.send('evm_mine');
        
        publicSalePurchase = await mvgDistribution.publicSalePurchase(accounts[2].address);
        let amountPerInterval = parseInt((publicSalePurchase.totalAmount - publicSalePurchase.claimedAmount) / (Sale.releasedTime / Sale.intervalTime));

        let claimable_0 = await mvgDistribution.computeClaimableAmount(currentStage, accounts[2].address);
        expect(claimable_0).to.equal(amountPerInterval);
        
        // add One Interval Time
        await network.provider.send('evm_increaseTime', [intervalTime]);
        await network.provider.send('evm_mine');

        claimable_0 = await mvgDistribution.computeClaimableAmount(currentStage, accounts[2].address);
        expect(claimable_0).to.equal(amountPerInterval * 2);

        await network.provider.send('evm_increaseTime', [Sale.releasedTime]);
        await network.provider.send('evm_mine');

        claimable_0 = await mvgDistribution.computeClaimableAmount(currentStage, accounts[2].address);
        expect(claimable_0).to.equal(publicSalePurchase.totalAmount - publicSalePurchase.claimedAmount);

        // claim Amount by User from particular Sale
        await mvgDistribution.connect(accounts[2]).claimPurchase(currentStage);

        publicSalePurchase = await mvgDistribution.publicSalePurchase(accounts[2].address);
        bal = await mvgToken.balanceOf(accounts[2].address);
        expect(bal).to.equal(publicSalePurchase.totalAmount);
        console.log(bal);
        assert(publicSalePurchase.status);
    });
  
});
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("TokenVesting", function () {
  let Token;
  let testToken;
  let TokenVesting;
  let owner;
  let addr1;
  let addr2;
  let addrs;

  before(async function () {
    Token = await ethers.getContractFactory("MyToken");
    TokenVesting = await ethers.getContractFactory("MockTokenVesting");
  });
  beforeEach(async function () {
    [owner, addr1, addr2, ...addrs] = await ethers.getSigners();
    testToken = await Token.deploy();
    await testToken.deployed();
  });

  describe("Vesting", () => {
    it("Should assign the total supply of tokens to the owner", async () => {
        const ownerBalance = await testToken.balanceOf(owner.address);
        expect(await testToken.totalSupply()).to.equal(ownerBalance);
      });
    it("Should vest tokens gradually - Marketing", async () => {
        const tokenVesting = await TokenVesting.deploy(testToken.address);
        expect((await tokenVesting.getToken()).toString()).to.equal(
            testToken.address
        );
        await expect(testToken.transfer(tokenVesting.address, 100000000))
            .to.emit(testToken, "Transfer")
            .withArgs(owner.address, tokenVesting.address, 100000000);
        const vestingContractBalance = await testToken.balanceOf(
        tokenVesting.address
        );
        expect(vestingContractBalance).to.equal(100000000);

        await tokenVesting.setTGE(2);
        let tge = await tokenVesting.marketingTGE();
        tge = tge.toString();
        expect(tge).to.equal("2");
        await tokenVesting.calculatePools();
        let marketingTGEPool = await tokenVesting.marketingTGEPool();
        marketingTGEPool = marketingTGEPool.toString();
        expect(marketingTGEPool).to.equal("130000");
        let marketingVestingPool = await tokenVesting.marketingVestingPool();
        marketingVestingPool = marketingVestingPool.toString();
        expect(marketingVestingPool).to.equal("6370000");
        let withdrawable = await tokenVesting.getWithdrawableAmount();
        withdrawable = withdrawable.toString();
        expect(withdrawable).to.equal("73500000");

        const r = 1;
        const baseTime = 1647427800;
        const beneficiary = addr1;
        const startTime = baseTime;
        const cliff = 60;
        const duration = 144;
        const slicePeriodSeconds = 36;
        const revokable = true;
        const amount = 10000;

        await tokenVesting.createVestingSchedule(
            r,
            beneficiary.address,
            startTime,
            cliff,
            duration,
            slicePeriodSeconds,
            revokable,
            amount
          );
        expect(await tokenVesting.getVestingSchedulesCount()).to.be.equal(1);

        expect(
            await tokenVesting.getVestingSchedulesCountByBeneficiary(
              beneficiary.address
            )
        ).to.be.equal(1);

        const vestingScheduleId = await tokenVesting.getVestingIdAtIndex(0);

        expect(
            await tokenVesting.computeReleasableAmount(vestingScheduleId, 1)
        ).to.be.equal(200);

        const afterCliff = baseTime + 60;
        await tokenVesting.setCurrentTime(afterCliff);

        expect(
            await tokenVesting
              .connect(beneficiary)
              .computeReleasableAmount(vestingScheduleId, r)
        ).to.be.equal(2160);
        
        let interval = afterCliff + 36;
        await tokenVesting.setCurrentTime(interval);

        expect(
            await tokenVesting
              .connect(beneficiary)
              .computeReleasableAmount(vestingScheduleId, r)
        ).to.be.equal(4120);

        interval = interval + 36;
        await tokenVesting.setCurrentTime(interval);

        expect(
            await tokenVesting
              .connect(beneficiary)
              .computeReleasableAmount(vestingScheduleId, r)
        ).to.be.equal(6080);

        interval = interval + 36;
        await tokenVesting.setCurrentTime(interval);

        expect(
            await tokenVesting
              .connect(beneficiary)
              .computeReleasableAmount(vestingScheduleId, r)
        ).to.be.equal(8040);

        interval = interval + 36;
        await tokenVesting.setCurrentTime(interval);

        expect(
            await tokenVesting
              .connect(beneficiary)
              .computeReleasableAmount(vestingScheduleId, r)
        ).to.be.equal(10000);

        await expect(
            tokenVesting.connect(addr2).release(vestingScheduleId, 100, r)
            ).to.be.revertedWith(
                "TokenVesting: only beneficiary and owner can release vested tokens"
        );
        
        await expect(
            tokenVesting.connect(beneficiary).release(vestingScheduleId, 10001, r)
        ).to.be.revertedWith(
            "TokenVesting: cannot release tokens, not enough vested tokens"
        );

        await expect(
            tokenVesting.connect(beneficiary).release(vestingScheduleId, 1000, r)
        )
            .to.emit(testToken, "Transfer")
            .withArgs(tokenVesting.address, beneficiary.address, 1000);
        
        expect(
            await tokenVesting
                .connect(beneficiary)
                .computeReleasableAmount(vestingScheduleId, r)
            ).to.be.equal(9000);
            
        let vestingSchedule = await tokenVesting.getVestingSchedule(
                vestingScheduleId,
                r
            );
        expect(vestingSchedule.released).to.be.equal(1000);

        await tokenVesting.setCurrentTime(baseTime + interval + 1);
        expect(
          await tokenVesting
            .connect(beneficiary)
            .computeReleasableAmount(vestingScheduleId, r)
        ).to.be.equal(9000);

        await expect(
            tokenVesting.connect(beneficiary).release(vestingScheduleId, 4500, r)
          )
            .to.emit(testToken, "Transfer")
            .withArgs(tokenVesting.address, beneficiary.address, 4500);
        await expect(
                tokenVesting.connect(owner).release(vestingScheduleId, 4500, r)
              )
                .to.emit(testToken, "Transfer")
                .withArgs(tokenVesting.address, beneficiary.address, 4500);

        vestingSchedule = await tokenVesting.getVestingSchedule(
                    vestingScheduleId,
                    r
                );
        expect(vestingSchedule.released).to.be.equal(10000);

        expect(
            await tokenVesting
                .connect(beneficiary)
                .computeReleasableAmount(vestingScheduleId, r)
        ).to.be.equal(0);

        await expect(
            tokenVesting.connect(addr2).revoke(vestingScheduleId, r)
        ).to.be.revertedWith("Ownable: caller is not the owner");
    })
    it("should release tokens if revoked", async () => {
        // deploy vesting contract
        const tokenVesting = await TokenVesting.deploy(testToken.address);
        await tokenVesting.deployed();
        expect((await tokenVesting.getToken()).toString()).to.equal(
        testToken.address
      );
      await expect(testToken.transfer(tokenVesting.address, 100000000))
      .to.emit(testToken, "Transfer")
      .withArgs(owner.address, tokenVesting.address, 100000000);
      
      const r = 1;
      const baseTime = 1647427800;
      const beneficiary = addr1;
      const startTime = baseTime;
      const cliff = 60;
      const duration = 144;
      const slicePeriodSeconds = 36;
      const revokable = true;
      const amount = 10000;
  
      await tokenVesting.setTGE(2);
      await tokenVesting.calculatePools();
  
      await tokenVesting.createVestingSchedule(
        r,
        beneficiary.address,
        startTime,
        cliff,
        duration,
        slicePeriodSeconds,
        revokable,
        amount
      );
      let withdrawable = await tokenVesting.getWithdrawableAmount();
      withdrawable = withdrawable.toString();

      const vestingScheduleId = await tokenVesting.getVestingIdAtIndex(0);
      
      const afterCliff = baseTime + 60;
      await tokenVesting.setCurrentTime(afterCliff);

      await expect(tokenVesting.revoke(vestingScheduleId, r))
      .to.emit(testToken, "Transfer")
      .withArgs(tokenVesting.address, beneficiary.address, 2160);
    })    
  });
});
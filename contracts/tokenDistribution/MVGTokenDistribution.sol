//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Token distribution Contract
/// @author SoluLab
/// @notice You can use this contract for token distribution with three stages of the token distribution sale

contract MVGDistribution is Ownable {
    using SafeERC20 for IERC20;

    /// @notice the ICOStage is used to determine the stage of the token distribution phase
    enum ICOStage {
        SeedSale,
        StrategicSale,
        PublicSale
    }

    /// @notice this struct is used to decide the purchase parameters
    struct Purchase {
        uint8 saleType; // 0 for SeedSale, 1 for StrategicSale, 2 for PublicSale
        uint256 investedAmount;
        uint256 totalAmount;
        uint256 claimedAmount;
        bool status;
    }

    /// @notice this struct is used for the vesting sale initiation
    struct VestingSale {
        uint256 saleStartTime;
        uint256 cliffTime;
        uint256 intervalTime;
        uint256 releasedTime;
        uint256 percentageOfTGE;
        uint256 rate;
    }

    ICOStage public stage = ICOStage.SeedSale;
    IERC20 private _token;

    /// @notice whitelisting the seed sale and strategic sale 
    mapping(address => bool) public whiteListInSeedSale;
    mapping(address => bool) public whiteListInStrategicSale;

    /// @notice the mapping here is used for the sale purchase 
    mapping(address => Purchase) public seedSalePurchase;
    mapping(address => Purchase) public strategicSalePurchase;
    mapping(address => Purchase) public publicSalePurchase;

    /// @notice mapping for the sale details
    mapping(uint8 => VestingSale) public saleDetail;

    /// @notice for the amount of tokens available for each sale
    uint256 public tokenToSellInSeedSale;
    uint256 public tokenToSellInStrategicSale;
    uint256 public tokenToSellInPublicSale;

    constructor(address _mvgToken, uint256 _seedSaleRate) {
        require(_mvgToken != address(0x0));
        _token = IERC20(_mvgToken);

        tokenToSellInSeedSale = (_token.totalSupply() * 2) / 100; // 2% of totalSupply (10,000,000)
        tokenToSellInStrategicSale = (_token.totalSupply() * 5) / 100; // 5% of totalSupply (25,000,000)
        tokenToSellInPublicSale = (_token.totalSupply() * 9) / 100; // 9% of totalSupply (45,000,000)

        saleDetail[uint8(ICOStage.SeedSale)] = VestingSale(
            _getCurrentTime(), // sale Start Time
            8 weeks, // cliff Time
            1 days, // Interval
            88 weeks, // Vesting Period
            7, // released at TGE(%)
            _seedSaleRate // rate of seedSale
        );
    }

    /// @notice activate stage is used to decide the role 
    /// @param setStage is used to decide the role and stage 
    /// @param rateOfSale is a dynamic input given to decide the initial rate of the sale
    function activateStage(uint8 setStage, uint256 rateOfSale)
        public
        onlyOwner
    {
        require(
            0 < setStage,
            "Please enter 1 for StrategicSale and 2 for PublicSale."
        );
        require(
            setStage <= 2,
            "Please enter 1 for StrategicSale and 2 for PublicSale."
        );

        if (setStage == uint8(ICOStage.StrategicSale)) {
            stage = ICOStage.StrategicSale;
            saleDetail[uint8(ICOStage.StrategicSale)] = VestingSale(
                _getCurrentTime(), // sale Start Time
                8 weeks, // cliff Time
                1 days, // Interval
                88 weeks, // Vesting Period
                10, // released at TGE(%)
                rateOfSale // rate of seedSale
            );
        } else if (setStage == uint8(ICOStage.PublicSale)) {
            stage = ICOStage.PublicSale;
            saleDetail[uint8(ICOStage.PublicSale)] = VestingSale(
                _getCurrentTime(), // sale Start Time
                0, // cliff Time
                1 days, // Interval
                24 weeks, // Vesting Period
                10, // released at TGE(%)
                rateOfSale // rate of seedSale
            );
        }
    }

    /// @param addr is to input the address
    function setWhiteListForSeedSale(address addr) public onlyOwner {
        whiteListInSeedSale[addr] = true;
    }

    /// @param addr is to input the address
    function setBlackListForSeedSale(address addr) public onlyOwner {
        whiteListInSeedSale[addr] = false;
    }

    /// @param addr is to input the address
    function setWhiteListForStrategicSale(address addr) public onlyOwner {
        whiteListInStrategicSale[addr] = true;
    }

    /// @param addr is to input the address
    function setBlackListForStrategicSale(address addr) public onlyOwner {
        whiteListInStrategicSale[addr] = false;
    }

    /// @notice this function helps in the buying and vesting of tokens
    function buyAndVesting() public payable {
        require(msg.value > 0, "Amount must be Greater than Zero");
        uint256 totalToken = 0;
        uint256 claimedToken = 0;
        if (stage == ICOStage.SeedSale) {
            require(
                whiteListInSeedSale[msg.sender],
                "You are not Whitelisted for Seed Sale"
            );
            totalToken = msg.value * saleDetail[uint8(ICOStage.SeedSale)].rate;
            claimedToken =
                (totalToken *
                    saleDetail[uint8(ICOStage.SeedSale)].percentageOfTGE) /
                100;
            require(
                (uint256(tokenToSellInSeedSale) >= uint256(totalToken)),
                "Seed Sale Limit exceeds"
            );
            if (seedSalePurchase[msg.sender].investedAmount > 0) {
                seedSalePurchase[msg.sender].investedAmount += msg.value;
                seedSalePurchase[msg.sender].totalAmount += totalToken;
                seedSalePurchase[msg.sender].claimedAmount += claimedToken;
                seedSalePurchase[msg.sender].status = false;
            } else {
                seedSalePurchase[msg.sender] = Purchase(
                    0, // Seed Sale
                    msg.value,
                    totalToken,
                    claimedToken,
                    false
                );
            }
        } else if (stage == ICOStage.StrategicSale) {
            require(
                whiteListInStrategicSale[msg.sender],
                "You are not Whitelisted for Strategic Sale"
            );
            totalToken =
                msg.value *
                saleDetail[uint8(ICOStage.StrategicSale)].rate;
            claimedToken =
                (totalToken *
                    saleDetail[uint8(ICOStage.StrategicSale)].percentageOfTGE) /
                100;
            require(
                (uint256(tokenToSellInStrategicSale) >= uint256(totalToken)),
                "Strategic Sale Limit exceeds"
            );
            if (strategicSalePurchase[msg.sender].investedAmount > 0) {
                strategicSalePurchase[msg.sender].investedAmount += msg.value;
                strategicSalePurchase[msg.sender].totalAmount += totalToken;
                strategicSalePurchase[msg.sender].claimedAmount += claimedToken;
                strategicSalePurchase[msg.sender].status = false;
            } else {
                strategicSalePurchase[msg.sender] = Purchase(
                    1, // Strategic Sale
                    msg.value,
                    totalToken,
                    claimedToken,
                    false
                );
            }
        } else if (stage == ICOStage.PublicSale) {
            totalToken =
                msg.value *
                saleDetail[uint8(ICOStage.PublicSale)].rate;
            claimedToken =
                (totalToken *
                    saleDetail[uint8(ICOStage.PublicSale)].percentageOfTGE) /
                100;
            require(
                (uint256(tokenToSellInPublicSale) >= uint256(totalToken)),
                "Public Sale Limit exceeds"
            );
            if (publicSalePurchase[msg.sender].investedAmount > 0) {
                publicSalePurchase[msg.sender].investedAmount += msg.value;
                publicSalePurchase[msg.sender].totalAmount += totalToken;
                publicSalePurchase[msg.sender].claimedAmount += claimedToken;
                publicSalePurchase[msg.sender].status = false;
            } else {
                publicSalePurchase[msg.sender] = Purchase(
                    2, // Public Sale
                    msg.value,
                    totalToken,
                    claimedToken,
                    false
                );
            }
        }

        if (stage == ICOStage.SeedSale) {
            tokenToSellInSeedSale -= totalToken;
        } else if (stage == ICOStage.StrategicSale) {
            tokenToSellInStrategicSale -= totalToken;
        } else if (stage == ICOStage.PublicSale) {
            tokenToSellInPublicSale -= totalToken;
        }

        bool sended = _token.transfer(msg.sender, claimedToken);
        require(sended, "Something went wrong, Token not Transffered");
    }

    /// @notice this function is used to claim the purchase 
    /// @param fromStage to decide which stage it is 
    function claimPurchase(uint8 fromStage) public {
        Purchase storage purchase;
        if (uint8(ICOStage.SeedSale) == fromStage) {
            purchase = seedSalePurchase[msg.sender];
            bool isSeedSale = purchase.saleType == 0;
            require(isSeedSale, "you didn't purchase anything from Seed Sale");
        } else if (uint8(ICOStage.StrategicSale) == fromStage) {
            purchase = strategicSalePurchase[msg.sender];
            bool isStrategicSale = purchase.saleType == 1;
            require(
                isStrategicSale,
                "you didn't purchase anything from Strategic Sale"
            );
        } else {
            purchase = publicSalePurchase[msg.sender];
            bool isPublicSale = purchase.saleType == 2;
            require(
                isPublicSale,
                "you didn't purchase anything from Public Sale"
            );
        }
        require(!(purchase.status), "You have claimed all of your amount");
        uint256 claimAmount = computeClaimableAmount(fromStage, msg.sender);
        purchase.claimedAmount = purchase.claimedAmount + claimAmount;
        if (purchase.claimedAmount < purchase.totalAmount) {
            purchase.status = false;
        } else {
            purchase.status = true;
        }
        address payable msgSender = payable(msg.sender);
        _token.safeTransfer(msgSender, claimAmount);
    }

    /// @notice used to compute claimable amount
    /// @param fromStage to decide which stage it is
    /// @param ofAddress is used to check the address for which the amount is to be calculated
    function computeClaimableAmount(uint8 fromStage, address ofAddress)
        public
        view
        returns (uint256)
    {
        uint256 currentTime = _getCurrentTime();
        Purchase storage purchase;
        VestingSale storage vesting = saleDetail[fromStage];
        if (uint8(ICOStage.SeedSale) == fromStage) {
            purchase = seedSalePurchase[ofAddress];
        } else if (uint8(ICOStage.StrategicSale) == fromStage) {
            purchase = strategicSalePurchase[ofAddress];
        } else {
            purchase = publicSalePurchase[ofAddress];
        }
        if (
            (currentTime < (vesting.saleStartTime + vesting.cliffTime)) ||
            purchase.status
        ) {
            return 0;
        } else if (
            currentTime >=
            (vesting.saleStartTime + vesting.cliffTime + vesting.releasedTime)
        ) {
            return (purchase.totalAmount - purchase.claimedAmount);
        } else {
            uint256 vestingStartTime = vesting.saleStartTime +
                vesting.cliffTime;
            uint256 timeForVest = currentTime - vestingStartTime;
            uint256 totalSlice = vesting.releasedTime / vesting.intervalTime;
            uint256 releaseAtTGE = (purchase.totalAmount *
                vesting.percentageOfTGE) / 100;
            uint256 totalVestingAmount = purchase.totalAmount - releaseAtTGE;
            uint256 vestedAmount = (totalVestingAmount * timeForVest) /
                (totalSlice * vesting.intervalTime);
            return (vestedAmount - (purchase.claimedAmount - releaseAtTGE));
        }
    }
    /// @notice withdraw amount function is used to transfer the funds
    function withdrawAmount() public onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    /// @notice used to get the current time
    function _getCurrentTime() internal view returns (uint256) {
        return block.timestamp;
    }
}

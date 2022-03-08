// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract MVGVesting is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    //TGE 2% Marketing

    uint256 public marketingTGE;

    uint256 public totalTokensinContract;
    uint256 public totalWithdrawableAmount;

    //tokens that can be withdrawn at any time.

    uint256 public marketingTGEPool;

    //tokens that can be vested.
    uint256 public advisersAndPartnershipsVestingPool;
    uint256 public marketingVestingPool;

    //total tokens each division has
    uint256 public vestingSchedulesTotalAmountforAdvisorsAndPartnership;
    uint256 public vestingSchedulesTotalAmountforMarketing;

    //tracking TGE pool

    uint256 public marketingTGEBank;

    //tracking beneficiary count
    uint256 public advisersAndPartnershipsBeneficiariesCount = 0;
    uint256 public marketingBeneficiariesCount = 0;

    mapping(address => uint256) private _holdersVestingCount;

    mapping(bytes32 => VestingSchedule) private _vestingSchedulesforAdvisorsAndPartnership;
    mapping(bytes32 => VestingSchedule) private _vestingSchedulesforMarketing;

    //keeping track of beneficiary
    mapping(address => bool) private _advisersAndPartnershipsBeneficiaries;
    mapping(address => bool) private _marketingBeneficiaries;

    bytes32[] private _vestingSchedulesIds;

    enum Roles {
        AdvisersAndPartnerships,
        Marketing
    }

    struct VestingSchedule {
        bool initialized;
        address beneficiary;
        uint256 cliff;
        uint256 start;
        uint256 duration;
        uint256 intervalPeriod;
        bool revocable;
        uint256 amountTotal;
        uint256 released;
        bool revoked;
    }
    IERC20 private _token;

    event Released(uint256 amount);
    event Revoked();

    constructor(address token_) {
        require(token_ != address(0x0));
        _token = IERC20(token_);
    }

    modifier onlyIfVestingScheduleExists(bytes32 vestingScheduleId, Roles r) {
        if (r == Roles.AdvisersAndPartnerships) {
            require(_vestingSchedulesforAdvisorsAndPartnership[vestingScheduleId].initialized == true);
        } else if (r == Roles.Marketing) {
            require(_vestingSchedulesforMarketing[vestingScheduleId].initialized == true);
        }
        _;
    }

    modifier onlyIfVestingScheduleNotRevoked(bytes32 vestingScheduleId, Roles r) {
        if (r == Roles.AdvisersAndPartnerships) {
            require(_vestingSchedulesforAdvisorsAndPartnership[vestingScheduleId].initialized == true);
            require(_vestingSchedulesforAdvisorsAndPartnership[vestingScheduleId].revoked == false);
        } else if (r == Roles.Marketing) {
            require(_vestingSchedulesforMarketing[vestingScheduleId].initialized == true);
            require(_vestingSchedulesforMarketing[vestingScheduleId].revoked == false);
        }
        _;
    }

    function _getCurrentTime() internal view virtual returns (uint256) {
        return block.timestamp;
    }

    function _updateTotalSupply() internal onlyOwner {
        totalTokensinContract = _token.balanceOf(address(this));
    }

    function _updateTotalWithdrawableAmount() internal onlyOwner {
        uint256 reservedAmount = vestingSchedulesTotalAmountforAdvisorsAndPartnership +
            vestingSchedulesTotalAmountforMarketing;

        totalWithdrawableAmount = _token.balanceOf(address(this)).sub(reservedAmount);
    }

    function _addBeneficiary(address _address, Roles r) internal onlyOwner {
        if (r == Roles.AdvisersAndPartnerships) {
            advisersAndPartnershipsBeneficiariesCount++;
            _advisersAndPartnershipsBeneficiaries[_address] = true;
        } else if (r == Roles.Marketing) {
            marketingBeneficiariesCount++;
            _marketingBeneficiaries[_address] = true;
        }
    }

    function _conditionWhileCreatingSchedule(
        Roles r,
        address _beneficiary,
        uint256 _cliff,
        uint256 _start,
        uint256 _duration,
        uint256 _intervalPeriod,
        bool _revocable,
        uint256 _amount,
        bytes32 vestingScheduleId
    ) internal {
        if (r == Roles.AdvisersAndPartnerships) {
            _vestingSchedulesforAdvisorsAndPartnership[vestingScheduleId] = VestingSchedule(
                true,
                _beneficiary,
                _cliff,
                _start,
                _duration,
                _intervalPeriod,
                _revocable,
                _amount,
                0,
                false
            );
            vestingSchedulesTotalAmountforAdvisorsAndPartnership = vestingSchedulesTotalAmountforAdvisorsAndPartnership;
        } else if (r == Roles.Marketing) {
            _vestingSchedulesforMarketing[vestingScheduleId] = VestingSchedule(
                true,
                _beneficiary,
                _cliff,
                _start,
                _duration,
                _intervalPeriod,
                _revocable,
                _amount,
                0,
                false
            );
            vestingSchedulesTotalAmountforMarketing = vestingSchedulesTotalAmountforMarketing;
        }
    }

    function _computeReleasableAmount(VestingSchedule memory vestingSchedule) internal view returns (uint256) {
        uint256 currentTime = _getCurrentTime();
        if ((currentTime < vestingSchedule.cliff) || vestingSchedule.revoked == true) {
            return 0;
        } else if (currentTime >= vestingSchedule.start.add(vestingSchedule.duration)) {
            return vestingSchedule.amountTotal.sub(vestingSchedule.released);
        } else {
            uint256 timeFromStart = currentTime.sub(vestingSchedule.start);
            uint256 secondsPerSlice = vestingSchedule.intervalPeriod;
            uint256 vestedSlicePeriods = timeFromStart.div(secondsPerSlice);
            uint256 vestedSeconds = vestedSlicePeriods.mul(secondsPerSlice);
            uint256 vestedAmount = vestingSchedule.amountTotal.mul(vestedSeconds).div(vestingSchedule.duration);
            vestedAmount = vestedAmount.sub(vestingSchedule.released);
            return vestedAmount;
        }
    }

    receive() external payable {}

    fallback() external payable {}

    function getVestingSchedulesCountByBeneficiary(address _beneficiary) external view returns (uint256) {
        return _holdersVestingCount[_beneficiary];
    }

    function getVestingIdAtIndex(uint256 index) external view returns (bytes32) {
        require(index < getVestingSchedulesCount(), "TokenVesting: index out of bounds");
        return _vestingSchedulesIds[index];
    }

    function getVestingScheduleByAddressAndIndex(
        address holder,
        uint256 index,
        Roles r
    ) external view returns (VestingSchedule memory) {
        return getVestingSchedule(computeVestingScheduleIdForAddressAndIndex(holder, index), r);
    }

    function getVestingSchedulesTotalAmount(Roles r) external view returns (uint256) {
        if (r == Roles.AdvisersAndPartnerships) {
            return vestingSchedulesTotalAmountforAdvisorsAndPartnership;
        } else {
            return vestingSchedulesTotalAmountforMarketing;
        }
    }

    function getToken() external view returns (address) {
        return address(_token);
    }

    function createVestingSchedule(
        Roles r,
        address _beneficiary,
        uint256 _start,
        uint256 _cliff,
        uint256 _duration,
        uint256 _intervalPeriod,
        bool _revocable,
        uint256 _amount
    ) public onlyOwner {
        require(
            this.getWithdrawableAmount() >= _amount,
            "TokenVesting: cannot create vesting schedule because not sufficient tokens"
        );
        uint256 cliff = _start.add(_cliff);

        require(_duration > 0, "TokenVesting: duration must be > 0");
        require(_amount > 0, "TokenVesting: amount must be > 0");
        require(_intervalPeriod >= 1, "TokenVesting: slicePeriodSeconds must be >= 1");
        require(r == Roles.AdvisersAndPartnerships || r == Roles.Marketing, "TokenVesting: roles must me 0 or 1");

        bytes32 vestingScheduleId = this.computeNextVestingScheduleIdForHolder(_beneficiary);
        _conditionWhileCreatingSchedule(
            r,
            _beneficiary,
            cliff,
            _start,
            _duration,
            _intervalPeriod,
            _revocable,
            _amount,
            vestingScheduleId
        );
        _addBeneficiary(_beneficiary, r);
        _vestingSchedulesIds.push(vestingScheduleId);
        uint256 currentVestingCount = _holdersVestingCount[_beneficiary];
        _holdersVestingCount[_beneficiary] = currentVestingCount.add(1);
    }

    function getVestingSchedule(bytes32 vestingScheduleId, Roles r) public view returns (VestingSchedule memory) {
        if (r == Roles.AdvisersAndPartnerships) {
            return _vestingSchedulesforAdvisorsAndPartnership[vestingScheduleId];
        } else {
            return _vestingSchedulesforMarketing[vestingScheduleId];
        }
    }

    function computeVestingScheduleIdForAddressAndIndex(address holder, uint256 index) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(holder, index));
    }

    function revoke(bytes32 vestingScheduleId, Roles r)
        public
        onlyOwner
        onlyIfVestingScheduleNotRevoked(vestingScheduleId, r)
    {
        if (r == Roles.AdvisersAndPartnerships) {
            VestingSchedule storage vestingSchedule = _vestingSchedulesforAdvisorsAndPartnership[vestingScheduleId];
            require(vestingSchedule.revocable == true, "TokenVesting: vesting is not revocable");
            uint256 vestedAmount = _computeReleasableAmount(vestingSchedule);
            if (vestedAmount > 0) {
                release(vestingScheduleId, vestedAmount, r);
            }
            uint256 unreleased = vestingSchedule.amountTotal.sub(vestingSchedule.released);
            vestingSchedulesTotalAmountforAdvisorsAndPartnership = vestingSchedulesTotalAmountforAdvisorsAndPartnership
                .sub(unreleased);
            vestingSchedule.revoked = true;
        } else if (r == Roles.Marketing) {
            VestingSchedule storage vestingSchedule = _vestingSchedulesforMarketing[vestingScheduleId];
            require(vestingSchedule.revocable == true, "TokenVesting: vesting is not revocable");
            uint256 vestedAmount = _computeReleasableAmount(vestingSchedule);
            if (vestedAmount > 0) {
                release(vestingScheduleId, vestedAmount, r);
            }
            uint256 unreleased = vestingSchedule.amountTotal.sub(vestingSchedule.released);
            vestingSchedulesTotalAmountforMarketing = vestingSchedulesTotalAmountforMarketing.sub(unreleased);
            vestingSchedule.revoked = true;
        }
    }

    function withdraw(uint256 amount) public onlyOwner {
        require(this.getWithdrawableAmount() >= amount, "TokenVesting: not enough withdrawable funds");
        totalWithdrawableAmount = totalWithdrawableAmount.sub(amount);
        _token.safeTransfer(owner(), amount);
    }

    function release(
        bytes32 vestingScheduleId,
        uint256 amount,
        Roles r
    ) public onlyIfVestingScheduleNotRevoked(vestingScheduleId, r) {
        VestingSchedule storage vestingSchedule;
        if (r == Roles.AdvisersAndPartnerships) {
            vestingSchedule = _vestingSchedulesforAdvisorsAndPartnership[vestingScheduleId];
        } else {
            vestingSchedule = _vestingSchedulesforMarketing[vestingScheduleId];
        }

        bool isBeneficiary = msg.sender == vestingSchedule.beneficiary;
        bool isOwner = msg.sender == owner();
        require(isBeneficiary || isOwner, "TokenVesting: only beneficiary and owner can release vested tokens");
        uint256 vestedAmount = _computeReleasableAmount(vestingSchedule);
        require(vestedAmount >= amount, "TokenVesting: cannot release tokens, not enough vested tokens");
        vestingSchedule.released = vestingSchedule.released.add(amount);
        address payable beneficiaryPayable = payable(vestingSchedule.beneficiary);
        if (r == Roles.AdvisersAndPartnerships) {
            vestingSchedulesTotalAmountforAdvisorsAndPartnership = vestingSchedulesTotalAmountforAdvisorsAndPartnership
                .sub(amount);
        } else if (r == Roles.Marketing) {
            vestingSchedulesTotalAmountforMarketing = vestingSchedulesTotalAmountforMarketing.sub(amount);
        }

        _token.safeTransfer(beneficiaryPayable, amount);
    }

    function getVestingSchedulesCount() public view returns (uint256) {
        return _vestingSchedulesIds.length;
    }

    function computeReleasableAmount(bytes32 vestingScheduleId, Roles r)
        public
        view
        onlyIfVestingScheduleNotRevoked(vestingScheduleId, r)
        returns (uint256)
    {
        VestingSchedule storage vestingSchedule;
        if (r == Roles.AdvisersAndPartnerships) {
            vestingSchedule = _vestingSchedulesforAdvisorsAndPartnership[vestingScheduleId];
        } else {
            vestingSchedule = _vestingSchedulesforMarketing[vestingScheduleId];
        }
        return _computeReleasableAmount(vestingSchedule);
    }

    function getWithdrawableAmount() public view returns (uint256) {
        return totalWithdrawableAmount;
    }

    /**
     * @dev Computes the next vesting schedule identifier for a given holder address.
     */
    function computeNextVestingScheduleIdForHolder(address holder) public view returns (bytes32) {
        return computeVestingScheduleIdForAddressAndIndex(holder, _holdersVestingCount[holder]);
    }

    /**
     * @dev Returns the last vesting schedule for a given holder address.
     */
    function getLastVestingScheduleForHolder(address holder, Roles r) public view returns (VestingSchedule memory) {
        if (r == Roles.AdvisersAndPartnerships) {
            return
                _vestingSchedulesforAdvisorsAndPartnership[
                    computeVestingScheduleIdForAddressAndIndex(holder, _holdersVestingCount[holder] - 1)
                ];
        } else {
            return
                _vestingSchedulesforMarketing[
                    computeVestingScheduleIdForAddressAndIndex(holder, _holdersVestingCount[holder] - 1)
                ];
        }
    }

    function withdrawFromTGEBank(Roles r, uint256 _amount) public {
        bool isOwner = msg.sender == owner();

        if (r == Roles.Marketing) {
            require(_marketingBeneficiaries[msg.sender] == true || isOwner, "You're not a beneficiary");
            require(_amount <= marketingTGEBank.div(marketingBeneficiariesCount), "You cannot withdraw this much");
            marketingTGEBank = marketingTGEBank.sub(_amount);
            _token.safeTransfer(msg.sender, _amount);
        }
    }

    function setTGE(uint256 tgeForM) public onlyOwner {
        marketingTGE = tgeForM;
    }

    function calculatePools() public onlyOwner {
        _updateTotalSupply();
        vestingSchedulesTotalAmountforAdvisorsAndPartnership = totalTokensinContract.mul(10).div(100);
        vestingSchedulesTotalAmountforMarketing = totalTokensinContract.mul(6).div(100);

        marketingTGEPool = vestingSchedulesTotalAmountforMarketing.mul(marketingTGE).div(100);

        marketingTGEBank = marketingTGEPool;

        marketingVestingPool = vestingSchedulesTotalAmountforMarketing.sub(marketingTGEPool);

        _updateTotalWithdrawableAmount();
    }
}

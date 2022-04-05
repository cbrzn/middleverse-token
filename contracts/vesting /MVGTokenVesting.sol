// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/// @title Linear Token Vesting Contract
/// @author SoluLab
/// @notice You can use this contract for linear vesting with three roles and set TGE for each roles

contract MVGTokenVesting is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice variable to set martketingTGE
    /// @dev if needed variables for other TGE can be added
    uint256 public marketingTGE;

    /// @notice variables to keep count of total tokens in the contract
    uint256 public totalTokensinContract;
    uint256 public totalWithdrawableAmount;

    /// @notice total tokens each division has
    uint256 public vestingSchedulesTotalAmountforAdvisorsAndPartnership;
    uint256 public vestingSchedulesTotalAmountforMarketing;
    uint256 public vestingSchedulesTotalAmountforReserveFunds;

    /// @notice tokens that can be withdrawn at any time
    uint256 public marketingTGEPool;

    /// @notice tokens that can be vested.
    uint256 public advisersAndPartnershipsVestingPool;
    uint256 public marketingVestingPool;
    uint256 public reserveFundsVestingPool;

    /// @notice tracking beneficiary count
    uint256 public advisersAndPartnershipsBeneficiariesCount = 0;
    uint256 public marketingBeneficiariesCount = 0;
    uint256 public reserveFundsBeneficiariesCount = 0;

    /// @notice to check holders vesting counts
    mapping(address => uint256) private _holdersVestingCount;

    /// @notice vesting schedules for different roles
    mapping(bytes32 => VestingSchedule) private _vestingSchedulesforAdvisorsAndPartnership;
    mapping(bytes32 => VestingSchedule) private _vestingSchedulesforMarketing;
    mapping(bytes32 => VestingSchedule) private _vestingSchedulesforReserveFunds;

    /// @notice keeping track of beneficiary in different roles
    mapping(address => bool) private _advisersAndPartnershipsBeneficiaries;
    mapping(address => bool) private _marketingBeneficiaries;
    mapping(address => bool) private _reserveFundsBeneficiaries;

    /// @notice vesting schedule ID to track vesting
    bytes32[] private _vestingSchedulesIds;

    /// @notice division of roles
    enum Roles {
        AdvisersAndPartnerships,
        Marketing,
        ReserveFunds
    }

    /// @notice creating a vesting schedule for beneficaries
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
        uint256 tgeAmount;
        bool revoked;
    }

    IERC20 private _token;

    /// @notice event to trigger the release of tokens and revoke the authority of a certain account
    /// @param amount total that was sent for relese function
    event Released(uint256 amount);
    event Revoked();

    /// @notice token address is used to import tokens from a given contract
    /// @param token_ that is supposed to be called into the contract
    constructor(address token_) {
        require(token_ != address(0x0));
        _token = IERC20(token_);
    }

    /// @dev to check if a vesting schedule exists already
    /// @param vestingScheduleId to know the vesting schedule details that were created
    /// @param r to know the role of the vesting schedule that is created
    modifier onlyIfVestingScheduleExists(bytes32 vestingScheduleId, Roles r) {
        if (r == Roles.AdvisersAndPartnerships) {
            require(_vestingSchedulesforAdvisorsAndPartnership[vestingScheduleId].initialized == true);
        } else if (r == Roles.Marketing) {
            require(_vestingSchedulesforMarketing[vestingScheduleId].initialized == true);
        } else {
            require(_vestingSchedulesforReserveFunds[vestingScheduleId].initialized == true);
        }
        _;
    }

    /// @dev to check if a vesting schedule has not be revoked already
    /// @param vestingScheduleId to know the vesting schedule details that were created
    /// @param r to know the role of the vesting schedule that is created
    modifier onlyIfVestingScheduleNotRevoked(bytes32 vestingScheduleId, Roles r) {
        if (r == Roles.AdvisersAndPartnerships) {
            require(_vestingSchedulesforAdvisorsAndPartnership[vestingScheduleId].initialized == true);
            require(_vestingSchedulesforAdvisorsAndPartnership[vestingScheduleId].revoked == false);
        } else if (r == Roles.Marketing) {
            require(_vestingSchedulesforMarketing[vestingScheduleId].initialized == true);
            require(_vestingSchedulesforMarketing[vestingScheduleId].revoked == false);
        } else {
            require(_vestingSchedulesforReserveFunds[vestingScheduleId].initialized == true);
            require(_vestingSchedulesforReserveFunds[vestingScheduleId].revoked == false);
        }
        _;
    }

    /// @notice function to reutrn the current time
    /// @return the current time
    function getCurrentTime() public view virtual returns (uint256) {
        return block.timestamp;
    }

    /// @notice to update the total supply of tokens in the contract
    function _updateTotalSupply() internal onlyOwner {
        totalTokensinContract = _token.balanceOf(address(this));
    }

    /// @notice internal function to update the total withdrawable amount
    function _updateTotalWithdrawableAmount() internal onlyOwner {
        uint256 reservedAmount = vestingSchedulesTotalAmountforAdvisorsAndPartnership +
            vestingSchedulesTotalAmountforMarketing +
            vestingSchedulesTotalAmountforReserveFunds;
        totalWithdrawableAmount = _token.balanceOf(address(this)) - (reservedAmount);
    }

    /// @notice updates the beneficiary count
    /// @param _address that is the address of the beneficiary
    /// @param r the role of the beneficiary
    function _addBeneficiary(address _address, Roles r) internal onlyOwner {
        if (r == Roles.AdvisersAndPartnerships) {
            advisersAndPartnershipsBeneficiariesCount++;
            _advisersAndPartnershipsBeneficiaries[_address] = true;
        } else if (r == Roles.Marketing) {
            marketingBeneficiariesCount++;
            _marketingBeneficiaries[_address] = true;
        } else {
            reserveFundsBeneficiariesCount++;
            _reserveFundsBeneficiaries[_address] = true;
        }
    }

    /// @notice to check the conditions while creating the vesting schedule
    /// @dev the _timeFrame is used to divide the given time into equal distribution during the vesting schedule
    /// @param r to decide the role of the beneficiary
    /// @param _beneficiary the address of the beneficiary
    /// @param _cliff to decide the cliff period
    /// @param _start to decide the start pereiod of the vesting schedule
    /// @param _duration to decide the duration of the vesting schedule
    /// @param _intervalPeriod to decide the interval period between the start and duration
    /// @param _revocable to decide if the beneficiary vesting schedule can be revoked
    /// @param _amount the amount being given into the vesting schedule
    /// @param vestingScheduleId the ID that is created of the particular vesting schedule
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
            uint256 _tgeAmount = 0;
            uint256 _extraTime = _intervalPeriod / 4;
            uint256 _timeFrame = _extraTime + _intervalPeriod;
            _duration = _timeFrame;
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
                _tgeAmount,
                false
            );
            vestingSchedulesTotalAmountforAdvisorsAndPartnership = vestingSchedulesTotalAmountforAdvisorsAndPartnership;
        } else if (r == Roles.Marketing) {
            uint256 _tgeAmount = (_amount * marketingTGE) / (100);
            _amount = _amount - (_tgeAmount);
            uint256 _extraTime = _duration / (4);
            uint256 _timeFrame = _extraTime + (_duration);
            _duration = _timeFrame;
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
                _tgeAmount,
                false
            );
            vestingSchedulesTotalAmountforMarketing = vestingSchedulesTotalAmountforMarketing;
        } else {
            uint256 _tgeAmount = 0;
            uint256 _extraTime = _intervalPeriod / (4);
            uint256 _timeFrame = _extraTime + (_intervalPeriod);
            _duration = _timeFrame;
            _vestingSchedulesforReserveFunds[vestingScheduleId] = VestingSchedule(
                true,
                _beneficiary,
                _cliff,
                _start,
                _duration,
                _intervalPeriod,
                _revocable,
                _amount,
                0,
                _tgeAmount,
                false
            );
            vestingSchedulesTotalAmountforReserveFunds = vestingSchedulesTotalAmountforReserveFunds;
        }
    }

    /// @notice calculating the total release amount
    /// @param vestingSchedule is to send in the details of the vesting schedule created
    /// @param r is the role of the beneficiary
    /// @return the calculated releaseable amount depending on the role
    function _computeReleasableAmount(VestingSchedule memory vestingSchedule, Roles r) internal view returns (uint256) {
        uint256 currentTime = getCurrentTime();
        if (r == Roles.AdvisersAndPartnerships) {
            if ((currentTime < vestingSchedule.cliff) || vestingSchedule.revoked == true) {
                return 0;
                // return vestingSchedule.tgeAmount;
            } else if (currentTime >= vestingSchedule.start + (vestingSchedule.duration)) {
                return vestingSchedule.amountTotal - (vestingSchedule.released);
            } else {
                uint256 cliffTimeEnd = vestingSchedule.cliff;
                uint256 timeFromStart = currentTime - (cliffTimeEnd);
                uint256 timePerInterval = vestingSchedule.intervalPeriod;
                uint256 vestedIntervalPeriods = timeFromStart / (timePerInterval);
                uint256 vestedTime = vestedIntervalPeriods * (timePerInterval);
                uint256 vestedAmount = ((vestingSchedule.amountTotal) * (vestedTime)) / (vestingSchedule.duration);
                vestedAmount = vestedAmount - (vestingSchedule.released);
                return vestedAmount;
            }
        } else if (r == Roles.Marketing) {
            if (vestingSchedule.revoked == true) {
                return 0;
            }
            if (currentTime < vestingSchedule.cliff) {
                return vestingSchedule.tgeAmount;
            } else if (currentTime >= vestingSchedule.start + (vestingSchedule.duration)) {
                return (vestingSchedule.amountTotal + (vestingSchedule.tgeAmount)) - (vestingSchedule.released);
            } else {
                uint256 cliffTimeEnd = vestingSchedule.cliff;
                uint256 timeFromStart = currentTime - (cliffTimeEnd);
                uint256 timePerInterval = vestingSchedule.intervalPeriod;
                uint256 vestedIntervalPeriods = timeFromStart / (timePerInterval);
                uint256 vestedTime = vestedIntervalPeriods * (timePerInterval);
                uint256 twentyPercentValue = ((vestingSchedule.amountTotal) * (20)) / (100);
                uint256 vestedAmount = ((vestingSchedule.amountTotal) * (vestedTime)) / (vestingSchedule.duration);
                vestedAmount =
                    (vestedAmount + (twentyPercentValue) + (vestingSchedule.tgeAmount)) -
                    (vestingSchedule.released);
                return vestedAmount;
            }
        } else {
            if ((currentTime < vestingSchedule.cliff) || vestingSchedule.revoked == true) {
                return 0;
            } else if (currentTime >= vestingSchedule.start + (vestingSchedule.duration)) {
                return vestingSchedule.amountTotal - (vestingSchedule.released);
            } else {
                uint256 cliffTimeEnd = vestingSchedule.cliff;
                uint256 timeFromStart = currentTime - (cliffTimeEnd);
                uint256 timePerInterval = vestingSchedule.intervalPeriod;
                uint256 vestedIntervalPeriods = timeFromStart / (timePerInterval);
                uint256 vestedTime = vestedIntervalPeriods * (timePerInterval);
                uint256 twentyPercentValue = (vestingSchedule.amountTotal * (20)) / (100);
                uint256 vestedAmount = (vestingSchedule.amountTotal * (vestedTime)) / (vestingSchedule.duration);
                vestedAmount = (vestedAmount - (vestingSchedule.released)) + (twentyPercentValue);
                return vestedAmount;
            }
        }
    }

    receive() external payable {}

    fallback() external payable {}

    /// @param _beneficiary is the address of the beneficiary
    /// @return the vesting schedule count by beneficiary
    function getVestingSchedulesCountByBeneficiary(address _beneficiary) external view returns (uint256) {
        return _holdersVestingCount[_beneficiary];
    }

    /// @param index is used to call the vesting Schedule ID by index or it's count
    /// @return the vesting ID by the index at which it is stored
    function getVestingIdAtIndex(uint256 index) external view returns (bytes32) {
        require(index < getVestingSchedulesCount(), "TokenVesting: index out of bounds");
        return _vestingSchedulesIds[index];
    }

    /// @param holder is the address of the holder of the account
    /// @param index is the index of the different vesting schdules held by the address
    /// @return the vesting schedule by address and index
    function getVestingScheduleByAddressAndIndex(
        address holder,
        uint256 index,
        Roles r
    ) external view returns (VestingSchedule memory) {
        return getVestingSchedule(computeVestingScheduleIdForAddressAndIndex(holder, index), r);
    }

    /// @param r is used to know the role
    /// @return total amount of each role
    function getVestingSchedulesTotalAmount(Roles r) external view returns (uint256) {
        if (r == Roles.AdvisersAndPartnerships) {
            return vestingSchedulesTotalAmountforAdvisorsAndPartnership;
        } else if (r == Roles.Marketing) {
            return vestingSchedulesTotalAmountforMarketing;
        } else {
            return vestingSchedulesTotalAmountforReserveFunds;
        }
    }

    /// @return the token of a particular address
    function getToken() external view returns (address) {
        return address(_token);
    }

    /// @notice this function is used to create the vesting schedule
    /// @param r to decide the role of the beneficiary
    /// @param _beneficiary the address of the beneficiary
    /// @param _cliff to decide the cliff period
    /// @param _start to decide the start pereiod of the vesting schedule
    /// @param _duration to decide the duration of the vesting schedule
    /// @param _intervalPeriod to decide the interval period between the start and duration
    /// @param _revocable to decide if the beneficiary vesting schedule can be revoked
    /// @param _amount the amount being given into the vesting schedule
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
        uint256 cliff = _start + (_cliff);

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
        _holdersVestingCount[_beneficiary] = currentVestingCount + (1);
    }

    /// @param vestingScheduleId is used to check the vesting schedule details
    /// @param r to get details about the role of the vesting schedule
    /// @return the vesting schedule
    function getVestingSchedule(bytes32 vestingScheduleId, Roles r) public view returns (VestingSchedule memory) {
        if (r == Roles.AdvisersAndPartnerships) {
            return _vestingSchedulesforAdvisorsAndPartnership[vestingScheduleId];
        } else if (r == Roles.Marketing) {
            return _vestingSchedulesforMarketing[vestingScheduleId];
        } else {
            return _vestingSchedulesforReserveFunds[vestingScheduleId];
        }
    }

    /// @param holder is the address of the holder of the account
    /// @param index is the index of the different vesting schdules held by the address
    /// @return vesting schedule ID for a particular index of an address
    function computeVestingScheduleIdForAddressAndIndex(address holder, uint256 index) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(holder, index));
    }

    /// @notice we use the revoke function to immediately stop the vesting schedule of a benificiary
    /// @param vestingScheduleId is used to check the vesting details of the beneficiary
    /// @param r is used to find the role of the beneficiary
    function revoke(bytes32 vestingScheduleId, Roles r)
        public
        onlyOwner
        onlyIfVestingScheduleNotRevoked(vestingScheduleId, r)
    {
        if (r == Roles.AdvisersAndPartnerships) {
            VestingSchedule storage vestingSchedule = _vestingSchedulesforAdvisorsAndPartnership[vestingScheduleId];
            require(vestingSchedule.revocable == true, "TokenVesting: vesting is not revocable");
            uint256 vestedAmount = _computeReleasableAmount(vestingSchedule, r);
            if (vestedAmount > 0) {
                vestingSchedule.revoked = true;

                uint256 unreleased = vestingSchedule.amountTotal - (vestingSchedule.released);
                vestingSchedulesTotalAmountforAdvisorsAndPartnership =
                    vestingSchedulesTotalAmountforAdvisorsAndPartnership -
                    (unreleased);

                releaseWhenRevoked(vestingScheduleId, vestedAmount, r);
            }
        } else if (r == Roles.Marketing) {
            VestingSchedule storage vestingSchedule = _vestingSchedulesforMarketing[vestingScheduleId];
            require(vestingSchedule.revocable == true, "TokenVesting: vesting is not revocable");
            uint256 vestedAmount = _computeReleasableAmount(vestingSchedule, r);
            if (vestedAmount > 0) {
                vestingSchedule.revoked = true;
                uint256 unreleased = vestingSchedule.amountTotal - (vestingSchedule.released);

                vestingSchedulesTotalAmountforMarketing = vestingSchedulesTotalAmountforMarketing - (unreleased);
                releaseWhenRevoked(vestingScheduleId, vestedAmount, r);
            }
        } else {
            VestingSchedule storage vestingSchedule = _vestingSchedulesforReserveFunds[vestingScheduleId];
            require(vestingSchedule.revocable == true, "TokenVesting: vesting is not revocable");
            uint256 vestedAmount = _computeReleasableAmount(vestingSchedule, r);
            if (vestedAmount > 0) {
                vestingSchedule.revoked = true;

                uint256 unreleased = vestingSchedule.amountTotal - (vestingSchedule.released);
                vestingSchedulesTotalAmountforReserveFunds = vestingSchedulesTotalAmountforReserveFunds - (unreleased);

                releaseWhenRevoked(vestingScheduleId, vestedAmount, r);
            }
        }
    }

    /// @notice to withdraw the desired amount
    /// @param amount is the amount that is to be withdrawn
    function withdraw(uint256 amount) public onlyOwner {
        require(this.getWithdrawableAmount() >= amount, "TokenVesting: not enough withdrawable funds");
        totalWithdrawableAmount = totalWithdrawableAmount - (amount);
        _token.safeTransfer(owner(), amount);
    }

    /// @param vestingScheduleId is used to get the details of the created vesting scheduel
    /// @param amount is used to get the total amount to be released
    /// @param r is used to know the role
    function release(
        bytes32 vestingScheduleId,
        uint256 amount,
        Roles r
    ) public onlyIfVestingScheduleNotRevoked(vestingScheduleId, r) {
        VestingSchedule storage vestingSchedule;
        if (r == Roles.AdvisersAndPartnerships) {
            vestingSchedule = _vestingSchedulesforAdvisorsAndPartnership[vestingScheduleId];
        } else if (r == Roles.Marketing) {
            vestingSchedule = _vestingSchedulesforMarketing[vestingScheduleId];
        } else {
            vestingSchedule = _vestingSchedulesforReserveFunds[vestingScheduleId];
        }
        bool isBeneficiary = msg.sender == vestingSchedule.beneficiary;
        uint256 currentTime = getCurrentTime();
        bool isOwner = msg.sender == owner();
        require(isBeneficiary || isOwner, "TokenVesting: only beneficiary and owner can release vested tokens");
        uint256 vestedAmount = _computeReleasableAmount(vestingSchedule, r);
        require(vestedAmount >= amount, "TokenVesting: cannot release tokens, not enough vested tokens");
        vestingSchedule.released = vestingSchedule.released + (amount);
        address payable beneficiaryPayable = payable(vestingSchedule.beneficiary);
        if (r == Roles.AdvisersAndPartnerships) {
            vestingSchedulesTotalAmountforAdvisorsAndPartnership =
                vestingSchedulesTotalAmountforAdvisorsAndPartnership -
                (amount);
        } else if (r == Roles.Marketing) {
            if (currentTime < vestingSchedule.cliff) {
                vestingSchedule.tgeAmount = vestingSchedule.tgeAmount - (amount);
                vestingSchedule.released = vestingSchedule.released - (amount);
            } else {
                vestingSchedulesTotalAmountforMarketing = vestingSchedulesTotalAmountforMarketing - (amount);
            }
        } else {
            vestingSchedulesTotalAmountforReserveFunds = vestingSchedulesTotalAmountforReserveFunds - (amount);
        }

        _token.safeTransfer(beneficiaryPayable, amount);
    }

    /// @notice to get the number of vesting schedules
    /// @return the number of vesting schedules
    function getVestingSchedulesCount() public view returns (uint256) {
        return _vestingSchedulesIds.length;
    }

    /// @param vestingScheduleId is used to get the details of the vesting schedule ID that has been created
    /// @param r is used to know the role
    /// @return the releasable amount left for the vesting schedule ID
    function computeReleasableAmount(bytes32 vestingScheduleId, Roles r) public view returns (uint256) {
        VestingSchedule storage vestingSchedule;
        if (r == Roles.AdvisersAndPartnerships) {
            vestingSchedule = _vestingSchedulesforAdvisorsAndPartnership[vestingScheduleId];
        } else if (r == Roles.Marketing) {
            vestingSchedule = _vestingSchedulesforMarketing[vestingScheduleId];
        } else {
            vestingSchedule = _vestingSchedulesforReserveFunds[vestingScheduleId];
        }
        return _computeReleasableAmount(vestingSchedule, r);
    }

    /// @return to get the total withdrawable amount
    function getWithdrawableAmount() public view returns (uint256) {
        return totalWithdrawableAmount;
    }

    /// @notice computes the next vesting schedule identifier for a given holder address
    /// @param holder is the holder and we input the adrress
    /// @return the next vesting schedule ID for holder
    function computeNextVestingScheduleIdForHolder(address holder) public view returns (bytes32) {
        return computeVestingScheduleIdForAddressAndIndex(holder, _holdersVestingCount[holder]);
    }

    /// @notice finds the last vesting schedule for a given holder address
    /// @param holder is the holder and we input the address here
    /// @param r is used to get to know the role of the holder
    /// @return the last vesting schedule for a given address
    function getLastVestingScheduleForHolder(address holder, Roles r) public view returns (VestingSchedule memory) {
        if (r == Roles.AdvisersAndPartnerships) {
            return
                _vestingSchedulesforAdvisorsAndPartnership[
                    computeVestingScheduleIdForAddressAndIndex(holder, _holdersVestingCount[holder] - 1)
                ];
        } else if (r == Roles.Marketing) {
            return
                _vestingSchedulesforMarketing[
                    computeVestingScheduleIdForAddressAndIndex(holder, _holdersVestingCount[holder] - 1)
                ];
        } else {
            return
                _vestingSchedulesforReserveFunds[
                    computeVestingScheduleIdForAddressAndIndex(holder, _holdersVestingCount[holder] - 1)
                ];
        }
    }

    /// @notice is used to set the TGE of the marketing role
    /// @param tgeForM is used to set the TGE for ecosystem and marketing
    /// @dev the same function can be used to set the TGE for different roles if needed
    function setTGE(uint256 tgeForM) public onlyOwner {
        marketingTGE = tgeForM;
    }

    /// @notice updates the pool and total amount for each role
    /// @dev this function is to be called once the TGE is set and the contract is deployed
    function calculatePools() public onlyOwner {
        _updateTotalSupply();
        vestingSchedulesTotalAmountforAdvisorsAndPartnership = (totalTokensinContract * (5)) / (100);
        vestingSchedulesTotalAmountforMarketing = (totalTokensinContract * (65)) / (10) / (100);
        vestingSchedulesTotalAmountforReserveFunds = (totalTokensinContract * (15)) / (100);
        marketingTGEPool = (vestingSchedulesTotalAmountforMarketing * (marketingTGE)) / (100);
        advisersAndPartnershipsVestingPool = vestingSchedulesTotalAmountforAdvisorsAndPartnership;
        reserveFundsVestingPool = vestingSchedulesTotalAmountforReserveFunds;
        marketingVestingPool = vestingSchedulesTotalAmountforMarketing - (marketingTGEPool);
        _updateTotalWithdrawableAmount();
    }

    /// @notice this function is used to release the amount before the revoke function
    /// @dev this function has been implemented to avoid the reentrancy issue in the revoke function
    /// @param vestingScheduleId to know the vesting schedule ID for the particular beneficiary
    /// @param amount the amount that is to be released
    /// @param r the role is decided by this parameter
    function releaseWhenRevoked(
        bytes32 vestingScheduleId,
        uint256 amount,
        Roles r
    ) public {
        VestingSchedule storage vestingSchedule;
        if (r == Roles.AdvisersAndPartnerships) {
            vestingSchedule = _vestingSchedulesforAdvisorsAndPartnership[vestingScheduleId];
        } else if (r == Roles.Marketing) {
            vestingSchedule = _vestingSchedulesforMarketing[vestingScheduleId];
        } else {
            vestingSchedule = _vestingSchedulesforReserveFunds[vestingScheduleId];
        }
        bool isBeneficiary = msg.sender == vestingSchedule.beneficiary;
        uint256 currentTime = getCurrentTime();
        bool isOwner = msg.sender == owner();
        require(isBeneficiary || isOwner, "TokenVesting: only beneficiary and owner can release vested tokens");
        uint256 vestedAmount = _computeReleasableAmountforRevoked(vestingSchedule, r);
        require(vestedAmount >= amount, "TokenVesting: cannot release tokens, not enough vested tokens");
        vestingSchedule.released = vestingSchedule.released + (amount);
        address payable beneficiaryPayable = payable(vestingSchedule.beneficiary);
        if (r == Roles.AdvisersAndPartnerships) {
            vestingSchedulesTotalAmountforAdvisorsAndPartnership =
                vestingSchedulesTotalAmountforAdvisorsAndPartnership -
                (amount);
        } else if (r == Roles.Marketing) {
            if (currentTime < vestingSchedule.cliff) {
                vestingSchedule.tgeAmount = vestingSchedule.tgeAmount - (amount);
                vestingSchedule.released = vestingSchedule.released - (amount);
            } else {
                vestingSchedulesTotalAmountforMarketing = vestingSchedulesTotalAmountforMarketing - (amount);
            }
        } else {
            vestingSchedulesTotalAmountforReserveFunds = vestingSchedulesTotalAmountforReserveFunds - (amount);
        }

        _token.safeTransfer(beneficiaryPayable, amount);
    }

    /// @notice this function is used to calculate the releasable amount for the revoke function
    /// @dev this function has been implemented to avoid the reentrancy issue in the revoke function
    /// @param vestingSchedule to know the vesting schedule required
    /// @param r the role is decided by this parameter
    function _computeReleasableAmountforRevoked(VestingSchedule memory vestingSchedule, Roles r)
        internal
        view
        returns (uint256)
    {
        uint256 currentTime = getCurrentTime();
        if (r == Roles.AdvisersAndPartnerships) {
            if ((currentTime < vestingSchedule.cliff)) {
                return 0;
                // return vestingSchedule.tgeAmount;
            } else if (currentTime >= vestingSchedule.start + (vestingSchedule.duration)) {
                return vestingSchedule.amountTotal - (vestingSchedule.released);
            } else {
                uint256 cliffTimeEnd = vestingSchedule.cliff;
                uint256 timeFromStart = currentTime - (cliffTimeEnd);
                uint256 timePerInterval = vestingSchedule.intervalPeriod;
                uint256 vestedIntervalPeriods = timeFromStart / (timePerInterval);
                uint256 vestedTime = vestedIntervalPeriods * (timePerInterval);
                uint256 vestedAmount = ((vestingSchedule.amountTotal) * (vestedTime)) / (vestingSchedule.duration);
                vestedAmount = vestedAmount - (vestingSchedule.released);
                return vestedAmount;
            }
        } else if (r == Roles.Marketing) {
            if (currentTime < vestingSchedule.cliff) {
                return vestingSchedule.tgeAmount;
            } else if (currentTime >= vestingSchedule.start + (vestingSchedule.duration)) {
                return (vestingSchedule.amountTotal + (vestingSchedule.tgeAmount)) - (vestingSchedule.released);
            } else {
                uint256 cliffTimeEnd = vestingSchedule.cliff;
                uint256 timeFromStart = currentTime - (cliffTimeEnd);
                uint256 timePerInterval = vestingSchedule.intervalPeriod;
                uint256 vestedIntervalPeriods = timeFromStart / (timePerInterval);
                uint256 vestedTime = vestedIntervalPeriods * (timePerInterval);
                uint256 twentyPercentValue = ((vestingSchedule.amountTotal) * (20)) / (100);
                uint256 vestedAmount = ((vestingSchedule.amountTotal) * (vestedTime)) / (vestingSchedule.duration);
                vestedAmount =
                    (vestedAmount + (twentyPercentValue) + (vestingSchedule.tgeAmount)) -
                    (vestingSchedule.released);
                return vestedAmount;
            }
        } else {
            if ((currentTime < vestingSchedule.cliff) || vestingSchedule.revoked == true) {
                return 0;
            } else if (currentTime >= vestingSchedule.start + (vestingSchedule.duration)) {
                return vestingSchedule.amountTotal - (vestingSchedule.released);
            } else {
                uint256 cliffTimeEnd = vestingSchedule.cliff;
                uint256 timeFromStart = currentTime - (cliffTimeEnd);
                uint256 timePerInterval = vestingSchedule.intervalPeriod;
                uint256 vestedIntervalPeriods = timeFromStart / (timePerInterval);
                uint256 vestedTime = vestedIntervalPeriods * (timePerInterval);
                uint256 twentyPercentValue = (vestingSchedule.amountTotal * (20)) / (100);
                uint256 vestedAmount = (vestingSchedule.amountTotal * (vestedTime)) / (vestingSchedule.duration);
                vestedAmount = (vestedAmount - (vestingSchedule.released)) + (twentyPercentValue);
                return vestedAmount;
            }
        }
    }
}
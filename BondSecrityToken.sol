// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract BondSecurityToken {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    
    address public custodian;
    address public issuer;
    address public owner;
    
    // Bond details
    string public isin;
    uint256 public faceValue; // in paise
    uint256 public couponRateBps; // basis points (900 = 9%)
    uint256 public issueDate;
    uint256 public maturityDate;
    uint256 public couponFrequency; // payments per year
    bool public isActive;
    
    // Coupon tracking
    uint256 public currentCouponPeriod;
    mapping(uint256 => uint256) public couponPerToken; // period => coupon amount
    mapping(address => mapping(uint256 => bool)) public couponClaimed;
    mapping(address => uint256) public lastClaimedPeriod;
    
    // ERC-20 basic mappings
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    // Permission mappings
    mapping(address => bool) public isAllowlisted;
    mapping(address => bool) public isBlacklisted;
    mapping(address => string) public investorKYC;
    
    // Events
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event AddressAllowlisted(address indexed account, string kycId);
    event AddressBlacklisted(address indexed account);
    event CouponDistributed(uint256 indexed period, uint256 couponPerToken);
    event CouponClaimed(address indexed investor, uint256 indexed period, uint256 amount);
    event BondMatured();
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier onlyActive() {
        require(isActive, "Bond is not active");
        _;
    }
    
    modifier onlyAllowlisted(address account) {
        require(isAllowlisted[account], "Address not allowlisted");
        require(!isBlacklisted[account], "Address is blacklisted");
        _;
    }
    
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply,
        address _custodian,
        address _issuer,
        string memory _isin,
        uint256 _faceValue,
        uint256 _couponRateBps,
        uint256 _maturityYears,
        uint256 _couponFrequency
    ) {
        name = _name;
        symbol = _symbol;
        totalSupply = _totalSupply * 10**decimals;
        custodian = _custodian;
        issuer = _issuer;
        owner = msg.sender;
        
        isin = _isin;
        faceValue = _faceValue;
        couponRateBps = _couponRateBps;
        couponFrequency = _couponFrequency;
        
        issueDate = block.timestamp;
        maturityDate = block.timestamp + (_maturityYears * 365 days);
        isActive = true;
        
        // Assign total supply to custodian
        balanceOf[_custodian] = totalSupply;
        
        // Initially allowlist custodian, issuer, and owner
        isAllowlisted[_custodian] = true;
        isAllowlisted[_issuer] = true;
        isAllowlisted[owner] = true;
        
        emit Transfer(address(0), _custodian, totalSupply);
    }
    
    function addToWhitelist(address account, string memory kycId) external onlyOwner {
        isAllowlisted[account] = true;
        investorKYC[account] = kycId;
        emit AddressAllowlisted(account, kycId);
    }
    
    function removeFromWhitelist(address account) external onlyOwner {
        isAllowlisted[account] = false;
        delete investorKYC[account];
    }
    
    function addToBlacklist(address account) external onlyOwner {
        isBlacklisted[account] = true;
        emit AddressBlacklisted(account);
    }
    
    function removeFromBlacklist(address account) external onlyOwner {
        isBlacklisted[account] = false;
    }
    
    function transfer(address to, uint256 amount) 
        external 
        onlyActive 
        onlyAllowlisted(msg.sender) 
        onlyAllowlisted(to) 
        returns (bool) 
    {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        
        emit Transfer(msg.sender, to, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) 
        external 
        onlyActive 
        onlyAllowlisted(from) 
        onlyAllowlisted(to) 
        returns (bool) 
    {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        
        emit Transfer(from, to, amount);
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    function distributeCoupons() external onlyOwner onlyActive {
        require(block.timestamp < maturityDate, "Bond has matured");
        
        currentCouponPeriod++;
        
        // Calculate coupon per token: (faceValue * couponRateBps / 10000) / couponFrequency
        uint256 couponAmount = (faceValue * couponRateBps) / (10000 * couponFrequency);
        couponPerToken[currentCouponPeriod] = couponAmount;
        
        emit CouponDistributed(currentCouponPeriod, couponAmount);
    }
    
    function claimCoupons() external onlyAllowlisted(msg.sender) {
        require(balanceOf[msg.sender] > 0, "No tokens held");
        
        uint256 totalCouponOwed = 0;
        uint256 userBalance = balanceOf[msg.sender];
        
        for (uint256 i = lastClaimedPeriod[msg.sender] + 1; i <= currentCouponPeriod; i++) {
            if (!couponClaimed[msg.sender][i]) {
                uint256 periodCoupon = (couponPerToken[i] * userBalance) / (10**decimals);
                totalCouponOwed += periodCoupon;
                couponClaimed[msg.sender][i] = true;
                emit CouponClaimed(msg.sender, i, periodCoupon);
            }
        }
        
        lastClaimedPeriod[msg.sender] = currentCouponPeriod;
    }
    
    function pendingCoupons(address account) external view returns (uint256) {
        if (balanceOf[account] == 0) return 0;
        
        uint256 totalPending = 0;
        uint256 userBalance = balanceOf[account];
        
        for (uint256 i = lastClaimedPeriod[account] + 1; i <= currentCouponPeriod; i++) {
            if (!couponClaimed[account][i]) {
                totalPending += (couponPerToken[i] * userBalance) / (10**decimals);
            }
        }
        
        return totalPending;
    }
    
    function matureBond() external onlyOwner {
        isActive = false;
        emit BondMatured();
    }
    
    function getBondDetails() external view returns (
        string memory _isin,
        uint256 _faceValue,
        uint256 _couponBps,
        uint256 _issueDate,
        uint256 _maturityDate,
        uint256 _couponFrequency,
        bool _isActive,
        uint256 _currentPeriod
    ) {
        return (
            isin,
            faceValue,
            couponRateBps,
            issueDate,
            maturityDate,
            couponFrequency,
            isActive,
            currentCouponPeriod
        );
    }
}
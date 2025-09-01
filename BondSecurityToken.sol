// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * BondSecurityToken - A Smart Contract for Tokenized Corporate Bonds
 * 
 * WHAT THIS DOES IN PLAIN ENGLISH:
 * - Creates digital tokens that represent pieces of a real corporate bond
 * - Only allows KYC-verified people to buy/sell these tokens
 * - Pays interest (coupons) to token holders automatically
 * - When bond matures, pays back the money and destroys tokens
 */

contract BondSecurityToken {
    
    // BASIC INFO ABOUT OUR BOND TOKEN
    string public name;           // Like "Keertana Bond 2025"
    string public symbol;         // Like "KGB25"
    uint8 public decimals = 18;   // How divisible tokens are (like rupee has 100 paise)
    uint256 public totalSupply;   // Total number of tokens created
    
    // WHO OWNS HOW MANY TOKENS
    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowances;
    
    // KYC AND SECURITY - Only verified people can trade!
    mapping(address => bool) public isAllowlisted;           // Who can trade tokens
    mapping(address => string) public investorKYC;          // Links wallet to KYC ID
    mapping(address => bool) public isBlacklisted;          // Blocked addresses
    
    // BOND SPECIFIC INFORMATION
    struct BondDetails {
        string isin;              // Unique bond identifier (like Aadhaar for bonds)
        uint256 faceValue;        // Value per token in paise (₹100 = 10000 paise)
        uint256 couponRate;       // Interest rate in basis points (9% = 900)
        uint256 issueDate;        // When bond was created
        uint256 maturityDate;     // When bond expires
        uint256 couponFrequency;  // How often interest is paid (quarterly = 4)
        bool isActive;            // Is this bond still valid?
    }
    
    BondDetails public bondInfo;
    
    // ROLES - Who can do what?
    address public owner;         // Platform owner
    address public custodian;     // Holds the real bond
    address public issuer;        // Company that issued the bond
    
    // CORPORATE ACTIONS (Interest payments, etc.)
    uint256 public totalCouponsDistributed;    // Total interest paid out
    uint256 public lastCouponDate;             // When was last interest paid
    mapping(address => uint256) public couponsClaimed;  // How much each person claimed
    
    // EVENTS - Like notifications when things happen
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event InvestorWhitelisted(address indexed investor, string kycId);
    event InvestorBlacklisted(address indexed investor);
    event CouponDistributed(uint256 totalAmount, uint256 perToken);
    event CouponClaimed(address indexed investor, uint256 amount);
    event BondMatured();
    event TransferBlocked(address indexed from, address indexed to, string reason);
    
    // SECURITY CHECKS
    modifier onlyOwner() {
        require(msg.sender == owner, "Only platform owner can do this");
        _;
    }
    
    modifier onlyCustodian() {
        require(msg.sender == custodian, "Only custodian can do this");
        _;
    }
    
    modifier onlyAllowlisted(address account) {
        require(isAllowlisted[account], "Address not KYC verified");
        require(!isBlacklisted[account], "Address is blacklisted");
        _;
    }
    
    modifier bondActive() {
        require(bondInfo.isActive, "Bond is not active");
        require(block.timestamp < bondInfo.maturityDate, "Bond has matured");
        _;
    }
    
    /**
     * CONSTRUCTOR - Sets up the bond when contract is deployed
     * Think of this like filling out a form when creating a new bond
     */
    constructor(
        string memory _name,           // "Keertana Corporate Bond 2025"
        string memory _symbol,         // "KGB25"
        uint256 _totalSupply,          // 1000000 (for ₹10 crore bond at ₹100 per token)
        address _custodian,            // Who holds the real bond
        address _issuer,               // Company that issued bond
        string memory _isin,           // Bond's unique ID
        uint256 _faceValue,            // ₹100 in paise = 10000
        uint256 _couponRate,           // 9% = 900 basis points
        uint256 _maturityYears,        // 5 years
        uint256 _couponFrequency       // 4 = quarterly payments
    ) {
        name = _name;
        symbol = _symbol;
        totalSupply = _totalSupply;
        owner = msg.sender;            // Person deploying contract becomes owner
        custodian = _custodian;
        issuer = _issuer;
        
        // Set up bond details
        bondInfo = BondDetails({
            isin: _isin,
            faceValue: _faceValue,
            couponRate: _couponRate,
            issueDate: block.timestamp,
            maturityDate: block.timestamp + (_maturityYears * 365 days),
            couponFrequency: _couponFrequency,
            isActive: true
        });
        
        // Give all tokens to custodian initially
        balances[_custodian] = _totalSupply;
        
        // Automatically whitelist important addresses
        isAllowlisted[_custodian] = true;
        isAllowlisted[_issuer] = true;
        isAllowlisted[owner] = true;
        
        investorKYC[_custodian] = "CUSTODIAN";
        investorKYC[_issuer] = "ISSUER";
        investorKYC[owner] = "PLATFORM";
        
        emit Transfer(address(0), _custodian, _totalSupply);
    }
    
    /**
     * CHECK TOKEN BALANCE
     * Like checking how much money you have in your wallet
     */
    function balanceOf(address account) public view returns (uint256) {
        return balances[account];
    }
    
    /**
     * TRANSFER TOKENS - Send tokens to someone else
     * Like sending money to a friend, but with security checks
     */
    function transfer(address to, uint256 amount) 
        public 
        bondActive 
        onlyAllowlisted(msg.sender)
        onlyAllowlisted(to)
        returns (bool) 
    {
        require(balances[msg.sender] >= amount, "Not enough tokens");
        require(to != address(0), "Cannot send to null address");
        
        balances[msg.sender] -= amount;
        balances[to] += amount;
        
        emit Transfer(msg.sender, to, amount);
        return true;
    }
    
    /**
     * APPROVE SOMEONE TO SPEND YOUR TOKENS
     * Like giving someone permission to use your credit card
     */
    function approve(address spender, uint256 amount) public returns (bool) {
        allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    /**
     * TRANSFER FROM - Spend someone else's tokens (if approved)
     * Like using someone's credit card (with their permission)
     */
    function transferFrom(address from, address to, uint256 amount) 
        public 
        bondActive
        onlyAllowlisted(from)
        onlyAllowlisted(to)
        returns (bool) 
    {
        require(balances[from] >= amount, "Not enough tokens");
        require(allowances[from][msg.sender] >= amount, "Not approved for this amount");
        require(to != address(0), "Cannot send to null address");
        
        balances[from] -= amount;
        balances[to] += amount;
        allowances[from][msg.sender] -= amount;
        
        emit Transfer(from, to, amount);
        return true;
    }
    
    /**
     * ADD INVESTOR TO WHITELIST - Allow someone to trade tokens
     * Like adding someone to a VIP list
     */
    function addToWhitelist(address investor, string memory kycId) 
        public 
        onlyOwner 
    {
        isAllowlisted[investor] = true;
        investorKYC[investor] = kycId;
        emit InvestorWhitelisted(investor, kycId);
    }
    
    /**
     * ADD MULTIPLE INVESTORS AT ONCE
     * Like adding a whole group to the VIP list
     */
    function batchWhitelist(address[] memory investors, string[] memory kycIds) 
        public 
        onlyOwner 
    {
        require(investors.length == kycIds.length, "Arrays must be same length");
        
        for (uint i = 0; i < investors.length; i++) {
            isAllowlisted[investors[i]] = true;
            investorKYC[investors[i]] = kycIds[i];
            emit InvestorWhitelisted(investors[i], kycIds[i]);
        }
    }
    
    /**
     * BLACKLIST AN INVESTOR - Block someone from trading
     * Like banning someone from the VIP list
     */
    function blacklistInvestor(address investor) public onlyOwner {
        isBlacklisted[investor] = true;
        emit InvestorBlacklisted(investor);
    }
    
    /**
     * DISTRIBUTE COUPONS - Pay interest to all token holders
     * Like a company paying dividends
     */
    function distributeCoupons() public onlyCustodian bondActive {
        uint256 timeSinceLastCoupon = block.timestamp - lastCouponDate;
        uint256 expectedGap = 365 days / bondInfo.couponFrequency;  // Quarterly = 91.25 days
        
        require(timeSinceLastCoupon >= expectedGap, "Too early for coupon payment");
        
        // Calculate coupon per token
        // Example: 9% annual on ₹100 token, paid quarterly = ₹2.25 per token
        uint256 couponPerToken = (bondInfo.faceValue * bondInfo.couponRate) / 
                                (10000 * bondInfo.couponFrequency);
        
        uint256 totalCouponAmount = totalSupply * couponPerToken;
        totalCouponsDistributed += totalCouponAmount;
        lastCouponDate = block.timestamp;
        
        emit CouponDistributed(totalCouponAmount, couponPerToken);
    }
    
    /**
     * CLAIM YOUR COUPON PAYMENT - Withdraw interest earned
     * Like withdrawing interest from your savings account
     */
    function claimCoupons() public onlyAllowlisted(msg.sender) returns (uint256) {
        uint256 balance = balances[msg.sender];
        require(balance > 0, "No tokens held");
        
        // Calculate how much coupon this person should get
        uint256 couponPerToken = (bondInfo.faceValue * bondInfo.couponRate) / 
                                (10000 * bondInfo.couponFrequency);
        
        uint256 totalOwedCoupons = balance * couponPerToken * 
                                  (totalCouponsDistributed / (totalSupply * couponPerToken));
        
        uint256 pendingCoupons = totalOwedCoupons - couponsClaimed[msg.sender];
        require(pendingCoupons > 0, "No coupons to claim");
        
        couponsClaimed[msg.sender] += pendingCoupons;
        
        // Note: In real implementation, this would transfer actual money (INR/stablecoin)
        // For now, we just record the claim
        
        emit CouponClaimed(msg.sender, pendingCoupons);
        return pendingCoupons;
    }
    
    /**
     * MATURE THE BOND - End the bond's life and pay back principal
     * Like closing a fixed deposit when it matures
     */
    function matureBond() public onlyCustodian {
        require(block.timestamp >= bondInfo.maturityDate, "Bond not yet matured");
        require(bondInfo.isActive, "Bond already matured");
        
        bondInfo.isActive = false;
        
        // In real implementation, principal would be paid back here
        // and all tokens would be burned (destroyed)
        
        emit BondMatured();
    }
    
    /**
     * GET BOND INFORMATION
     * Like checking details of your fixed deposit
     */
    function getBondDetails() public view returns (
        string memory,    // ISIN
        uint256,         // Face Value
        uint256,         // Coupon Rate
        uint256,         // Issue Date
        uint256,         // Maturity Date
        uint256,         // Coupon Frequency
        bool             // Is Active
    ) {
        return (
            bondInfo.isin,
            bondInfo.faceValue,
            bondInfo.couponRate,
            bondInfo.issueDate,
            bondInfo.maturityDate,
            bondInfo.couponFrequency,
            bondInfo.isActive
        );
    }
    
    /**
     * CALCULATE PENDING COUPONS - See how much interest you can claim
     * Like checking pending interest in your savings account
     */
    function pendingCoupons(address investor) public view returns (uint256) {
        uint256 balance = balances[investor];
        if (balance == 0) return 0;
        
        uint256 couponPerToken = (bondInfo.faceValue * bondInfo.couponRate) / 
                                (10000 * bondInfo.couponFrequency);
        
        uint256 totalOwedCoupons = balance * couponPerToken * 
                                  (totalCouponsDistributed / (totalSupply * couponPerToken));
        
        return totalOwedCoupons - couponsClaimed[investor];
    }
}

/*
HOW THIS CONTRACT WORKS - STEP BY STEP:

1. DEPLOYMENT: 
   - Creates bond token (like KGB25)
   - Sets up all the rules (interest rate, maturity date, etc.)
   - Gives all tokens to custodian initially

2. INVESTOR ONBOARDING:
   - Admin adds KYC-verified investors to whitelist
   - Only whitelisted people can buy/sell tokens

3. PRIMARY ISSUANCE:
   - Custodian transfers tokens to investors
   - Investors pay money, get bond tokens

4. SECONDARY TRADING:
   - Investors can trade tokens with each other
   - All transfers are checked for KYC compliance

5. COUPON PAYMENTS:
   - Custodian triggers coupon distribution quarterly
   - Investors can claim their interest payments

6. MATURITY:
   - When bond expires, principal is paid back
   - All tokens become worthless (burned)

OUTPUTS YOU'LL SEE:
- Transfer events when tokens move
- Whitelist events when investors are added
- Coupon events when interest is paid
- All data is transparent on blockchain
*/
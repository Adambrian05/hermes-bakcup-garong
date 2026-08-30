// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title LendingPool — undercollateralized lending with credit lines
contract LendingPool is ReentrancyGuard {
    struct Loan {
        uint256 principal;
        uint256 interestRate;   // annual, 1e18 = 100%
        uint64 startTime;
        uint64 maturity;
        uint8 state;            // 0=active, 1=repaid, 2=defaulted
    }
    
    IERC20 public immutable usdc;
    mapping(address => mapping(uint256 => Loan)) public loans;
    mapping(address => uint256) public loanCount;
    mapping(address => uint256) public creditLine;      // max borrowable
    mapping(address => uint256) public outstandingDebt;  // total owed
    
    uint256 public poolBalance;    // total USDC in pool
    uint256 public totalLent;      // total lent out
    address public oracle;         // credit score oracle
    address public liquidator;
    
    uint256 public constant LIQUIDATION_BONUS = 500; // 5%
    
    constructor(address _usdc, address _oracle, address _liquidator) {
        usdc = IERC20(_usdc);
        oracle = _oracle;
        liquidator = _liquidator;
    }
    
    /// @notice Lenders deposit USDC into the pool
    function supply(uint256 amount) external nonReentrant {
        usdc.transferFrom(msg.sender, address(this), amount);
        poolBalance += amount;
    }
    
    /// @notice Borrow against credit line
    function borrow(uint256 amount) external nonReentrant {
        require(amount <= creditLine[msg.sender] - outstandingDebt[msg.sender], "over credit");
        require(amount <= poolBalance, "insufficient pool");
        
        uint256 id = loanCount[msg.sender]++;
        loans[msg.sender][id] = Loan({
            principal: amount,
            interestRate: IOracle(oracle).getRate(msg.sender),
            startTime: uint64(block.timestamp),
            maturity: uint64(block.timestamp + 30 days),
            state: 0
        });
        
        outstandingDebt[msg.sender] += amount;
        poolBalance -= amount;
        totalLent += amount;
        
        usdc.transfer(msg.sender, amount);
    }
    
    /// @notice Repay a specific loan
    function repay(uint256 loanId) external nonReentrant {
        Loan storage loan = loans[msg.sender][loanId];
        require(loan.state == 0, "not active");
        
        uint256 interest = _calcInterest(loan);
        uint256 totalOwed = loan.principal + interest;
        
        usdc.transferFrom(msg.sender, address(this), totalOwed);
        
        loan.state = 1;
        outstandingDebt[msg.sender] -= loan.principal;
        poolBalance += totalOwed;
        totalLent -= loan.principal;
    }
    
    /// @notice Liquidate overdue loan (permissionless)
    function liquidate(address borrower, uint256 loanId) external {
        Loan storage loan = loans[borrower][loanId];
        require(loan.state == 0, "not active");
        require(block.timestamp > loan.maturity, "not overdue");
        
        uint256 interest = _calcInterest(loan);
        uint256 totalOwed = loan.principal + interest;
        uint256 bonus = totalOwed * LIQUIDATION_BONUS / 10000;
        
        // Liquidator pays the debt, gets bonus from pool
        usdc.transferFrom(msg.sender, address(this), totalOwed);
        usdc.transfer(msg.sender, bonus);
        
        loan.state = 2;
        outstandingDebt[borrower] -= loan.principal;
        poolBalance += totalOwed - bonus;
        totalLent -= loan.principal;
    }
    
    /// @notice Admin sets credit line based on off-chain score
    function setCreditLine(address user, uint256 amount) external {
        require(msg.sender == oracle, "not oracle");
        creditLine[user] = amount;
    }
    
    /// @notice Emergency: admin can reduce credit line
    function reduceCreditLine(address user, uint256 newAmount) external {
        require(msg.sender == oracle, "not oracle");
        require(newAmount < creditLine[user], "must reduce");
        creditLine[user] = newAmount;
    }
    
    function _calcInterest(Loan memory loan) internal view returns (uint256) {
        uint256 elapsed = block.timestamp - loan.startTime;
        return loan.principal * loan.interestRate * elapsed / (365 days * 1e18);
    }
    
    /// @notice View: total pool value
    function poolValue() external view returns (uint256) {
        return poolBalance + totalLent;
    }
}

interface IOracle {
    function getRate(address user) external view returns (uint256);
}

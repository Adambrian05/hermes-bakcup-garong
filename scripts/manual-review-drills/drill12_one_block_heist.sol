// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * DRILL 12: THE ONE-BLOCK HEIST
 * Difficulty: EXPERT
 * Focus: Flash loan + AMM price manipulation + lending protocol drain
 * 
 * THIS IS THE #1 MOST COMMON DEFI EXPLOIT PATTERN.
 * Harvest Finance ($34M), Cream Finance ($130M), Mango ($114M) — all this pattern.
 * 
 * THE BUG IS REAL. ONE TRANSACTION. FULL DRAIN.
 * 
 * RULES:
 * - Everything happens in ONE block (one transaction).
 * - Flash loan provides the capital.
 * - AMM is the oracle (spot price).
 * - Lending protocol trusts the AMM price.
 * - Show exact numbers.
 */

// ============================================================
// CONTRACT 1: SimpleAMM (constant product x*y=k)
// ============================================================
contract SimpleAMM {
    uint256 public reserveTokenA; // e.g., WETH
    uint256 public reserveTokenB; // e.g., USDC
    
    uint256 public totalLP;
    mapping(address => uint256) public lpBalance;
    
    constructor(uint256 _reserveA, uint256 _reserveB) {
        reserveTokenA = _reserveA;
        reserveTokenB = _reserveB;
        totalLP = 1000e18;
        lpBalance[msg.sender] = 1000e18;
    }
    
    // Get spot price of TokenA in terms of TokenB
    function getPriceA() external view returns (uint256) {
        // price = reserveB / reserveA (scaled 1e18)
        return reserveTokenB * 1e18 / reserveTokenA;
    }
    
    // Swap TokenA -> TokenB
    function swapAToB(uint256 amountA) external returns (uint256 amountB) {
        require(amountA > 0, "zero");
        // Constant product: (reserveA + amountA) * (reserveB - amountB) = reserveA * reserveB
        uint256 newReserveA = reserveTokenA + amountA;
        uint256 newReserveB = reserveTokenA * reserveTokenB / newReserveA;
        amountB = reserveTokenB - newReserveB;
        
        // 0.3% fee
        amountB = amountB * 997 / 1000;
        
        reserveTokenA = newReserveA;
        reserveTokenB -= amountB;
        
        // In real code: transfer tokens
    }
    
    // Swap TokenB -> TokenA
    function swapBToA(uint256 amountB) external returns (uint256 amountA) {
        require(amountB > 0, "zero");
        uint256 newReserveB = reserveTokenB + amountB;
        uint256 newReserveA = reserveTokenA * reserveTokenB / newReserveB;
        amountA = reserveTokenA - newReserveA;
        
        // 0.3% fee
        amountA = amountA * 997 / 1000;
        
        reserveTokenB = newReserveB;
        reserveTokenA -= amountA;
        
        // In real code: transfer tokens
    }
    
    // Add liquidity
    function addLiquidity(uint256 amountA, uint256 amountB) external returns (uint256 lp) {
        if (totalLP == 0) {
            lp = amountA; // simplified
        } else {
            uint256 lpA = amountA * totalLP / reserveTokenA;
            uint256 lpB = amountB * totalLP / reserveTokenB;
            lp = lpA < lpB ? lpA : lpB;
        }
        
        reserveTokenA += amountA;
        reserveTokenB += amountB;
        totalLP += lp;
        lpBalance[msg.sender] += lp;
    }
    
    // Remove liquidity
    function removeLiquidity(uint256 lp) external returns (uint256 amountA, uint256 amountB) {
        require(lp <= lpBalance[msg.sender], "too much");
        
        amountA = lp * reserveTokenA / totalLP;
        amountB = lp * reserveTokenB / totalLP;
        
        reserveTokenA -= amountA;
        reserveTokenB -= amountB;
        totalLP -= lp;
        lpBalance[msg.sender] -= lp;
    }
}

// ============================================================
// CONTRACT 2: LendingProtocol (uses AMM spot price as oracle)
// ============================================================
contract LendingProtocol {
    SimpleAMM public immutable oracle; // ← AMM IS THE ORACLE
    
    uint256 public constant LTV = 75e16; // 75% loan-to-value
    uint256 public constant LIQUIDATION_THRESHOLD = 80e16;
    uint256 public constant LIQUIDATION_BONUS = 10e16; // 10% bonus for liquidator
    
    struct Loan {
        uint256 collateralA; // TokenA deposited
        uint256 debtB;       // TokenB borrowed
    }
    
    mapping(address => Loan) public loans;
    uint256 public totalCollateral;
    uint256 public totalDebt;
    uint256 public protocolBalanceB; // TokenB available to borrow
    
    constructor(address _oracle) {
        oracle = SimpleAMM(_oracle);
    }
    
    // Fund the lending pool with TokenB
    function fundPool(uint256 amountB) external {
        protocolBalanceB += amountB;
        // In real code: IERC20(tokenB).transferFrom(msg.sender, address(this), amountB);
    }
    
    // Deposit TokenA as collateral, borrow TokenB
    function depositAndBorrow(uint256 collateralAmount, uint256 borrowAmount) external {
        require(collateralAmount > 0, "zero coll");
        
        // VALUE COLLATERAL USING AMM SPOT PRICE ← THE VULNERABILITY
        uint256 priceA = oracle.getPriceA(); // TokenB per TokenA
        uint256 collateralValue = collateralAmount * priceA / 1e18;
        uint256 maxBorrow = collateralValue * LTV / 1e18;
        
        require(borrowAmount <= maxBorrow, "undercollateralized");
        require(borrowAmount <= protocolBalanceB, "insufficient liquidity");
        
        loans[msg.sender].collateralA += collateralAmount;
        loans[msg.sender].debtB += borrowAmount;
        totalCollateral += collateralAmount;
        totalDebt += borrowAmount;
        protocolBalanceB -= borrowAmount;
        
        // In real code: transfers
    }
    
    // Repay debt and withdraw collateral
    function repayAndWithdraw(uint256 repayAmount, uint256 withdrawAmount) external {
        Loan storage loan = loans[msg.sender];
        
        uint256 repay = repayAmount > loan.debtB ? loan.debtB : repayAmount;
        loan.debtB -= repay;
        totalDebt -= repay;
        protocolBalanceB += repay;
        
        if (withdrawAmount > 0) {
            require(withdrawAmount <= loan.collateralA, "too much");
            loan.collateralA -= withdrawAmount;
            totalCollateral -= withdrawAmount;
            
            // Check health after withdrawal
            if (loan.debtB > 0) {
                uint256 priceA = oracle.getPriceA();
                uint256 collValue = loan.collateralA * priceA / 1e18;
                require(loan.debtB * 1e18 / collValue <= LTV, "unhealthy");
            }
        }
        
        // In real code: transfers
    }
    
    // Liquidate an unhealthy position
    function liquidate(address user) external {
        Loan storage loan = loans[user];
        require(loan.debtB > 0, "no debt");
        
        uint256 priceA = oracle.getPriceA();
        uint256 collValue = loan.collateralA * priceA / 1e18;
        uint256 healthRatio = loan.debtB * 1e18 / collValue;
        
        require(healthRatio > LIQUIDATION_THRESHOLD, "healthy");
        
        // Liquidator repays debt, gets collateral + bonus
        uint256 debtToRepay = loan.debtB;
        uint256 collToSeize = debtToRepay * (1e18 + LIQUIDATION_BONUS) / priceA;
        
        if (collToSeize > loan.collateralA) {
            collToSeize = loan.collateralA;
        }
        
        loan.collateralA -= collToSeize;
        loan.debtB = 0;
        totalCollateral -= collToSeize;
        totalDebt -= debtToRepay;
        protocolBalanceB += debtToRepay;
        
        // Liquidator gets the collateral
        // In real code: IERC20(tokenA).transfer(msg.sender, collToSeize);
        // Liquidator pays the debt
        // In real code: IERC20(tokenB).transferFrom(msg.sender, address(this), debtToRepay);
    }
    
    function getHealthRatio(address user) external view returns (uint256) {
        Loan storage loan = loans[user];
        if (loan.debtB == 0) return type(uint256).max;
        uint256 priceA = oracle.getPriceA();
        uint256 collValue = loan.collateralA * priceA / 1e18;
        return collValue * 1e18 / loan.debtB;
    }
}

// ============================================================
// CONTRACT 3: FlashLoanProvider
// ============================================================
contract FlashLoanProvider {
    uint256 public constant FEE_BPS = 9; // 0.09%
    
    uint256 public poolBalanceA;
    uint256 public poolBalanceB;
    
    constructor() {
        poolBalanceA = 100_000e18; // 100K TokenA
        poolBalanceB = 200_000_000e18; // 200M TokenB
    }
    
    function flashLoanA(uint256 amount, address target, bytes calldata data) external {
        require(amount <= poolBalanceA, "insufficient");
        uint256 fee = amount * FEE_BPS / 10000;
        
        poolBalanceA -= amount;
        // In real code: IERC20(tokenA).transfer(target, amount);
        
        (bool success,) = target.call(data);
        require(success, "flash loan failed");
        
        // In real code: require balance >= amount + fee
        poolBalanceA += amount + fee;
    }
    
    function flashLoanB(uint256 amount, address target, bytes calldata data) external {
        require(amount <= poolBalanceB, "insufficient");
        uint256 fee = amount * FEE_BPS / 10000;
        
        poolBalanceB -= amount;
        // In real code: IERC20(tokenB).transfer(target, amount);
        
        (bool success,) = target.call(data);
        require(success, "flash loan failed");
        
        poolBalanceB += amount + fee;
    }
}

/**
 * THE ATTACK (one transaction):
 * 
 * Initial state:
 * - AMM: 10,000 TokenA / 20,000,000 TokenB (price: 2000 B per A)
 * - LendingProtocol: funded with 10,000,000 TokenB
 * - FlashLoan: 100,000 A / 200,000,000 B available
 * 
 * YOUR TASK:
 * 
 * Step 1: Flash loan a LARGE amount of TokenB
 * Step 2: Swap TokenB -> TokenA on AMM (this PUMPS TokenA price)
 * Step 3: Deposit TokenA into LendingProtocol at INFLATED price
 * Step 4: Borrow MAX TokenB against inflated collateral
 * Step 5: Swap remaining TokenA back to TokenB on AMM
 * Step 6: Repay flash loan + fee
 * Step 7: KEEP THE PROFIT (borrowed TokenB that's now undercollateralized)
 * 
 * QUESTIONS:
 * 
 * Q1: What's the optimal flash loan amount to maximize profit?
 *     (Hint: too much = price impact eats your profit. Too little = not enough collateral.)
 * 
 * Q2: After the attack, what's the AMM price? What's the lending protocol's loss?
 * 
 * Q3: Can you make this MORE profitable by also manipulating the price
 *     DOWNWARD after borrowing (to make your position "worth less" but
 *     you already have the borrowed funds)?
 * 
 * Q4: What if the lending protocol used a TWAP instead of spot price?
 *     Would the attack still work? Why or why not?
 * 
 * Q5: BONUS — Can you chain this with a liquidation?
 *     (Hint: what if there's an EXISTING borrower whose position
 *     becomes liquidatable when you pump the price, then you
 *     liquidate them at the inflated price?)
 * 
 * SHOW EXACT NUMBERS FOR EACH STEP.
 */

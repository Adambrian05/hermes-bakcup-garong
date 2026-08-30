// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title YieldVault — users deposit ERC20, earn yield from strategy
contract YieldVault is ReentrancyGuard {
    IERC20 public immutable asset;
    uint256 public totalShares;
    mapping(address => uint256) public shares;
    mapping(address => uint256) public lastDepositTime;
    
    uint256 public strategyBalance;  // funds deployed to strategy
    address public strategy;         // external yield strategy
    address public feeRecipient;
    uint256 public feeBps = 500;     // 5% performance fee
    
    uint256 private _totalAssets;    // cached total assets
    
    constructor(address _asset, address _strategy, address _feeRecipient) {
        asset = IERC20(_asset);
        strategy = _strategy;
        feeRecipient = _feeRecipient;
    }
    
    function deposit(uint256 amount) external nonReentrant {
        _harvestYield();
        
        uint256 newShares;
        if (totalShares == 0) {
            newShares = amount;
        } else {
            newShares = amount * totalShares / totalAssets();
        }
        
        asset.transferFrom(msg.sender, address(this), amount);
        shares[msg.sender] += newShares;
        totalShares += newShares;
        lastDepositTime[msg.sender] = block.timestamp;
    }
    
    function withdraw(uint256 shareAmount) external nonReentrant {
        require(shares[msg.sender] >= shareAmount, "insufficient shares");
        require(block.timestamp >= lastDepositTime[msg.sender] + 1 days, "locked");
        
        uint256 assetsOut = shareAmount * totalAssets() / totalShares;
        
        shares[msg.sender] -= shareAmount;
        totalShares -= shareAmount;
        
        _harvestYield();
        
        if (address(this).balance < assetsOut) {
            _withdrawFromStrategy(assetsOut - address(this).balance);
        }
        
        asset.transfer(msg.sender, assetsOut);
    }
    
    function totalAssets() public view returns (uint256) {
        return asset.balanceOf(address(this)) + strategyBalance;
    }
    
    function _harvestYield() internal {
        uint256 before = asset.balanceOf(address(this));
        IStrategy(strategy).harvest();
        uint256 after_ = asset.balanceOf(address(this));
        
        uint256 yield = after_ - before;
        if (yield > 0) {
            uint256 fee = yield * feeBps / 10000;
            asset.transfer(feeRecipient, fee);
            strategyBalance = strategyBalance + yield - fee;
        }
    }
    
    function _withdrawFromStrategy(uint256 amount) internal {
        IStrategy(strategy).withdraw(amount);
        strategyBalance -= amount;
    }
    
    function donate(uint256 amount) external {
        asset.transferFrom(msg.sender, address(this), amount);
    }
}

interface IStrategy {
    function harvest() external;
    function withdraw(uint256 amount) external;
}

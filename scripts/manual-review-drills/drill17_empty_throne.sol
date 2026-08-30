// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * DRILL 17: THE EMPTY THRONE
 * Difficulty: EXPERT
 * Focus: Vault share inflation / donation attacks / accounting order
 *
 * THREE BUGS ACROSS TWO VAULT IMPLEMENTATIONS FROM THE SAME TEAM.
 * ALL ARE REAL PATTERNS SEEN IN C4/SHERLOCK FINDINGS.
 *
 * Bug #1 (NaiveVault):  first-depositor share inflation via donation
 * Bug #2 (OrderVault):  transferFrom BEFORE share accounting (accounting order)
 * Bug #3 (both):        redeem rounds UP in the user's favor
 */

// ============================================================
// TOKEN (plain ERC20, no hooks)
// ============================================================
contract MockToken {
    string public name = "Mock";
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "insufficient");
        require(allowance[from][msg.sender] >= amount, "not approved");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

// ============================================================
// NAIVE VAULT — shares = balanceOf(this)
// (the "obvious" way people write vaults, and the one that breaks)
// ============================================================
contract NaiveVault {
    MockToken public asset;
    uint256 public totalShares;
    mapping(address => uint256) public shares;

    constructor(address _asset) { asset = MockToken(_asset); }

    function deposit(uint256 amount) external {
        asset.transferFrom(msg.sender, address(this), amount);
        uint256 newShares;
        if (totalShares == 0) {
            newShares = amount; // 1:1 bootstrap
        } else {
            // shares proportional to assets held
            newShares = amount * totalShares / asset.balanceOf(address(this));
        }
        shares[msg.sender] += newShares;
        totalShares += newShares;
    }

    function redeem(uint256 amount) external {
        require(shares[msg.sender] >= amount, "not enough shares");
        uint256 assets = amount * asset.balanceOf(address(this)) / totalShares;
        shares[msg.sender] -= amount;
        totalShares -= amount;
        asset.transfer(msg.sender, assets);
    }

    function sharePrice() public view returns (uint256) {
        if (totalShares == 0) return 1e18;
        return asset.balanceOf(address(this)) * 1e18 / totalShares;
    }
}

// ============================================================
// ORDER VAULT — same team, "fixed" version
// (accounting uses totalAssets() read BEFORE the transfer)
// ============================================================
contract OrderVault {
    MockToken public asset;
    uint256 public totalShares;
    uint256 public totalAssetsTracked;
    mapping(address => uint256) public shares;

    constructor(address _asset) { asset = MockToken(_asset); }

    function totalAssets() public view returns (uint256) {
        return totalAssetsTracked;
    }

    function deposit(uint256 amount) external {
        // READ BEFORE TRANSFER (accounting order — is this right?)
        uint256 assetsBefore = totalAssetsTracked;

        asset.transferFrom(msg.sender, address(this), amount);

        uint256 newShares;
        if (totalShares == 0) {
            newShares = amount;
        } else {
            newShares = amount * totalShares / assetsBefore;
        }
        shares[msg.sender] += newShares;
        totalShares += newShares;
        totalAssetsTracked += amount;
    }

    function redeem(uint256 amount) external {
        require(shares[msg.sender] >= amount, "not enough shares");
        uint256 assets = amount * totalAssetsTracked / totalShares;
        shares[msg.sender] -= amount;
        totalShares -= amount;
        totalAssetsTracked -= assets;
        asset.transfer(msg.sender, assets);
    }

    function sharePrice() public view returns (uint256) {
        if (totalShares == 0) return 1e18;
        return totalAssetsTracked * 1e18 / totalShares;
    }
}

/**
 * THREE BUGS. PROVE ALL THREE WITH EXACT NUMBERS.
 *
 * ============================================================
 * BUG #1 HINTS (NaiveVault first-depositor inflation)
 * ============================================================
 * NaiveVault uses balanceOf(this) as the asset base.
 *
 * The bootstrap: first depositor gets 1:1 shares.
 *
 * Attack: attacker is the FIRST depositor.
 *   1. Attacker deposits 1 wei of asset
 *      → shares[attacker] = 1, totalShares = 1
 *   2. Attacker directly transfers 1,000,000e18 tokens to the vault
 *      → balanceOf(vault) = 1 + 1,000,000e18
 *      → totalShares still = 1
 *   3. Victim deposits 500,000e18
 *      → newShares = 500,000e18 * 1 / (1,000,000e18 + 1) = 0 (rounds down!)
 *      → victim gets ZERO shares but their tokens are in the vault
 *
 *   What happens to the victim's funds? Who can redeem them?
 *   Calculate exact numbers. What's the attacker's profit?
 *   Does this require the victim to deposit less than the donation?
 *
 * ============================================================
 * BUG #2 HINTS (OrderVault accounting order)
 * ============================================================
 * OrderVault reads assetsBefore BEFORE transferFrom.
 * At first glance this looks SAFE against donation.
 *
 * But trace carefully:
 *   - totalAssetsTracked is the base for share calculation
 *   - The actual tokens are moved AFTER the read
 *   - Is totalAssetsTracked ever out of sync with balanceOf?
 *
 *   Think: what if the vault receives tokens WITHOUT going through deposit?
 *   - Direct transfer to vault address
 *   - totalAssetsTracked doesn't change
 *   - But sharePrice uses totalAssetsTracked...
 *
 *   Now the REAL bug: redeem()
 *   - assets = shares * totalAssetsTracked / totalShares
 *   - transfer happens AFTER totalAssetsTracked -= assets
 *   - Is there a way to make totalAssetsTracked wrong?
 *
 *   CRITICAL: what if two users redeem and the rounding interacts?
 *   Or: deposit reads assetsBefore, but if totalShares > 0, the share
 *   calc uses the OLD assets. Is that exploitable with a large deposit?
 *
 * ============================================================
 * BUG #3 HINTS (rounding direction)
 * ============================================================
 * Both vaults: redeem calculates assets = shares * balance / totalShares
 * with integer division (rounds DOWN).
 *
 * Wait — rounds down means user gets LESS. That's not a bug in user's favor.
 *
 * Re-read the code CAREFULLY. Is there any division that rounds UP
 * or where the victim loses a wei that accumulates?
 *
 * Actually: in NaiveVault bootstrap, attacker gets 1:1.
 * If deposit amount < balance, newShares rounds to 0.
 * The rounding IS the attack vector (Bug #1).
 *
 * For Bug #3: look at OrderVault redeem:
 *   totalAssetsTracked -= assets (assets already rounded down)
 *   asset.transfer(msg.sender, assets)
 * The dust (fractional wei) stays in totalAssetsTracked but NOT transferred.
 * Is that actually a bug, or just dust? Judge honestly.
 *
 * ============================================================
 * YOUR TASK
 * ============================================================
 * 1. Prove Bug #1 with exact numbers: attacker profit, victim loss
 * 2. Determine if Bug #2 is real or if OrderVault is actually safe.
 *    BE HONEST — if the "fix" works, say so. Don't force a bug.
 * 3. Judge Bug #3 honestly: rounding dust vs real exploit.
 * 4. For each: severity + real-world match (ERC4626, etc.)
 *
 * SHOW EXACT NUMBERS. NO HAND-WAVING.
 */

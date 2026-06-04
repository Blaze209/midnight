# Findings Report - Morpho Midnight

## 1. [CRITICAL] Realization of bad debt without seizing collateral allows free debt reduction

### Vulnerable Code
`src/Midnight.sol:631-645` — `liquidate()`

### Root Cause
The `liquidate` function allows anyone to realize "bad debt" for a liquidatable position and socialize the loss among lenders by calling the function with `seizedAssets = 0` and `repaidUnits = 0`.

The `badDebt` is calculated as the difference between the current debt and the total debt that can be repaid by all activated collaterals, accounting for the liquidation incentive (`maxLif`):
`badDebt = originalDebt - Sum(CollateralValue_i / maxLif_i)`.

Because `maxLif` is always greater than 1 (except when LLTV=1), a position can have "bad debt" even when its total collateral value is still significantly higher than its total debt. By realizing this "bad debt" without actually seizing the borrower's collateral, the borrower's debt is reduced (forgiven) at the expense of lenders (who are slashed), while the borrower retains all their collateral.

### Attack Path
1. A borrower has a liquidatable position.
2. The position is solvent (Collateral Value > Debt), but "incentive-insolvent" (`Collateral Value < Debt * maxLif`).
3. An attacker calls `liquidate` with `seizedAssets = 0` and `repaidUnits = 0`.
4. The code reaches line 631, identifies `badDebt > 0`, reduces `_position.debt`, and increases the market's `lossFactor`.
5. Lenders are slashed proportionally to the realized `badDebt`.
6. The borrower can now repay their reduced debt and withdraw all their collateral.

### PoC
```bash
./run_poc.sh
```
Expected output: `[PASS] testExploitRealizeBadDebtWithoutSeizing()`

### Impact
Critical. Direct theft of lender funds. Borrowers can intentionally or unintentionally benefit from lender slashing without losing their collateral.

### Fix
Realizing `badDebt` should only be possible if all activated collateral is seized.

```solidity
<<<<<<< SEARCH
        if (badDebt > 0) {
            // forge-lint: disable-next-item(unsafe-typecast) as badDebt <= _position.debt
            _position.debt -= uint128(badDebt);
=======
        if (badDebt > 0) {
            require(repaidUnits > 0 || seizedAssets > 0, InconsistentInput());
            // forge-lint: disable-next-item(unsafe-typecast) as badDebt <= _position.debt
            _position.debt -= uint128(badDebt);
>>>>>>> REPLACE
```

---

## 2. [HIGH] Precision loss in `maxRepaid` computation allows over-liquidation

### Vulnerable Code
`src/Midnight.sol:659` — `liquidate()` (in version `7538c438~1`)

### Root Cause
The `maxRepaid` calculation for the Recovery Close Factor (RCF) check uses a formula with significant precision loss:
`maxRepaid = (_position.debt - maxDebt).mulDivUp(WAD, WAD - lif.mulDivUp(lltv, WAD))`

The term `lif.mulDivUp(lltv, WAD)` scales down the value prematurely, leading to a denominator that is less precise than possible.

### Attack Path
1. A position is subject to the Recovery Close Factor.
2. Due to precision loss, the calculated `maxRepaid` is slightly higher than intended.
3. A liquidator can over-liquidate the position beyond what's needed for recovery.

### PoC
```bash
./run_poc.sh
```
Expected output: `[PASS] testExploitPrecisionLoss()`

### Impact
High. Violates protocol invariants and results in unfair liquidation for borrowers.

### Fix
Refactor the formula to delay division:
`maxRepaid = (_position.debt - maxDebt).mulDivUp(WAD * WAD, WAD * WAD - lif * lltv)`

```solidity
<<<<<<< SEARCH
                uint256 maxRepaid = lltv < WAD
                    ? (_position.debt - maxDebt).mulDivUp(WAD, WAD - lif.mulDivUp(lltv, WAD))
                    : type(uint256).max;
=======
                uint256 maxRepaid = lltv < WAD
                    ? (_position.debt - maxDebt).mulDivUp(WAD * WAD, WAD * WAD - lif * lltv)
                    : type(uint256).max;
>>>>>>> REPLACE
```

### Status
CONFIRMED

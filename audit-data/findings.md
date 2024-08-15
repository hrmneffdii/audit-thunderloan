### [H-1] Erronous `ThunderLoan::updateExchangeRate` in the deposit function causes the protocol to think it has more fees that it really does, which block redemption and incorrectly sets the exchange rate

**Description**

In the ThunderLoan system, the `exchangeRate`is responsible for calculating the exchane rate between assetTokens and underlying tokens. In a way, it's responsible for keeping track how may fees to give to liquidity provider. However the `deposit` function updates this rate without collecting any fees

```javascript
    function deposit(IERC20 token, uint256 amount) external revertIfZero(amount) revertIfNotAllowedToken(token) {
        AssetToken assetToken = s_tokenToAssetToken[token];
        uint256 exchangeRate = assetToken.getExchangeRate();
        uint256 mintAmount = (amount * assetToken.EXCHANGE_RATE_PRECISION()) / exchangeRate;
        emit Deposit(msg.sender, token, amount);
        assetToken.mint(msg.sender, mintAmount);
        // @audit high 
@>      uint256 calculatedFee = getCalculatedFee(token, amount);
@>      assetToken.updateExchangeRate(calculatedFee);
        token.safeTransferFrom(msg.sender, address(assetToken), amount);
    }
```

**Impact**

There are several impact to this bug :

1. The `redeem` function is blocked, because the protocol thinks the owed tokens is more than it has
2. Rewards re incorrectly calculated,leading to liquidity provider getting way more or less than deserved.

**Proof of Concepts**

1. LP deposit
2. Users take a flash loan
3. It is now impossible for LP to redeem

<details>
<summary> Proof of codes </summary>

```javascript
function testCantRedeemAfterFlashLoan() public setAllowedToken hasDeposits {
        uint256 amountToBorrow = AMOUNT * 10;        
        vm.startPrank(user);
        tokenA.mint(address(mockFlashLoanReceiver), AMOUNT);
        thunderLoan.flashloan(address(mockFlashLoanReceiver), tokenA, amountToBorrow, "");
        vm.stopPrank();

        vm.startPrank(liquidityProvider);
        thunderLoan.redeem(tokenA, type(uint256).max);
        vm.stopPrank();
    }
```
</details>

**Recommended mitigation**

Remove the incorrectly update exchange rate lines from `deposit`.

```diff
    function deposit(IERC20 token, uint256 amount) external revertIfZero(amount) revertIfNotAllowedToken(token) {
        AssetToken assetToken = s_tokenToAssetToken[token];
        uint256 exchangeRate = assetToken.getExchangeRate();
        uint256 mintAmount = (amount * assetToken.EXCHANGE_RATE_PRECISION()) / exchangeRate;
        emit Deposit(msg.sender, token, amount);
        assetToken.mint(msg.sender, mintAmount);
        // @audit high 
-       uint256 calculatedFee = getCalculatedFee(token, amount);
-       assetToken.updateExchangeRate(calculatedFee);
        token.safeTransferFrom(msg.sender, address(assetToken), amount);
    }
```

### [M-#] Using T-Swap as oracle leads to price and oracle manipulation attacks.

**Description**

The TSwap protocol is a constant product formula based AMM (Automated Market Model). The price of a token is determined by how many reserves are on either side of the pool. Because of this, it's easy to malicious users to manipulate the price of the token by buying or selling large amount of token in the same transaction. esentially ignoring protocol fees.

**Impact**

Liquidity providers drastically reduced fees for providing liquidity. 

**Proof of Concepts**

The following all happens in one transaction.

1. User takes a flashloan from `ThunderLoan` for 1000 `tokenA`. They are charged the original fee `fee1` . During flash loan, they do following : 
    a. User sells 1000 `tokenA`, tanking the price down.
    b. Instead of repaying right away, the user takes another flash loan for another 1000 `tokenA`.
        - Due to the fact the way `ThunderLoan` calculates price based on the `TSwapPool`, this second flash loan supposedly more cheaper than expected.
    c. The user then repays the first flash loan ,and then repays the second flash loan.

Proof of code, following `ThuderLoanTest.t.sol::testOracleManipulation`.

**Recommended mitigation**

Consider using a different price oracle mechanism, like a chainlink price feed with a Uniswap TWAP fallback oracle.
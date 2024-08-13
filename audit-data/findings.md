### [H-#] Erronous `ThunderLoan::updateExchangeRate` in the deposit function causes the protocol to think it has more fees that it really does, which block redemption and incorrectly sets the exchange rate

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

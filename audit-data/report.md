---
title: TSwap Audit Report
author: Pluton
date: \today
header-includes:
  - \usepackage{titling}
  - \usepackage{graphicx}
  - \usepackage{hyperref} 
---

\begin{titlepage}
    \centering
    \begin{figure}[h]
        \centering
        \includegraphics[width=0.8\textwidth]{logo.pdf} 
    \end{figure}
    \vspace{2cm}
    \noindent\rule{1\textwidth}{0.85pt}
    {\Huge\bfseries Puppy Raffle Audit Report\par}
    \noindent\rule{1\textwidth}{0.85pt}
    {\Large\itshape Prepared by Pluton \par}
    {\Large Version 1.0\par}
    \vspace{5cm}
    {\Large\bfseries Lead Auditor \par} 
    {\Large \href{https://herman-effendi.vercel.app/}{Herman Effendi} \par} 
    \vfill
    {\large \today\par}
\end{titlepage}

# Table of Contents
- [Table of Contents](#table-of-contents)
- [Introduction](#introduction)
- [Risk Classification](#risk-classification)
- [Audit Details](#audit-details)
  - [Scope](#scope)
  - [Roles](#roles)
- [Executive Summary](#executive-summary)
  - [Issues found](#issues-found)
- [Findings](#findings)
  - [High](#high)
    - [\[H-1\] Incorrect fee calculation in `TSwapPool::getInputAmountBasedOnOutput`, causes the protocol take fee too much from user.](#h-1-incorrect-fee-calculation-in-tswappoolgetinputamountbasedonoutput-causes-the-protocol-take-fee-too-much-from-user)
    - [\[H-2\] `TSwapPool::sellPoolTokens` have mismatche input and output token, causing user to receive incorrect amount of token](#h-2-tswappoolsellpooltokens-have-mismatche-input-and-output-token-causing-user-to-receive-incorrect-amount-of-token)
    - [\[H-3\] In `TSwapPool::_swap` the extra tokens given to users to after every `swapCount` breaks the protocol invariant of `x * y = k`](#h-3-in-tswappool_swap-the-extra-tokens-given-to-users-to-after-every-swapcount-breaks-the-protocol-invariant-of-x--y--k)
  - [Medium](#medium)
    - [\[M-1\] `TSwapPool::deposit` is missing deadline check, causing the transaction to complete even after the deadline](#m-1-tswappooldeposit-is-missing-deadline-check-causing-the-transaction-to-complete-even-after-the-deadline)
    - [\[M-2\] Lack of slippage protection in `TSwapPool::SwapExactOutput` causes users to potentially receive way fewer token.](#m-2-lack-of-slippage-protection-in-tswappoolswapexactoutput-causes-users-to-potentially-receive-way-fewer-token)
  - [Low](#low)
    - [\[L-1\] `TSwapPool::LiquidityAdd` event has a parameter out of order](#l-1-tswappoolliquidityadd-event-has-a-parameter-out-of-order)
    - [\[L-2\] Default value returned by `SwapExactInput` result in incorect return value given](#l-2-default-value-returned-by-swapexactinput-result-in-incorect-return-value-given)
  - [Informational](#informational)
    - [\[I-1\] `PoolFactory::PoolFactory__PoolDoesNotExist` is not used and should be removed](#i-1-poolfactorypoolfactory__pooldoesnotexist-is-not-used-and-should-be-removed)
    - [\[I-2\] Lacking zero address](#i-2-lacking-zero-address)
    - [\[I-3\] `PoolFactory::createPool` should use `.symbol()` instead of `.name()`](#i-3-poolfactorycreatepool-should-use-symbol-instead-of-name)

\newpage

# Introduction

The Pluton team strives to identify as many vulnerabilities as possible within the allotted time but accepts no responsibility for the results detailed in this document. Their security audit should not be considered an endorsement of the business or product. The audit was limited in scope and focused exclusively on the security aspects of the Solidity code for the contracts.

# Risk Classification

|            |        | Impact |        |     |
| ---------- | ------ | ------ | ------ | --- |
|            |        | High   | Medium | Low |
|            | High   | H      | H/M    | M   |
| Likelihood | Medium | H/M    | M      | M/L |
|            | Low    | M      | M/L    | L   |

We use the [CodeHawks](https://docs.codehawks.com/hawks-auditors/how-to-evaluate-a-finding-severity) severity matrix to determine severity. See the documentation for more details.

# Audit Details 

The findings described in this document correspond the following commit hash:

```javascript
e643a8d4c2c802490976b538dd009b351b1c8dda
```

## Scope 

```javascript
./src/
#--- PoolFactory.sol
#--- TSwapPool.sol
```

## Roles

- Liquidity provider : Someone who act give a many tokens for the pool
- Users : Someone who use the functionality the protocol for swapping tokens

# Executive Summary

## Issues found

| Severity | Number of issues found |
| -------- | ---------------------- |
| High     | 3                      |
| Medium   | 2                      |
| Low      | 0                      |
| Info     | 3                      |
| Total    | 8                      |

# Findings

## High

### [H-1] Incorrect fee calculation in `TSwapPool::getInputAmountBasedOnOutput`, causes the protocol take fee too much from user.

**Description**

The `getInputAmountBasedOnOutput` is intended to calculate the amount of tokens a users should deposit give an amount of token of output token. However, the function currently miscalculate. it scale he amount by 10_000 instead of 1_000.

**Impact**

The protocol takes fees too much rather than expected.

**Proof of Concepts**

<details>

<summary> Code </summary>

```javascript
function testGetInputAmountBasedOnOutput() public view {
        uint256 outputAmount = 50e18; 
        uint256 inputReserves = 200e18;
        uint256 outputReserves = 100e18;
        
        uint256 expected = ((inputReserves * outputAmount) * 1000) / ((outputReserves - outputAmount) * 997);
        uint256 result = pool.getInputAmountBasedOnOutput(outputAmount, inputReserves, outputReserves);

        assert(result >= expected);
}
```


</details>

**Recommended mitigation**

```diff
    function getInputAmountBasedOnOutput(
        uint256 outputAmount,
        uint256 inputReserves,
        uint256 outputReserves
    )
        public
        pure
        revertIfZero(outputAmount)
        revertIfZero(outputReserves)
        returns (uint256 inputAmount)
    {
-    return ((inputReserves * outputAmount) * 10000) / ((outputReserves - outputAmount) * 997);
+    return ((inputReserves * outputAmount) * 1000) / ((outputReserves - outputAmount) * 997);
    }
```

### [H-2] `TSwapPool::sellPoolTokens` have mismatche input and output token, causing user to receive incorrect amount of token

**Description**

The `sellPoolTokens` function is intended o allow users to easily ell pool tokens and receive eth in exchange. Users indicate how many pool tokens they are willing to sell as a parameter. However, the function currently miscalculates the swaped amount. 

This due to the fact that he `swapExactOutput` function is called, whereas `swapExactInput` function is the one that should be called because the user specify the input amount, not the output amount.

**Impact**

Users will swap the wrong amount of token. which is a severe distruption of protocol functionality.

**Recommended mitigation**

Consider change the implementation to use `swapExactInput` instead of `swapExactOutput`. Note that this would also require `minWethToReceive` to be pass in `swapExactInput`.

```diff
    function sellPoolTokens(
        uint256 poolTokenAmount
+       uint256 minWethToReceive,
        ) external returns (uint256 wethAmount) {
-       return swapExactOutput(i_poolToken, i_wethToken, poolTokenAmount, uint64(block.timestamp));
+       return swapExactInput(i_poolToken, poolTokenAmount, i_wethToken, minWethToReceive, uint64(block.timestamp));
    }
```

### [H-3] In `TSwapPool::_swap` the extra tokens given to users to after every `swapCount` breaks the protocol invariant of `x * y = k`

**Description**

The protocol follows strict invariant of `x * y = k`. where :
`x` : The balance of pool token
`y` : The balance of eth
`k` : The constant product formula, the ratio beetween

This means, that whenever the balances changes in the protocol, the ratio between two amount remain constant, hence the `k`. However, this is broken due to extra incentive in the `_swap` function. Meaning that overtime the protocol funds will drained.

The following th below code
```javascript
    swap_count++;
        if (swap_count >= SWAP_COUNT_MAX) {
            swap_count = 0;
            outputToken.safeTransfer(msg.sender, 1_000_000_000_000_000_000);
        }
```

**Impact**

A user could maliciuosly drain the protocol of funds by doing alot of swap and collecting extra incentive given out ot protocol.

**Proof of Concepts**

**Recommended mitigation**

Remove the extra incentive if the protocol want to keep the balance or we should set aside tokens in the same way we do this in fees.

```diff
-    swap_count++;
-       if (swap_count >= SWAP_COUNT_MAX) {
-           swap_count = 0;
-           outputToken.safeTransfer(msg.sender, 1_000_000_000_000_000_000);
-       }
```


## Medium

### [M-1] `TSwapPool::deposit` is missing deadline check, causing the transaction to complete even after the deadline

**Description**

The `deposit` function accepts a deadline as parameter, which according to documentation is "The deadline for the transaction to be completed by". However, this parameter is never used. As a consequence, that add liquidity to the pool might be execute at unexpected times, in market conditions where the deposit rate is unfavorable.

**Impact**

Transactions could be sent when the market conditions are unfavorable to deposit even we adding deadline as a parameter. 

**Proof of Concepts**

The `deadline` parameter is unused

**Recommended mitigation** 

Consider making the following function change 

```javascript
    function deposit(
            uint256 wethToDeposit,
            uint256 minimumLiquidityTokensToMint,
            uint256 maximumPoolTokensToDeposit,
            uint64 deadline
        )
            external
+           revertIfDeadlinePassed(deadline)
            revertIfZero(wethToDeposit)
            returns (uint256 liquidityTokensToMint)    
```

### [M-2] Lack of slippage protection in `TSwapPool::SwapExactOutput` causes users to potentially receive way fewer token.

**Description**

The `SwapExactOutput` function doesn't include any slippage protection. This function is similar to what is done im `SwapExactInput`, where the function specifies `minOutputAmount`. `SwapExactInput` should specifies a `maxInputAmount`.

**Impact**

If the market changes suddenly, it could lead to users experiencing less favorable swap outcomes.

**Proof of Concepts**

1. The price of 1 WETH right now is 1_000 USDC.
2. User inputs a `SwapExactOutput` looking for 1 WETH
   - inputToken USDC
   - outputToken WETH
   - outputAmount 1
   - deadline whatever
3. The function doesn't offer `maxInputAmount`
4. as the transaction pending in the mempool, the market changes!! and the price maybe around 1 WETH -> 10_000 USDC, 10x more than user expected.
5. The transaction completes, but the user sent the protocol 10_000 instead of 1_000 USDC.
   
**Recommended mitigation**

We should include  `maxInputAmount` so the user only has spend up to a specify amount as well as predict how much they will spend in protocol.

<details>

```diff
 function swapExactOutput(
        IERC20 inputToken,
        IERC20 outputToken,
        uint256 outputAmount,
+       uint256 maxInputAmount,
        uint64 deadline
    )
        public
        revertIfZero(outputAmount)
        revertIfDeadlinePassed(deadline)
        returns (uint256 inputAmount)
    {
        uint256 inputReserves = inputToken.balanceOf(address(this));
        uint256 outputReserves = outputToken.balanceOf(address(this));

        inputAmount = getInputAmountBasedOnOutput(outputAmount, inputReserves, outputReserves);
+       if(inputAmount > maxInputAmount){
+           revert();
+       }
        _swap(inputToken, inputAmount, outputToken, outputAmount);
    }

```
</details>

## Low

### [L-1] `TSwapPool::LiquidityAdd` event has a parameter out of order

**Description**

When the `LiquidityAdded` event is emitted by `TSwapPool::_addLiquidityMintAndTransfer` function, it's logs values in an incorrect order. The `PoolTokenDeposit` value should go in the third parameter position, whereas the `wethToDeposit` value should go in second.

**Impact**

Event emitted is incorrect, may lead to  incorect filling parameter as well

**Recommended mitigation**

```diff
-    emit LiquidityAdded(msg.sender, poolTokensToDeposit, wethToDeposit);
+    emit LiquidityAdded(msg.sender, wethToDeposit, poolTokensToDeposit);
```

### [L-2] Default value returned by `SwapExactInput` result in incorect return value given

**Description**

The `SwapExactInput` function is expected to return th actual amount of token bought by caller. However, while it declares the named return value `output` it is never assigned by value, nor uses explicit return statement.

**Impact**

The return value is always zero, it always give incorrect information for the caller.

**Proof of Concepts**

<details>

<summary> Code </summary>

```javascript
function testSwapExactInput() public {
        vm.startPrank(liquidityProvider);
        weth.approve(address(pool), 10e18);
        poolToken.approve(address(pool), 10e18);
        pool.deposit(10e18, 0, 10e18, uint64(block.timestamp));
        vm.stopPrank();

        
        vm.startPrank(user);
        weth.approve(address(pool), 1e18);
        uint256 result = pool.swapExactInput(weth, 1e18, poolToken, 1e17, uint64(block.timestamp));
        vm.stopPrank();

        assert(result == 0);
    }
```

</details>

**Recommended mitigation**

Shoul be corrected the name variable as result

```diff
    function swapExactInput(){
        ...
-       returns (uint256 output)
+       returns (uint256 outputAmount)
        ...
        }
```

## Informational

### [I-1] `PoolFactory::PoolFactory__PoolDoesNotExist` is not used and should be removed
 
```diff
-     error PoolFactory__PoolDoesNotExist(address tokenAddress);
```

### [I-2] Lacking zero address

```diff
    constructor(address wethToken) {
+       if(weth == address(0)){
+            revert();
+       }
        i_wethToken = wethToken;
    }
```

### [I-3] `PoolFactory::createPool` should use `.symbol()` instead of `.name()`

```diff
-    string memory liquidityTokenName = string.concat("T-Swap ", IERC20(tokenAddress).name());
-    string memory liquidityTokenSymbol = string.concat("ts", IERC20(tokenAddress).name());
+    string memory liquidityTokenName = string.concat("T-Swap ", IERC20(tokenAddress).symbol());
+    string memory liquidityTokenSymbol = string.concat("ts", IERC20(tokenAddress).symbol ());
```
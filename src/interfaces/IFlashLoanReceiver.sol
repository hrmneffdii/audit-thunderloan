// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.20;

// @audit info : unused import 
// it's bad practice o edit live code for tests/mocks
import { IThunderLoan } from "./IThunderLoan.sol";

/**
 * @dev Inspired by Aave:
 * https://github.com/aave/aave-v3-core/blob/master/contracts/flashloan/interfaces/IFlashLoanReceiver.sol
 */
interface IFlashLoanReceiver {
    // q where is the natspec?
    // is the token, the token that's being borrowed?
    // is the amount represent the token amount?
    function executeOperation(
        address token,
        uint256 amount,
        uint256 fee,
        address initiator,
        bytes calldata params
    )
        external
        returns (bool);
}

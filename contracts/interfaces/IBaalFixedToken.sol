//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import "@daohaus/baal-contracts/contracts/interfaces/IBaalToken.sol";

interface IBaalFixedToken is IBaalToken {
    function initialMint(address initialHolder) external;
}
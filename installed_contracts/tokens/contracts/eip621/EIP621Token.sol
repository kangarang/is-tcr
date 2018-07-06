pragma solidity ^0.4.11;

import "./EIP621AbstractToken.sol";


contract EIP621Token is EIP621AbstractToken {

    constructor(
        uint256 _initialAmount,
        string _tokenName,
        uint8 _decimalUnits,
        string _tokenSymbol
    ) EIP20(
        _initialAmount,
        _tokenName,
        _decimalUnits,
        _tokenSymbol
    ) public {}

    function increaseSupply(uint value, address to) public returns (bool success) {
        totalSupply = safeAdd(totalSupply, value);
        balances[to] = safeAdd(balances[to], value);

        emit Transfer(0, to, value);
        return true;
    }

    function safeAdd(uint a, uint b) internal returns (uint) {
        require(a + b >= a);
        return a + b;
    }

    function decreaseSupply(uint value, address from) public returns (bool success) {
        balances[from] = safeSub(balances[from], value);
        totalSupply = safeSub(totalSupply, value);

        emit Transfer(from, 0, value);
        return true;
    }

    function safeSub(uint a, uint b) internal returns (uint) {
        require(a >= b);
        return a - b;
    }
}
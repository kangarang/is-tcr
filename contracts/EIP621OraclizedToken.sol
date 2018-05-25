pragma solidity ^0.4.11;

import "./EIP621Token.sol";


contract EIP621OraclizedToken is EIP621Token {

    address public supplyOracle;

    modifier onlySupplyOracle {
        require(msg.sender == supplyOracle);
        _;
    }

    function EIP621OraclizedToken(
        uint256 _initialAmount,
        string _tokenName,
        uint8 _decimalUnits,
        string _tokenSymbol,
        address _supplyOracle
    ) EIP621Token (
        _initialAmount,
        _tokenName,
        _decimalUnits,
        _tokenSymbol
    ) {
        require(_supplyOracle != 0);
        supplyOracle = _supplyOracle; 
    }

    function changeSupplyOracle(address _newOracle) public onlySupplyOracle returns (bool success) {
        require(supplyOracle != _newOracle);
        supplyOracle = _newOracle;

        emit SupplyOracleChanged(msg.sender, _newOracle);
        return true;
    }

    function increaseSupply(uint value, address to) public onlySupplyOracle returns (bool success) {
        totalSupply = safeAdd(totalSupply, value);
        balances[to] = safeAdd(balances[to], value);

        Transfer(0, to, value);
        return true;
    }

    function decreaseSupply(uint value, address from) public onlySupplyOracle returns (bool success) {
        balances[from] = safeSub(balances[from], value);
        totalSupply = safeSub(totalSupply, value);

        Transfer(from, 0, value);
        return true;
    }

    event SupplyOracleChanged(address indexed oldOracle, address indexed newOracle);
}
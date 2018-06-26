pragma solidity ^0.4.11;

import "./EIP621Token.sol";


contract EIP621OraclizedToken is EIP621Token {

    address public supplyOracle;
    address public pSupplyOracle;

    modifier onlySupplyOracle {
        require(msg.sender == supplyOracle || msg.sender == pSupplyOracle);
        _;
    }

    function EIP621OraclizedToken(
        uint256 _initialAmount,
        string _tokenName,
        uint8 _decimalUnits,
        string _tokenSymbol
    ) public EIP621Token (
        _initialAmount,
        _tokenName,
        _decimalUnits,
        _tokenSymbol
    ) {
        supplyOracle = msg.sender;
        pSupplyOracle = msg.sender;
    }

    function changePSupplyOracle(address _pNewOracle) public onlySupplyOracle returns (bool success) {
        require(pSupplyOracle != _pNewOracle);
        pSupplyOracle = _pNewOracle;

        emit PSupplyOracleChanged(msg.sender, _pNewOracle);
        return true;
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

    event SupplyOracleChanged(address oldOracle, address newOracle);
    event PSupplyOracleChanged(address oldOracle, address newOracle);
}
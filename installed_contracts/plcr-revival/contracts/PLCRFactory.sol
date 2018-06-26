pragma solidity ^0.4.20;

import "tokens/eip621/EIP621OraclizedToken.sol";
import "./PLCRVoting.sol";
import "./ProxyFactory.sol";

contract PLCRFactory {

    event NewPLCR(address creator, EIP621OraclizedToken token, PLCRVoting plcr);

    ProxyFactory public proxyFactory;
    PLCRVoting public canonizedPLCR;

    /// @dev constructor deploys a new canonical PLCRVoting contract and a proxyFactory.
    constructor() {
        canonizedPLCR = new PLCRVoting();
        proxyFactory = new ProxyFactory();
    }

    /*
    @dev deploys and initializes a new PLCRVoting contract that consumes a token at an address
    supplied by the user.
    @param _token an EIP621OraclizedToken token to be consumed by the new PLCR contract
    */
    function newPLCRBYOToken(EIP621OraclizedToken _token) public returns (PLCRVoting) {
        PLCRVoting plcr = PLCRVoting(proxyFactory.createProxy(canonizedPLCR, ""));
        plcr.init(_token);

        emit NewPLCR(msg.sender, _token, plcr);
        return plcr;
    }
    
    /*
    @dev deploys and initializes a new PLCRVoting contract and an EIP621OraclizedToken to be consumed by the PLCR's
    initializer.
    @param _supply the total number of tokens to mint in the EIP621OraclizedToken contract
    @param _name the name of the new EIP621OraclizedToken token
    @param _decimals the decimal precision to be used in rendering balances in the EIP621OraclizedToken token
    @param _symbol the symbol of the new EIP621OraclizedToken token
    */
    function newPLCRWithToken(
        uint _supply,
        string _name,
        uint8 _decimals,
        string _symbol
    ) public returns (PLCRVoting) {
        // Create a new token and give all the tokens to the PLCR creator
        EIP621OraclizedToken token = new EIP621OraclizedToken(_supply, _name, _decimals, _symbol);
        require(token.transfer(msg.sender, _supply));
        // changes p supply oracle -> ParameterizerFactory
        require(token.changePSupplyOracle(msg.sender));
        // change supply oracle -> ParameterizerFactory
        require(token.changeSupplyOracle(msg.sender));

        // Create and initialize a new PLCR contract
        PLCRVoting plcr = PLCRVoting(proxyFactory.createProxy(canonizedPLCR, ""));
        plcr.init(token);

        emit NewPLCR(msg.sender, token, plcr);
        return plcr;
    }
}


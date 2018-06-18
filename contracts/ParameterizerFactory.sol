pragma solidity ^0.4.20;

import "plcr-revival/PLCRFactory.sol";
import "plcr-revival/PLCRVoting.sol";
import "./Parameterizer.sol";
import "tokens/eip621/EIP621OraclizedToken.sol";

contract ParameterizerFactory {

    event NewParameterizer(address creator, EIP621OraclizedToken token, PLCRVoting plcr, Parameterizer parameterizer);

    PLCRFactory public plcrFactory;
    ProxyFactory public proxyFactory;
    Parameterizer public canonizedParameterizer;

    /// @dev constructor deploys a new canonical Parameterizer contract and a proxyFactory.
    constructor(PLCRFactory _plcrFactory) public {
        plcrFactory = _plcrFactory;
        proxyFactory = plcrFactory.proxyFactory();
        canonizedParameterizer = new Parameterizer();
    }

    /*
    @dev deploys and initializes a new Parameterizer contract that consumes a token at an address
    supplied by the user.
    @param _token             an EIP621OraclizedToken token to be consumed by the new Parameterizer contract
    @param _plcr              a PLCR voting contract to be consumed by the new Parameterizer contract
    @param _parameters        array of canonical parameters
    */
    function newParameterizerBYOToken(
        EIP621OraclizedToken _token,
        uint[] _parameters
    ) public returns (Parameterizer) {
        // Deploy & initialize a new PLCRVoting proxy contract
        PLCRVoting plcr = plcrFactory.newPLCRBYOToken(_token);

        // Create & initialize a new Parameterizer proxy contract
        Parameterizer parameterizer = Parameterizer(proxyFactory.createProxy(canonizedParameterizer, ""));
        parameterizer.init(
            _token,
            plcr,
            _parameters
        );

        emit NewParameterizer(msg.sender, _token, plcr, parameterizer);
        return parameterizer;
    }

    /*
    @dev deploys and initializes new EIP621OraclizedToken, PLCRVoting, and Parameterizer contracts
    @param _supply            the total number of tokens to mint in the EIP621OraclizedToken contract
    @param _name              the name of the new EIP621OraclizedToken token
    @param _decimals          the decimal precision to be used in rendering balances in the EIP621OraclizedToken token
    @param _symbol            the symbol of the new EIP621OraclizedToken token
    @param _parameters        array of canonical parameters
    */
    function newParameterizerWithToken(
        uint _supply,
        string _name,
        uint8 _decimals,
        string _symbol,
        uint[] _parameters
    ) public returns (Parameterizer) {
        // Creates a new EIP621OraclizedToken token
        // Deploys & initializes a new PLCRVoting proxy contract
        PLCRVoting plcr = plcrFactory.newPLCRWithToken(_supply, _name, _decimals, _symbol);
        EIP621OraclizedToken token = EIP621OraclizedToken(plcr.token());
        // transfer tokens -> creator
        require(token.transfer(msg.sender, _supply));
        // changes supply oracle -> RegistryFactory
        require(token.changeSupplyOracle(msg.sender));

        // Create & initialize a new Parameterizer proxy contract
        Parameterizer parameterizer = Parameterizer(proxyFactory.createProxy(canonizedParameterizer, ""));
        parameterizer.init(
            token,
            plcr,
            _parameters
        );

        emit NewParameterizer(msg.sender, token, plcr, parameterizer);
        return parameterizer;
    }
}

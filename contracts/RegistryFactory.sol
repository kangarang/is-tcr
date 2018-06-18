pragma solidity ^0.4.20;

import "tokens/eip621/EIP621OraclizedToken.sol";
import "./ParameterizerFactory.sol";
import "./Registry.sol";
import "plcr-revival/PLCRVoting.sol";
import "./Parameterizer.sol";

contract RegistryFactory {

    event NewRegistry(address creator, EIP621OraclizedToken token, PLCRVoting plcr, Parameterizer parameterizer, Registry registry);

    ParameterizerFactory public parameterizerFactory;
    ProxyFactory public proxyFactory;
    Registry public canonizedRegistry;

    /// @dev constructor deploys a new proxyFactory.
    constructor(ParameterizerFactory _parameterizerFactory) public {
        parameterizerFactory = _parameterizerFactory;
        proxyFactory = parameterizerFactory.proxyFactory();
        canonizedRegistry = new Registry();
    }

    /*
    @dev            deploys and initializes a new Registry contract that consumes a token at an address
                    supplied by the user
    @param _token   an EIP621OraclizedToken token to be consumed by the new Registry contract
    */
    function newRegistryBYOToken(
        EIP621OraclizedToken _token,
        uint[] _parameters,
        string _name
    ) public returns (Registry) {
        // Deploy & initialize new PLCRVoting & Parameterizer proxy contracts
        Parameterizer parameterizer = parameterizerFactory.newParameterizerBYOToken(_token, _parameters);
        PLCRVoting plcr = parameterizer.voting();

        // Create & initialize a new Registry proxy contract
        Registry registry = Registry(proxyFactory.createProxy(canonizedRegistry, ""));
        registry.init(_token, plcr, parameterizer, _name);

        emit NewRegistry(msg.sender, _token, plcr, parameterizer, registry);
        return registry;
    }

    /*
    @dev                deploys and initializes a new Registry contract, an EIP621OraclizedToken, a PLCRVoting, and Parameterizer
                        to be consumed by the Registry's initializer.
    @param _supply      the total number of tokens to mint in the EIP621OraclizedToken contract
    @param _name        the name of the new EIP621OraclizedToken token
    @param _decimals    the decimal precision to be used in rendering balances in the EIP621OraclizedToken token
    @param _symbol      the symbol of the new EIP621OraclizedToken token
    */
    function newRegistryWithToken(
        uint _supply,
        string _tokenName,
        uint8 _decimals,
        string _symbol,
        uint[] _parameters,
        string _registryName
    ) public returns (Registry) {
        // Creates a new EIP621OraclizedToken token
        // Deploys & initializes (1) PLCRVoting & (2) Parameterizer proxy contracts
        Parameterizer parameterizer = parameterizerFactory.newParameterizerWithToken(_supply, _tokenName, _decimals, _symbol, _parameters);
        PLCRVoting plcr = parameterizer.voting();
        EIP621OraclizedToken token = EIP621OraclizedToken(parameterizer.token());
        // transfer tokens -> creator
        require(token.transfer(msg.sender, _supply));
        // change supply oracle -> Registry proxy
        require(token.changeSupplyOracle(registry));

        // Create & initialize a new Registry proxy contract
        Registry registry = Registry(proxyFactory.createProxy(canonizedRegistry, ""));
        registry.init(token, plcr, parameterizer, _registryName);

        emit NewRegistry(msg.sender, token, plcr, parameterizer, registry);
        return registry;
    }
}

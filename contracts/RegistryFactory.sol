pragma solidity ^0.4.20;

import "tokens/eip621/EIP621OraclizedToken.sol";
import "./ProxyFactory.sol";
import "./Registry.sol";

contract RegistryFactory {

    event NewRegistry(address creator, EIP621OraclizedToken token, address plcr, address parameterizer, Registry registry);

    ProxyFactory public proxyFactory;
    Registry public canonizedRegistry;

    /// @dev constructor deploys a new canonical Registry contract and a proxyFactory.
    constructor() public {
        proxyFactory = new ProxyFactory();
        canonizedRegistry = new Registry();
    }

    /*
    @dev deploys and initializes a new Registry contract that consumes a token at an address
    supplied by the user.
    @param _token an EIP20 token to be consumed by the new Registry contract
    */
    function newRegistryBYOTokenAndFriends(
        EIP621OraclizedToken _token,
        address _plcr,
        address _parameterizer,
        string _name
    ) public returns (Registry) {
        Registry registry = Registry(proxyFactory.createProxy(canonizedRegistry, ""));

        registry.init(_token, _plcr, _parameterizer, _name);
        emit NewRegistry(msg.sender, _token, _plcr, _parameterizer, registry);
        return registry;
    }
    
    /*
    @dev deploys and initializes a new Registry contract, an EIP20, a PLCRVoting, and Parameterizer
      to be consumed by the Registry's initializer.
    @param _supply the total number of tokens to mint in the EIP20 contract
    @param _name the name of the new EIP20 token
    @param _decimals the decimal precision to be used in rendering balances in the EIP20 token
    @param _symbol the symbol of the new EIP20 token
    */
    // function newRegistryWithToken(
    //     uint _supply,
    //     string _tokenName,
    //     uint8 _decimals,
    //     string _symbol,
    //     uint[] _parameters,
    //     string _registryName
    // ) public returns (Registry) {
    //     // Create a new token and give all the tokens to the PLCR creator
    //     EIP621OraclizedToken token = new EIP621OraclizedToken(_supply, _tokenName, _decimals, _symbol, msg.sender);
    //     token.transfer(msg.sender, _supply);

    //     PLCRVoting plcr = PLCRVoting(proxyFactory.createProxy(canonizedPLCR, ""));
    //     plcr.init(token);

    //     emit NewPLCR(msg.sender, token, plcr);

    //     Parameterizer parameterizer = Parameterizer(proxyFactory.createProxy(canonizedParameterizer, ""));
    //     parameterizer.init(token, plcr, _parameters);
    //     emit NewParameterizer(msg.sender, token, plcr, parameterizer);

    //     Registry registry = Registry(proxyFactory.createProxy(canonizedRegistry, ""));
    //     registry.init(token, plcr, parameterizer, _registryName);
    //     emit NewRegistry(msg.sender, token, plcr, parameterizer, registry);

    //     require(token.changeSupplyOracle(registry));
    //     return registry;
    // }
}


/* eslint-env mocha */
/* global assert contract artifacts */
const Registry = artifacts.require('Registry.sol');
const Token = artifacts.require('EIP621OraclizedToken.sol');

const utils = require('../utils.js');

contract('EIP621OraclizedToken', (accounts) => {
  const initialAmount = 1000;
  const tokenName = 'admiralCoin';
  const decimalUnits = 2;
  const tokenSymbol = 'MARK';
  const oracle = accounts[2];

  describe('As the oracle', () => {
    let registry;
    let token;

    beforeEach(async () => {
      token = await Token.new(
        initialAmount,
        tokenName,
        decimalUnits,
        tokenSymbol,
        oracle,
      );
      registry = await Registry.deployed();
    });

    it('Should change the supply oracle', async () => {
      // change the supplyOracle
      await utils.as(oracle, token.changeSupplyOracle, registry.address);
      // verify: supplyOracle === registry
      const newOracle = await token.supplyOracle.call();
      assert.strictEqual(newOracle, registry.address, 'oracle was not changed correctly');
    });

    it('Should not increase the supply after changing the oracle', async () => {
      // change the supplyOracle
      await utils.as(oracle, token.changeSupplyOracle, registry.address);
      // verify: supplyOracle === registry
      const newOracle = await token.supplyOracle.call();
      assert.strictEqual(newOracle, registry.address, 'oracle was not changed correctly');

      const increaseAmount = 10;
      try {
        await utils.as(oracle, token.increaseSupply, increaseAmount, accounts[1]);
      } catch (err) {
        assert(utils.isEVMException(err), err.toString());
        return;
      }
      assert(false, 'previous oracle was able to increase the supply after changing the supplyOracle');
    });
  });
});

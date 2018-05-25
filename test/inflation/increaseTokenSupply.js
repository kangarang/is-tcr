/* eslint-env mocha */
/* global assert contract artifacts */
const Registry = artifacts.require('Registry.sol');
const Token = artifacts.require('EIP621OraclizedToken.sol');

const utils = require('../utils.js');

// const BN = small => new BNJS(small.toString());

contract('Registry / EIP621OraclizedToken', (accounts) => {
  const defaultTo = accounts[1];
  const oracle = accounts[2];

  describe('As the oracle', () => {
    let registry;
    let token;

    // new token, new registry each iteration
    beforeEach(async () => {
      registry = await Registry.deployed();
      token = await Token.deployed();
    });

    it('Should change the supply oracle to the registry', async () => {
      // change the supplyOracle
      await utils.as(oracle, token.changeSupplyOracle, registry.address);
      // verify: supplyOracle === registry
      const newOracle = await token.supplyOracle.call();
      assert.strictEqual(newOracle, registry.address, 'oracle was not changed correctly');
    });

    it('Should increase the supply as the oracle via the registry', async () => {
      // initial supply / balance
      const initSupply = await token.totalSupply.call();
      const initBalance = await token.balanceOf.call(defaultTo);

      // inflate
      const incAmount = 10;
      await utils.as(oracle, registry.increaseTokenSupply, incAmount, defaultTo);

      // new supply / balance
      const newSupply = await token.totalSupply.call();
      const newBalance = await token.balanceOf.call(defaultTo);

      // verify: supplies / balances + increased amount
      assert.strictEqual(newSupply.toString(), initSupply.add(incAmount).toString(), 'new supply is incorrect');
      assert.strictEqual(newBalance.toString(), initBalance.add(incAmount).toString(), 'new balance is incorrect');
    });
  });
});

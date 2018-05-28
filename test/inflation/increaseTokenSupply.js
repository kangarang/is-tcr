/* eslint-env mocha */
/* global assert contract */
const utils = require('../utils.js');

// const BN = small => new BNJS(small.toString());

contract('Inflation', (accounts) => {
  const defaultTo = accounts[1];
  const oracle = accounts[2];

  describe('As the oracle', () => {
    let registry;
    let token;

    // new token, new registry each iteration
    beforeEach(async () => {
      const { registryProxy, tokenInstance } = await utils.getProxies(accounts[2]);
      registry = registryProxy;
      token = tokenInstance;

      await utils.approveProxies(accounts, token, false, false, registry);
    });


    it('Should change the supply oracle to the registry', async () => {
      // change the supplyOracle
      await utils.as(oracle, token.changeSupplyOracle, registry.address);
      // verify: supplyOracle === registry
      const newOracle = await token.supplyOracle.call();
      assert.strictEqual(newOracle, registry.address, 'oracle was not changed correctly');
    });

    it('Should change the supply oracle to the registry & increase the supply via the registry', async () => {
      // verify: correct oracle
      const actualOracle = await token.supplyOracle.call();
      assert.strictEqual(actualOracle, oracle, 'incorrect oracle');

      // change the supplyOracle
      await utils.as(oracle, token.changeSupplyOracle, registry.address);
      // verify: supplyOracle === registry
      const newOracle = await token.supplyOracle.call();
      assert.strictEqual(newOracle, registry.address, 'oracle was not changed correctly');

      // initial supply / balance
      const initSupply = await token.totalSupply.call();
      const initBalance = await token.balanceOf.call(defaultTo);

      // inflate the supply
      const incAmount = '10';
      await registry.increaseTokenSupply(incAmount, defaultTo);

      // new supply / balance
      const newSupply = await token.totalSupply.call();
      const newBalance = await token.balanceOf.call(defaultTo);

      // verify: supplies / balances + increased amount
      assert.strictEqual(newSupply.toString(), initSupply.add(incAmount).toString(), 'new supply is incorrect');
      assert.strictEqual(newBalance.toString(), initBalance.add(incAmount).toString(), 'new balance is incorrect');
    });
  });
});

/* eslint-env mocha */
/* global assert contract */
const utils = require('./utils.js');

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


    it('should change the supply oracle to the registry', async () => {
      // change the supplyOracle
      await utils.as(oracle, token.changeSupplyOracle, registry.address);
      // verify: supplyOracle === registry
      const newOracle = await token.supplyOracle.call();
      assert.strictEqual(newOracle, registry.address, 'oracle was not changed to registry correctly');
    });

    it('should change the supply oracle to the registry, then revert when trying to increase the supply as an EOA', async () => {
      // verify: correct oracle
      const actualOracle = await token.supplyOracle.call();
      assert.strictEqual(actualOracle, oracle, 'incorrect oracle');

      // change the supplyOracle
      await utils.as(oracle, token.changeSupplyOracle, registry.address);
      // verify: supplyOracle === registry
      const newOracle = await token.supplyOracle.call();
      assert.strictEqual(newOracle, registry.address, 'oracle was not changed to registry correctly');

      // initial supply / balance
      const initSupply = await token.totalSupply.call();
      const initBalance = await token.balanceOf.call(defaultTo);

      const increaseAmount = 10;
      try {
        await utils.as(oracle, token.increaseSupply, increaseAmount, defaultTo);
      } catch (err) {
        assert(utils.isEVMException(err), err.toString());
        // new supply / balance
        const newSupply = await token.totalSupply.call();
        const newBalance = await token.balanceOf.call(defaultTo);
        // verify: supplies / balances + increased amount
        assert.strictEqual(newSupply.toString(), initSupply.toString(), 'new supply is incorrect');
        assert.strictEqual(newBalance.toString(), initBalance.toString(), 'new balance is incorrect');
        return;
      }
      assert(false, 'previous oracle was able to increase the supply after changing the supplyOracle');
    });

    it('should change the supply oracle to the registry, then revert when trying to decrease the supply as an EOA', async () => {
      // verify: correct oracle
      const actualOracle = await token.supplyOracle.call();
      assert.strictEqual(actualOracle, oracle, 'incorrect oracle');

      // change the supplyOracle
      await utils.as(oracle, token.changeSupplyOracle, registry.address);
      // verify: supplyOracle === registry
      const newOracle = await token.supplyOracle.call();
      assert.strictEqual(newOracle, registry.address, 'oracle was not changed to registry correctly');

      // initial supply / balance
      const initSupply = await token.totalSupply.call();
      const initBalance = await token.balanceOf.call(defaultTo);

      // deflate the supply
      const decAmount = '10';
      try {
        await utils.as(oracle, token.decreaseSupply, decAmount, defaultTo);
      } catch (err) {
        assert(utils.isEVMException(err), err.toString());
        // new supply / balance
        const newSupply = await token.totalSupply.call();
        const newBalance = await token.balanceOf.call(defaultTo);
        // verify: supplies / balances - decreased amount
        assert.strictEqual(newSupply.toString(), initSupply.toString(), 'new supply is incorrect');
        assert.strictEqual(newBalance.toString(), initBalance.toString(), 'new balance is incorrect');
        return;
      }
      assert(false, 'previous oracle was able to decrease the supply after changing the supplyOracle');
    });
  });
});

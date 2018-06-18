/* eslint-env mocha */
/* global assert contract */
const utils = require('./utils.js');

contract('Inflation', (accounts) => {
  describe('As the oracle', () => {
    const [defaultFrom, defaultTo] = accounts;
    let registry;
    let token;

    // new token, new registry each iteration
    beforeEach(async () => {
      const { registryProxy, tokenInstance } = await utils.getProxies();
      registry = registryProxy;
      token = tokenInstance;

      await utils.approveProxies(accounts, token, false, false, registry);
    });

    it('should print the correct supply oracle (registry)', async () => {
      const oracle = await token.supplyOracle.call();
      assert.strictEqual(oracle, registry.address, 'oracle was not instantiated as registry correctly');
    });

    it('should revert when trying to increase the supply as an EOA', async () => {
      // verify: correct oracle
      const actualOracle = await token.supplyOracle.call();
      assert.strictEqual(actualOracle, registry.address, 'incorrect oracle');

      // initial supply / balance
      const initSupply = await token.totalSupply.call();
      const initBalance = await token.balanceOf.call(defaultTo);

      const increaseAmount = 10;
      try {
        await utils.as(defaultFrom, token.increaseSupply, increaseAmount, defaultTo);
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
      assert(false, 'EOA was able to increase the supply');
    });

    it('should revert when trying to decrease the supply as an EOA', async () => {
      // verify: correct oracle
      const actualOracle = await token.supplyOracle.call();
      assert.strictEqual(actualOracle, registry.address, 'incorrect oracle');

      // initial supply / balance
      const initSupply = await token.totalSupply.call();
      const initBalance = await token.balanceOf.call(defaultTo);

      // deflate the supply
      const decAmount = '10';
      try {
        await utils.as(defaultFrom, token.decreaseSupply, decAmount, defaultTo);
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

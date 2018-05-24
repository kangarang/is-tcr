/* eslint-env mocha */
/* global assert contract artifacts */
const EIP621OraclizedToken = artifacts.require('EIP621OraclizedToken.sol');

contract('EIP621OraclizedToken', (accounts) => {
  const initialAmount = 1000;
  const tokenName = 'admiralCoin';
  const decimalUnits = 2;
  const tokenSymbol = 'MARK';
  const defaultTo = accounts[1];
  const supplyOracle = accounts[2];

  const asOracle = function asOracle(fn, ...args) {
    let sendObject;
    if (typeof args[args.length - 1] === 'object') {
      sendObject = args[args.length - 1];
    } else {
      sendObject = {};
    }
    sendObject.from = supplyOracle;
    return fn(...args, sendObject);
  };

  const isEVMException = function isEVMException(err) {
    return err.toString().includes('invalid opcode') ||
      err.toString().includes('revert');
  };

  describe('As the oracle', () => {
    it('Should increase the supply by 10', async () => {
      const increaseAmount = 10;

      const instance = await EIP621OraclizedToken.new(
        initialAmount,
        tokenName,
        decimalUnits,
        tokenSymbol,
        supplyOracle,
      );
      await asOracle(instance.increaseSupply, increaseAmount, defaultTo);

      // Await on use
      const recipientBalance = instance.balanceOf.call(defaultTo);
      const expectedBalance = increaseAmount.toString(10);

      // Await on use
      const totalSupply = instance.totalSupply.call();
      const expectedSupply = (initialAmount + increaseAmount).toString(10);

      assert.strictEqual(
        (await recipientBalance).toString(10),
        expectedBalance,
      );
      assert.strictEqual((await totalSupply).toString(10), expectedSupply);
    });

    it('Should increase supply by 10 then decrease by 6', async () => {
      const increaseAmount = 10;
      const decreaseAmount = 6;
      const totalChange = increaseAmount - decreaseAmount;

      const instance = await EIP621OraclizedToken.new(
        initialAmount,
        tokenName,
        decimalUnits,
        tokenSymbol,
        supplyOracle,
      );

      await asOracle(instance.increaseSupply, increaseAmount, defaultTo);
      await asOracle(instance.decreaseSupply, decreaseAmount, defaultTo);

      // Await on use
      const recipientBalance = instance.balanceOf.call(defaultTo);
      const expectedBalance = totalChange.toString(10);

      // Await on use
      const totalSupply = instance.totalSupply.call();
      const expectedSupply = (initialAmount + totalChange).toString(10);

      assert.strictEqual(
        (await recipientBalance).toString(10),
        expectedBalance,
      );
      assert.strictEqual((await totalSupply).toString(10), expectedSupply);
    });

    it('Should fail to decrease the supply to less than zero', async () => {
      const decreaseAmount = initialAmount + 1;

      const instance = await EIP621OraclizedToken.new(
        initialAmount,
        tokenName,
        decimalUnits,
        tokenSymbol,
        supplyOracle,
      );

      try {
        await asOracle(instance.decreaseSupply, decreaseAmount, defaultTo);
      } catch (err) {
        assert(isEVMException(err), err.toString());
        return;
      }
      assert(false, 'The supply was decreased to an amount less than zero');
    });
    // it('Should fail to increase the supply to less than the starting supply');
  });

  describe('As other than the oracle', () => {
    it('Should fail to increase or decrease the supply', async () => {
      const changeAmount = 10;

      const instance = await EIP621OraclizedToken.new(
        initialAmount,
        tokenName,
        decimalUnits,
        tokenSymbol,
        supplyOracle,
      );
      try {
        await instance.increaseSupply(changeAmount, defaultTo);
        assert(
          false,
          'An entity other than the oracle was able to adjust the supply',
        );
      } catch (err) {
        assert(isEVMException(err), err.toString());
      }
      try {
        await instance.decreaseSupply(changeAmount, defaultTo);
        assert(
          false,
          'An entity other than the oracle was able to adjust the supply',
        );
      } catch (err) {
        assert(isEVMException(err));
      }
    });
  });
});

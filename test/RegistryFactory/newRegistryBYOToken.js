/* eslint-env mocha */
/* global contract assert artifacts */

const Token = artifacts.require('tokens/eip621/EIP621OraclizedToken.sol');
const RegistryFactory = artifacts.require('./RegistryFactory.sol');
const Registry = artifacts.require('./Registry.sol');
const fs = require('fs');

const config = JSON.parse(fs.readFileSync('./conf/config.json'));
const paramConfig = config.paramDefaults;

contract('RegistryFactory', (accounts) => {
  describe('Function: newRegistryBYOToken', () => {
    it('should deploy and initialize a new Registry contract', async () => {
      const registryFactory = await RegistryFactory.deployed();
      const tokenParams = {
        supply: '1000',
        name: 'TEST',
        decimals: '2',
        symbol: 'TST',
      };
      // new EIP621OraclizedToken token
      const token = await Token.new(
        tokenParams.supply,
        tokenParams.name,
        tokenParams.decimals,
        tokenParams.symbol,
      );

      // new parameterizer using factory/proxy
      const parameters = [
        paramConfig.minDeposit,
        paramConfig.pMinDeposit,
        paramConfig.applyStageLength,
        paramConfig.pApplyStageLength,
        paramConfig.commitStageLength,
        paramConfig.pCommitStageLength,
        paramConfig.revealStageLength,
        paramConfig.pRevealStageLength,
        paramConfig.dispensationPct,
        paramConfig.pDispensationPct,
        paramConfig.voteQuorum,
        paramConfig.pVoteQuorum,
        paramConfig.inflationFactor,
      ];
      // new registry using factory/proxy
      const registryReceipt = await registryFactory.newRegistryBYOToken(
        token.address,
        parameters,
        'NEW TCR',
      );
      const { creator, plcr, parameterizer } = registryReceipt.logs[0].args;
      const registry = Registry.at(registryReceipt.logs[0].args.registry);

      // verify: registry's token
      const registryToken = await registry.token.call();
      assert.strictEqual(
        registryToken,
        token.address,
        'the token attached to the Registry contract does not correspond to the one emitted in the newRegistry event',
      );
      // verify: registry's name
      const registryName = await registry.name.call();
      assert.strictEqual(
        registryName,
        'NEW TCR',
        'the registry\'s name is incorrect',
      );
      // verify: registry's creator
      assert.strictEqual(creator, accounts[0], 'the creator emitted in the newRegistry event ' +
        'not correspond to the one which sent the creation transaction');
      // verify: registry's plcr
      const registryPLCR = await registry.voting.call();
      assert.strictEqual(
        registryPLCR,
        plcr,
        'the registry\'s plcr is incorrect',
      );
      // verify: registry's parameterizer
      const registryParameterizer = await registry.parameterizer.call();
      assert.strictEqual(
        registryParameterizer,
        parameterizer,
        'the registry\'s parameterizer is incorrect',
      );
    });
  });
});

/* eslint-env mocha */
/* global contract assert artifacts */

const Token = artifacts.require('tokens/eip621/EIP621OraclizedToken.sol');
const ParameterizerFactory = artifacts.require('./ParameterizerFactory.sol');
const Parameterizer = artifacts.require('./Parameterizer.sol');
const fs = require('fs');

const config = JSON.parse(fs.readFileSync('./conf/config.json'));
const paramConfig = config.paramDefaults;

contract('ParameterizerFactory', (accounts) => {
  describe('Function: newParameterizerBYOToken', () => {
    it('should deploy and initialize a new Parameterizer contract', async () => {
      const parameterizerFactory = await ParameterizerFactory.deployed();
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
      const parameterizerReceipt = await parameterizerFactory
        .newParameterizerBYOToken(token.address, parameters);

      const parameterizer = Parameterizer.at(parameterizerReceipt.logs[0].args.parameterizer);
      const { creator, plcr } = parameterizerReceipt.logs[0].args;

      // verify: parameterizer's token
      const parameterizerToken = await parameterizer.token.call();
      assert.strictEqual(
        parameterizerToken,
        token.address,
        'the token connected to parameterizer is incorrect',
      );
      // verify: parameterizer's plcr
      const parameterizerPLCR = await parameterizer.voting.call();
      assert.strictEqual(
        parameterizerPLCR,
        plcr,
        'the parameterizer\'s plcr is incorrect',
      );
      // verify: parameterizer's creator
      assert.strictEqual(creator, accounts[0], 'the creator emitted in the newParameterizer event ' +
        'not correspond to the one which sent the creation transaction');
    });
  });
});

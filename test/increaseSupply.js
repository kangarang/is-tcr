/* eslint-env mocha */
/* global assert contract */
// const fs = require('fs');

// const config = JSON.parse(fs.readFileSync('./conf/config.json'));
// const paramConfig = config.paramDefaults;

const utils = require('./utils.js');

contract('Token/Registry', (accounts) => {
  describe('Function: increaseSupply', () => {
    const [applicant, challenger] = accounts;
    let registry;
    let token;
    // let parameterizer;
    // let voting;

    // new token, new registry each iteration
    beforeEach(async () => {
      const {
        registryProxy,
        tokenInstance,
        // paramProxy,
        // votingProxy,
      } = await utils.getProxies();

      registry = registryProxy;
      token = tokenInstance;
      // parameterizer = paramProxy;
      // voting = votingProxy;

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
      const initBalance = await token.balanceOf.call(challenger);

      const increaseAmount = 10;
      try {
        await utils.as(applicant, token.increaseSupply, increaseAmount, challenger);
      } catch (err) {
        assert(utils.isEVMException(err), err.toString());
        // new supply / balance
        const newSupply = await token.totalSupply.call();
        const newBalance = await token.balanceOf.call(challenger);
        // verify: supplies / balances + increased amount
        assert.strictEqual(newSupply.toString(), initSupply.toString(), 'new supply is incorrect');
        assert.strictEqual(newBalance.toString(), initBalance.toString(), 'new balance is incorrect');
        return;
      }
      assert(false, 'EOA was able to increase the supply');
    });

    // it('correct supply', async () => {
    //   const listing = utils.getListingHash('blahblahblah.net');
    //   const minDeposit = await parameterizer.get.call('minDeposit');

    //   const initialSupply = await token.totalSupply.call();
    //   console.log('initialSupply:', initialSupply.toString());
    //   // apply, whitelist
    //   await utils.addToWhitelist(listing, minDeposit, applicant, registry);
    //   // challenge
    //   const pollID = await utils.challengeAndGetPollID(listing, challenger, registry);

    //   // commit x2
    //   await utils.commitVote(pollID, '1', '500', '420', voterAlice, voting);
    //   await utils.commitVote(pollID, '0', '300', '9001', voterBob, voting);
    //   await utils.increaseTime(paramConfig.commitStageLength + 1);

    //   // reveal x2
    //   await utils.as(voterAlice, voting.revealVote, pollID, '1', '420');
    //   await utils.as(voterBob, voting.revealVote, pollID, '0', '9001');
    //   await utils.increaseTime(paramConfig.revealStageLength + 1);

    //   // resolveChallenge
    //   await utils.as(applicant, registry.updateStatus, listing);
    //   const middleSupply = await token.totalSupply.call();
    //   console.log('middleSupply:', middleSupply.toString());
    //   await utils.as(voterAlice, registry.claimReward, pollID, '420');
    // });
  });
});

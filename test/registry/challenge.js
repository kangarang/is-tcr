/* eslint-env mocha */
/* global assert contract */
const fs = require('fs');
const BN = require('bignumber.js');

const config = JSON.parse(fs.readFileSync('./conf/config.json'));
const paramConfig = config.paramDefaults;

const utils = require('../utils.js');

contract('Registry', (accounts) => {
  describe('Function: challenge', () => {
    const [applicant, challenger, voter] = accounts;

    let token;
    let voting;
    let parameterizer;
    let registry;

    before(async () => {
      const {
        votingProxy, paramProxy, registryProxy, tokenInstance,
      } = await utils.getProxies();
      voting = votingProxy;
      parameterizer = paramProxy;
      registry = registryProxy;
      token = tokenInstance;

      await utils.approveProxies(accounts, token, voting, parameterizer, registry);
    });

    it('should successfully challenge an application', async () => {
      const listing = utils.getListingHash('failure.net');

      const challengerStartingBalance = await token.balanceOf.call(challenger);

      await utils.as(applicant, registry.apply, listing, paramConfig.minDeposit, '');
      await utils.challengeAndGetPollID(listing, challenger, registry);
      await utils.increaseTime(paramConfig.commitStageLength + paramConfig.revealStageLength + 1);
      await registry.updateStatus(listing);

      const isWhitelisted = await registry.isWhitelisted.call(listing);
      assert.strictEqual(isWhitelisted, false, 'An application which should have failed succeeded');

      const challengerFinalBalance = await token.balanceOf.call(challenger);
      // Note edge case: no voters, so challenger gets entire stake
      const expectedFinalBalance =
        challengerStartingBalance.add(new BN(paramConfig.minDeposit, 10));
      assert.strictEqual(
        challengerFinalBalance.toString(10), expectedFinalBalance.toString(10),
        'Reward not properly disbursed to challenger',
      );
    });

    it('should successfully challenge a listing', async () => {
      const listing = utils.getListingHash('failure.net');

      const challengerStartingBalance = await token.balanceOf.call(challenger);

      await utils.addToWhitelist(listing, paramConfig.minDeposit, applicant, registry);

      await utils.challengeAndGetPollID(listing, challenger, registry);
      await utils.increaseTime(paramConfig.commitStageLength + paramConfig.revealStageLength + 1);
      await registry.updateStatus(listing);

      const isWhitelisted = await registry.isWhitelisted.call(listing);
      assert.strictEqual(isWhitelisted, false, 'An application which should have failed succeeded');

      const challengerFinalBalance = await token.balanceOf.call(challenger);
      // Note edge case: no voters, so challenger gets entire stake
      const expectedFinalBalance =
        challengerStartingBalance.add(new BN(paramConfig.minDeposit, 10));
      assert.strictEqual(
        challengerFinalBalance.toString(10), expectedFinalBalance.toString(10),
        'Reward not properly disbursed to challenger',
      );
    });

    it('should unsuccessfully challenge an application', async () => {
      const listing = utils.getListingHash('winner.net');
      const minDeposit = new BN(paramConfig.minDeposit, 10);

      await utils.as(applicant, registry.apply, listing, minDeposit, '');
      const pollID = await utils.challengeAndGetPollID(listing, challenger, registry);
      await utils.commitVote(pollID, 1, 10, 420, voter, voting);
      await utils.increaseTime(paramConfig.commitStageLength + 1);
      await utils.as(voter, voting.revealVote, pollID, 1, 420);
      await utils.increaseTime(paramConfig.revealStageLength + 1);
      await registry.updateStatus(listing);

      const isWhitelisted = await registry.isWhitelisted.call(listing);
      assert.strictEqual(
        isWhitelisted, true,
        'An application which should have succeeded failed',
      );
    });

    it('should unsuccessfully challenge a listing', async () => {
      const listing = utils.getListingHash('winner2.net');
      const minDeposit = await parameterizer.get('minDeposit');
      await utils.addToWhitelist(listing, minDeposit.toString(), applicant, registry);

      const pollID = await utils.challengeAndGetPollID(listing, challenger, registry);
      await utils.commitVote(pollID, 1, 10, 420, voter, voting);
      await utils.increaseTime(paramConfig.commitStageLength + 1);
      await utils.as(voter, voting.revealVote, pollID, 1, 420);
      await utils.increaseTime(paramConfig.revealStageLength + 1);
      await registry.updateStatus(listing);

      const isWhitelisted = await registry.isWhitelisted.call(listing);
      assert.strictEqual(isWhitelisted, true, 'An application which should have succeeded failed');
    });

    it('should not be able to challenge a listing hash that doesn\'t exist', async () => {
      const listing = utils.getListingHash('doesNotExist.net');

      try {
        await utils.challengeAndGetPollID(listing, challenger, registry);
      } catch (err) {
        assert(utils.isEVMException(err), err.toString());
        return;
      }
      assert(false, 'challenge succeeded when listing does not exist');
    });

    it('should revert if challenge occurs on a listing with an open challenge', async () => {
      const listing = utils.getListingHash('doubleChallenge.net');
      const minDeposit = new BN(await parameterizer.get.call('minDeposit'), 10);

      await utils.addToWhitelist(listing, minDeposit.toString(), applicant, registry);

      await utils.challengeAndGetPollID(listing, challenger, registry);

      try {
        await utils.as(challenger, registry.challenge, listing, '');
      } catch (err) {
        assert(utils.isEVMException(err), err.toString());
        return;
      }
      assert(false, 'challenge succeeded when challenge is already open');
    });

    it('should revert if token transfer from user fails', async () => {
      const listing = utils.getListingHash('challengerNeedsTokens.net');

      const minDeposit = new BN(await parameterizer.get.call('minDeposit'), 10);
      await utils.as(applicant, registry.apply, listing, minDeposit, '');

      // Approve the contract to transfer 0 tokens from account so the transfer will fail
      await token.approve(registry.address, '0', { from: challenger });

      try {
        await utils.as(challenger, registry.challenge, listing, '');
      } catch (err) {
        assert(utils.isEVMException(err), err.toString());
        return;
      }
      assert(false, 'allowed challenge with not enough tokens');
    });
  });
});


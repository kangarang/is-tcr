/* eslint-env mocha */
/* global assert contract */
const fs = require('fs');

const config = JSON.parse(fs.readFileSync('./conf/config.json'));
const paramConfig = config.paramDefaults;

const utils = require('./utils.js');

contract('Token/Registry', (accounts) => {
  describe('Function: increaseSupply', () => {
    const [applicant, challenger, voterAlice, voterBob, voterCat] = accounts;
    let registry;
    let token;
    let parameterizer;
    let voting;

    // new token, new registry each iteration
    beforeEach(async () => {
      const {
        registryProxy,
        tokenInstance,
        paramProxy,
        votingProxy,
      } = await utils.getProxies();

      registry = registryProxy;
      token = tokenInstance;
      parameterizer = paramProxy;
      voting = votingProxy;

      await utils.approveProxies(accounts, token, voting, parameterizer, registry);
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

    it('should return the correct supply and balances after challenge resolution inflation', async () => {
      const listing = utils.getListingHash('blahblahblah.net');
      const initialSupply = await token.totalSupply.call();
      const initialMinDeposit = await parameterizer.get.call('minDeposit');
      const registryInitialBalance = await token.balanceOf.call(registry.address);

      // apply, whitelist
      await utils.addToWhitelist(listing, applicant, registry);
      // challenge
      const pollID = await utils.challengeAndGetPollID(listing, challenger, registry);

      // commit x3
      await utils.commitVote(pollID, '1', '800', '420', voterAlice, voting);
      await utils.commitVote(pollID, '0', '300', '9001', voterBob, voting);
      await utils.commitVote(pollID, '0', '700', '69', voterCat, voting);
      await utils.increaseTime(paramConfig.commitStageLength + 1);

      // reveal x3
      await utils.as(voterAlice, voting.revealVote, pollID, '1', '420');
      await utils.as(voterBob, voting.revealVote, pollID, '0', '9001');
      await utils.as(voterCat, voting.revealVote, pollID, '0', '69');
      await utils.increaseTime(paramConfig.revealStageLength + 1);

      // resolveChallenge
      await utils.as(applicant, registry.updateStatus, listing);

      // calculate expected values
      const majorityBlocInflation = await registry.getMajorityBlocInflation.call(pollID, '1800');
      const totalNumCandidates = await registry.totalNumCandidates.call();
      const newMinDeposit = await parameterizer.get('minDeposit');
      const minDepositInflation = newMinDeposit.sub(initialMinDeposit);
      const expectedFinalSupply = initialSupply.add(majorityBlocInflation).add((totalNumCandidates.mul(minDepositInflation)));

      const actualFinalSupply = await token.totalSupply.call();
      assert.strictEqual(
        actualFinalSupply.toString(),
        expectedFinalSupply.toString(),
        'incorrect final inflated supply',
      );

      // check the registry's balance
      const rewardPool = (await registry.challenges.call(pollID))[0];

      // init + applicant + challenger stake + inflation + minDeposit inflation - (applicant minDeposit + challenger stake - rewardPool)
      const registryExpectedBalance = registryInitialBalance.add(initialMinDeposit).add(initialMinDeposit)
        .add(majorityBlocInflation)
        .add(minDepositInflation.mul(totalNumCandidates))
        .sub(initialMinDeposit.mul('2').sub(rewardPool));

      const registryFinalBalance = await token.balanceOf.call(registry.address);
      assert.strictEqual(
        registryFinalBalance.toString(),
        registryExpectedBalance.toString(),
        'incorrect final registry balance',
      );
    });

    it('should transfer the correct amount to the winner of a challenge (challenger)', async () => {
      const listing = utils.getListingHash('chickendinner.net');
      const initialBalance = await token.balanceOf.call(challenger);
      const minDeposit = await parameterizer.get.call('minDeposit');
      const registryInitialBalance = await token.balanceOf.call(registry.address);

      // apply, whitelist
      await utils.addToWhitelist(listing, applicant, registry);
      // challenge
      const pollID = await utils.challengeAndGetPollID(listing, challenger, registry);

      // commit x3
      await utils.commitVote(pollID, '1', '800', '420', voterAlice, voting);
      await utils.commitVote(pollID, '0', '300', '9001', voterBob, voting);
      await utils.commitVote(pollID, '0', '700', '69', voterCat, voting);
      await utils.increaseTime(paramConfig.commitStageLength + 1);

      // reveal x3
      await utils.as(voterAlice, voting.revealVote, pollID, '1', '420');
      await utils.as(voterBob, voting.revealVote, pollID, '0', '9001');
      await utils.as(voterCat, voting.revealVote, pollID, '0', '69');
      await utils.increaseTime(paramConfig.revealStageLength + 1);

      // calculate expected values
      const challengeReward = await registry.determineReward.call(pollID);
      const expectedBalance = initialBalance.sub(minDeposit).add(challengeReward);
      // resolve challenge
      await utils.as(applicant, registry.updateStatus, listing);

      // if the challenger wins: he gets original stake + portion of applicant's stake
      const actualFinalBalance = await token.balanceOf.call(challenger);
      assert.strictEqual(
        actualFinalBalance.toString(),
        expectedBalance.toString(),
        'incorrect final challenger balance',
      );

      // check the registry's balance
      const majorityBlocInflation = await registry.getMajorityBlocInflation.call(pollID, '1800');
      const totalNumCandidates = await registry.totalNumCandidates.call();
      const newMinDeposit = await parameterizer.get('minDeposit');
      const minDepositInflation = newMinDeposit.sub(minDeposit);
      const rewardPool = (await registry.challenges.call(pollID))[0];

      // init + applicant + challenger stake + inflation + minDeposit inflation - (applicant minDeposit + challenger stake - rewardPool)
      const registryExpectedBalance = registryInitialBalance.add(minDeposit).add(minDeposit)
        .add(majorityBlocInflation)
        .add(minDepositInflation.mul(totalNumCandidates))
        .sub(minDeposit.mul('2').sub(rewardPool));

      const registryFinalBalance = await token.balanceOf.call(registry.address);
      assert.strictEqual(
        registryFinalBalance.toString(),
        registryExpectedBalance.toString(),
        'incorrect final registry balance',
      );
    });

    it('should transfer the correct amount to the winner of a challenge (applicant)', async () => {
      const listing = utils.getListingHash('chickendinnerapplicant.net');
      const initialBalance = await token.balanceOf.call(applicant);
      const minDeposit = await parameterizer.get.call('minDeposit');
      const registryInitialBalance = await token.balanceOf.call(registry.address);

      // apply, whitelist
      await utils.addToWhitelist(listing, applicant, registry);
      // challenge
      const pollID = await utils.challengeAndGetPollID(listing, challenger, registry);

      // commit x3
      await utils.commitVote(pollID, '1', '900', '420', voterAlice, voting);
      await utils.commitVote(pollID, '0', '300', '9001', voterBob, voting);
      await utils.commitVote(pollID, '0', '500', '69', voterCat, voting);
      await utils.increaseTime(paramConfig.commitStageLength + 1);

      // reveal x3
      await utils.as(voterAlice, voting.revealVote, pollID, '1', '420');
      await utils.as(voterBob, voting.revealVote, pollID, '0', '9001');
      await utils.as(voterCat, voting.revealVote, pollID, '0', '69');
      await utils.increaseTime(paramConfig.revealStageLength + 1);

      // calculate expected values
      const challengeReward = await registry.determineReward.call(pollID);
      const expectedBalance = initialBalance.sub(minDeposit).add(challengeReward);
      // resolve challenge
      await utils.as(applicant, registry.updateStatus, listing);

      // if applicant wins: she keeps original stake + should be transferred portion of challenge.stake
      const actualFinalBalance = await token.balanceOf.call(applicant);
      assert.strictEqual(
        actualFinalBalance.toString(),
        expectedBalance.toString(),
        'incorrect final applicant balance',
      );

      // check the registry's balance
      const majorityBlocInflation = await registry.getMajorityBlocInflation.call(pollID, '1700');
      const totalNumCandidates = await registry.totalNumCandidates.call();
      const newMinDeposit = await parameterizer.get('minDeposit');
      const minDepositInflation = newMinDeposit.sub(minDeposit);
      const rewardPool = (await registry.challenges.call(pollID))[0];

      // init + applicant + challenger stake + inflation + minDeposit inflation - (challenger stake - rewardPool)
      const registryExpectedBalance = registryInitialBalance.add(minDeposit).add(minDeposit)
        .add(majorityBlocInflation)
        .add(minDepositInflation.mul(totalNumCandidates))
        .sub(minDeposit.sub(rewardPool));

      const registryFinalBalance = await token.balanceOf.call(registry.address);
      assert.strictEqual(
        registryFinalBalance.toString(),
        registryExpectedBalance.toString(),
        'incorrect final registry balance',
      );
    });
  });
});

/* global artifacts */
const fs = require('fs');

const RegistryFactory = artifacts.require('./RegistryFactory.sol');

const Token = artifacts.require('tokens/eip621/EIP621OraclizedToken.sol');
const PLCRVoting = artifacts.require('PLCRVoting.sol');
const Parameterizer = artifacts.require('Parameterizer.sol');
const Registry = artifacts.require('Registry.sol');

const config = JSON.parse(fs.readFileSync('../conf/catt.json'));
const paramConfig = config.paramDefaults;

async function deployProxies() {
  const registryFactory = await RegistryFactory.deployed();
  const registryReceipt = await registryFactory.newRegistryWithToken(
    config.token.supply,
    config.token.name,
    config.token.decimals,
    config.token.symbol,
    [
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
    ],
    config.name,
  );

  const {
    token,
    plcr,
    parameterizer,
    registry,
  } = registryReceipt.logs[0].args;

  const tokenInstance = Token.at(token);
  const votingProxy = PLCRVoting.at(plcr);
  const paramProxy = Parameterizer.at(parameterizer);
  const registryProxy = Registry.at(registry);

  console.log('token:', tokenInstance.address);
  console.log('voting:', votingProxy.address);
  console.log('param', paramProxy.address);
  console.log('registry:', registryProxy.address);

  return tokenInstance;
}

module.exports = (deployer, network) => {
  async function giveTokensTo(tokenHolders, token) {
    // no token holders
    if (tokenHolders.length === 0) { return; }

    const tokenHolder = tokenHolders[0];
    // display converted unit amounts (account for decimals)
    const displayAmt = tokenHolder.amount.slice(
      0,
      tokenHolder.amount.length - parseInt(config.token.decimals, 10),
    );
    // eslint-disable-next-line
    console.log(`Allocating ${displayAmt} ${config.token.symbol} tokens to ` +
    `${tokenHolder.address}.`);
    // transfer to token holder
    await token.transfer(tokenHolder.address, tokenHolder.amount);

    // shift 1 ->
    await giveTokensTo(tokenHolders.slice(1), token);
  }

  if (config.token.deployToken && network !== 'test') {
    deployProxies().then(token => giveTokensTo(config.token.tokenHolders, token));
  } else {
    // eslint-disable-next-line
    console.log('skipping optional token deploy and using the token at address ' +
      `${config.token.address} on network ${network}.`);
  }
};

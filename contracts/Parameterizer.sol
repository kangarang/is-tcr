pragma solidity^0.4.11;

import "tokens/eip621/EIP621OraclizedToken.sol";
import "plcr-revival/PLCRVoting.sol";
import "zeppelin/math/SafeMath.sol";

contract Parameterizer {

    // ------
    // EVENTS
    // ------

    event _ReparameterizationProposal(string name, uint value, bytes32 propID, uint deposit, uint appEndDate, address indexed proposer);
    event _NewChallenge(bytes32 indexed propID, uint challengeID, uint commitEndDate, uint revealEndDate, address indexed challenger);
    event _ProposalAccepted(bytes32 indexed propID, string name, uint value);
    event _ProposalExpired(bytes32 indexed propID);
    event _ChallengeSucceeded(bytes32 indexed propID, uint indexed challengeID, uint rewardPool, uint totalWinningTokens);
    event _ChallengeFailed(bytes32 indexed propID, uint indexed challengeID, uint rewardPool, uint totalWinningTokens);
    event _RewardClaimed(uint indexed challengeID, uint reward, address indexed voter);
    event _MinDepositSet(uint minDeposit, uint oldMinDeposit);
    event _PMinDepositSet(uint pMinDeposit, uint oldPMinDeposit);
    event _TokenSupplyIncreased(uint amount, address to, uint newTotalSupply);

    // ------
    // DATA STRUCTURES
    // ------

    using SafeMath for uint;

    struct ParamProposal {
        uint appExpiry;
        uint challengeID;
        uint deposit;
        string name;
        address owner;
        uint processBy;
        uint value;
    }

    struct Challenge {
        uint rewardPool;        // (remaining) pool of tokens distributed amongst winning voters
        address challenger;     // owner of Challenge
        bool resolved;          // indication of if challenge is resolved
        uint stake;             // number of tokens at risk for either party during challenge
        uint totalWinningTokens;     // amount of tokens used for voting by the winning side
        mapping(address => bool) tokenClaims;
        uint majorityBlocInflation;
        uint inflationFactor;
        uint tokenSupply;
    }

    // ------
    // STATE
    // ------

    mapping(bytes32 => uint) public params;

    // maps challengeIDs to associated challenge data
    mapping(uint => Challenge) public challenges;

    // maps pollIDs to intended data change if poll passes
    mapping(bytes32 => ParamProposal) public proposals;

    // Global Variables
    EIP621OraclizedToken public token;
    PLCRVoting public voting;
    uint public PROCESSBY = 604800; // 7 days

    modifier onlySupplyOracle {
        require(msg.sender == token.supplyOracle() || msg.sender == token.pSupplyOracle());
        _;
    }

    /**
    @dev Initializer        Can only be called once
    @param _token           The address where the ERC20 token contract is deployed
    @param _plcr            address of a PLCR voting contract for the provided token
    @notice _parameters     array of canonical parameters
    */
    function init(
        address _token,
        address _plcr,
        uint[14] _parameters
    ) public {
        require(_token != 0 && address(token) == 0);
        require(_plcr != 0 && address(voting) == 0);

        token = EIP621OraclizedToken(_token);
        voting = PLCRVoting(_plcr);

        // minimum deposit for listing to be whitelisted
        set("minDeposit", _parameters[0]);
        
        // minimum deposit to propose a reparameterization
        set("pMinDeposit", _parameters[1]);

        // period over which applicants wait to be whitelisted
        set("applyStageLen", _parameters[2]);

        // period over which reparmeterization proposals wait to be processed
        set("pApplyStageLen", _parameters[3]);

        // length of commit period for voting
        set("commitStageLen", _parameters[4]);

        // length of commit period for voting in parameterizer
        set("pCommitStageLen", _parameters[5]);

        // length of reveal period for voting
        set("revealStageLen", _parameters[6]);

        // length of reveal period for voting in parameterizer
        set("pRevealStageLen", _parameters[7]);

        // percentage of losing party's deposit distributed to winning party
        set("dispensationPct", _parameters[8]);

        // percentage of losing party's deposit distributed to winning party in parameterizer
        set("pDispensationPct", _parameters[9]);

        // type of majority out of 100 necessary for candidate success
        set("voteQuorum", _parameters[10]);

        // type of majority out of 100 necessary for proposal success in parameterizer
        set("pVoteQuorum", _parameters[11]);

        // inflation multiplier, determines the majority_bloc inflation reward
        set("inflationFactor", _parameters[12]);  

        // reparameterization inflation multiplier, determines the majority_bloc inflation reward
        set("pInflationFactor", _parameters[13]);  
    }

    // TODO: supplyOracle -> transfer to/from registry if minDeposit manually set
    function setMinDeposit(uint _majorityBlocInflation, uint _tokenSupply) public onlySupplyOracle returns (uint) {
        uint minDeposit = get("minDeposit");

        // set the new minDeposit proportional to the inflated totalSupply
        // minDeposit * (totalSupply + majorityBlocInflation) / totalSupply
        uint newMinDeposit = minDeposit.mul(_tokenSupply.add(_majorityBlocInflation)).div(_tokenSupply);
        // (10 * (8000 + 2400)) / 8000 -> 13
        // TODO: assert correct ratios

        set("minDeposit", newMinDeposit);
        emit _MinDepositSet(newMinDeposit, minDeposit);
        return newMinDeposit.sub(minDeposit);
    }

    function setPMinDeposit(uint _majorityBlocInflation, uint _tokenSupply) public onlySupplyOracle returns (uint) {
        uint pMinDeposit = get("pMinDeposit");
        uint pNewMinDeposit = pMinDeposit.mul(_tokenSupply.add(_majorityBlocInflation)).div(_tokenSupply);

        set("pMinDeposit", pNewMinDeposit);
        emit _PMinDepositSet(pNewMinDeposit, pMinDeposit);
        return pNewMinDeposit.sub(pMinDeposit);
    }

    // -----------------------
    // TOKEN HOLDER INTERFACE
    // -----------------------

    /**
    @notice propose a reparamaterization of the key _name's value to _value.
    @param _name the name of the proposed param to be set
    @param _value the proposed value to set the param to be set
    */
    function proposeReparameterization(string _name, uint _value) public returns (bytes32) {
        uint deposit = get("pMinDeposit");
        bytes32 propID = keccak256(abi.encodePacked(_name, _value));

        if (keccak256(abi.encodePacked(_name)) == keccak256("dispensationPct") ||
            keccak256(abi.encodePacked(_name)) == keccak256("pDispensationPct")) {
            require(_value <= 100);
        }

        require(!propExists(propID)); // Forbid duplicate proposals
        require(get(_name) != _value); // Forbid NOOP reparameterizations

        // attach name and value to pollID
        proposals[propID] = ParamProposal({
            appExpiry: now.add(get("pApplyStageLen")),
            challengeID: 0,
            deposit: deposit,
            name: _name,
            owner: msg.sender,
            processBy: now.add(get("pApplyStageLen"))
                .add(get("pCommitStageLen"))
                .add(get("pRevealStageLen"))
                .add(PROCESSBY),
            value: _value
        });

        require(token.transferFrom(msg.sender, this, deposit)); // escrow tokens (deposit amt)

        emit _ReparameterizationProposal(_name, _value, propID, deposit, proposals[propID].appExpiry, msg.sender);
        return propID;
    }

    /**
    @notice challenge the provided proposal ID, and put tokens at stake to do so.
    @param _propID the proposal ID to challenge
    */
    function challengeReparameterization(bytes32 _propID) public returns (uint challengeID) {
        ParamProposal memory prop = proposals[_propID];
        uint deposit = prop.deposit;

        require(propExists(_propID) && prop.challengeID == 0);

        //start poll
        uint pollID = voting.startPoll(
            get("pVoteQuorum"),
            get("pCommitStageLen"),
            get("pRevealStageLen")
        );

        challenges[pollID] = Challenge({
            challenger: msg.sender,
            rewardPool: SafeMath.sub(100, get("pDispensationPct")).mul(deposit).div(100),
            stake: deposit,
            resolved: false,
            totalWinningTokens: 0,
            majorityBlocInflation: 0,
            inflationFactor: get("pInflationFactor"),
            tokenSupply: token.totalSupply()
        });

        proposals[_propID].challengeID = pollID;       // update listing to store most recent challenge
        (uint commitEndDate, uint revealEndDate,,,) = voting.pollMap(pollID);

        //take tokens from challenger
        require(token.transferFrom(msg.sender, this, deposit));
        emit _NewChallenge(_propID, pollID, commitEndDate, revealEndDate, msg.sender);
        return pollID;
    }

    /**
    @notice for the provided proposal ID, set it, resolve its challenge, or delete it depending on whether it can be set, has a challenge which can be resolved, or if its "process by" date has passed
    @param _propID the proposal ID to make a determination and state transition for
    */
    function processProposal(bytes32 _propID) public {
        ParamProposal storage prop = proposals[_propID];
        address propOwner = prop.owner;
        uint propDeposit = prop.deposit;

        // Before any token transfers, deleting the proposal will ensure that if reentrancy occurs the
        // prop.owner and prop.deposit will be 0, thereby preventing theft
        if (canBeSet(_propID)) {
            // There is no challenge against the proposal. The processBy date for the proposal has not
            // passed, but the proposal's appExpirty date has passed.
            set(prop.name, prop.value);
            emit _ProposalAccepted(_propID, prop.name, prop.value);
            delete proposals[_propID];
            require(token.transfer(propOwner, propDeposit));
        } else if (challengeCanBeResolved(_propID)) {
            // There is a challenge against the proposal.
            resolveChallenge(_propID);
        } else if (now > prop.processBy) {
            // There is no challenge against the proposal, but the processBy date has passed.
            emit _ProposalExpired(_propID);
            delete proposals[_propID];
            require(token.transfer(propOwner, propDeposit));
        } else {
            // There is no challenge against the proposal, and neither the appExpiry date nor the
            // processBy date has passed.
            revert();
        }

        assert(get("dispensationPct") <= 100);
        assert(get("pDispensationPct") <= 100);

        // verify that future proposal appExpiry and processBy times will not overflow
        now.add(get("pApplyStageLen"))
            .add(get("pCommitStageLen"))
            .add(get("pRevealStageLen"))
            .add(PROCESSBY);

        delete proposals[_propID];
    }

    /**
    @notice claim the tokens owed for the msg.sender in the provided challenge
    @param _challengeID the challenge ID to claim tokens for
    @param _salt the salt used to vote in the challenge being withdrawn for
    */
    function claimReward(uint _challengeID, uint _salt) public {
        // ensure voter has not already claimed tokens and challenge results have been processed
        require(challenges[_challengeID].tokenClaims[msg.sender] == false);
        require(challenges[_challengeID].resolved == true);

        // calculate user's portion of challenge reward (% of rewardPool)
        uint challengeReward = voterReward(msg.sender, _challengeID, _salt);
        // calculate user's portion of inflation reward (% of majorityBlocInflation)
        uint inflationReward = voterInflationReward(msg.sender, _challengeID, _salt);

        // ensures a voter cannot claim tokens again
        challenges[_challengeID].tokenClaims[msg.sender] = true;

        // transfer the sum of both rewards
        require(token.transfer(msg.sender, challengeReward.add(inflationReward)));
        emit _RewardClaimed(_challengeID, challengeReward.add(inflationReward), msg.sender);
    }

    // --------
    // GETTERS
    // --------

    /**
    @dev                Calculates the provided voter's token reward for the given poll.
    @param _voter       The address of the voter whose reward balance is to be returned
    @param _challengeID The ID of the challenge the voter's reward is being calculated for
    @param _salt        The salt of the voter's commit hash in the given poll
    @return             The uint indicating the voter's reward
    */
    function voterReward(address _voter, uint _challengeID, uint _salt) public view returns (uint) {
        uint totalWinningTokens = challenges[_challengeID].totalWinningTokens;
        uint rewardPool = challenges[_challengeID].rewardPool;
        uint voterTokens = voting.getNumPassingTokens(_voter, _challengeID, _salt);
        return (voterTokens * rewardPool) / totalWinningTokens;
    }

    /**
    @dev                Calculates the provided voter's inflation reward for the given poll.
    @param _voter       The address of the voter whose inflation reward is to be returned
    @param _challengeID The pollID of the challenge an inflation reward is being queried for
    @param _salt        The salt of the voter's commit hash in the given poll
    @return             The uint indicating the voter's inflation reward
    */
    function voterInflationReward(address _voter, uint _challengeID, uint _salt) public view returns (uint) {
        uint totalWinningTokens = challenges[_challengeID].totalWinningTokens;
        uint majorityBlocInflation = challenges[_challengeID].majorityBlocInflation;
        uint voterTokens = voting.getNumPassingTokens(_voter, _challengeID, _salt);
        return voterTokens.mul(majorityBlocInflation).div(totalWinningTokens);
    }

    /**
    @notice Determines whether a proposal passed its application stage without a challenge
    @param _propID The proposal ID for which to determine whether its application stage passed without a challenge
    */
    function canBeSet(bytes32 _propID) view public returns (bool) {
        ParamProposal memory prop = proposals[_propID];

        return (now > prop.appExpiry && now < prop.processBy && prop.challengeID == 0);
    }

    /**
    @notice Determines whether a proposal exists for the provided proposal ID
    @param _propID The proposal ID whose existance is to be determined
    */
    function propExists(bytes32 _propID) view public returns (bool) {
        return proposals[_propID].processBy > 0;
    }

    /**
    @notice Determines whether the provided proposal ID has a challenge which can be resolved
    @param _propID The proposal ID whose challenge to inspect
    */
    function challengeCanBeResolved(bytes32 _propID) view public returns (bool) {
        ParamProposal memory prop = proposals[_propID];
        Challenge memory challenge = challenges[prop.challengeID];

        return (prop.challengeID > 0 && challenge.resolved == false && voting.pollEnded(prop.challengeID));
    }

    /**
    @notice Determines the number of tokens to awarded to the winning party in a challenge
    @param _challengeID The challengeID to determine a reward for
    */
    function challengeWinnerReward(uint _challengeID) public view returns (uint) {
        // Edge case, nobody voted, give all tokens to the challenger.
        if (voting.getTotalNumberOfTokensForWinningOption(_challengeID) == 0) {
            return challenges[_challengeID].stake.mul(2);
        }

        // case: applicant won
        if (voting.isPassed(_challengeID)) {
            return challenges[_challengeID].stake.sub(challenges[_challengeID].rewardPool);
        }

        // case: challenger won
        return (challenges[_challengeID].stake.mul(2)).sub(challenges[_challengeID].rewardPool);
    }

    /**
    @notice gets the parameter keyed by the provided name value from the params mapping
    @param _name the key whose value is to be determined
    */
    function get(string _name) public view returns (uint value) {
        return params[keccak256(abi.encodePacked(_name))];
    }

    /**
    @dev                Getter for Challenge tokenClaims mappings
    @param _challengeID The challengeID to query
    @param _voter       The voter whose claim status to query for the provided challengeID
    */
    function tokenClaims(uint _challengeID, address _voter) public view returns (bool) {
        return challenges[_challengeID].tokenClaims[_voter];
    }

    /**
    @dev                        Getter for majority bloc inflation reward
    @param _challengeID         The poll ID to query
    @param _totalWinningTokens  The total number of tokens voted by the majority bloc voters
    */
    function getMajorityBlocInflation(uint _challengeID, uint _totalWinningTokens) public view returns (uint) {
        // unmodulated amount: totalSupply - winningTokens
        uint unmodulatedTokensToMint = challenges[_challengeID].tokenSupply.sub(_totalWinningTokens);
        // modulated: inflation factor percentage of raw amount
        return challenges[_challengeID].inflationFactor.mul(unmodulatedTokensToMint).div(100);
    }

    // ----------------
    // PRIVATE FUNCTIONS
    // ----------------

    /**
    @dev resolves a challenge for the provided _propID. It must be checked in advance whether the _propID has a challenge on it
    @param _propID the proposal ID whose challenge is to be resolved.
    */
    function resolveChallenge(bytes32 _propID) private {
        ParamProposal memory prop = proposals[_propID];
        Challenge storage challenge = challenges[prop.challengeID];

        // winner gets back their full staked deposit, and dispensationPct*loser's stake
        uint reward = challengeWinnerReward(prop.challengeID);

        challenge.resolved = true;
        challenge.totalWinningTokens = voting.getTotalNumberOfTokensForWinningOption(prop.challengeID);

        // calculate the inflation reward that is reserved for majority bloc voters
        uint majorityBlocInflation = getMajorityBlocInflation(prop.challengeID, challenge.totalWinningTokens);
        // during claimReward, voters will receive a token-weighted share of the minted inflation tokens
        challenge.majorityBlocInflation = majorityBlocInflation;

        // Why is this written in a different order than how it's written in Registry?
        // proposals are transient (no whitelist)
        // thus, Parameterizer doesn't use numCandidates
        // since the winnings of a challenge should not be diluted
        // we need the value of pMinDepositInflation so that we can transfer that to the winner
        // thus, we must first increase the supply

        uint pMinDepositInflation = 0;
        if (majorityBlocInflation > 0) {
            // set the new pMinDeposit proportional to the inflation
            pMinDepositInflation = this.setPMinDeposit(majorityBlocInflation, challenge.tokenSupply);

            // use the pMinDepositInflation to calculate additional inflation, withdrawable by candidates
            // inflate token supply for winner-voters + all candidates -- to keep up with the token's inflating supply
            require(token.increaseSupply(majorityBlocInflation.add(pMinDepositInflation), this));
            emit _TokenSupplyIncreased(majorityBlocInflation.add(pMinDepositInflation), this, token.totalSupply());
        }

        if (voting.isPassed(prop.challengeID)) { // The challenge failed
            if (prop.processBy > now) {
                set(prop.name, prop.value);
            }
            require(token.transfer(prop.owner, reward.add(pMinDepositInflation)));
            emit _ChallengeFailed(_propID, prop.challengeID, challenge.rewardPool, challenge.totalWinningTokens);
        }
        else { // The challenge succeeded or nobody voted
            require(token.transfer(challenge.challenger, reward.add(pMinDepositInflation)));
            emit _ChallengeSucceeded(_propID, prop.challengeID, challenge.rewardPool, challenge.totalWinningTokens);
        }
    }

    /**
    @dev sets the param keyed by the provided name to the provided value
    @param _name the name of the param to be set
    @param _value the value to set the param to be set
    */
    function set(string _name, uint _value) private {
        params[keccak256(abi.encodePacked(_name))] = _value;
    }
}


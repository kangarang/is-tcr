pragma solidity ^0.4.11;

import "tokens/eip621/EIP621OraclizedToken.sol";
import "./Parameterizer.sol";
import "plcr-revival/PLCRVoting.sol";
import "zeppelin/math/SafeMath.sol";

contract Registry {

    // ------
    // EVENTS
    // ------

    event _Application(bytes32 indexed listingHash, uint deposit, uint appEndDate, string data, address indexed applicant);
    event _Challenge(bytes32 indexed listingHash, uint challengeID, string data, uint commitEndDate, uint revealEndDate, address indexed challenger);
    event _ApplicationWhitelisted(bytes32 indexed listingHash);
    event _ApplicationRemoved(bytes32 indexed listingHash);
    event _ListingRemoved(bytes32 indexed listingHash);
    event _ListingWithdrawn(bytes32 indexed listingHash);
    event _ChallengeFailed(bytes32 indexed listingHash, uint indexed challengeID, uint rewardPool, uint totalWinningTokens);
    event _ChallengeSucceeded(bytes32 indexed listingHash, uint indexed challengeID, uint rewardPool, uint totalWinningTokens);
    event _RewardClaimed(uint indexed challengeID, uint reward, address indexed voter);
    event _TokenSupplyIncreased(uint amount, address to, uint newTotalSupply);
    event DEBUG(string name, uint value);

    using SafeMath for uint;

    struct Listing {
        uint applicationExpiry; // Expiration date of apply stage
        bool whitelisted;       // Indicates registry status
        address owner;          // Owner of Listing
        uint challengeID;       // Corresponds to a PollID in PLCRVoting
    }

    struct Challenge {
        uint rewardPool;        // (remaining) Pool of tokens to be distributed to winning voters (applicant/challenger -> voters)
        address challenger;     // Owner of Challenge
        bool resolved;          // Indication of if challenge is resolved
        uint totalWinningTokens;       // (remaining) Number of tokens used in voting by the winning side
        mapping(address => bool) tokenClaims; // Indicates whether a voter has claimed a reward yet
        uint majorityBlocInflation;
        uint inflationFactor;
        uint tokenSupply;
        uint stake;
    }

    // Maps challengeIDs to associated challenge data
    mapping(uint => Challenge) public challenges;

    // Maps listingHashes to associated listingHash data
    mapping(bytes32 => Listing) public listings;

    // Global Variables
    EIP621OraclizedToken public token;
    PLCRVoting public voting;
    Parameterizer public parameterizer;
    string public name;
    uint public totalNumCandidates;

    /**
    @dev Initializer. Can only be called once.
    @param _token The address where the ERC20 token contract is deployed
    */
    function init(address _token, address _voting, address _parameterizer, string _name) public {
        require(_token != 0 && address(token) == 0);
        require(_voting != 0 && address(voting) == 0);
        require(_parameterizer != 0 && address(parameterizer) == 0);

        token = EIP621OraclizedToken(_token);
        voting = PLCRVoting(_voting);
        parameterizer = Parameterizer(_parameterizer);
        name = _name;
        totalNumCandidates = 0;
    }

    // --------------------
    // PUBLISHER INTERFACE:
    // --------------------

    /**
    @dev                Allows a user to start an application. Takes tokens from user and sets
                        apply stage end time.
    @param _listingHash The hash of a potential listing a user is applying to add to the registry
    @param _data        Extra data relevant to the application. Think IPFS hashes.
    */
    function apply(bytes32 _listingHash, string _data) external {
        require(!isWhitelisted(_listingHash));
        require(!appWasMade(_listingHash));

        // Sets owner
        Listing storage listing = listings[_listingHash];
        listing.owner = msg.sender;

        // Sets apply stage end time
        listing.applicationExpiry = now.add(parameterizer.get("applyStageLen"));

        // increase global totalNumCandidates
        totalNumCandidates += 1;

        // Transfers tokens from user to Registry contract
        require(token.transferFrom(listing.owner, this, parameterizer.get("minDeposit")));

        emit _Application(_listingHash, parameterizer.get("minDeposit"), listing.applicationExpiry, _data, msg.sender);
    }

    /**
    @dev                Allows the owner of a listingHash to remove the listingHash from the whitelist
                        Returns all tokens to the owner of the listingHash
    @param _listingHash A listingHash msg.sender is the owner of.
    */
    function exit(bytes32 _listingHash) external {
        Listing storage listing = listings[_listingHash];

        address owner = listing.owner;
        require(msg.sender == owner);
        require(isWhitelisted(_listingHash));

        // Cannot exit during ongoing challenge
        require(listing.challengeID == 0 || challenges[listing.challengeID].resolved);

        // Remove listingHash & return tokens
        resetListing(_listingHash);
        // Transfers any remaining balance back to the owner
        require(token.transfer(owner, parameterizer.get("minDeposit")));
        emit _ListingWithdrawn(_listingHash);
    }

    // -----------------------
    // TOKEN HOLDER INTERFACE:
    // -----------------------

    /**
    @dev                Starts a poll for a listingHash which is either in the apply stage or
                        already in the whitelist. Tokens are taken from the challenger and the
                        applicant's deposits are locked.
    @param _listingHash The listingHash being challenged, whether listed or in application
    @param _data        Extra data relevant to the challenge. Think IPFS hashes.
    */
    function challenge(bytes32 _listingHash, string _data) external returns (uint challengeID) {
        Listing storage listing = listings[_listingHash];
        uint minDeposit = parameterizer.get("minDeposit");

        // Listing must be in apply stage or already on the whitelist
        require(appWasMade(_listingHash) || listing.whitelisted);
        // Prevent multiple challenges
        require(listing.challengeID == 0 || challenges[listing.challengeID].resolved);

        // Starts poll
        uint pollID = voting.startPoll(
            parameterizer.get("voteQuorum"),
            parameterizer.get("commitStageLen"),
            parameterizer.get("revealStageLen")
        );

        uint oneHundred = 100; // Kludge that we need to use SafeMath
        challenges[pollID] = Challenge({
            challenger: msg.sender,
            rewardPool: ((oneHundred.sub(parameterizer.get("dispensationPct"))).mul(minDeposit)).div(100),
            resolved: false,
            totalWinningTokens: 0,
            majorityBlocInflation: 0,
            inflationFactor: parameterizer.get("inflationFactor"),
            tokenSupply: token.totalSupply().div(1000000000000000000),
            stake: minDeposit
        });

        // set the challengeID, prevent candidate from exiting
        listing.challengeID = pollID;

        // Take tokens from challenger
        require(token.transferFrom(msg.sender, this, minDeposit));

        var (commitEndDate, revealEndDate,) = voting.pollMap(pollID);
        emit _Challenge(_listingHash, pollID, _data, commitEndDate, revealEndDate, msg.sender);
        return pollID;
    }

    /**
    @dev                Updates a listingHash's status from 'application' to 'listing' or resolves
                        a challenge if one exists.
    @param _listingHash The listingHash whose status is being updated
    */
    function updateStatus(bytes32 _listingHash) public {
        if (canBeWhitelisted(_listingHash)) {
            whitelistApplication(_listingHash);
        } else if (challengeCanBeResolved(_listingHash)) {
            resolveChallenge(_listingHash);
        } else {
            revert();
        }
    }

    // ----------------
    // TOKEN FUNCTIONS:
    // ----------------

    /**
    @dev                Called by a voter to claim their reward for each completed vote. Someone
                        must call updateStatus() before this can be called.
    @param _challengeID The PLCR pollID of the challenge a reward is being claimed for
    @param _salt        The salt of a voter's commit hash in the given poll
    */
    function claimReward(uint _challengeID, uint _salt) public {
        // Ensures the voter has not already claimed tokens and challenge results have been processed
        require(challenges[_challengeID].tokenClaims[msg.sender] == false);
        require(challenges[_challengeID].resolved == true);

        // calculate user's portion of challenge reward (% of rewardPool)
        uint challengeReward = voterReward(msg.sender, _challengeID, _salt);
        // calculate user's portion of inflation reward (% of majorityBlocInflation)
        uint inflationReward = voterInflationReward(msg.sender, _challengeID, _salt);

        // Ensures a voter cannot claim tokens again
        challenges[_challengeID].tokenClaims[msg.sender] = true;
	
        // transfer the sum of both rewards
        require(token.transfer(msg.sender, challengeReward.add(inflationReward)));
        emit _RewardClaimed(_challengeID, challengeReward.add(inflationReward), msg.sender);
    }

    // --------
    // GETTERS:
    // --------

    /**
    @dev                Calculates the provided voter's token reward for the given poll.
    @param _voter       The address of the voter whose reward balance is to be returned
    @param _challengeID The pollID of the challenge a reward balance is being queried for
    @param _salt        The salt of the voter's commit hash in the given poll
    @return             The uint indicating the voter's reward
    */
    function voterReward(address _voter, uint _challengeID, uint _salt) public view returns (uint) {
        uint totalWinningTokens = challenges[_challengeID].totalWinningTokens;
        uint rewardPool = challenges[_challengeID].rewardPool;
        uint voterTokens = voting.getNumPassingTokens(_voter, _challengeID, _salt);
        return voterTokens.mul(rewardPool).div(totalWinningTokens);
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
    @dev                Determines whether the given listingHash be whitelisted.
    @param _listingHash The listingHash whose status is to be examined
    */
    function canBeWhitelisted(bytes32 _listingHash) view public returns (bool) {
        uint challengeID = listings[_listingHash].challengeID;

        // Ensures that the application was made,
        // the application period has ended,
        // the listingHash can be whitelisted,
        // and either: the challengeID == 0, or the challenge has been resolved.
        if (
            appWasMade(_listingHash) &&
            listings[_listingHash].applicationExpiry < now &&
            !isWhitelisted(_listingHash) &&
            (challengeID == 0 || challenges[challengeID].resolved == true)
        ) { return true; }

        return false;
    }

    /**
    @dev                Returns true if the provided listingHash is whitelisted
    @param _listingHash The listingHash whose status is to be examined
    */
    function isWhitelisted(bytes32 _listingHash) view public returns (bool whitelisted) {
        return listings[_listingHash].whitelisted;
    }

    /**
    @dev                Returns true if apply was called for this listingHash
    @param _listingHash The listingHash whose status is to be examined
    */
    function appWasMade(bytes32 _listingHash) view public returns (bool exists) {
        return listings[_listingHash].applicationExpiry > 0;
    }

    /**
    @dev                Returns true if the application/listingHash has an unresolved challenge
    @param _listingHash The listingHash whose status is to be examined
    */
    function challengeExists(bytes32 _listingHash) view public returns (bool) {
        uint challengeID = listings[_listingHash].challengeID;

        return (listings[_listingHash].challengeID > 0 && !challenges[challengeID].resolved);
    }

    /**
    @dev                Determines whether voting has concluded in a challenge for a given
                        listingHash. Throws if no challenge exists.
    @param _listingHash A listingHash with an unresolved challenge
    */
    function challengeCanBeResolved(bytes32 _listingHash) view public returns (bool) {
        uint challengeID = listings[_listingHash].challengeID;

        require(challengeExists(_listingHash));

        return voting.pollEnded(challengeID);
    }

    /**
    @dev                Determines the number of tokens awarded to the winning party in a challenge.
    @param _challengeID The challengeID to determine a reward for
    */
    function determineReward(uint _challengeID) public view returns (uint) {
        require(!challenges[_challengeID].resolved && voting.pollEnded(_challengeID));

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
        // 3000 raw           =  (8000 - 5000)
        uint unmodulatedTokensToMint = challenges[_challengeID].tokenSupply.sub(_totalWinningTokens);
        emit DEBUG("unmodulatedTokensToMint", unmodulatedTokensToMint);
        // 2400 modulated     =  (80 * 3000) / 100
        return challenges[_challengeID].inflationFactor.mul(unmodulatedTokensToMint).div(100);
    }

    // ----------------
    // PRIVATE FUNCTIONS:
    // ----------------

    /**
    @dev                Determines the winner in a challenge. Rewards the winner tokens and
                        either whitelists or de-whitelists the listingHash.
    @param _listingHash A listingHash with a challenge that is to be resolved
    */
    function resolveChallenge(bytes32 _listingHash) private {
        uint challengeID = listings[_listingHash].challengeID;

        // Calculates the winner's reward,
        // if applicant wins: dispensationPct * challenger's stake
        // if challenger wins: stake + (dispensationPct * applicant's stake)
        uint challengeWinnerReward = determineReward(challengeID);

        // Sets flag on challenge being processed
        challenges[challengeID].resolved = true;

        // Stores the total tokens used for voting by the winning side for reward purposes
        uint totalWinningTokens = voting.getTotalNumberOfTokensForWinningOption(challengeID);
        challenges[challengeID].totalWinningTokens = totalWinningTokens;
        emit DEBUG("totalWinningTokens", totalWinningTokens);

        uint majorityBlocInflation = getMajorityBlocInflation(challengeID, totalWinningTokens);
        emit DEBUG("majorityBlocInflation", majorityBlocInflation);

        // tokens NOT in the majority bloc voters are subject to inflation-dilution (remainder of total_supply - majority_bloc_tokens)
        // inflationFactor is parameter uint percentage. it modifies the actual number of tokens that will be inflated

        // during claimReward, voters will receive a token-weighted share of the minted inflation tokens
        challenges[challengeID].majorityBlocInflation = majorityBlocInflation;

        // Case: challenge failed
        if (voting.isPassed(challengeID)) {
            whitelistApplication(_listingHash);
            require(token.transfer(listings[_listingHash].owner, challengeWinnerReward));
            emit _ChallengeFailed(_listingHash, challengeID, challenges[challengeID].rewardPool, totalWinningTokens);
        }
        // Case: challenge succeeded or nobody voted
        else {
            resetListing(_listingHash);
            require(token.transfer(challenges[challengeID].challenger, challengeWinnerReward));
            emit _ChallengeSucceeded(_listingHash, challengeID, challenges[challengeID].rewardPool, totalWinningTokens);
        }

        if (majorityBlocInflation > 0) {
            // set the new minDeposit proportional to the inflation
            uint minDepositInflation = parameterizer.setMinDeposit(majorityBlocInflation, challenges[challengeID].tokenSupply);

            // use the minDepositInflation to calculate additional inflation, withdrawable by candidates
            // inflate token supply for winner-voters + all candidates
            emit DEBUG("totalNumCandidates", totalNumCandidates);
            require(token.increaseSupply(majorityBlocInflation.add(minDepositInflation.mul(totalNumCandidates)), this));
            // 2400 + (3 * 4) -> 2412
            emit _TokenSupplyIncreased(majorityBlocInflation.add(minDepositInflation.mul(totalNumCandidates)), this, token.totalSupply());
        }
    }

    /**
    @dev                Called by updateStatus() if the applicationExpiry date passed without a
                        challenge being made. Called by resolveChallenge() if an
                        application/listing beat a challenge.
    @param _listingHash The listingHash of an application/listingHash to be whitelisted
    */
    function whitelistApplication(bytes32 _listingHash) private {
        if (!listings[_listingHash].whitelisted) { emit _ApplicationWhitelisted(_listingHash); }
        listings[_listingHash].whitelisted = true;
    }

    /**
    @dev                Deletes a listingHash from the whitelist and transfers tokens back to owner
    @param _listingHash The listing hash to delete
    */
    function resetListing(bytes32 _listingHash) private {
        Listing storage listing = listings[_listingHash];

        // Emit events before deleting listing to check whether is whitelisted
        if (listing.whitelisted) {
            emit _ListingRemoved(_listingHash);
        } else {
            emit _ApplicationRemoved(_listingHash);
        }

        totalNumCandidates -= 1;

        // Delete listing to prevent reentry
        delete listings[_listingHash];
    }
}

pragma solidity 0.5.1;

// Pr000xy - a public utility ERC20 for creating & claiming transparent proxies
// with gas-efficient addresses. Tokens are minted when specific salts or nonces
// are submitted that result in the creation of new proxies with more zero bytes
// than usual. They are then burned when transferring ownership of those proxies
// from the contract to the claimer. Pr000xy also allows for bounties to be
// placed on matching proxy addresses to a set of conditions (i.e. finding
// custom vanity addresses).
//
// A detailed description with additional context can be found here:
//
//   https://medium.com/@0age/on-efficient-ethereum-addresses-3fef0596e263
//
// DISCLAIMER: DO NOT HODL THIS TOKEN! Pr000xy may technically be an ERC20
// token, but makes for a TERRIBLE "investment" for a whole bunch of reasons,
// such as:
//  * The code is unaudited, mostly untested, and highly experimental, and so
//    should not be considered secure by any measure (this goes for placing
//    offers as well - don't put up any offer that you're not prepared to lose),
//  * The token itself is highly deflationary, meaning that it will almost
//    certainly decrease in value as address mining becomes more efficient,
//  * The token's value will be highly volatile and total supply will fluctuate
//    greatly, as creation of new, comparatively rare addresses will issue a
//    massive number of tokens at once,
//  * The token will be vulnerable to "shadow mining", where miners can wait to
//    submit discovered addresses and instead submit a large group all at once,
//    making it a target for manipulation,
//  * The token contract itself will likely become obsolete as better methods
//    for performing this functionality become available and new versions come
//    online... and no, there will be no way to "convert your tokens to the new
//    version", because
//  * There's no organization, group, collective, or whatever backing the
//    tokens, and they're not a claim on any asset, voting right, share, or
//    anything at all except for that they can be burned in order to take
//    ownership of an unclaimed proxy.
// 
// TO REITERATE: this should NOT be considered an investment of any kind! There
// is no ICO or token sale - don't be a giver-of-ETH to a scammer.

import "./token/ERC20.sol";
import "./token/ERC20Detailed.sol";
import "./Pr000xyInterface.sol";


/**
 * @title Interface for each created proxy contract. Only the administrator of
 * the proxy may use these methods - for any other caller, the proxy is totally
 * transparent and will simply reroute to the fallback function which then uses
 * delegatecall to forward the call to the proxy's implementation contract.
 */
interface AdminUpgradeabilityProxyInterface {
  function upgradeTo(address) external;
  function upgradeToAndCall(address, bytes calldata) external payable;
  function changeAdmin(address) external;
  function admin() external view returns (address);
}


/**
 * @title Interface to a registry contract containing reward function values.
 */
interface Pr000xyRewardsInterface {
  function getPr000xyReward(uint24) external view returns (uint256);
}


/**
 * @title Logic contract initially set on each created proxy contract.
 */
contract InitialProxyImplementation {
  function test() external pure returns (bool) {
    return true;
  }
}


/**
 * @title Pr000xy - a public utility ERC20 for creating & claiming transparent
 * upgradeable proxies with gas-efficient account addresses.
 * @author 0age
 * @notice Tokens are minted when specific salts or nonces are submitted that
 * result in the creation of new proxies with more zero bytes than usual. They
 * are then burned when transferring ownership of those proxies from the
 * contract to the claimer. Pr000xy also allows for additional bounties to be
 * placed on matching proxy addresses to a set of conditions (i.e. finding
 * custom vanity addresses).
 * @dev This contract is an upgradeable proxy factory, where each created proxy
 * uses the same initialization code. The initialization code to be used is
 * provided as a constructor argument, with the expectation that it implements
 * the AdminUpgradeabilityProxy interface above. The initialization code used
 * for Pr000xy is a slightly modified version (with a stripped down constructor
 * but the same code once fully-instantiated) of the AdminUpgradeabilityProxy
 * contract by Zeppelin, used in zOS v2.0, which can be found here:
 *
 * https://github.com/zeppelinos/zos/blob/master/packages/lib/contracts/
 *   upgradeability/AdminUpgradeabilityProxy.sol
 *
 * Creating proxies through Pr000xy requires support for CREATE2, which will not
 * be available until (at least) block 7,080,000. This contract has not yet been
 * fully tested or audited - proceed with caution and please share any exploits
 * or optimizations you discover.
 */
contract Pr000xy is ERC20, ERC20Detailed, Pr000xyInterface {
  /**
   * @dev Filter conditions in the search space when making and matching offers.
   */
  enum Condition {                        // nibble (1 hex character, 1/2 byte)
    NoMatch,                              // 0
    MatchCaseInsensitive,                 // 1
    MatchUpperCase,                       // 2
    MatchLowerCase,                       // 3
    MatchRangeLessThanCaseInsensitive,    // 4
    MatchRangeGreaterThanCaseInsensitive, // 5
    MatchRangeLessThanUpperCase,          // 6
    MatchRangeGreaterThanUpperCase,       // 7
    MatchRangeLessThanLowerCase,          // 8
    MatchRangeGreaterThanLowerCase,       // 9
    MatchAgainstPriorCaseInsensitive,     // 10 (a)
    MatchAgainstInitialCaseInsensitive,   // 11 (b)
    MatchAgainstPriorCaseSensitive,       // 12 (c)
    MatchAgainstInitialCaseSensitive,     // 13 (d)
    NoMatchNoUpperCase,                   // 14 (e)
    NoMatchNoLowerCase                    // 15 (f)
  }

  /**
   * @dev Parameters of an open offer for a proxy matching a set of constraints.
   */
  struct Offer {
    uint256 id; // the offer ID
    uint256 amount; // value offered for a match
    uint256 expiration; // timestamp for when offer is no longer valid
    bytes20 searchSpace; // each nibble designates a particular filter condition
    address target; // match each nibble of the proxy given the search space
    address payable offerer; // address staking funds & burning tokens if needed
    address recipient; // address where proxy ownership will be transferred
  }

  /**
   * @dev Parameters for locating a value at the appropriate index.
   */
  struct Location {
    bool exists;   // whether the value exists or not
    uint256 index; // index of the value in the relevant array
  }

  /**
   * @dev Boolean that indicates whether contract initialization is complete.
   */
  bool public initialized;

  /**
   * @dev Address that points to starting implementation for created proxies.
   */
  address private _targetImplementation;

  /**
   * @dev The block of initialization code to use when creating proxies.
   */
  bytes private _initCode;

  /**
   * @dev The hash of the initialization code used to create proxies.
   */
  bytes32 private _initCodeHash;

  /**
   * @dev Mapping with arrays of tracked proxies for leading & total zero bytes.
   */
  mapping(uint256 => mapping(uint256 => address[])) private _proxies;

  /**
   * @dev Array with outstanding offer details.
   */
  Offer[] private _offers;

  /**
   * @dev Mapping for locating the appropriate index of a given proxy.
   */
  mapping(address => Location) private _proxyLocations;

  /**
   * @dev Mapping for locating the appropriate index of a given offer.
   */
  mapping(uint256 => Location) private _offerLocations;

  /**
   * @dev Mapping with appropriate rewards for each address zero byte "combo".
   * The key is calculated as (starting zero bytes) * 20 + (total zero bytes).
   * The calculated amounts can be verified by running the following script:
   *
   * https://gist.github.com/0age/d55d8315c2119adfba3cc90b3f5c15df
   *
   */
  mapping(uint24 => uint256) private _rewards;

  /**
   * @dev Address that points to the registry containing token reward amounts.
   */
  Pr000xyRewardsInterface private _rewardsInitializer;

  /**
   * @dev Counter for tracking incremental assignment of token reward amounts.
   */
  uint24 private _initializationCounter;

  /**
   * @dev In the constructor, deploy and set the initial target implementation
   * for created proxies, then set the initialization code for said proxies as
   * well as a supplied address linking to a registry of token reward values.
   * @param rewardsRegistry address The address of the token rewards registry.
   * @param proxyInitCode bytes The initialization code used to deploy each
   * proxy. Validation could optionally be performed on a mock proxy in the
   * constructor to ensure that the interface works as expected. The contract
   * expects that the submitted initialization code will take a 32-byte-padded
   * address as the last parameter, and also that said parameter will be left
   * off of the initialization code, as this constructor will populate it using
   * the address of a freshly deployed target implementation.
   */
  constructor(
    address rewardsRegistry,
    bytes memory proxyInitCode
  ) public ERC20Detailed("Pr000xy", "000", 0) {
    // deploy logic contract to serve as initial implementation for each proxy.
    _targetImplementation = address(new InitialProxyImplementation());

    // construct and store initialization code that will be used for each proxy.
    _initCode = abi.encodePacked(
      proxyInitCode, // the initialization code for the proxy without arguments
      hex"000000000000000000000000", // padding in front of the address argument
      _targetImplementation // the implementation address (constructor argument)
    );

    // hash and store the contract initialization code.
    _initCodeHash = keccak256(abi.encodePacked(_initCode));

    // set up reward values in the initialization function using the registry.
    _rewardsInitializer = Pr000xyRewardsInterface(rewardsRegistry);

    // start the counter at the first rewards registry key with non-zero value.
    _initializationCounter = 5;
  }

  /**
   * @dev In initializer, call into rewards registry to populate return values.
   */
  function initialize() external {
    require(!initialized, "Contract has already been initialized.");

    // pick up where initializer left off by designating an in-memory counter.
    uint24 i = _initializationCounter;

    // iterate through each key, up to largest key (420) until gas is exhausted.
    while (i < 421 && gasleft() > 30000) {
      // get the relevant reward amount for the given key from the registry.
      _rewards[i] = _rewardsInitializer.getPr000xyReward(i);
      // increment the in-memory counter.
      i++;
    }

    // write in-memory counter to storage to pick up assignment from this stage.
    _initializationCounter = i;

    // mark initialization as complete once counter exceeds the largest key.
    if (_initializationCounter == 421) {
      initialized = true;
    }
  }

  /**
   * @dev Create an upgradeable proxy, add to collection, and pay reward if
   * applicable. Pr000xy will be set as the initial as admin, and the target
   * implementation will be set as the initial implementation (logic contract).
   * @param salt bytes32 The nonce that will be passed into create2. The first
   * 20 bytes of the salt must match those of the calling address.
   * @return Address of the new proxy.
   */
  function createProxy(bytes32 salt) external containsCaller(salt) returns (
    address proxy
  ) {
    // deploy the proxy using the provided salt.
    proxy = _deployProxy(salt, _initCode);

    // ensure that the proxy was successfully deployed.
    _requireSuccessfulDeployment(proxy);

    // set up the proxy: place it into storage, pay any reward, and emit events.
    _processDeployment(proxy);
  }

  /**
   * @dev Claims an upgradeability proxy, removes from collection, burns value.
   * Specify an admin and a new implementation (logic contract) to point to.
   * @param proxy address The address of the proxy.
   * @param owner address The new owner of the claimed proxy. Note that this
   * field is independent of the claimant - the claimant (msg.sender) must burn
   * the required tokens, but the owner will actually control the proxy.
   * Providing the null address (0x0) will fallback to setting msg.sender as the
   * owner of the proxy.
   * @param implementation address the logic contract to be set on the claimed
   * proxy. Providing the null address (0x0) causes setting a new implementation
   * to be skipped.
   * @param data bytes Optional parameter for calling an initializer on the new
   * implementation immediately after it has been set. Not providing any bytes
   * will bypass this step.
   * @return The address of the new proxy.
   */
  function claimProxy(
    address proxy,
    address owner,
    address implementation,
    bytes calldata data
  ) external proxyExists(proxy) {
    // calculate total number of leading and trailing zero bytes, respectively.
    (uint256 leadingZeroBytes, uint256 totalZeroBytes) = _getZeroBytes(proxy);

    // find the index of the proxy by address.
    uint256 proxyIndex = _proxyLocations[proxy].index;

    // pop the requested proxy out of the appropriate array.
    _popProxyFrom(leadingZeroBytes, totalZeroBytes, proxyIndex);

    // set up the proxy with the provided implementation and owner.
    _transferProxy(proxy, implementation, owner, data);

    // burn tokens from the claiming address if applicable and emit an event.
    _finalizeClaim(
      msg.sender,
      proxy,
      _getValue(leadingZeroBytes, totalZeroBytes)
    );
  }

  /**
   * @dev Claims the last proxy created in a given category, removes from
   * collection, and burns value. Specify an admin and a new implementation
   * (logic contract) to point to (set to null address to leave set to current).
   * NOTE: this method does not support calling an initialization function.
   * @param leadingZeroBytes uint256 The number of leading zero bytes in the
   * claimed proxy.
   * @param totalZeroBytes uint256 The total number of zero bytes in the
   * claimed proxy.
   * @param owner address The new owner of the claimed proxy. Note that this
   * field is independent of the claimant - the claimant (msg.sender) must burn
   * the required tokens, but the owner will actually control the proxy.
   * Providing the null address (0x0) will fallback to setting msg.sender as the
   * owner of the proxy.
   * @param implementation address the logic contract to be set on the claimed
   * proxy. Providing the null address (0x0) causes setting a new implementation
   * to be skipped.
   * @param data bytes Optional parameter for calling an initializer on the new
   * implementation immediately after it has been set. Not providing any bytes
   * will bypass this step.
   * @return The address of the new proxy.
   */
  function claimLatestProxy(
    uint256 leadingZeroBytes,
    uint256 totalZeroBytes,
    address owner,
    address implementation,
    bytes calldata data
  ) external returns (address proxy) {
    // get the length of the relevant array.
    uint256 proxyCount = _proxies[leadingZeroBytes][totalZeroBytes].length;

    // ensure that there is at least one proxy in the relevant array.
    require(
      proxyCount > 0,
      "No proxies found that correspond to the given zero byte arguments."
    );

    // pop the most recent proxy out of the last item in the appropriate array.
    proxy = _popProxy(leadingZeroBytes, totalZeroBytes);

    // set up the proxy with the provided implementation and owner.
    _transferProxy(proxy, implementation, owner, data);

    // burn tokens from the claiming address if applicable and emit an event.
    _finalizeClaim(
      msg.sender,
      proxy,
      _getValue(leadingZeroBytes, totalZeroBytes)
    );
  }

  /**
   * @dev Make an offer for a proxy that matches a given set of constraints. A
   * value (in ether) may be attached to the offer and will be paid to anyone
   * who submits a transaction identifying a match between an offer and a proxy.
   * Note that the required number of Pr000xy tokens, if any, will still need to
   * be burned from the address making the offer in order for the proxy to be
   * claimed. However, for proxy addresses that are not gas-efficient, the token
   * will not be required at all in order to match an offer.
   * @param searchSpace bytes20 A sequence of bytes that determines which areas
   * of the target address should be matched against. The 0x00 byte means that
   * the target byte can be skipped, otherwise each nibble represents a
   * different filter condition as indicated by the Condition enum.
   * @param target address The targeted address, with each relevant byte and
   * nibble determined by the corresponding byte in searchSpace.
   * @param target address The address to be assigned as the administrator of
   * the proxy once it has been created and matched with the offer. Providing
   * the null address (0x0) will fallback to setting recipient to msg.sender.
   */
  function makeOffer(
    bytes20 searchSpace, // each nibble designates a particular filter condition
    address target,      // match each nibble of the proxy given search space
    address recipient    // the administrator to be assigned to the proxy
  ) external payable returns (uint256 offerID) {
    // ensure that offer is valid (i.e. search space and target don't conflict).
    _requireOfferValid(searchSpace, target);

    // use the caller's address as a fallback if a recipient is not specified.
    address recipientFallback = (
      recipient == address(0) ? msg.sender : recipient
    );

    // generate the offerID based on arguments, state, blockhash & array length.
    offerID = uint256(
      keccak256(
        abi.encodePacked(
          msg.sender,
          msg.value,
          searchSpace,
          target,
          recipientFallback,
          blockhash(block.number - 1),
          _offers.length
        )
      )
    );

    // ensure that duplicate offer IDs are not created "on accident".
    while (_offerLocations[offerID].exists) {
      offerID = uint256(keccak256(abi.encodePacked(offerID)));
    }

    // populate an Offer struct with the details of the offer.
    Offer memory offer = Offer({
      id: offerID,
      amount: msg.value,
      expiration: 0,
      searchSpace: searchSpace,
      target: target,
      offerer: msg.sender,
      recipient: recipientFallback
    });

    // set the offer in the offer location mapping.
    _offerLocations[offerID] = Location({
      exists: true,
      index: _offers.length
    });

    // add the offer to the relevant array.
    _offers.push(offer);

    // emit an event to track that the offer was created.
    emit OfferCreated(offerID, msg.sender, msg.value);
  }

  /**
   * @dev Match an offer to a proxy and claim the amount offered for finding it.
   * Note that this function is susceptible to front-running in current form.
   * @param proxy address The address of the proxy.
   * @param offerID uint256 The ID of the offer to match and fulfill.
   */
  function matchOffer(
    address proxy,
    uint256 offerID
  ) external proxyExists(proxy) offerExists(offerID) {
    // remove the offer from storage by index location and place it into memory.
    Offer memory offer = _popOfferFrom(_offerLocations[offerID].index);

    // ensure that the offer has not expired.
    _requireOfferNotExpired(offer.expiration);

    // check that the match is good.
    _requireValidMatch(proxy, offer.searchSpace, offer.target);

    // calculate total number of leading and trailing zero bytes, respectively.
    (uint256 leadingZeroBytes, uint256 totalZeroBytes) = _getZeroBytes(proxy);

    // burn tokens from the claiming address if applicable and emit an event.
    _finalizeClaim(
      offer.offerer,
      proxy,
      _getValue(leadingZeroBytes, totalZeroBytes)
    );

    // pop the requested proxy out of the collection by index location.
    _popProxyFrom(
      leadingZeroBytes,
      totalZeroBytes,
      _proxyLocations[proxy].index
    );

    // transfer ownership, mark as fulfilled, make payment, and emit an event.
    _processOfferFulfillment(proxy, offer);
  }

  /**
   * @dev Create an upgradeable proxy and immediately match it with an offer.
   * @param salt bytes32 The nonce that will be passed into create2. The first
   * 20 bytes of the salt must match those of the calling address.
   * @param offerID uint256 The ID of the offer to match.
   * @return The address of the new proxy.
   */
  function createAndMatch(
    bytes32 salt,
    uint256 offerID
  ) external offerExists(offerID) containsCaller(salt) {
    // remove the offer from storage array by index and place it into memory.
    Offer memory offer = _popOfferFrom(_offerLocations[offerID].index);

    // ensure that the offer has not expired.
    _requireOfferNotExpired(offer.expiration);

    // create the proxy.
    address proxy = _deployProxy(salt, _initCode);

    // ensure that the proxy was successfully deployed.
    _requireSuccessfulDeployment(proxy);

    // check that the match is good.
    _requireValidMatch(proxy, offer.searchSpace, offer.target);

    // get reward value for minting to creator and burning from match recipient.
    uint256 proxyTokenValue = _getReward(proxy);

    // mint tokens to the creator if applicable and emit an event.
    _finalizeDeployment(proxy, proxyTokenValue);

    // burn tokens from the claiming address if applicable and emit an event.
    _finalizeClaim(offer.offerer, proxy, proxyTokenValue);

    // transfer ownership, mark as fulfilled, make payment, and emit an event.
    _processOfferFulfillment(proxy, offer);
  }

  /**
   * @dev Create an upgradeable proxy and immediately claim it. No tokens will
   * be minted or burned in the process. Leave the implementation address set to
   * the null address to skip changing the implementation.
   * @param salt bytes32 The nonce that will be passed into create2. The first
   * 20 bytes of the salt must match those of the calling address.
   * @param owner address The owner to assign to the claimed proxy. Providing
   * the null address (0x0) will fallback to setting msg.sender as the owner of
   * the proxy.
   * @param implementation address the logic contract to be set on the claimed
   * proxy. Providing the null address (0x0) causes setting a new implementation
   * to be skipped.
   * @param data bytes Optional parameter for calling an initializer on the new
   * implementation immediately after it is set. Not providing any bytes will
   * bypass this step.
   * @return The address of the new proxy.
   */
  function createAndClaim(
    bytes32 salt,
    address owner,
    address implementation,
    bytes calldata data
  ) external containsCaller(salt) returns (address proxy) {
    // deploy the proxy using the provided salt.
    proxy = _deployProxy(salt, _initCode);

    // immediately assign the proxy to the provided implementation and owner.
    _transferProxy(proxy, implementation, owner, data);

    // emit an event to track that proxy was created and simultaneously claimed.
    emit ProxyCreatedAndClaimed(msg.sender, proxy);
  }

  /**
   * @dev Create a group of upgradeable proxies, add to collection, and pay the
   * aggregate reward. This contract will be initially set as the admin, and 
   * the test implementation will be set as the initial target implementation.
   * If a particular proxy creation fails, it will be skipped without causing
   * the entire batch to revert. Also note that no tokens are minted until the
   * end of the batch.
   * @param salts bytes32[] The nonces that will be passed into create2. The
   * first 20 bytes of each salt must match those of the calling address.
   * @return Addresses of the new proxies.
   */
  function batchCreate(
    bytes32[] calldata salts
  ) external returns (address[] memory proxies) {
    // initialize a fixed-size array, as arrays in memory cannot be resized.
    address[] memory processedProxies = new address[](salts.length);

    // track the total number of tokens to mint at the end of the batch.
    uint256 totalTokenValue;

    // track the current proxy's deployment address.
    address proxy;

    // variable for checking if the current proxy is already deployed.
    bool proxyAlreadyCreated;
    
    // iterate through each provided salt argument.
    for (uint256 i; i < salts.length; i++) {
      // do not deploy if the caller is not properly encoded in salt argument.
      if (address(bytes20(salts[i])) != msg.sender) continue;

      // determine contract address where the proxy contract will be created.
      (, proxyAlreadyCreated) = _proxyCreationDryRun(salts[i]);

      // do not deploy the proxy if it has already been created.
      if (proxyAlreadyCreated) continue;

      // deploy the proxy using the provided salt.
      proxy = _deployProxy(salts[i], _initCode);

      // increase number of tokens to mint by output of proxy deploy process.
      totalTokenValue = totalTokenValue + _processBatchDeployment(proxy);

      // add the proxy address to the returned array.
      processedProxies[i] = proxy;

    }

    // mint the total number of created tokens all at once if applicable.
    if (totalTokenValue > 0) {
      // mint the appropriate number of tokens to the submitter's balance.
      _mint(msg.sender, totalTokenValue);
    }

    // return the populated fixed-size array.
    return processedProxies;
  }

  /**
   * @dev Efficient version of batchCreate that uses less gas. The first twenty
   * bytes of each salt are automatically populated using the calling address,
   * and remaining salt segments are passed in as a packed byte array, using
   * twelve bytes per segment, and a function selector of 0x00000000. No values
   * will be returned; derived proxies must be calculated seperately or observed
   * in event logs. Also note that an attempt to include a salt that tries to
   * create a proxy that already exists will cause the entire batch to revert.
   */
  function batchCreateEfficient_H6KNX6() external { // solhint-disable-line
    // track the total number of tokens to mint at the end of the batch.
    uint256 totalTokenValue;

    // track the current proxy's deployment address.
    address proxy;

    // bring init code into memory.
    bytes memory initCodeWithParams = _initCode;

    // determine length and offset of data.
    bytes32 encodedData;
    bytes32 encodedSize;

    // determine the number of salt segments passed in as part of calldata.
    uint256 passedSaltSegments;

    // calculate init code length and offset and number of salts using assembly.
    assembly { // solhint-disable-line
      encodedData := add(0x20, initCodeWithParams)            // offset
      encodedSize := mload(initCodeWithParams)                // length
      passedSaltSegments := div(sub(calldatasize, 0x04), 0x0c) // (- sig & / 12)
    }

    // iterate through each provided salt segment argument.
    for (uint256 i; i < passedSaltSegments; i++) {
      // using inline assembly: call CREATE2 using msg.sender ++ salt segment.
      assembly { // solhint-disable-line
        proxy := create2(               // call create2 and store output result.
          0,                            // do not forward any value to create2.
          encodedData,                  // set offset of init data in memory.
          encodedSize,                  // set length of init data in memory.
          add(                          // combine msg.sender and provided salt.
            shl(0x60, caller),          // place msg.sender at start of word.
            shr(0xa0, calldataload(add(0x04, mul(i, 0x0c)))) // segment at end.
          )
        )
      }

      // increase number of tokens to mint by output of proxy deploy process.
      totalTokenValue = totalTokenValue + _processBatchDeployment(proxy);
    }

    // mint the total number of created tokens all at once if applicable.
    if (totalTokenValue > 0) {
      // mint the appropriate number of tokens to the submitter's balance.
      _mint(msg.sender, totalTokenValue);
    }
  }

  /**
   * @dev Create a group of upgradeable proxies and immediately attempt to match
   * each with an offer. If an invalid offer ID other than 0 is provided, the
   * proxy deployment and match will both be skipped. If a valid offer ID is
   * supplied but the proxy has already been deployed, the match will be made
   * but proxy creation will be skipped. If the submitter fails to receive an
   * attempted payment to the calling address, the entire batch transaction will
   * revert. Also note that no tokens are minted until the end of the batch.
   * @param salts bytes32[] An array of nonces that will be passed into create2.
   * The first 20 bytes of each salt must match those of the calling address.
   * @param offerIDs uint256[] The IDs of the offers to match. May be shorter
   * than the salts argument, causing execution to proceed in a similar fashion
   * to batchCreate but without any return values.
   */
  function batchCreateAndMatch(
    bytes32[] calldata salts,
    uint256[] calldata offerIDs
  ) external {
    // declare variables.
    Offer memory offer; // // Offer object with relevant details of the offer.
    uint256 totalTokenValue; // total tokens to mint at the end of the batch.
    address proxy; // the current proxy's deployment address.
    bool hasOffer; // whether an offer has been provided for the current proxy.

    // iterate through each provided salt and offer argument.
    for (uint256 i; i < salts.length; i++) {
      // do not deploy if the caller is not properly encoded in salt argument.
      if (address(bytes20(salts[i])) != msg.sender) continue;

      // determine if an offer has been provided for the given proxy.
      hasOffer = offerIDs.length > i && offerIDs[i] != 0;

      // validate offer and check for existing proxy if an offerID was provided.
      if (hasOffer) {
        // get offer from storage array by index and place it into memory.
        offer = _offers[_offerLocations[offerIDs[i]].index];

        // validate offer, fulfill if possible, and skip deploy if applicable.
        if (_validateAndFulfillExistingMatch(offer, salts[i])) continue;

        // deploy the proxy using provided salt.
        proxy = _deployProxy(salts[i], _initCode);

        // match the proxy, emit events, and add reward to total to be minted.
        totalTokenValue = totalTokenValue + _processBatchDeploymentWithMatch(
          proxy,
          offer
        );
      } else {
        // when no offer has been provided, simply deploy the proxy.
        proxy = _deployProxy(salts[i], _initCode);

        // register the proxy as usual and add reward to total.
        totalTokenValue = totalTokenValue + _processBatchDeployment(proxy);
      }
    }

    // mint the total number of created tokens all at once if applicable.
    if (totalTokenValue > 0) {
      // mint the appropriate number of tokens to the submitter's balance.
      _mint(msg.sender, totalTokenValue);
    }
  }

  /**
   * @dev Set a given offer to expire in 24 hours.
   * @param offerID uint256 The ID of the offer to schedule expiration on.
   */
  function scheduleOfferExpiration(
    uint256 offerID
  ) external offerExists(offerID) returns (uint256 expiration) {
    // find the index of the offer by offer ID.
    uint256 offerIndex = _offerLocations[offerID].index;

    // require that the originator of the offer is the caller.
    _requireOnlyOfferOriginator(offerIndex);

    // ensure that the offer is not already set to expire.
    require(
      _offers[offerIndex].expiration == 0,
      "Offer has already been set to expire."
    );

    // determine the expiration time based on the current time.
    expiration = now + 24 hours; // solhint-disable-line

    // set the offer to expire in 24 hours.
    _offers[offerIndex].expiration = expiration;

    // emit an event to track that offer was set to expire.
    emit OfferSetToExpire(offerID, msg.sender, expiration);
  }

  /**
   * @dev Cancel an expired offer and refund the amount offered.
   * @param offerID uint256 The ID of the offer to cancel.
   */
  function cancelOffer(
    uint256 offerID
  ) external offerExists(offerID) {
    // find the index of the offer by offer ID.
    uint256 offerIndex = _offerLocations[offerID].index;

    // require that the originator of the offer is the caller.
    _requireOnlyOfferOriginator(offerIndex);

    // ensure that the offer has been set to expire.
    require(
      _offers[offerIndex].expiration != 0,
      "Offer has not been set to expire."
    );

    // ensure that the expiration period has concluded.
    require(
      _offers[offerIndex].expiration < now, // solhint-disable-line
      "Offer has not yet expired."
    );

    // remove the offer from storage and place it into memory.
    Offer memory offer = _popOfferFrom(offerIndex);

    // transfer the reward back to the originator of the offer.
    offer.offerer.transfer(offer.amount);
  }

  /**
   * @dev Compute the address of the upgradeable proxy that will be created when
   * submitting a given salt or nonce to the contract. The CREATE2 address is
   * computed in accordance with EIP-1014, and adheres to the formula therein of
   * `keccak256( 0xff ++ address ++ salt ++ keccak256(init_code)))[12:]` when
   * performing the computation. The computed address is then checked for any
   * existing contract code - if any is found, the null address will be returned
   * instead.
   * @param salt bytes32 The nonce that will be passed into the CREATE2 address
   * calculation.
   * @return Address of the proxy that will be created, or the null address if
   * a contract already exists at that address.
   */
  function findProxyCreationAddress(
    bytes32 salt
  ) external view returns (address proxy) {
    // variable for checking if the current proxy is already deployed.
    bool proxyAlreadyCreated;

    // perform a dry-run of the proxy contract deployment.
    (proxy, proxyAlreadyCreated) = _proxyCreationDryRun(salt);

    // if proxy already exists, return the null address to signify failure.
    if (proxyAlreadyCreated) {
      proxy = address(0);
    }
  }

  /**
   * @dev Check a given proxy address against an offer and determine if there is
   * a match. The proxy need not already exist in order to check for a match,
   * but will of course need to be created before an actual match can be made.
   * @param proxy address The address of the proxy to check for a match.
   * @param offerID uint256 The ID of the offer to check for a match.
   * @return Boolean signifying if the proxy fulfills the offer's requirements.
   */
  function matchesOffer(
    address proxy,
    uint256 offerID
  ) external view returns (bool hasMatch) {
    require(
      _offerLocations[offerID].exists,
      "No offer found that corresponds to the given offer ID."
    );

    // get the offer based on the index of the offer ID.
    Offer memory offer = _offers[_offerLocations[offerID].index];

    /* solhint-disable not-rely-on-time */
    // determine match status via expiration, constraints, and offerer balance.
    return (
      (offer.expiration == 0 || offer.expiration > now) &&
      balanceOf(offer.offerer) >= _getReward(proxy) &&
      _matchesOfferConstraints(proxy, offer.searchSpace, offer.target)
    );
    /* solhint-enable not-rely-on-time */
  }

  /**
   * @dev Get the number of "zero" bytes (0x00) in an address (20 bytes long).
   * Each zero byte reduces the cost of including address in calldata by 64 gas.
   * Each leading zero byte enables the address to be packed that much tighter.
   * @param account address The address in question.
   * @return The leading number and total number of zero bytes in the address.
   */
  function getZeroBytes(address account) external pure returns (
    uint256 leadingZeroBytes,
    uint256 totalZeroBytes
  ) {
    return _getZeroBytes(account);
  }

  /**
   * @dev Get the token value of an address with a given number of zero bytes.
   * An address is valued at 1 token when there are three leading zero bytes.
   * @param leadingZeroBytes uint256 The number of leading zero bytes in the
   * address.
   * @param totalZeroBytes uint256 The total number of zero bytes in the
   * address.
   * @return The reward size given the number of leading and zero bytes.
   */
  function getValue(
    uint256 leadingZeroBytes,
    uint256 totalZeroBytes
  ) external view returns (uint256 value) {
    return _getValue(leadingZeroBytes, totalZeroBytes);
  }

  /**
   * @dev Get the tokens that must be paid in order to claim a given proxy.
   * Note that this function is equivalent to calling getValue on the output of
   * getZeroBytes.
   * @param proxy address The address of the proxy.
   * @return The reward size of the given proxy.
   */
  function getReward(address proxy) external view returns (uint256 value) {
    return _getReward(proxy);
  }

  /**
   * @dev Count total claimable proxy address w/ given # of leading and total
   * zero bytes.
   * @param leadingZeroBytes uint256 The desired number of leading zero bytes.
   * @param totalZeroBytes uint256 The desired number of total zero bytes.
   * @return The total number of claimable proxies.
   */
  function countProxiesAt(
    uint256 leadingZeroBytes,
    uint256 totalZeroBytes
  ) external view returns (uint256 totalPertinentProxies) {
    return _proxies[leadingZeroBytes][totalZeroBytes].length;
  }

  /**
   * @dev Get a claimable proxy address w/ given # of leading and total zero
   * bytes at a given index.
   * @param leadingZeroBytes uint256 The desired number of leading zero bytes.
   * @param totalZeroBytes uint256 The desired number of total zero bytes.
   * @param index uint256 The desired index of the proxy in the relevant array.
   * @return The address of the claimable proxy (if it exists).
   */
  function getProxyAt(
    uint256 leadingZeroBytes,
    uint256 totalZeroBytes,
    uint256 index
  ) external view returns (address proxy) {
    return _proxies[leadingZeroBytes][totalZeroBytes][index];
  }

  /**
   * @dev Count total outstanding offers.
   * @return The total number of outstanding offers.
   */
  function countOffers() external view returns (uint256 totalOffers) {
    return _offers.length;
  }

  /**
   * @dev Get an outstanding offer ID at a given index.
   * @param index uint256 The desired index of the offer in the relevant array.
   * @return The offerID of the outstanding offer.
   */
  function getOfferID(uint256 index) external view returns (uint256 offerID) {
    offerID = _offers[index].id;

    require(
      _offerLocations[offerID].exists,
      "No offer found that corresponds to the given offer ID."
    );
  }

  /**
   * @dev Get an outstanding offer with a given offerID.
   * @param offerID uint256 The desired ID of the offer.
   * @return The details of the outstanding offer.
   */
  function getOffer(uint256 offerID) external view returns (
    uint256 amount,
    uint256 expiration,
    bytes20 searchSpace,
    address target,
    address offerer,
    address recipient
  ) {
    require(
      _offerLocations[offerID].exists,
      "No offer found that corresponds to the given offer ID."
    );

    // get the offer based on the index of the offer ID.
    Offer memory offer = _offers[_offerLocations[offerID].index];

    return (
      offer.amount,
      offer.expiration,
      offer.searchSpace,
      offer.target,
      offer.offerer,
      offer.recipient
    );
  }

  /**
   * @dev Get the address of the logic contract that is implemented on newly
   * created proxies.
   * @return The address of the proxy implementation.
   */
  function getInitialProxyImplementation() external view returns (
    address implementation
  ) {
    return _targetImplementation;
  }

  /**
   * @dev Get the initialization code that is used to create each upgradeable
   * proxy.
   * @return The proxy initialization code.
   */
  function getProxyInitializationCode() external view returns (
    bytes memory initializationCode
  ) {
    return _initCode;
  }

  /**
   * @dev Get the keccak256 hash of the initialization code used to create
   * upgradeable proxies.
   * @return The hash of the proxy initialization code.
   */
  function getProxyInitializationCodeHash() external view returns (
    bytes32 initializationCodeHash
  ) {
    return _initCodeHash;
  }

  /**
   * @dev Check if a proxy at a given address is administered by this contract.
   * @param proxy address The address of the proxy.
   * @return Boolean that signifies if the proxy is currently administered by
   * this contract.
   */
  function isAdmin(address proxy) external view returns (bool admin) {
    return _isAdmin(proxy);
  }

  /**
   * @dev Internal function to check if a proxy at a given address is
   * administered by this contract.
   * @param proxy address The address of the proxy.
   * @return Boolean that signifies if the proxy is currently administered by
   * this contract.
   */
  function _isAdmin(address proxy) internal view returns (bool admin) {
    /* solhint-disable avoid-low-level-calls */
    (bool success, bytes memory result) = proxy.staticcall(
      abi.encodeWithSignature("admin()")
    );
    /* solhint-enable avoid-low-level-calls */

    if (success) {
      address addr;
      assembly { // solhint-disable-line
        addr := mload(add(result, 0x20))
      }

      return addr == address(this);
    }
  }

  /**
   * @dev Internal function to create an upgradeable proxy, with this contract
   * as avoidthe admin and the target implementation as the initial implementation.
   * @param salt bytes32 The nonce that will be passed into create2.
   * @param initCodeWithParams bytes The initialization code and constructor
   * arguments that will be passed into create2 and used to deploy the proxy.
   * @return The address of the new proxy.
   */
  function _deployProxy(
    bytes32 salt,
    bytes memory initCodeWithParams
  ) internal returns (address proxy) {
    // using inline assembly: load data and length of data, then call CREATE2.
    assembly { // solhint-disable-line
      let encodedData := add(0x20, initCodeWithParams)
      let encodedSize := mload(initCodeWithParams)
      proxy := create2(
        callvalue,
        encodedData,
        encodedSize,
        salt
      )
    }
  }

  /**
   * @dev Internal function to process a newly-deployed proxy. Stores references
   * to the the proxy, assigns a reward, and emits an event.
   * @param proxy address The proxy in question.
   */
  function _processDeployment(address proxy) internal {
    // calculate total number of leading and trailing zero bytes, respectively.
    (uint256 leadingZeroBytes, uint256 totalZeroBytes) = _getZeroBytes(proxy);

    // set the proxy in the proxy location mapping.
    _proxyLocations[proxy] = Location({
      exists: true,
      index: _proxies[leadingZeroBytes][totalZeroBytes].length
    });

    // add the proxy to the relevant array in storage.
    _proxies[leadingZeroBytes][totalZeroBytes].push(proxy);

    // mint tokens to the creator if applicable and emit an event.
    _finalizeDeployment(proxy, _getValue(leadingZeroBytes, totalZeroBytes));
  }

  /**
   * @dev Internal function to process a newly-deployed proxy as part of a
   * batch. Stores references to the the proxy, emits an event, and returns the
   * number of additional tokens that will need to be minted at the end of the
   * batch job without actually minting them yet.
   * @param proxy address The proxy in question.
   * @return The number of additional tokens that will be minted.
   */
  function _processBatchDeployment(
    address proxy
  ) internal returns (uint256 proxyTokenValue) {
    // calculate total number of leading and trailing zero bytes, respectively.
    (uint256 leadingZeroBytes, uint256 totalZeroBytes) = _getZeroBytes(proxy);

    // set the proxy in the proxy location mapping.
    _proxyLocations[proxy] = Location({
      exists: true,
      index: _proxies[leadingZeroBytes][totalZeroBytes].length
    });

    // add the proxy to the relevant array in storage.
    _proxies[leadingZeroBytes][totalZeroBytes].push(proxy);

    // determine the tokens that will need to be minted on behalf of this proxy.
    proxyTokenValue = _getValue(leadingZeroBytes, totalZeroBytes);

    // emit an event to track that proxy was created.
    emit ProxyCreated(msg.sender, proxyTokenValue, proxy);
  }

  /**
   * @dev Internal function to process a newly-deployed proxy as part of a
   * batch while simultaneously performing a match. Does not store the reference
   * to the the proxy since it is immediately claimed as part of the match, but
   * emits the appropriate events and returns the number of additional tokens
   * that will need to be minted at the end of the batch job without actually
   * minting them yet.
   * @param proxy address The proxy in question.
   * @param offer Offer The offer in question.
   * @return The number of additional tokens that will be minted.
   */
  function _processBatchDeploymentWithMatch(
    address proxy,
    Offer memory offer
  ) internal returns (uint256 proxyTokenValue) {
    // determine how many tokens, if any, proxy in question is worth.
    proxyTokenValue = _getReward(proxy);

    // emit an event to track that proxy was created.
    emit ProxyCreated(msg.sender, proxyTokenValue, proxy);

    // remove the offer from storage array by index.
    _popOfferFrom(_offerLocations[offer.id].index);

    // burn tokens from claiming address if applicable and emit an event.
    _finalizeClaim(offer.offerer, proxy, proxyTokenValue);

    // transfer ownership, mark as fulfilled, make payment, and emit an event.
    _processOfferFulfillment(proxy, offer);
  }

  /**
   * @dev Internal function to finalize a created proxy. Mints the required
   * amount of tokens and emits an event.
   * @param proxy address The proxy in question.
   * @param proxyTokenValue uint256 how many tokens the given proxy is worth.
   */
  function _finalizeDeployment(
    address proxy,
    uint256 proxyTokenValue
  ) internal {
    if (proxyTokenValue > 0) {
      // mint the appropriate number of tokens to the submitter's balance.
      _mint(msg.sender, proxyTokenValue);
    }

    // emit an event to track that proxy was created.
    emit ProxyCreated(msg.sender, proxyTokenValue, proxy);
  }

  /**
   * @dev Internal function to finalize a claimed proxy. Burns the required
   * amount of tokens and emits an event.
   * @param claimant address The address claiming the proxy. Note that this may
   * or may not be the same address as the proxy administrator.
   * @param proxy address The proxy in question.
   * @param proxyTokenValue uint256 how many tokens the given proxy is worth.
   */
  function _finalizeClaim(
    address claimant,
    address proxy,
    uint256 proxyTokenValue
  ) internal {
    if (proxyTokenValue > 0) {
      // burn the required number of tokens from the recipient's balance.
      _burn(claimant, proxyTokenValue);
    }

    // emit an event to track that proxy was claimed.
    emit ProxyClaimed(claimant, proxyTokenValue, proxy);
  }

  /**
   * @dev Internal function to process a fulfilled offer. Clears the offer from
   * storage, makes the payment to the submitter, and emits an event. Note that
   * a new implementation is not set or initialized when an offer is matched, as
   * it would introduce a potential source of failure when performing the match.
   * @param proxy address The proxy in question.
   * @param offer Offer The offer in question.

   */
  function _processOfferFulfillment(
    address proxy,
    Offer memory offer
  ) internal {
    // set up proxy with the provided owner - skip setting a new implementation.
    _transferProxy(proxy, address(0), offer.recipient, "");

    // transfer the reward to the match submitter if one is specified.
    if (offer.amount > 0) {
      msg.sender.transfer(offer.amount);
    }

    // emit an event to track that offer was fulfilled.
    emit OfferFulfilled(offer.id, offer.offerer, msg.sender, offer.amount);
  }

  /**
   * @dev Internal function to validate a given offer and match it if a proxy
   * already exists. Used as part of batchCreateAndMatch to ensure that offers
   * can be matched even if a given proxy is not deployed.
   * @param offer Offer The offer in question that will be validated.
   * @param salt bytes32 The salt to use in deriving the location of the proxy.
   * @return A boolean signifying if the deployment step should be skipped, due
   * to either a bad match or an existing proxy at the derived location.
   */
  function _validateAndFulfillExistingMatch(
    Offer memory offer,
    bytes32 salt
  ) internal returns (bool willSkipDeployment) {
    // declare variable for the computed target address.
    address proxyTarget;

    // declare variable for whether or not current proxy was already deployed.
    bool proxyAlreadyCreated;

    // check if the offer is invalid (no recipient or has expired).
    if (
      offer.recipient == address(0) ||
      (offer.expiration != 0 && offer.expiration <= now) // solhint-disable-line
    ) {
      // if so, skip the deployment step.
      return true;
    }

    // perform a dry-run of the proxy contract deployment.
    (proxyTarget, proxyAlreadyCreated) = _proxyCreationDryRun(salt);

    // determine how many tokens, if any, the given proxy address is worth.
    uint256 proxyTokenValue = _getReward(proxyTarget);

    // check if offer doesn't match or offerer balance is insufficient.
    if (
      !_matchesOfferConstraints(proxyTarget, offer.searchSpace, offer.target) ||
      balanceOf(offer.offerer) < proxyTokenValue
    ) {
      // if so, skip the deployment step.
      return true;
    }

    // if proxy already exists, go ahead and fulfill the match.
    if (proxyAlreadyCreated) {
      // remove the offer from storage array by index.
      _popOfferFrom(_offerLocations[offer.id].index);

      // burn tokens from claiming address if applicable and emit an event.
      _finalizeClaim(offer.offerer, proxyTarget, proxyTokenValue);

      // transfer ownership, register fulfillment make payment & emit an event.
      _processOfferFulfillment(proxyTarget, offer);

      // skip the deployment step.
      return true;
    }
  }

  /**
   * @dev Internal function to assign a new administrator to a proxy. The
   * implementation can be upgraded as well, or skipped by leaving the argument
   * to the implementation parameter set to the null address.
   * @param proxy address The proxy in question.
   * @param implementation address The new logic contract to point the proxy to.
   * If it is set to the null address, it will not be altered.
   * @param owner uint256 address The new administrator of the proxy. If it is
   * set to the null address, msg.sender will be used as the owner.
   * @param data bytes Optional parameter for calling an initializer on the new
   * implementation immediately after it is set.
   */
  function _transferProxy(
    address proxy,
    address implementation,
    address owner,
    bytes memory data
  ) internal {
    // set up the upgradeable proxy interface.
    AdminUpgradeabilityProxyInterface proxyInterface = (
      AdminUpgradeabilityProxyInterface(proxy)
    );

    // if an implementation is provided, set it before transferring admin role.
    if (implementation != address(0)) {
      if (data.length > 0) {
        // if data has been provided, pass it to the appropriate function.
        proxyInterface.upgradeToAndCall(implementation, data);
      } else {
        // otherwise, simply upgrade.
        proxyInterface.upgradeTo(implementation);
      }
    }

    if (owner != address(0)) {    
      // set up the proxy with the new administrator.
      proxyInterface.changeAdmin(owner);
    } else {
      // set up the proxy with the caller as the new administrator.
      proxyInterface.changeAdmin(msg.sender);      
    }
  }

  /**
   * @dev Internal function to pop off a proxy address with a given number of
   * leading and total zero bytes from the end of the relevant array.
   * @param leadingZeroBytes uint256 The desired number of leading zero bytes.
   * @param totalZeroBytes uint256 The desired number of total zero bytes.
   * @return The address of the popped proxy.
   */
  function _popProxy(
    uint256 leadingZeroBytes,
    uint256 totalZeroBytes
  ) internal returns (address proxy) {
    // get the total number of proxies with the specified number of zero bytes.
    uint256 count = _proxies[leadingZeroBytes][totalZeroBytes].length;

    // ensure that at least one proxy with specified zero bytes is available.
    require(
      count > 0,
      "No proxy found that corresponds to the given arguments."
    );

    // retrieve the proxy at the last index.
    proxy = _proxies[leadingZeroBytes][totalZeroBytes][count - 1];

    // shorten the _proxies array, which will also delete the last item.
    _proxies[leadingZeroBytes][totalZeroBytes].length--;

    // remove the proxy from the relevant locations mapping.
    delete _proxyLocations[proxy];
  }

  /**
   * @dev Internal function to pop off a proxy address with a given number of
   * leading and total zero bytes from any location in the relevant array.
   * @param leadingZeroBytes uint256 The desired number of leading zero bytes.
   * @param totalZeroBytes uint256 The desired number of total zero bytes.
   * @param index uint256 The desired index of the proxy in the relevant array.
   * @return The address of the popped proxy.
   */
  function _popProxyFrom(
    uint256 leadingZeroBytes,
    uint256 totalZeroBytes,
    uint256 index
  ) internal returns (address proxy) {
    // get the total number of proxies with the specified number of zero bytes.
    uint256 count = _proxies[leadingZeroBytes][totalZeroBytes].length;

    // ensure that the provided index is within range.
    require(
      count > index,
      "No proxy found that corresponds to the given arguments."
    );

    // retrieve the proxy from the specified index.
    proxy = _proxies[leadingZeroBytes][totalZeroBytes][index];

    // retrieve the proxy at the last index.
    address lastProxy = _proxies[leadingZeroBytes][totalZeroBytes][count - 1];

    // reassign the proxy at the specified index to the proxy at the last index.
    _proxies[leadingZeroBytes][totalZeroBytes][index] = lastProxy;

    // reassign the index of the last proxy in the locations mapping.
    _proxyLocations[lastProxy].index = index;

    // shorten the _proxies array, which will also delete redundant last item.
    _proxies[leadingZeroBytes][totalZeroBytes].length--;

    // remove the proxy from the locations mapping.
    delete _proxyLocations[proxy];
  }

  /**
   * @dev Internal function to pop off an offer from the relevant array.
   * @param index uint256 The desired index of the offer in the relevant array.
   * @return The offer.
   */
  function _popOfferFrom(uint256 index) internal returns (Offer memory offer) {
    // retrive the offer at the given index.
    offer = _offers[index];

    // retrive the offer at the last index.
    Offer memory lastOffer = _offers[_offers.length - 1];

    // reassign the offer at the specified index to the offer at the last index.
    _offers[index] = lastOffer;

    // reassign the index of the last offer in the locations mapping.
    _offerLocations[lastOffer.id].index = index;

    // shorten _offers array, which will also delete the redundant last item.
    _offers.length--;

    // remove the offer from the relevant locations mapping.
    delete _offerLocations[offer.id];
  }

  /**
   * @dev Internal function to compute the address of the upgradeable proxy that
   * will be created when submitting a given salt or nonce to the contract, as
   * well as whether or not said proxy has been created. The CREATE2 address is
   * computed in accordance with EIP-1014, and adheres to the formula therein of
   * `keccak256( 0xff ++ address ++ salt ++ keccak256(init_code)))[12:]` when
   * performing the computation. The computed address is then checked for any
   * existing contract code - if any is found, notYetCreated will return false.
   * @param salt bytes32 The nonce that will be passed into the CREATE2 address
   * calculation.
   * @return The proxy creation address and a boolean signifying whether the
   * proxy has already been created.
   */
  function _proxyCreationDryRun(
    bytes32 salt
  ) internal view returns (address proxy, bool alreadyCreated) {
    // variable for checking code size of any pre-existing contract at address.
    uint256 existingContractSize;

    // determine the contract address where the proxy contract will be created.
    proxy = address(
      uint160(                      // downcast to match the address type.
        uint256(                    // convert to uint to truncate upper digits.
          keccak256(                // compute the CREATE2 hash using 4 inputs.
            abi.encodePacked(       // pack all inputs to the hash together.
              hex"ff",              // start with 0xff to distinguish from RLP.
              address(this),        // this contract will be the caller.
              salt,                 // pass in the supplied salt value.
              _initCodeHash         // pass in the hash of initialization code.
            )
          )
        )
      )
    );

    // determine if any contract code already exists at computed proxy address.
    assembly { // solhint-disable-line
      existingContractSize := extcodesize(proxy)
    }

    // if so, exit and return the null address to signify failure.
    if (existingContractSize > 0) {
      alreadyCreated = true;
    }
  }

  /**
   * @dev Internal function to get the number of "zero" bytes (0x00) in an
   * address (20 bytes long). Each zero byte reduces the cost of including
   * address in calldata by 64 gas. Each leading zero byte enables the address
   * to be packed that much tighter.
   * @param account address The address in question.
   * @return The leading number and total number of zero bytes in the address.
   */
  function _getZeroBytes(address account) internal pure returns (
    uint256 leading,
    uint256 total
  ) {
    // convert the address to bytes.
    bytes20 b = bytes20(account);

    // designate a flag that will be flipped once leading zero bytes are found.
    bool searchingForLeadingZeroBytes = true;

    // iterate through each byte of the address and count the zero bytes found.
    for (uint256 i; i < 20; i++) {
      if (b[i] == 0) {
        total++; // increment the total value if the byte is equal to 0x00.
      } else if (searchingForLeadingZeroBytes) {
        leading = i; // set leading byte value upon reaching a non-zero byte.
        searchingForLeadingZeroBytes = false; // stop search upon finding value.
      }
    }

    // special handling for the null address.
    if (total == 20) {
      leading = 20;
    }
  }

  /**
   * @dev Internal function to get the token value of an address with a given
   * number of zero bytes. An address is valued at 1 token when there are three
   * leading zero bytes.
   * @param leadingZeroBytes uint256 The number of leading zero bytes in the
   * address.
   * @param totalZeroBytes uint256 The total number of zero bytes in the
   * address.
   * @return The reward size given the number of leading and zero bytes.
   */
  function _getValue(
    uint256 leadingZeroBytes,
    uint256 totalZeroBytes
  ) internal view returns (uint256 value) {
    // only consider cases where there are at least three zero bytes.
    if (totalZeroBytes > 2) {
      // find and return the value of a proxy with the given parameters.
      return _rewards[uint24(leadingZeroBytes * 20 + totalZeroBytes)];
    }

    // return 0 in cases where there are two or fewer zero bytes.
    return 0;
  }

  /**
   * @dev Internal function to get the tokens that must be paid in order to
   * claim a given proxy. Note that this function is equivalent to calling
   * _getValue on the output of _getZeroBytes.
   * @param proxy address The address of the proxy.
   * @return The reward size of the given proxy.
   */
  function _getReward(address proxy) internal view returns (uint256 reward) {
    // calculate total number of leading and trailing zero bytes, respectively.
    (uint256 leadingZeroBytes, uint256 totalZeroBytes) = _getZeroBytes(proxy);

    // calculate value of reward based on number of leading & total zero bytes.
    return _getValue(leadingZeroBytes, totalZeroBytes);
  }

  /* solhint-disable function-max-lines */
  /**
   * @dev Internal function to check a given proxy address against the target
   * address based on areas dictated by an associated search space, which can be
   * used in determining whether a proxy can be matched to an offer.
   * @param proxy address The address of the proxy.
   * @param searchSpace bytes20 A sequence of bytes that determines which areas
   * of the target address should be matched against. The 0x00 byte means that
   * the target byte can be skipped, otherwise each nibble represents a
   * different filter condition as indicated by the Condition enum.
   * @param target address The targeted address, with each relevant byte and
   * nibble determined by the corresponding byte in searchSpace.
   * @return Boolean signifying if the proxy fulfills the offer's requirements.
   */
  function _matchesOfferConstraints(
    address proxy,
    bytes20 searchSpace,
    address target
  ) internal pure returns (bool matchIsGood) {
    // convert the addresses to bytes.
    bytes20 p = bytes20(proxy);
    bytes20 t = bytes20(target);

    // get the initial nibble of the proxy now to prevent stack depth errors.
    uint8 initialNibble = (uint8(p[0]) - uint8(p[0]) % 16) / 16;

    // declare variable types.
    uint8 leftNibbleProxy;
    uint8 rightNibbleProxy;
    uint8 leftNibbleSearchSpace;
    uint8 rightNibbleSearchSpace;
    uint8 leftNibbleTarget;
    uint8 rightNibbleTarget;

    // get the capitalized characters in the checksum of the proxy.
    // optionally check if any search space conditions are case-sensitive first.
    bool[40] memory caps = _getChecksumCapitalizedCharacters(proxy);

    // iterate over bytes, processing left and right nibble in each iteration.
    for (uint256 i; i < p.length; i++) {
      // skip bytes in the search space with no match.
      if (searchSpace[i] == hex"00") continue;

      // get left and right nibble from proxy, search space, and target bytes.
      rightNibbleProxy = uint8(p[i]) % 16;
      leftNibbleProxy = (uint8(p[i]) - rightNibbleProxy) / 16;
      rightNibbleSearchSpace = uint8(searchSpace[i]) % 16;
      leftNibbleSearchSpace = (
        (uint8(searchSpace[i]) - rightNibbleSearchSpace) / 16);
      rightNibbleTarget = uint8(t[i]) % 16;
      leftNibbleTarget = (uint8(t[i]) - rightNibbleTarget) / 16;

      // check that the left nibble meets the conditions of the offer.
      if (
        !_nibbleConditionMet(
          leftNibbleProxy,
          caps[2 * i],
          leftNibbleSearchSpace,
          leftNibbleTarget
        )
      ) {
        uint8 priorNibble = uint8(p[i - 1]) % 16;
        if (
          !_nibbleRelativeConditionMet(
            leftNibbleProxy,
            caps[2 * i],
            leftNibbleSearchSpace,
            priorNibble,
            caps[2 * i - 1],
            initialNibble,
            caps[0]
          )
        ) {
          return false;
        }
      }

      // check that the right nibble meets the conditions of the offer.
      if (
        !_nibbleConditionMet(
          rightNibbleProxy,
          caps[2 * i + 1],
          rightNibbleSearchSpace,
          rightNibbleTarget
        ) && !_nibbleRelativeConditionMet(
          rightNibbleProxy,
          caps[2 * i + 1],
          rightNibbleSearchSpace,
          leftNibbleProxy, // priorNibble
          caps[2 * i],
          initialNibble,
          caps[0]
        )
      ) {
        return false;
      }
    }

    // return a successful match.
    return true;
  }
  /* solhint-enable function-max-lines */

  /**
   * @dev Internal function for getting a fixed-size array of whether or not
   * each character in an account will be capitalized in the checksum.
   * @param account address The account to get the checksum capitalization
   * information for.
   * @return A fixed-size array of booleans that signify if each character or
   * "nibble" of the hex encoding of the address will be capitalized by the
   * checksum.
   */
  function _getChecksumCapitalizedCharacters(
    address account
  ) internal pure returns (bool[40] memory characterIsCapitalized) {
    // convert the address to bytes.
    bytes20 a = bytes20(account);

    // hash the address (used to calculate checksum).
    bytes32 b = keccak256(abi.encodePacked(_toAsciiString(a)));

    // declare variable types.
    uint8 leftNibbleAddress;
    uint8 rightNibbleAddress;
    uint8 leftNibbleHash;
    uint8 rightNibbleHash;

    // iterate over bytes, processing left and right nibble in each iteration.
    for (uint256 i; i < a.length; i++) {
      // locate the byte and extract each nibble for the address and the hash.
      rightNibbleAddress = uint8(a[i]) % 16;
      leftNibbleAddress = (uint8(a[i]) - rightNibbleAddress) / 16;
      rightNibbleHash = uint8(b[i]) % 16;
      leftNibbleHash = (uint8(b[i]) - rightNibbleHash) / 16;

      // set the capitalization flags based on the characters and the checksums.
      characterIsCapitalized[2 * i] = (
        leftNibbleAddress > 9 &&
        leftNibbleHash > 7
      );
      characterIsCapitalized[2 * i + 1] = (
        rightNibbleAddress > 9 &&
        rightNibbleHash > 7
      );
    }
  }

  /**
   * @dev Internal function for converting the bytes representation of an
   * address to an ASCII string. This function is derived from the function at
   * https://ethereum.stackexchange.com/a/56499/48410
   * @param data bytes20 The account address to be converted.
   * @return The account string in ASCII format. Note that leading "0x" is not
   * included.
   */
  function _toAsciiString(
    bytes20 data
  ) internal pure returns (string memory asciiString) {
    // create an in-memory fixed-size bytes array.
    bytes memory asciiBytes = new bytes(40);

    // declare variable types.
    uint8 b;
    uint8 leftNibble;
    uint8 rightNibble;

    // iterate over bytes, processing left and right nibble in each iteration.
    for (uint256 i = 0; i < data.length; i++) {
      // locate the byte and extract each nibble.
      b = uint8(uint160(data) / (2 ** (8 * (19 - i))));
      leftNibble = b / 16;
      rightNibble = b - 16 * leftNibble;

      // to convert to ascii characters, add 48 to 0-9 and 87 to a-f.
      asciiBytes[2 * i] = byte(leftNibble + (leftNibble < 10 ? 48 : 87));
      asciiBytes[2 * i + 1] = byte(rightNibble + (rightNibble < 10 ? 48 : 87));
    }

    return string(asciiBytes);
  }

  /* solhint-disable code-complexity */
  /**
   * @dev Internal function for checking if a particular nibble (half-byte or
   * single hex character) meets the condition implied by the associated nibble
   * in the search space. Note that this function will return false in the event
   * a relative condition is passed in as the searchSpace argument; in those
   * cases, use _nibbleRelativeConditionMet() instead.
   * @param proxy uint8 The nibble from the proxy address to check.
   * @param capitalization bool Whether or not the nibble is capitalized in the
   * checksum of the address.
   * @param searchSpace uint8 The nibble to use in determining which areas of
   * the target address should be matched against. The 0x00 byte means that the
   * target byte can be skipped, otherwise each nibble represents a different
   * filter condition as indicated by the Condition enum.
   * @param target uint8 The nibble from the target address to check against.
   * @return A boolean indicating if the condition has been met.
   */
  function _nibbleConditionMet(
    uint8 proxy,
    bool capitalization,
    uint8 searchSpace,
    uint8 target
  ) internal pure returns (bool) {
    if (searchSpace == uint8(Condition.NoMatch)) {
      return true;
    }

    if (searchSpace == uint8(Condition.MatchCaseInsensitive)) {
      return (proxy == target);
    }

    if (searchSpace == uint8(Condition.MatchUpperCase)) {
      return ((proxy == target) && capitalization);
    }

    if (searchSpace == uint8(Condition.MatchLowerCase)) {
      return ((proxy == target) && !capitalization);
    }

    if (searchSpace == uint8(Condition.MatchRangeLessThanCaseInsensitive)) {
      return (proxy < target);
    }

    if (searchSpace == uint8(Condition.MatchRangeGreaterThanCaseInsensitive)) {
      return (proxy > target);
    }

    if (searchSpace == uint8(Condition.MatchRangeLessThanUpperCase)) {
      return ((proxy < target) && (proxy < 10 || capitalization));
    }

    if (searchSpace == uint8(Condition.MatchRangeGreaterThanUpperCase)) {
      return ((proxy > target) && (proxy < 10 || capitalization));
    }

    if (searchSpace == uint8(Condition.MatchRangeLessThanLowerCase)) {
      return ((proxy < target) && (proxy < 10 || !capitalization));
    }

    if (searchSpace == uint8(Condition.MatchRangeGreaterThanLowerCase)) {
      return ((proxy > target) && (proxy < 10 || !capitalization));
    }

    if (searchSpace == uint8(Condition.NoMatchNoUpperCase)) {
      return !capitalization;
    }

    if (searchSpace == uint8(Condition.NoMatchNoLowerCase)) {
      return (target < 10 || capitalization);
    }
  }
  /* solhint-enable code-complexity */

  /**
   * @dev Internal function for checking if a particular nibble (half-byte or
   * single hex character) meets the condition implied by the associated nibble
   * in the search space. Note that this function will return false in the event
   * a non-relative condition is passed in as the searchSpace argument; in those
   * cases, use _nibbleConditionMet() instead.
   * @param proxy uint8 The nibble from the proxy address to check.
   * @param capitalization bool Whether or not the nibble is capitalized in the
   * checksum of the address.
   * @param searchSpace uint8 The nibble to use in determining which areas of
   * the target address should be matched against. Each nibble represents a
   * different filter condition as indicated by the Condition enum.
   * @param prior uint8 The prior nibble from the target address.
   * @param priorCapitalization bool Whether or not the nibble immediately
   * before the nibble to check is capitalized in the checksum of the address.
   * @param initial uint8 The first nibble from the target address.
   * @param initialCapitalization bool Whether or not first nibble is
   * capitalized in the checksum of the address.
   * @return A boolean indicating if the condition has been met.
   */
  function _nibbleRelativeConditionMet(
    uint8 proxy,
    bool capitalization,
    uint8 searchSpace,
    uint8 prior,
    bool priorCapitalization,
    uint8 initial,
    bool initialCapitalization
  ) internal pure returns (bool) {
    if (searchSpace == uint8(Condition.MatchAgainstPriorCaseInsensitive)) {
      return (proxy == prior);
    }

    if (searchSpace == uint8(Condition.MatchAgainstInitialCaseInsensitive)) {
      return (proxy == initial);
    }

    if (searchSpace == uint8(Condition.MatchAgainstPriorCaseSensitive)) {
      return (
        (proxy == prior) &&
        (capitalization == priorCapitalization)
      );
    }

    if (searchSpace == uint8(Condition.MatchAgainstInitialCaseSensitive)) {
      return (
        (proxy == initial) &&
        (capitalization == initialCapitalization)
      );
    }
  }

  /**
   * @dev Internal function that ensures that a given proxy was deployed.
   * @param proxy address The address of the proxy in question.
   */
  function _requireSuccessfulDeployment(address proxy) internal pure {
    // ensure that the proxy argument is not equal to the null address.
    require(
      proxy != address(0),
      "Failed to deploy an upgradeable proxy using the provided salt."
    );
  }

  /**
   * @dev Internal function to ensure that an offer has not expired.
   * @param expiration uint256 The expiration (using epoch time) in question.
   */
  function _requireOfferNotExpired(uint256 expiration) internal view {
    // ensure that the expiration is 0 (not set) or ahead of the current time.
    require(
      expiration == 0 || expiration > now, // solhint-disable-line
      "Offer has expired and is no longer valid."
    );
  }

  /**
   * @dev Internal function to ensure that a proxy matches an offer.
   * @param proxy address The address of the proxy in question.
   * @param searchSpace bytes20 A sequence of bytes that determines which areas
   * of the target address should be matched against. The 0x00 byte means that
   * the target byte can be skipped, otherwise each nibble represents a
   * different filter condition as indicated by the Condition enum.
   * @param target address The targeted address, with each relevant byte and
   * nibble determined by the corresponding byte in searchSpace.
   */
  function _requireValidMatch(
    address proxy,
    bytes20 searchSpace,
    address target
  ) internal pure {
    // ensure that the constraints of the offer are met.
    require(
      _matchesOfferConstraints(proxy, searchSpace, target),
      "Proxy does not conform to the constraints of the provided offer."
    );
  }

  /**
   * @dev Internal function to ensure that an offer was originally supplied by
   * the caller.
   * @param index uint256 The desired index of the offer in the relevant array.
   */
  function _requireOnlyOfferOriginator(uint256 index) internal view {
    // ensure that the offer was originally supplied by the caller.
    require(
      _offers[index].offerer == msg.sender,
      "Only the originator of the offer may perform this operation."
    );
  }

  /**
   * @dev Internal function to ensure that an offer has valid constraints (i.e.
   * the search space and the target do not conflict).
   * @param searchSpace bytes20 A sequence of bytes that determines which areas
   * of the target address should be matched against. The 0x00 byte means that
   * the target byte can be skipped, otherwise each nibble represents a
   * different filter condition as indicated by the Condition enum.
   * @param target address The targeted address, with each relevant byte and
   * nibble determined by the corresponding byte in searchSpace.
   */
  function _requireOfferValid(
    bytes20 searchSpace,
    address target
  ) internal pure {
    // check that a relative condition has not been used in the first item.
    _requireNoInitialRelativeCondition(
      (uint8(searchSpace[0]) - uint8(searchSpace[0]) % 16) / 16 // first nibble
    );

    // convert the address to bytes.
    bytes20 a = bytes20(target);

    // declare variable types.
    uint8 leftNibbleSearchSpace;
    uint8 rightNibbleSearchSpace;
    uint8 leftNibbleTarget;
    uint8 rightNibbleTarget;

    // iterate over bytes, processing left and right nibble in each iteration.
    for (uint256 i; i < a.length; i++) {
      // skip bytes in the search space with no match condition.
      if (searchSpace[i] == hex"00") continue;

      // locate the byte and extract each nibble for search space and target.
      rightNibbleSearchSpace = uint8(searchSpace[i]) % 16;
      leftNibbleSearchSpace = (
        (uint8(searchSpace[i]) - rightNibbleSearchSpace) / 16);
      rightNibbleTarget = uint8(a[i]) % 16;
      leftNibbleTarget = (uint8(a[i]) - rightNibbleTarget) / 16;

      // check left nibble - only need to validate conditions greater than 1.
      if (leftNibbleSearchSpace > 1) {
        // check that there's not a target on relative or "no-match" conditions.
        _requireNoTargetUnlessNeeded(leftNibbleSearchSpace, leftNibbleTarget);

        // check that a case isn't specified on a digit target.
        _requireNoCaseOnDigit(leftNibbleSearchSpace, leftNibbleTarget);

        // check that a case isn't specified on a digit-only range.
        _requireNoCaseOnDigitRange(leftNibbleSearchSpace, leftNibbleTarget);

        // check that an impossible range isn't specified.
        _requireRangeBoundsValid(leftNibbleSearchSpace, leftNibbleTarget);
      }

      // do the same for the right nibble.
      if (rightNibbleSearchSpace > 1) {
        _requireNoTargetUnlessNeeded(rightNibbleSearchSpace, rightNibbleTarget);
        _requireNoCaseOnDigit(rightNibbleSearchSpace, rightNibbleTarget);
        _requireNoCaseOnDigitRange(rightNibbleSearchSpace, rightNibbleTarget);
        _requireRangeBoundsValid(rightNibbleSearchSpace, rightNibbleTarget);
      }
    }
  }

  /**
   * @dev Internal function to ensure that a target is not specified on offers
   * with relative conditions or for "no-match" conditions.
   * @param searchItem uint8 The nibble from the search space designating the
   * condition to check against.
   * @param target uint8 The nibble that designates what value to target.
   */
  function _requireNoTargetUnlessNeeded(
    uint8 searchItem,
    uint8 target
  ) internal pure {
    require(
      target == 0 || searchItem < 10,
      "Cannot specify target for relative or no-match conditions."
    );
  }

  /**
   * @dev Internal function to ensure that a capitalization condition isn't
   * specified on a digit target.
   * @param searchItem uint8 The nibble from the search space designating the
   * condition to check against.
   * @param target uint8 The nibble that designates what value to target.
   */
  function _requireNoCaseOnDigit(uint8 searchItem, uint8 target) internal pure {
    if (
      target < 10 && (
        searchItem == uint8(Condition.MatchUpperCase) ||
        searchItem == uint8(Condition.MatchLowerCase)
      )
    ) {
      revert("Cannot match upper-case or lower-case against a digit.");
    }
  }

  /**
   * @dev Internal function to ensure that a capitalization condition isn't
   * specified on a digit-only range.
   * @param searchItem uint8 The nibble from the search space designating the
   * condition to check against.
   * @param target uint8 The nibble that designates what value to target.
   */
  function _requireNoCaseOnDigitRange(
    uint8 searchItem,
    uint8 target
  ) internal pure {
    if (
      searchItem > 5 && (
        searchItem == uint8(Condition.MatchRangeLessThanUpperCase) ||
        searchItem == uint8(Condition.MatchRangeLessThanLowerCase)
      ) && target < 11
    ) {
      revert("Cannot specify upper-case or lower-case on digit-only range.");
    }
  }

  /**
   * @dev Internal function to ensure that an impossible range isn't specified.
   * @param searchItem uint8 The nibble from the search space designating the
   * condition to check against.
   * @param target uint8 The nibble that designates what value to target.
   */
  function _requireRangeBoundsValid(
    uint8 searchItem,
    uint8 target
  ) internal pure {
    if (
      searchItem > 3 && (
        target == 0 && (
          searchItem == uint8(Condition.MatchRangeLessThanCaseInsensitive) ||
          searchItem == uint8(Condition.MatchRangeLessThanUpperCase) ||
          searchItem == uint8(Condition.MatchRangeLessThanLowerCase)
        ) || target == 15 && (
          searchItem == uint8(Condition.MatchRangeGreaterThanCaseInsensitive) ||
          searchItem == uint8(Condition.MatchRangeGreaterThanUpperCase) ||
          searchItem == uint8(Condition.MatchRangeGreaterThanLowerCase)
        )
      )
    ) {
      revert("Cannot specify a range where no values fall within the bounds.");
    }   
  }

  /**
   * @dev Internal function to ensure that a relative condition has not been
   * specified as the first item in the search space.
   * @param firstNibble uint8 The first nibble from the search space designating
   * the condition to check against.
   */
  function _requireNoInitialRelativeCondition(uint8 firstNibble) internal pure {
    if (
      firstNibble == uint8(Condition.MatchAgainstPriorCaseInsensitive) ||
      firstNibble == uint8(Condition.MatchAgainstInitialCaseInsensitive) ||
      firstNibble == uint8(Condition.MatchAgainstPriorCaseSensitive) ||
      firstNibble == uint8(Condition.MatchAgainstInitialCaseSensitive)
    ) {
      revert("Cannot specify preceding target against initial character.");
    }
  }

  /**
   * @dev Modifier to ensure that first 20 bytes of a submitted salt match
   * those of the calling account. This provides protection against the salt
   * being stolen by frontrunners or other attackers.
   * @param salt bytes32 The salt value to check against the calling address.
   */
  modifier containsCaller(bytes32 salt) {
    // prevent proxy submissions from being stolen from tx.pool by requiring
    // that the first 20 bytes of the submitted salt match msg.sender.
    require(
      address(bytes20(salt)) == msg.sender,
      "Invalid salt - first 20 bytes of the salt must match calling address."
    );
    _;
  }

  /**
   * @dev Modifier that ensures that a given proxy is known and owned by the
   * contract. Contracts that become owned by Pr000xy, but were not originally
   * created by Pr000xy, must be excluded as they may have changed the proxy's
   * state in the meantime.
   * @param proxy address The address of the proxy in question.
   */
  modifier proxyExists(address proxy) {
    // ensure that a proxy exists at the provided address.
    require(
      _proxyLocations[proxy].exists,
      "No proxy found that corresponds to the given address."
    );
    _;
  }

  /**
   * @dev Modifier that ensures that a given offer is known and owned by the
   * contract.
   * @param offerID uint256 The ID of the offer in question.
   */
  modifier offerExists(uint256 offerID) {
    // ensure that the provided offer ID exists.
    require(
      _offerLocations[offerID].exists,
      "No offer found that corresponds to the given offer ID."
    );
    _;
  }
}
pragma solidity 0.5.1;


/**
 * @title Interface to Pr000xy - a public utility ERC20 for creating & claiming
 * transparent proxies with gas-efficient addresses.
 * @author 0age
 */
interface Pr000xyInterface {
  /**
   * @dev Event that signifies the creation of a new upgradeable proxy.
   * @param creator address indexed Address of the submitter of the salt that
   * was used to create the proxy.
   * @param value uint256 indexed Token value of the submitted proxy.
   * @param proxy address Address of the created proxy.
   */
  event ProxyCreated(
    address indexed creator,
    uint256 indexed value,
    address proxy
  );

  /**
   * @dev Event that signifies that a proxy has been claimed.
   * @param claimant address indexed Address of the recipient of the proxy.
   * @param value uint256 indexed Token value of the claimed proxy.
   * @param proxy address Address of the claimed proxy.
   */
  event ProxyClaimed(
    address indexed claimant,
    uint256 indexed value,
    address proxy
  );

  /**
   * @dev Event that signifies the creation of a new upgradeable proxy that is
   * immediately claimed by the creator.
   * @param creator address indexed Address of the submitter of the salt that is
   * used to create the proxy.
   * @param proxy address Address of the created proxy.
   */
  event ProxyCreatedAndClaimed(
    address indexed creator,
    address proxy
  );

  /**
   * @dev Event that signifies that an offer for a named proxy has been created.
   * @param offerID uint256 indexed The ID of the offer.
   * @param offerer address indexed The account that created the offer.
   * @param reward uint256 Reward for finding a match to fulfill the offer.
   */
  event OfferCreated(
    uint256 indexed offerID,
    address indexed offerer,
    uint256 reward
  );

  /**
   * @dev Event that signifies that an offer for a named proxy has been created.
   * @param offerID uint256 indexed The ID of the offer.
   * @param offerer address indexed The account that created the offer.
   * @param submitter address indexed Address of submitter of the fulfillment.
   * @param reward uint256 Reward for finding the match that fulfills the offer.
   */
  event OfferFulfilled(
    uint256 indexed offerID,
    address indexed offerer,
    address indexed submitter,
    uint256 reward
  );

  /**
   * @dev Event that signifies that an offer has been set to expire.
   * @param offerID uint256 indexed The ID of the offer.
   * @param offerer address indexed The account that created the offer.
   * @param expiration uint256 The expiration (using epoch time) in question.
   */
  event OfferSetToExpire(
    uint256 indexed offerID,
    address indexed offerer,
    uint256 expiration
  );

  /**
   * @dev Create an upgradeable proxy, add to collection, and pay reward if
   * applicable. Pr000xy will be set as the initial as admin, and the target
   * implementation will be set as the initial implementation (logic contract).
   * @param salt bytes32 The nonce that will be passed into create2. The first
   * 20 bytes of the salt must match those of the calling address.
   * @return Address of the new proxy.
   */
  function createProxy(bytes32 salt) external returns (address proxy);

  /**
   * @dev Claims an upgradeability proxy, removes from collection, burns value.
   * Specify an admin and a new implementation (logic contract) to point to.
   * NOTE: this method does not support calling an initialization function.
   * @param proxy address The address of the proxy.
   * @param owner address The new owner of the claimed proxy.
   * @param implementation address the logic contract to be set on the claimed
   * proxy.
   * @param data bytes Optional parameter for calling an initializer on the new
   * implementation immediately after the change in ownership.
   * @return The address of the new proxy.
   */
  function claimProxy(
    address proxy,
    address owner,
    address implementation,
    bytes calldata data
  ) external;

  /**
   * @dev Claims the last proxy created in a given category, removes from
   * collection, and burns value. Specify an admin and a new implementation
   * (logic contract) to point to (set to null address to leave set to current).
   * NOTE: this method does not support calling an initialization function.
   * @param leadingZeroBytes uint256 The number of leading zero bytes in the
   * claimed proxy.
   * @param totalZeroBytes uint256 The total number of zero bytes in the
   * claimed proxy.
   * @param owner address The new owner of the claimed proxy.
   * @param implementation address the logic contract to be set on the claimed
   * proxy.
   * @param data bytes Optional parameter for calling an initializer on the new
   * implementation immediately after the change in ownership.
   * @return The address of the new proxy.
   */
  function claimLatestProxy(
    uint256 leadingZeroBytes,
    uint256 totalZeroBytes,
    address owner,
    address implementation,
    bytes calldata data
  ) external returns (address proxy);

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
  ) external payable returns (uint256 offerID);

  /**
   * @dev Match an offer to a proxy and claim the amount offered for finding it.
   * Note that this function is susceptible to front-running in current form.
   * @param proxy address The address of the proxy.
   * @param offerID uint256 The ID of the offer to match and fulfill.
   */
  function matchOffer(address proxy, uint256 offerID) external;

  /**
   * @dev Create an upgradeable proxy and immediately match it with an offer.
   * @param salt bytes32 The nonce that will be passed into create2. The first
   * 20 bytes of the salt must match those of the calling address.
   * @param offerID uint256 The ID of the offer to match.
   * @return The address of the new proxy.
   */
  function createAndMatch(bytes32 salt, uint256 offerID) external;

  /**
   * @dev Create an upgradeable proxy and immediately claim it. No tokens will
   * be minted or burned in the process. Leave the implementation address set to
   * the null address to skip changing the implementation.
   * @param salt bytes32 The nonce that will be passed into create2. The first
   * 20 bytes of the salt must match those of the calling address.
   * @param owner address The new owner of the claimed proxy.
   * @param implementation address The logic contract set for the claimed proxy.
   * @param data bytes Optional parameter for calling an initializer on the new
   * implementation immediately after the change in ownership.
   * @return The address of the new proxy.
   */
  function createAndClaim(
    bytes32 salt,
    address owner,
    address implementation,
    bytes calldata data
  ) external returns (address proxy);

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
  ) external returns (address[] memory proxies);

  /**
   * @dev Efficient version of batchCreate that uses less gas. The first twenty
   * bytes of each salt are automatically populated using the calling address,
   * and remaining salt segments are passed in as a packed byte array, using
   * twelve bytes per segment, and a function selector of 0x00000000. No values
   * will be returned; derived proxies must be calculated seperately or observed
   * in event logs. Also note that an attempt to include a salt that tries to
   * create a proxy that already exists will cause the entire batch to revert.
   */
  function batchCreateEfficient_H6KNX6() external; // solhint-disable-line

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
  ) external;

  /**
   * @dev Set a given offer to expire in 24 hours.
   * @param offerID uint256 The ID of the offer to schedule expiration on.
   */
  function scheduleOfferExpiration(
    uint256 offerID
  ) external returns (uint256 expiration);

  /**
   * @dev Cancel an expired offer and refund the amount offered.
   * @param offerID uint256 The ID of the offer to cancel.
   */
  function cancelOffer(
    uint256 offerID
  ) external;

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
  ) external view returns (address proxy);

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
  ) external view returns (bool hasMatch);

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
  );

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
  ) external view returns (uint256 value);

  /**
   * @dev Get the tokens that must be paid in order to claim a given proxy.
   * Note that this function is equivalent to calling getValue on the output of
   * getZeroBytes.
   * @param proxy address The address of the proxy.
   * @return The reward size of the given proxy.
   */
  function getReward(address proxy) external view returns (uint256 value);

  /**
   * @dev Count total claimable proxy address with a given number of leading and
   * total zero bytes.
   * @param leadingZeroBytes uint256 The desired number of leading zero bytes.
   * @param totalZeroBytes uint256 The desired number of total zero bytes.
   * @return The total number of claimable proxies.
   */
  function countProxiesAt(
    uint256 leadingZeroBytes,
    uint256 totalZeroBytes
  ) external view returns (uint256 totalPertinentProxies);

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
  ) external view returns (address proxy);

  /**
   * @dev Count total outstanding offers.
   * @return The total number of outstanding offers.
   */
  function countOffers() external view returns (uint256 totalOffers);

  /**
   * @dev Get an outstanding offer ID at a given index.
   * @param index uint256 The desired index of the offer in the relevant array.
   * @return The offerID of the outstanding offer.
   */
  function getOfferID(uint256 index) external view returns (uint256 offerID);

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
  );

  /**
   * @dev Get the address of the logic contract that is implemented on newly
   * created proxies.
   * @return The address of the proxy implementation.
   */
  function getInitialProxyImplementation() external view returns (
    address implementation
  );

  /**
   * @dev Get the initialization code that is used to create each upgradeable
   * proxy.
   * @return The proxy initialization code.
   */
  function getProxyInitializationCode() external view returns (
    bytes memory initializationCode
  );

  /**
   * @dev Get the keccak256 hash of the initialization code used to create
   * upgradeable proxies.
   * @return The hash of the proxy initialization code.
   */
  function getProxyInitializationCodeHash() external view returns (
    bytes32 initializationCodeHash
  );

  /**
   * @dev Check if a proxy at a given address is administrated by this contract.
   * @param proxy address The address of the proxy.
   * @return Boolean that signifies if the proxy is currently administered by
   * this contract.
   */
  function isAdmin(address proxy) external view returns (bool admin);
}
pragma solidity 0.5.1;


/**
 * @title Initializeable logic contract implementation - used for testing.
 */
contract InitializeableImplementation {
  bool private _initialized;

  function initialize() external {  // function signature: 0x8129fc1c
    _initialized = true;
  }

  function initialized() external view returns (bool) {
    return _initialized;
  }
}
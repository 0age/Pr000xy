var assert = require('assert')
var fs = require('fs')
var util = require('ethereumjs-util')

const Pr000xyRewardsArtifact = require('../../build/contracts/Pr000xyRewards.json')
const Pr000xyArtifact = require('../../build/contracts/Pr000xy.json')
const UpgradeableArtifact = require('../../build/contracts/AdminUpgradeabilityProxy.json')
const ProxyImplArtifact = require('../../build/contracts/InitialProxyImplementation.json')
const Create2FactoryArtifact = require('../../build/contracts/Create2Factory.json')

module.exports = {test: async function (provider, testingContext) {
  var web3 = provider
  let passed = 0
  let failed = 0
  let gasUsage = {}
  console.log('running tests...')

  const privKey = '0x0f00f00f00f00f00f00f00f00f00f00f00f00f00f00f00f00f00f00f00f00f00'
  const pubKey = await web3.eth.accounts.privateKeyToAccount(privKey)
  await web3.eth.accounts.wallet.add(pubKey)

  let address = pubKey.address

  const nullAddress = '0x0000000000000000000000000000000000000000'
  const badAddress = '0xbAd00BAD00BAD00bAD00bAD00bAd00BaD00bAD00'
  const unownedAddress = '0x1010101010101010101010101010101010101010'
  const oneAddress = '0x0000001010101010101010101010101010101010'

  async function deployTx(data, title, gas) {
    let tx
    await web3.eth.sendTransaction({
      from: address,
      value: 0,
      data: data,
      gas: gas
    }, async (err, txHash) => {
      tx = txHash
    }).catch(error => {
      console.error(error)
    })
    while (!tx) {
      continue
    }
    return tx
  }

  async function tx(target, data, title, value) {
    let tx
    if (typeof value === 'undefined') {
      value = 0
    }
    await web3.eth.sendTransaction({
      to: target,
      from: address,
      value: value,
      data: data,
      gas: 7600000,
      gasPrice: 10
    }, async (err, txHash) => {
      tx = txHash
    }).catch(error => {
      console.error(error)
    })
    while (!tx) {
      continue
    }
    return tx
  }

  async function parse(tx) {
    let receipt
    while (!receipt) {
      receipt = await web3.eth.getTransactionReceipt(tx)
    }
    return receipt
  }

  async function getCreate2Address(sender, salt, initCode) {
    return util.toChecksumAddress(
      util.bufferToHex(
        util.generateAddress2(
          util.toBuffer(sender),
          util.toBuffer(salt),
          util.toBuffer(initCode)
        )
      )
    )
  }

  function match(address, searchSpace, target) {
    address = web3.utils.toChecksumAddress(address)
    target = web3.utils.toChecksumAddress(target)
    // iterate through each byte of the address, checking for constraints.
    for (var i = 2; i < searchSpace.length; i++) {
      s = searchSpace[i]
      p = (address[i])
      t = (target[i])
      // if search space byte is equal to 0, skip this byte.
      if (s === '0') {
        continue;
      }

      if (s === '1') {
        // 1: nibble must match, case insensitive.
        if (p.toLowerCase() !== t.toLowerCase()) {
          return false;
        }
      } else if (s === '2') {
       // 2: nibble must match and be upper-case.
        if (p.toLowerCase() !== t.toLowerCase() || p === p.toLowerCase()) {
          return false;
        }
      } else if (s === '3') {
       // 3: nibble must match and be lower-case.
        if (p.toLowerCase() !== t.toLowerCase() || p !== p.toLowerCase()) {
          return false;
        }
      } else {
        // otherwise behavior is undefined.
        return false;
      }
    }

    // return a successful match.
    return true;
  }

  assert.ok(
    match(
      '0x003450089012345678901234567890123A56b89A',
      '0x0011100100111111111111111111111111111001',
      '0x123456789012345678901234567890123a56B89a'
    )
  )

  a = '0x0000000000000000000000000000000000000000'
  b = '0x0000000000000000000000000000000000000000000000000000000000000000'
  c = '0x00'

  d = await getCreate2Address(a,b,c)
  assert.strictEqual(d, '0x4D1A2e2bB4F88F0250f26Ffff098B0b30B26BF38')

  r = new RegExp("^0{6}|^0{4}((.{2})*(00)){2}|^((.{2})*(00)){5}")
  term = '0x0000000000000000000000000000000000000000'
  assert.ok(r.test(oneAddress.slice(-40)))

  blockNumber = await web3.eth.getBlockNumber()

  if (testingContext === 'geth') {
    console.log('*** fund the dev account ***')
    accounts = await web3.eth.getAccounts()
    account = accounts[0]

    balance = web3.utils.toBN(await web3.eth.getBalance(account));

    sendable = web3.utils.numberToHex(balance.div(web3.utils.toBN('2')))

    await web3.eth.sendTransaction({from:account, to:address, value: sendable, gas: '0x5208', gasPrice: '0x4A817C800'})

    // bring up gas limit if necessary by doing a bunch of transactions
    var block = await web3.eth.getBlock("latest");
  }

  console.log('*** deploy Pr000xyRewards contract ***')
  const Pr000xyRewardsDeployer = new web3.eth.Contract(Pr000xyRewardsArtifact.abi)
  const Pr000xyRewardsInitCode = await Pr000xyRewardsDeployer.deploy({
    data: Pr000xyRewardsArtifact.bytecode
  }).encodeABI()
  Pr000xyRewardsDeployTx = await deployTx(Pr000xyRewardsInitCode, 'deploy', block.gasLimit - 1)
  Pr000xyRewardsDeployReceipt = await parse(Pr000xyRewardsDeployTx)
  Pr000xyRewardsAddress = Pr000xyRewardsDeployReceipt.contractAddress
  console.log(
    `Pr000xyRewards deployment ${
      Pr000xyRewardsDeployReceipt.status ? 'succeeded' : 'failed'
    } - ${
      Pr000xyRewardsDeployReceipt.gasUsed
    } gas used. Address: ${Pr000xyRewardsAddress}`
  )

  console.log('*** deploy Pr000xy contract ***')
  const Pr000xyDeployer = new web3.eth.Contract(Pr000xyArtifact.abi)
  
  // swap this in for Pr000xyRewardsAddress for use by mine/create2factory.js
  RopstenPr000xyRewardsAddress = '0x749DA89712DC88284Fc35712c06eAC88Dd749e01'

  const Pr000xyInitCode = await Pr000xyDeployer.deploy({
    data: Pr000xyArtifact.bytecode,
    arguments: [Pr000xyRewardsAddress, UpgradeableArtifact.bytecode]
  }).encodeABI()

  //console.log('\n\n' + Pr000xyInitCode + '\n\n')
  //process.exit(0)

  Pr000xyDeployTx = await deployTx(Pr000xyInitCode, 'deploy', block.gasLimit - 1)
  Pr000xyDeployReceipt = await parse(Pr000xyDeployTx)
  Pr000xyAddress = Pr000xyDeployReceipt.contractAddress
  console.log(
    `Pr000xy deployment ${
      Pr000xyDeployReceipt.status ? 'succeeded' : 'failed'
    } - ${
      Pr000xyDeployReceipt.gasUsed
    } gas used. Address: ${Pr000xyAddress}`
  )

  Pr000xy = new web3.eth.Contract(Pr000xyArtifact.abi, Pr000xyAddress)

  console.log('*** call initialize on Pr000xy ***')
  let initializeData = await Pr000xy.methods.initialize().encodeABI()
  initializeTx = await tx(Pr000xyAddress, initializeData, 'initialize')
  initializeReceipt = await parse(initializeTx)
  console.log(
    `Call to initialize() ${
      initializeReceipt.status ? 'succeeded' : 'failed'
    } - ${
      initializeReceipt.gasUsed
    } gas used.`
  )

  console.log('*** call initialized on Pr000xy ***')
  let test = await Pr000xy.methods.initialized().call({
    from: address,
    gas: 5999999
  })
  assert.ok(test)

  console.log('*** call getInitialProxyImplementation on Pr000xy ***')
  let proxyImpl = await Pr000xy.methods.getInitialProxyImplementation().call({
    from: address,
    gas: 5999999
  })
  console.log(proxyImpl)

  console.log('*** call getProxyInitializationCode on Pr000xy ***')
  let initCode = await Pr000xy.methods.getProxyInitializationCode().call({
    from: address,
    gas: 5999999
  })
  //console.log(initCode)

  console.log('*** call getProxyInitializationCodeHash on Pr000xy ***')
  let initCodeHash = await Pr000xy.methods.getProxyInitializationCodeHash().call({
    from: address,
    gas: 5999999
  })
  console.log(initCodeHash)

  console.log('*** call getZeroBytes on nullAddress ***')
  result = await Pr000xy.methods.getZeroBytes(nullAddress).call({
    from: address,
    gas: 5999999
  })
  assert.strictEqual(result.leadingZeroBytes, '20')
  assert.strictEqual(result.totalZeroBytes, '20')

  console.log('*** call getZeroBytes on oneAddress ***')
  result = await Pr000xy.methods.getZeroBytes(oneAddress).call({
    from: address,
    gas: 5999999
  })
  assert.strictEqual(result.leadingZeroBytes, '3')
  assert.strictEqual(result.totalZeroBytes, '3')

  console.log('*** call getReward on Pr000xy ***')
  test = await Pr000xy.methods.getReward(oneAddress).call({
    from: address,
    gas: 5999999
  })
  assert.strictEqual(test, '1')

  console.log('*** call makeOffer on Pr000xy ***')
  let searchString = '0x0011100100111111111111111111111111111001'
  let targetString = web3.utils.toChecksumAddress(
    '0x123456789012345678901234567890123a56b89a'
  )
  let makeOfferData = await Pr000xy.methods.makeOffer(
    searchString,
    targetString,
    address
  ).encodeABI()
  makeOfferTx = await tx(Pr000xyAddress, makeOfferData, 'makeOffer')
  makeOfferReceipt = await parse(makeOfferTx)
  if (!makeOfferReceipt.status) {
    console.log('offer failed.')
    process.exit(1)
  }

  assert.strictEqual(
    makeOfferReceipt.logs[0].topics[0],
    web3.utils.keccak256("OfferCreated(uint256,address,uint256)")
  )
  let loggedOfferID = web3.utils.toBN(
    makeOfferReceipt.logs[0].topics[1]
  ).toString()

  console.log('*** call countOffers on Pr000xy ***')
  test = await Pr000xy.methods.countOffers().call({
    from: address,
    gas: 5999999
  })
  assert.strictEqual(test, '1')

  console.log('*** call getOfferID on Pr000xy ***')
  offerID = await Pr000xy.methods.getOfferID(0).call({
    from: address,
    gas: 5999999
  })
  assert.strictEqual(offerID, loggedOfferID)

  console.log('*** call getOffer on Pr000xy ***')
  test = await Pr000xy.methods.getOffer(offerID).call({
    from: address,
    gas: 5999999
  })
  assert.strictEqual(test.amount, '0')
  assert.strictEqual(test.expiration, '0')
  assert.strictEqual(test.target, targetString)
  assert.strictEqual(test.searchSpace, searchString)
  assert.strictEqual(test.offerer, address)
  assert.strictEqual(test.recipient, address)

  console.log('*** call scheduleOfferExpiration on Pr000xy ***')
  makeOfferData = await Pr000xy.methods.scheduleOfferExpiration(
    offerID
  ).encodeABI()
  makeOfferTx = await tx(Pr000xyAddress, makeOfferData, 'scheduleOfferExpiration')
  makeOfferReceipt = await parse(makeOfferTx)
  if (!makeOfferReceipt.status) {
    console.log('scheduling offer expiration failed.')
    process.exit(1)
  }

  console.log('*** deploy direct upgradeable Proxy contract ***')
  const UpgradeableDeployer = new web3.eth.Contract(UpgradeableArtifact.abi)
  const UpgradeableInitCode = await UpgradeableDeployer.deploy({
    data: UpgradeableArtifact.bytecode,
    arguments: [proxyImpl]
  }).encodeABI()

  assert.strictEqual(UpgradeableInitCode, initCode)

  UpgradeableDeployTx = await deployTx(UpgradeableInitCode, 'upgradeable', block.gasLimit - 1)
  UpgradeableDeployReceipt = await parse(UpgradeableDeployTx)
  UpgradeableAddress = UpgradeableDeployReceipt.contractAddress
  if (!UpgradeableDeployReceipt.status) {
    console.log('proxy creation failed.')
    process.exit(1)
  }

  DirectProxy = new web3.eth.Contract(ProxyImplArtifact.abi, UpgradeableAddress)

  console.log('*** call test on direct proxy ***')
  test = await DirectProxy.methods.test().call({
    from: address,
    gas: 5999999
  })
  assert.ok(test)

  Upgradeable = new web3.eth.Contract(UpgradeableArtifact.abi, UpgradeableAddress)

  console.log('*** call admin on direct proxy ***')
  adminAddr = await Upgradeable.methods.admin().call({
    from: address,
    gas: 5999999
  })
  assert.strictEqual(adminAddr, address)

  console.log('*** call isAdmin on Pr000xy for direct proxy ***')
  isAdmin = await Pr000xy.methods.isAdmin(
    DirectProxy.options.address
  ).call({
    from: address,
    gas: 5999999
  })
  assert.strictEqual(isAdmin, false)

  console.log('*** call findProxyCreationAddress on Pr000xy ***')
  addr = await Pr000xy.methods.findProxyCreationAddress(address + '1234').call({
    from: address,
    gas: 5999999
  })
  console.log(addr)

  console.log('*** call createProxy on Pr000xy ***')
  let createProxyData = await Pr000xy.methods.createProxy(
    address + '1234'
  ).encodeABI()
  createProxyTx = await tx(Pr000xyAddress, createProxyData, 'createProxy')
  createProxyReceipt = await parse(createProxyTx)
  if (!createProxyReceipt.status) {
    console.log('call failed.')
    process.exit(1)
  }

  ProxyUpgradeableAddress = '0x' + createProxyReceipt.logs[0].data.slice(26)
  console.log("new proxy:", ProxyUpgradeableAddress)

  initCode = (
    UpgradeableArtifact.bytecode +
    '000000000000000000000000'
    + proxyImpl.slice(-40)
  )

  x = await getCreate2Address(Pr000xyAddress, address + '123400000000000000000000', initCode)
  assert.strictEqual(x, web3.utils.toChecksumAddress(ProxyUpgradeableAddress))

  console.log('*** call balanceOf on Pr000xy for address ***')
  test = await Pr000xy.methods.balanceOf(address).call({
    from: address,
    gas: 5999999
  })
  assert.strictEqual(test, '0')

  UpgradeableNewTwo = new web3.eth.Contract(ProxyImplArtifact.abi, ProxyUpgradeableAddress)

  console.log('*** call test on created proxy ***')
  test = await UpgradeableNewTwo.methods.test().call({
    from: address,
    gas: 5999999
  })
  assert.ok(test)

  UpgradeableNewTwo = new web3.eth.Contract(Pr000xyArtifact.abi, ProxyUpgradeableAddress)

  console.log('*** call admin on created proxy via Pr000xy***')
  canClaim = await Pr000xy.methods.isAdmin(ProxyUpgradeableAddress).call({
    from: address,
    gas: 5999999
  })
  assert.ok(canClaim)

  console.log('*** call getZeroBytes on Pr000xy ***')
  result = await Pr000xy.methods.getZeroBytes(ProxyUpgradeableAddress).call({
    from: address,
    gas: 5999999
  })
  assert.strictEqual(result.leadingZeroBytes, '0')
  assert.strictEqual(result.totalZeroBytes, '0')

  console.log('*** call countProxiesAt on Pr000xy ***')
  count = await Pr000xy.methods.countProxiesAt(result.leadingZeroBytes, result.totalZeroBytes).call({
    from: address,
    gas: 5999999
  })
  assert.strictEqual(count, '1')
  index = count - 1

  console.log('*** claim created proxy via Pr000xy***')
  claimProxyData = await Pr000xy.methods.claimLatestProxy(
    result.leadingZeroBytes,
    result.totalZeroBytes,
    address,
    Pr000xyAddress,
    []
  ).encodeABI()
  claimProxyTx = await tx(Pr000xyAddress, claimProxyData, 'claimLatestProxy')
  claimProxyReceipt = await parse(claimProxyTx)
  if (!claimProxyReceipt.status) {
    console.log('call failed.')
    process.exit(1)
  }

  console.log('*** call admin on claimed proxy ***')
  Upgradeable = new web3.eth.Contract(UpgradeableArtifact.abi, ProxyUpgradeableAddress)

  adminClaimed = await Upgradeable.methods.admin().call({
    from: address,
    gas: 5999999
  })
  assert.strictEqual(adminClaimed, address)

  Upgradeable = new web3.eth.Contract(ProxyImplArtifact.abi, ProxyUpgradeableAddress)

  console.log('*** call test on created proxy ***')
  test = await Upgradeable.methods.test().call({
    from: address,
    gas: 5999999
  })
  assert.ok(test)

  Upgradeable = new web3.eth.Contract(Pr000xyArtifact.abi, ProxyUpgradeableAddress)

  console.log('*** find an address that is worth something ***')
  nonce = 13428446 // 999 optimization runs; 23315132 for 33333 runs
  found = false
  while (!found) {
    nonce += 1
    candidate = await getCreate2Address(
      Pr000xyAddress,
      address + nonce.toString().padEnd(24, '0'),
      initCode
    )
    found = r.test(candidate.slice(-40))
    if (nonce % 10000 === 0) {
      console.log(nonce, candidate.slice(-40))
    }
  }

  console.log('found', nonce, candidate)

  console.log('*** call getZeroBytes on found candidate ***')
  result = await Pr000xy.methods.getZeroBytes(candidate).call({
    from: address,
    gas: 5999999
  })
  console.log(result.leadingZeroBytes, result.totalZeroBytes)

  console.log('*** call getReward using found candidate ***')
  test = await Pr000xy.methods.getReward(candidate).call({
    from: address,
    gas: 5999999
  })
  assert.ok(parseInt(test, 10) > 0)

  console.log('*** call createProxy on Pr000xy for a reward ***')
  logIndex = 0
  createProxyData = '0x00000000' + nonce.toString().padEnd(24, '0')
  createProxyTx = await tx(Pr000xyAddress, createProxyData, 'createProxy')
  createProxyReceipt = await parse(createProxyTx)
  if (!createProxyReceipt.status) {
    console.log('call failed.')
    process.exit(1)
  }

  console.log('*** call balanceOf on Pr000xy for address ***')
  test = await Pr000xy.methods.balanceOf(address).call({
    from: address,
    gas: 5999999
  })
  assert.ok(parseInt(test, 10) > 0)

  ProxyUpgradeableAddress = '0x' + createProxyReceipt.logs[logIndex].data.slice(26)
  console.log("new proxy:", ProxyUpgradeableAddress)

  UpgradeableNewTwo = new web3.eth.Contract(ProxyImplArtifact.abi, ProxyUpgradeableAddress)

  console.log('*** call test on created proxy ***')
  test = await UpgradeableNewTwo.methods.test().call({
    from: address,
    gas: 5999999
  })
  assert.ok(test)

  UpgradeableNewTwo = new web3.eth.Contract(Pr000xyArtifact.abi, ProxyUpgradeableAddress)

  console.log('*** call admin on created proxy via Pr000xy***')
  canClaim = await Pr000xy.methods.isAdmin(ProxyUpgradeableAddress).call({
    from: address,
    gas: 5999999
  })
  assert.ok(canClaim)

  console.log('*** call getValue on Pr000xy ***')
  value = await Pr000xy.methods.getValue(result.leadingZeroBytes, result.totalZeroBytes).call({
    from: address,
    gas: 5999999
  })
  assert.ok(parseInt(value, 10) > 0)

  console.log('*** call countProxiesAt on Pr000xy ***')
  count = await Pr000xy.methods.countProxiesAt(result.leadingZeroBytes, result.totalZeroBytes).call({
    from: address,
    gas: 5999999
  })
  assert.strictEqual(count, '1')
  index = count - 1

  console.log('*** claim created proxy via Pr000xy***')
  claimProxyData = await Pr000xy.methods.claimLatestProxy(
    result.leadingZeroBytes,
    result.totalZeroBytes,
    address,
    Pr000xyAddress,
    []
  ).encodeABI()
  claimProxyTx = await tx(Pr000xyAddress, claimProxyData, 'claimLatestProxy')
  claimProxyReceipt = await parse(claimProxyTx)
  if (!claimProxyReceipt.status) {
    console.log('call failed.')
    process.exit(1)
  }

  console.log('*** call countProxiesAt on Pr000xy ***')
  count = await Pr000xy.methods.countProxiesAt(result.leadingZeroBytes, result.totalZeroBytes).call({
    from: address,
    gas: 5999999
  })
  assert.strictEqual(count, '0')

  console.log('*** call admin on claimed proxy ***')
  Upgradeable = new web3.eth.Contract(UpgradeableArtifact.abi, ProxyUpgradeableAddress)

  adminClaimed = await Upgradeable.methods.admin().call({
    from: address,
    gas: 5999999
  })
  assert.strictEqual(adminClaimed, address)

  Upgradeable = new web3.eth.Contract(ProxyImplArtifact.abi, ProxyUpgradeableAddress)

  console.log('*** call test on created proxy ***')
  test = await Upgradeable.methods.test().call({
    from: address,
    gas: 5999999
  })
  assert.ok(test)

  console.log('*** call makeOffer on Pr000xy ***')
  searchSpace = '0x3110000000000000000000000000000000000000'
  target = web3.utils.toChecksumAddress(
    '0xf000000000000000000000000000000000000000'
  )
  makeOfferData = await Pr000xy.methods.makeOffer(
    searchSpace, target, address
  ).encodeABI()
  makeOfferTx = await tx(Pr000xyAddress, makeOfferData, 'makeOffer', 1)
  makeOfferReceipt = await parse(makeOfferTx)
  if (makeOfferReceipt.status) {
    offerID = makeOfferReceipt.logs[0].topics[1]
    console.log(`offer made (ID: ${offerID}).`)
  } else {
    console.log('offer failed.')
    process.exit(1)
  }

  console.log('*** find an address that can match the offer ***')
  nonce = 0
  found = false
  while (!found) {
    nonce += 1
    candidate = await getCreate2Address(
      Pr000xyAddress,
      address + nonce.toString().padEnd(24, '0'),
      initCode
    )

    found = match(candidate, searchSpace, target)
    if (nonce % 10000 === 0) {
      console.log(nonce, candidate)
    }
  }

  console.log('found', nonce, candidate)

  console.log('*** call createAndMatch on Pr000xy ***')
  createAndMatchData = await Pr000xy.methods.createAndMatch(
    address + nonce.toString().padEnd(24, '0'), offerID
  ).encodeABI()
  createAndMatchTx = await tx(Pr000xyAddress, createAndMatchData, 'createAndMatch')
  createAndMatchReceipt = await parse(createAndMatchTx)
  if (createAndMatchReceipt.status) {
    offerID = makeOfferReceipt.logs[0].topics[1]
    console.log(`contract created and matched with offer.`)
  } else {
    console.log('match failed.')
    process.exit(1)
  }

  console.log('*** deploy Create2Factory contract ***')
  const Create2FactoryDeployer = new web3.eth.Contract(Create2FactoryArtifact.abi)
  const Create2FactoryInitCode = await Create2FactoryDeployer.deploy({
    data: Create2FactoryArtifact.bytecode
  }).encodeABI()
  Pr000xyRewardsDeployTx = await deployTx(Create2FactoryInitCode, 'Create2Factory', block.gasLimit - 1)
  Pr000xyRewardsDeployReceipt = await parse(Pr000xyRewardsDeployTx)
  Create2FactoryAddress = Pr000xyRewardsDeployReceipt.contractAddress
  console.log(
    `Create2Factory deployment ${
      Pr000xyRewardsDeployReceipt.status ? 'succeeded' : 'failed'
    } - ${
      Pr000xyRewardsDeployReceipt.gasUsed
    } gas used. Address: ${Create2FactoryAddress}`
  )

  Upgradeable = new web3.eth.Contract(Create2FactoryArtifact.abi, Create2FactoryAddress)

  console.log('*** call findCreate2Address ***')
  test = await Upgradeable.methods.findCreate2Address(
    address + '12345'.padEnd(24, '0'),
    web3.utils.keccak256(web3.utils.hexToBytes('0x3838533838f3'))
  ).call({
    from: address,
    gas: 5999999
  })
  console.log(test)

  console.log('*** create a contract***')
  claimProxyData = await Upgradeable.methods.callCreate2(
    address + '12345'.padEnd(24, '0'),
    '0x3838533838f3'
  ).encodeABI()

  claimProxyTx = await tx(Create2FactoryAddress, claimProxyData, 'callCreate2')
  claimProxyReceipt = await parse(claimProxyTx)
  if (!claimProxyReceipt.status) {
    console.log('call failed.')
    console.log(claimProxyReceipt)
    process.exit(1)
  }

  console.log('*** call findCreate2Address (now returns 0x0) ***')
  test = await Upgradeable.methods.findCreate2Address(
    address + '12345'.padEnd(24, '0'),
    web3.utils.keccak256(web3.utils.hexToBytes('0x3838533838f3'))
  ).call({
    from: address,
    gas: 5999999
  })
  assert.strictEqual(test, nullAddress)

  console.log('*** call findCreate2Address for Pr000xy + constructor args ***')
  test = await Upgradeable.methods.findCreate2Address(
    address + '7e6f238fff8300000026bc72',
    web3.utils.keccak256(web3.utils.hexToBytes(Pr000xyInitCode))
  ).call({
    from: address,
    gas: 5999999
  })
  //assert.strictEqual(test, '0x000000a2435649d8919d2a1C5eDa59481Ce84838')

  console.log('*** create a Pr000xy contract instance via Create2Factory ***')
  claimProxyData = await Upgradeable.methods.callCreate2(
    address + '7e6f238fff8300000026bc72',
    Pr000xyInitCode
  ).encodeABI()

  claimProxyTx = await tx(Create2FactoryAddress, claimProxyData, 'callCreate2')
  claimProxyReceipt = await parse(claimProxyTx)
  if (!claimProxyReceipt.status) {
    console.log('call failed.')
    process.exit(1)
  }
  
  Pr000xyCreate2 = new web3.eth.Contract(Pr000xyArtifact.abi, test)

  console.log('*** call initialize on Pr000xy ***')
  initializeData = await Pr000xyCreate2.methods.initialize().encodeABI()
  initializeTx = await tx(Pr000xyCreate2.options.address, initializeData, 'initialize')
  initializeReceipt = await parse(initializeTx)
  console.log(
    `Call to initialize() on Create2Factory Pr000xy ${
      initializeReceipt.status ? 'succeeded' : 'failed'
    } - ${
      initializeReceipt.gasUsed
    } gas used.`
  )

  console.log('*** call initialized on Create2Factory Pr000xy ***')
  test = await Pr000xyCreate2.methods.initialized().call({
    from: address,
    gas: 5999999
  })
  assert.ok(test)

  console.log('*** call batchCreate on Pr000xy ***')
  createProxyData = await Pr000xy.methods.batchCreate([
    address + (11111111).toString().padEnd(24, '0'),
    address + (22222222).toString().padEnd(24, '0'),
    address + (33333333).toString().padEnd(24, '0'),
    address + (44444444).toString().padEnd(24, '0')
  ]).encodeABI()
  createProxyTx = await tx(Pr000xyAddress, createProxyData, 'createBatch')
  createProxyReceipt = await parse(createProxyTx)
  if (!createProxyReceipt.status) {
    console.log('call failed.')
    process.exit(1)
  } 

  console.log('*** call batchCreateEfficient on Pr000xy ***')
  createProxyData = await Pr000xy.methods.batchCreateEfficient_H6KNX6().encodeABI()
  createProxyTx = await tx(Pr000xyAddress, createProxyData, 'createBatch')
  createProxyReceipt = await parse(createProxyTx)
  if (!createProxyReceipt.status) {
    console.log('call failed.')
    process.exit(1)
  }  

  console.log('*** call batchCreateEfficient on Pr000xy using raw tx ***')
  createProxyData = 
    '0x00000000' +
    '111111111111111111111111' +
    '222222222222222222222222' +
    '333333333333333333333333' +
    '444444444444444444444444'
  createProxyTx = await tx(Pr000xyAddress, createProxyData, 'batchCreateEfficient')
  createProxyReceipt = await parse(createProxyTx)
  if (!createProxyReceipt.status) {
    console.log('call failed.')
    process.exit(1)
  }  
  

  return 0
}}
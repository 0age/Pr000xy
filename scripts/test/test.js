var assert = require('assert')
var fs = require('fs')
var util = require('ethereumjs-util')

const Pr000xyArtifact = require('../../build/contracts/Pr000xy.json')
const Pr000xyRewardsArtifact = require('../../build/contracts/Pr000xyRewards.json')
const UpgradeableArtifact = require('../../build/contracts/AdminUpgradeabilityProxy.json')
const ProxyImplementationArtifact = require('../../build/contracts/InitialProxyImplementation.json')
const InitializeableImplementationArtifact = require('../../build/contracts/InitializeableImplementation.json')
const Create2FactoryArtifact = require('../../build/contracts/Create2Factory.json')

module.exports = {test: async function (provider, testingContext) {
  var web3 = provider
  let passed = 0
  let failed = 0
  let gasUsage = {}
  console.log('running tests...')

  // get available addresses and assign them to various roles
  const addresses = await web3.eth.getAccounts()
  if (addresses.length < 1) {
    console.log('cannot find enough addresses to run tests!')
    process.exit(1)
  }

  let address = addresses[0]
  const originalAddress = addresses[0]

  async function send(
    title,
    instance,
    method,
    args,
    from,
    value,
    gas,
    gasPrice,
    shouldSucceed,
    assertionCallback
  ) {
    let succeeded = true
    receipt = await instance.methods[method](...args).send({
      from: from,
      value: value,
      gas: gas,
      gasPrice: gasPrice
    }).catch(error => {
      //console.error(error)
      succeeded = false
    })

    if (succeeded !== shouldSucceed) {
      return false
    } else if (!shouldSucceed) {
      return true
    }

    assert.ok(receipt.status)

    let assertionsPassed
    try {
      assertionCallback(receipt)
      assertionsPassed = true
    } catch(error) {
      assertionsPassed = false
    }

    return assertionsPassed
  }

  async function call(
    title,
    instance,
    method,
    args,
    from,
    value,
    gas,
    gasPrice,
    shouldSucceed,
    assertionCallback
  ) {
    let succeeded = true
    returnValues = await instance.methods[method](...args).call({
      from: from,
      value: value,
      gas: gas,
      gasPrice: gasPrice
    }).catch(error => {
      //console.error(error)
      succeeded = false
    })

    if (succeeded !== shouldSucceed) {
      return false
    } else if (!shouldSucceed) {
      return true
    }

    let assertionsPassed
    try {
      assertionCallback(returnValues)
      assertionsPassed = true
    } catch(error) {
      assertionsPassed = false
    }

    return assertionsPassed
  }

  async function runTest(
    title,
    instance,
    method,
    callOrSend,
    args,
    shouldSucceed,
    assertionCallback,
    from,
    value
  ) {
    if (typeof(callOrSend) === 'undefined') {
      callOrSend = 'send'
    }
    if (typeof(args) === 'undefined') {
      args = []
    }
    if (typeof(shouldSucceed) === 'undefined') {
      shouldSucceed = true
    }
    if (typeof(assertionCallback) === 'undefined') {
      assertionCallback = (value) => {}
    }
    if (typeof(from) === 'undefined') {
      from = address
    }
    if (typeof(value) === 'undefined') {
      value = 0
    }
    let ok = false
    if (callOrSend === 'send') {
      ok = await send(
        title,
        instance,
        method,
        args,
        from,
        value,
        gasLimit - 1,
        10 ** 1,
        shouldSucceed,
        assertionCallback
      )
    } else if (callOrSend === 'call') {
      ok = await call(
        title,
        instance,
        method,
        args,
        from,
        value,
        gasLimit - 1,
        10 ** 1,
        shouldSucceed,
        assertionCallback
      )
    } else {
      console.error('must use call or send!')
      process.exit(1)
    }

    if (ok) {
      console.log(` ✓ ${title}`)
      passed++
    } else {
      console.log(` ✘ ${title}`)
      failed++
    }
  }

  function getCreate2Address(sender, salt, initCode) {
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

  async function setupNewDefaultAddress(newPrivateKey) {
    const pubKey = await web3.eth.accounts.privateKeyToAccount(newPrivateKey)
    await web3.eth.accounts.wallet.add(pubKey)

    const txCount = await web3.eth.getTransactionCount(pubKey.address)

    if (txCount > 0) {
      console.warn(
        `warning: ${pubKey.address} has already been used, which may cause ` +
        'some tests to fail.'
      )
    }

    await web3.eth.sendTransaction({
      from: originalAddress,
      to: pubKey.address,
      value: 10 ** 18,
      gas: '0x5208',
      gasPrice: '0x4A817C800'
    })
    address = pubKey.address
  }

  async function raiseGasLimit(necessaryGas) {
    iterations = 9999
    if (necessaryGas > 8000000) {
      console.error('the gas needed is too high!')
      process.exit(1)
    } else if (typeof necessaryGas === 'undefined') {
      iterations = 20
      necessaryGas = 8000000
    }

    // bring up gas limit if necessary by doing additional transactions
    var block = await web3.eth.getBlock("latest");
    while (iterations > 0 && block.gasLimit < necessaryGas) {
      await web3.eth.sendTransaction({
        from: originalAddress,
        to: originalAddress,
        value: '0x01',
        gas: '0x5208',
        gasPrice: '0x4A817C800'
      })
      var block = await web3.eth.getBlock("latest");
      iterations--
    }

    console.log("raising gasLimit, currently at " + block.gasLimit);
    return block.gasLimit
  }

  async function getDeployGas(dataPayload) {
    await web3.eth.estimateGas({
      from: address,
      data: dataPayload
    }).catch(async error => {
      if (
        error.message === (
          'Returned error: gas required exceeds allowance or always failing ' +
          'transaction'
        )
      ) {
        await raiseGasLimit()
        await getDeployGas(dataPayload)
      }
    })

    deployGas = await web3.eth.estimateGas({
      from: address,
      data: dataPayload
    })

    return deployGas
  }

  function validateCreatedProxy(salt, receipt) {
    const expectedProxyAddress = getCreate2Address(
      Pr000xy.options.address,
      salt,
      proxyInitializationCode
    )

    const expectedProxyValue = getReward(getZeroes(expectedProxyAddress))

    const logs = receipt.events.ProxyCreated.returnValues
    assert.strictEqual(logs.proxy, expectedProxyAddress)
    assert.strictEqual(logs.creator, address)
    assert.strictEqual(logs.value, expectedProxyValue)

    if (expectedProxyValue === '0') {
      assert.strictEqual(typeof receipt.events.Transfer, 'undefined')
    } else {
      const transferLogs = receipt.events.Transfer.returnValues
      assert.strictEqual(transferLogs.from, nullAddress)
      assert.strictEqual(transferLogs.to, address)
      assert.strictEqual(transferLogs.value, expectedProxyValue)
    }
  }

  function validateClaimedProxy(proxy, receipt) {
    const expectedProxyValue = getReward(getZeroes(proxy))

    const logs = receipt.events.ProxyClaimed.returnValues
    assert.strictEqual(logs.proxy, proxy)
    assert.strictEqual(logs.claimant, address)
    assert.strictEqual(logs.value, expectedProxyValue)

    if (expectedProxyValue === '0') {
      assert.strictEqual(typeof receipt.events.Transfer, 'undefined')
    } else {
      const transferLogs = receipt.events.Transfer.returnValues
      assert.strictEqual(transferLogs.to, nullAddress)
      assert.strictEqual(transferLogs.from, address)
      assert.strictEqual(transferLogs.value, expectedProxyValue)
    }

    const adminChangedEventSig = (
      web3.utils.keccak256("AdminChanged(address,address)")
    )

    assert.strictEqual(receipt.events[0].raw.topics[0], adminChangedEventSig)

    // event AdminChanged(address previousAdmin, address newAdmin);
    const adminChangedEvent = web3.eth.abi.decodeLog(
      [
        {
          name: 'previousAdmin',
          type: 'address'
        }, {
          name: 'newAdmin',
          type: 'address'
        }
      ],
      receipt.events[0].raw.data,
      []
    )

    assert.strictEqual(adminChangedEvent.previousAdmin, Pr000xy.options.address)
    assert.strictEqual(adminChangedEvent.newAdmin, address)
  }

  function getZeroes(account) {
    total = 0
    leading = 0

    // designate a flag that will be flipped once leading zero bytes are found.
    searchingForLeadingZeroBytes = true;

    // iterate through each byte of the address and count the zero bytes found.
    for (i = 2; i < 42; i = i + 2) {
      if (account[i] + account[i + 1] == '00') {
        total++; // increment the total value if the byte is equal to 0x00.
      } else if (searchingForLeadingZeroBytes) {
        leading = (i - 2) / 2; // set leading value upon reaching non-zero byte.
        searchingForLeadingZeroBytes = false; // stop search upon finding value.
      }
    }

    // special handling for the null address.
    if (total == 20) {
      leading = 20;
    }

    return [leading, total]
  }

  function getReward(zeroes) {
    leading = zeroes[0]
    total = zeroes[1]

    rewards = {
      '5': '4',
      '6': '454',
      '7': '57926',
      '8': '9100294',
      '9': '1742029446',
      '10': '404137334455',
      '11': '113431422629339',
      '12': '38587085346610622',
      '13': '15996770875963838293',
      '14': '8161556895428437076912',
      '15': '5204779792920449185083823',
      '16': '4248387252809145069797255323',
      '17': '4605429522902726696350853424531',
      '18': '7048004537575756103097351214228445',
      '19': '17077491850962604714099960694478075305',
      '25': '18',
      '26': '1510',
      '27': '165350',
      '28': '22735825',
      '29': '3869316742',
      '30': '807985948644',
      '31': '206183716874451',
      '32': '64298858504764852',
      '33': '24606700946514329477',
      '34': '11658059615639150243674',
      '35': '6939139116010292965409030',
      '36': '5310177709695884701197848448',
      '37': '5417944041740025730272641342830',
      '38': '7830936568539684766699669978646642',
      '39': '17976121735815156138387102662511898913',
      '44': '2',
      '45': '84',
      '46': '5728',
      '47': '522972',
      '48': '61659518',
      '49': '9184107994',
      '50': '1705003336895',
      '51': '391623153514096',
      '52': '111035232373186089',
      '53': '38953746656818437996',
      '54': '17036497937743417006573',
      '55': '9416523284246997364709332',
      '56': '6725785327750463676116311208',
      '57': '6433530232804950076993156196671',
      '58': '8751998904874491998186743074190073',
      '59': '18974577637063874242348921695171566572',
      '63': '1',
      '64': '16',
      '65': '501',
      '66': '25706',
      '67': '1879489',
      '68': '184770685',
      '69': '23598039458',
      '70': '3834163535637',
      '71': '782938604015677',
      '72': '199806334259175276',
      '73': '63729223611100778985',
      '74': '25550889257134282768770',
      '75': '13036857507600936595914846',
      '76': '8646792118767830540030515565',
      '77': '7719857784103882545156250250796',
      '78': '9845714873472744513017103980332671',
      '79': '20090471847730684189719534018111776322',
      '84': '256',
      '85': '4217',
      '86': '144997',
      '87': '7967408',
      '88': '627232017',
      '89': '66792260819',
      '90': '9305004719113',
      '91': '1662927453401532',
      '92': '377280206974005998',
      '93': '108312611697003383786',
      '94': '39480692955577390009145',
      '95': '18466558683234331672667696',
      '96': '11306368626474766596196174270',
      '97': '9373587789723760876051759069103',
      '98': '11158112222962749668746090824795165',
      '99': '21345818655172812214316074369647797631',
      '105': '65536',
      '106': '1149384',
      '107': '42311994',
      '108': '2503009344',
      '109': '213427112297',
      '110': '24790124569401',
      '111': '3798576841874147',
      '112': '754231113879134009',
      '113': '192496950430879408810',
      '114': '63155584261947917379593',
      '115': '26856456513120542636583476',
      '116': '15073641750015138940509892079',
      '117': '11535977580589283558152309456824',
      '118': '12751652018255015903154966566038849',
      '119': '22768501289012087466446392969820350793',
      '126': '16777216',
      '127': '314649014',
      '128': '12465892329',
      '129': '798621491520',
      '130': '74272940112557',
      '131': '9488446269991021',
      '132': '1615302625848366483',
      '133': '360793996621274970151',
      '134': '105231762185667073323510',
      '135': '40277499209379064589210374',
      '136': '20552522428100944971108965855',
      '137': '14418884344710441156786200615788',
      '138': '14712810623981817234669488026294327',
      '139': '24394367384979066549040576729916735405',
      '147': '4294967296',
      '148': '86578212486',
      '149': '3713485713636',
      '150': '259444579476332',
      '151': '26536334094930946',
      '152': '3766219523861070771',
      '153': '721233811714863908602',
      '154': '184095343314545289307447',
      '155': '62640228392039477591429356',
      '156': '28769426614997062585251169958',
      '157': '18349671535208654280022928803766',
      '158': '17164082814922458575890189696960250',
      '159': '26270291294258216720936037244430839003',
      '168': '1099511627776',
      '169': '23964464223668',
      '170': '1120582017742425',
      '171': '86090644707729148',
      '172': '9781914561024998962',
      '173': '1561650570729335220208',
      '174': '341747557162857934539820',
      '175': '101762631449317943805391008',
      '176': '41548592731868112513336784332',
      '177': '23852021372062826058224022750488',
      '178': '20283619999520397681386221215474723',
      '179': '28458767047291815304352793042317106218',
      '189': '281474976710656',
      '190': '6679635020504935',
      '191': '343348968927242275',
      '192': '29299651301902406699',
      '193': '3744527648085709786177',
      '194': '683111829267922829815475',
      '195': '174389101583031582235029592',
      '196': '62309305812704133847182785129',
      '197': '31798537455673449566787122847131',
      '198': '24338608729695493646905227621216324',
      '199': '31045005677747771435004953493418625136',
      '210': '72057594037927936',
      '211': '1877332990277416666',
      '212': '107151043349371744458',
      '213': '10283303505204142788147',
      '214': '1501666268767778355745184',
      '215': '319563996343164377392648004',
      '216': '97887186140032477917162659539',
      '217': '43715844026074104250142609225871',
      '218': '29744596511106126675202002373267873',
      '219': '34148289271564189198990160526277013772',
      '231': '18446744073709551616',
      '232': '532959419305417460751',
      '233': '34199245650990087306275',
      '234': '3749746141559948245944138',
      '235': '638710029020633448795855198',
      '236': '163084358451243040745529676767',
      '237': '62438084943177950193287569739764',
      '238': '37176696243831180424780470563509268',
      '239': '37940891085261431466299607797270323229',
      '252': '4722366482869645213696',
      '253': '153193891968249828851470',
      '254': '11227181263850205045367657',
      '255': '1435688191035029671162366337',
      '256': '293398319948847143266500005656',
      '257': '93630892949291171900768956557205',
      '258': '47791916641892757471645121003221337',
      '259': '42681178800470478513779470603886654646',
      '273': '1208925819614629174706176',
      '274': '44732959070623750795478391',
      '275': '3822247790422955620553331984',
      '276': '586336408451091794686883885323',
      '277': '149750686574114300529965478692459',
      '278': '63710659778031659693093889760656253',
      '279': '48775076109608200809979786955505409929',
      '294': '309485009821345068724781056',
      '295': '13334234657309393827615911462',
      '296': '1366330837671149190637746723640',
      '297': '261909596987600478890300387369290',
      '298': '89171615213500834928461796224542241',
      '299': '56898945742495262342667471915436095449',
      '315': '79228162514264337593543950336',
      '316': '4088297221333277495599464183220',
      '317': '523306049315415466265913015411891',
      '318': '133705003225903872825679864660094397',
      '319': '68269816560940632168200548199477007941',
      '336': '20282409603651670423947251286016',
      '337': '1305704925411524904272035688089603',
      '338': '222696176178091542181357768092554566',
      '339': '85320554291635892895811850639111324322',
      '357': '5192296858534827628530496329220096',
      '358': '444811280231209229153363695561872448',
      '359': '113723610876971601366349738253959088946',
      '378': '1329227995784915872903807060280344576',
      '379': '170474140766654103026661251472666657794',
      '399': '340282366920938463463374607431768211456',
      '420': '87112285931760246646623899502532662132736'
    }

    // designate a flag that will be flipped once leading zero bytes are found.
    searchingForLeadingZeroBytes = true;

    reward = rewards[(leading * 20 + total).toString()]
    if (typeof reward === 'undefined') {
      reward = '0'
    }

    return reward
  }

  // *************************** deploy contracts *************************** //
  setupNewDefaultAddress(
    '0xfeedfeedfeedfeedfeedfeedfeedfeedfeedfeedfeedfeedfeedfeedfeedfeed'
  )

  let deployGas;
  let dataPayload;
  let latestBlock = await web3.eth.getBlock('latest')
  const gasLimit = latestBlock.gasLimit

  const Pr000xyRewardsDeployer = new web3.eth.Contract(
    Pr000xyRewardsArtifact.abi
  )

  dataPayload = Pr000xyRewardsDeployer.deploy({
    data: Pr000xyRewardsArtifact.bytecode
  }).encodeABI()

  deployGas = await getDeployGas(dataPayload)

  const Pr000xyRewards = await Pr000xyRewardsDeployer.deploy({
    data: Pr000xyRewardsArtifact.bytecode
  }).send({
    from: address,
    gas: deployGas,
    gasPrice: 10 ** 1
  }).catch(error => {
    console.error(error)
    console.log(
      ` ✘ Pr000xyRewards contract deploys successfully for ${deployGas} gas`
    )
    failed++
    process.exit(1)
  })

  console.log(
    ` ✓ Pr000xyRewards contract deploys successfully for ${deployGas} gas`
  )
  passed++

  const Pr000xyDeployer = new web3.eth.Contract(Pr000xyArtifact.abi)

  dataPayload = Pr000xyDeployer.deploy({
    data: Pr000xyArtifact.bytecode,
    arguments: [
      Pr000xyRewards.options.address,
      UpgradeableArtifact.bytecode
    ]
  }).encodeABI()

  deployGas = await getDeployGas(dataPayload)

  const Pr000xy = await Pr000xyDeployer.deploy({
    data: Pr000xyArtifact.bytecode,
    arguments: [
      Pr000xyRewards.options.address,
      UpgradeableArtifact.bytecode
    ]
  }).send({
    from: address,
    gas: deployGas,
    gasPrice: 10 ** 1
  }).catch(error => {
    console.error(error)
    console.log(
      ` ✘ Pr000xy contract deploys successfully for ${deployGas} gas`
    )
    failed++
    process.exit(1)
  })

  console.log(
    ` ✓ Pr000xy contract deploys successfully for ${deployGas} gas`
  )
  passed++

  //code = await web3.eth.getCode(Pr000xy.options.address)
  //console.log(code)

  const InitializeableImplementationDeployer = new web3.eth.Contract(InitializeableImplementationArtifact.abi)

  dataPayload = InitializeableImplementationDeployer.deploy({
    data: InitializeableImplementationArtifact.bytecode
  }).encodeABI()

  deployGas = await getDeployGas(dataPayload)

  const InitializeableImplementation = await InitializeableImplementationDeployer.deploy({
    data: InitializeableImplementationArtifact.bytecode
  }).send({
    from: address,
    gas: deployGas,
    gasPrice: 10 ** 1
  }).catch(error => {
    console.error(error)
    console.log(
      ` ✘ Initializeable Implementation contract deploys successfully for ${deployGas} gas`
    )
    failed++
    process.exit(1)
  })

  console.log(
    ` ✓ Initializeable Implementation contract deploys successfully for ${deployGas} gas`
  )
  passed++

  // ****************** initialize and validate contracts ******************* //

  const nullAddress = '0x0000000000000000000000000000000000000000'
  const oneAddress = '0x0000001010101010101010101010101010101010'
  const badAddress = '0xbAd00BAD00BAD00bAD00bAD00bAd00BaD00bAD00'
  r = new RegExp("^0{6}|^0{4}((.{2})*(00)){2}|^((.{2})*(00)){5}")
  if (!r.test(oneAddress.slice(-40))) {
    console.error('regex check not working.')
    process.exit(1)
  }

  await runTest(
    'Pr000xy can be initialized',
    Pr000xy,
    'initialize'
  )

  await runTest(
    'Pr000xy initialization status check returns true',
    Pr000xy,
    'initialized',
    'call',
    [],
    true,
    isInitialized => {
      assert.strictEqual(isInitialized, true)
    }
  )

  await runTest(
    'Pr000xy initialization fails once already initialized',
    Pr000xy,
    'initialize',
    'send',
    [],
    false
  )

  let initialImplementationAddress; 
  await runTest(
    'initial implementation of logic contract for proxies is deployed',
    Pr000xy,
    'getInitialProxyImplementation',
    'call',
    [],
    true,
    implementationAddress => {
      initialImplementationAddress = implementationAddress
    }
  )

  InitialImplementation = new web3.eth.Contract(
    ProxyImplementationArtifact.abi,
    initialImplementationAddress
  )

  const proxyInitializationCode = (
    UpgradeableArtifact.bytecode +
    initialImplementationAddress
      .slice(-40)
      .padStart(64, '0')
      .toLowerCase()
  )

  await runTest(
    'the contract initialization code for creating proxies can be retrieved',
    Pr000xy,
    'getProxyInitializationCode',
    'call',
    [],
    true,
    initializationCode => {
      assert.strictEqual(
        proxyInitializationCode,
        initializationCode
      )
    }
  )

  const proxyInitializationCodeHash = (
    web3.utils.keccak256(proxyInitializationCode)
  )

  await runTest(
    'the keccak256 hash of the contract initialization code can be retrieved',
    Pr000xy,
    'getProxyInitializationCodeHash',
    'call',
    [],
    true,
    initializationCodeHash => {
      assert.strictEqual(proxyInitializationCodeHash, initializationCodeHash)
    }
  )

  await runTest(
    'total Pr000xy token supply starts at 0',
    Pr000xy,
    'totalSupply',
    'call',
    [],
    true,
    totalSupply => {
      assert.strictEqual(totalSupply, '0')
    }
  )

  await runTest(
    'Pr000xy token balance at address of contract creator starts at 0',
    Pr000xy,
    'balanceOf',
    'call',
    [address],
    true,
    balance => {
      assert.strictEqual(balance, '0')
    }
  )

  await runTest(
    'the proper token value of a given account can be retrieved',
    Pr000xy,
    'getReward',
    'call',
    [oneAddress],
    true,
    reward => {
      assert.strictEqual(reward, '1')
      assert.strictEqual(reward, getReward(getZeroes(oneAddress)))
    }
  )

  let salt = address + '00abcdef'.padEnd(24, '0')
  let expectedProxyAddress = getCreate2Address(
    Pr000xy.options.address,
    salt,
    proxyInitializationCode
  )

  await runTest(
    'the address of the proxy resulting from a given salt can be retrieved',
    Pr000xy,
    'findProxyCreationAddress',
    'call',
    [salt],
    true,
    proxy => {
      assert.strictEqual(proxy, expectedProxyAddress)
    }
  )

  await runTest(
    'the proper token value of the expected proxy address can be retrieved',
    Pr000xy,
    'getReward',
    'call',
    [expectedProxyAddress],
    true,
    reward => {
      assert.strictEqual(reward, '0')
    }
  )

  await runTest(
    'proxies creation fails if salt does not start with address of submitter',
    Pr000xy,
    'createProxy',
    'send',
    [oneAddress + '00abcdef'.padEnd(24, '0')],
    false
  )

  await runTest(
    'proxies can be created via createProxy',
    Pr000xy,
    'createProxy',
    'send',
    [salt],
    true,
    receipt => {
      validateCreatedProxy(salt, receipt)
    }
  )

  await runTest(
    'checks for address of the proxy resulting from the salt now return 0',
    Pr000xy,
    'findProxyCreationAddress',
    'call',
    [salt],
    true,
    proxy => {
      assert.strictEqual(proxy, nullAddress)
    }
  )

  let zeroes = getZeroes(expectedProxyAddress)

  await runTest(
    'total proxy count is incremented correctly',
    Pr000xy,
    'countProxiesAt',
    'call',
    zeroes,
    true,
    total => {
      assert.strictEqual(total, '1')
    }
  )

  await runTest(
    'proxy address can be retrieved by zeroes and index',
    Pr000xy,
    'getProxyAt',
    'call',
    zeroes.concat(0),
    true,
    address => {
      assert.strictEqual(address, expectedProxyAddress)
    }
  )

  await runTest(
    'a proxy address cannot be retrieved at an out-of-bounds index',
    Pr000xy,
    'getProxyAt',
    'call',
    zeroes.concat(1),
    false
  )  

  await runTest(
    'the created proxy is initially owned by the contract',
    Pr000xy,
    'isAdmin',
    'call',
    [expectedProxyAddress],
    true,
    isAdmin => {
      assert.ok(isAdmin)
    }
  )

  InitialProxyImplementation = new web3.eth.Contract(
    ProxyImplementationArtifact.abi,
    expectedProxyAddress
  )

  await runTest(
    'call to test on new proxy works',
    InitialProxyImplementation,
    'test',
    'call',
    [],
    true,
    yes => {
      assert.ok(yes)
    }
  )

  UpgradeableProxyImplementation = new web3.eth.Contract(
    UpgradeableArtifact.abi,
    expectedProxyAddress
  )

  await runTest(
    'call to admin on new proxy fails (not calling from admin address)',
    UpgradeableProxyImplementation,
    'admin',
    'call',
    [],
    false
  )

  await runTest(
    'call to upgradeTo on new proxy fails (not calling from admin)',
    UpgradeableProxyImplementation,
    'upgradeTo',
    'send',
    [Pr000xyRewards.options.address],
    false
  )

  await runTest(
    'call to upgradeToAndCall on new proxy fails (not calling from admin)',
    UpgradeableProxyImplementation,
    'upgradeToAndCall',
    'send',
    [InitializeableImplementation.options.address, '0x8129fc1c'],
    false
  )

  await runTest(
    'call to changeAdmin on new proxy fails (not calling from admin)',
    UpgradeableProxyImplementation,
    'changeAdmin',
    'send',
    [oneAddress],
    false
  )

  await runTest(
    'trying to reuse an already-used salt to create a proxy fails',
    Pr000xy,
    'createProxy',
    'send',
    [salt],
    false
  )

  await runTest(
    'trying to claim a proxy that does not exist fails',
    Pr000xy,
    'claimProxy',
    'send',
    [
      badAddress,
      nullAddress,
      nullAddress,
      '0x'
    ],
    false
  )

  await runTest(
    'trying to claim a proxy with implementation that is not a contract fails',
    Pr000xy,
    'claimProxy',
    'send',
    [
      expectedProxyAddress,
      nullAddress,
      badAddress,
      '0x'
    ],
    false
  )

  await runTest(
    'proxies can be claimed',
    Pr000xy,
    'claimProxy',
    'send',
    [
      expectedProxyAddress,
      nullAddress,
      nullAddress,
      '0x'
    ],
    true,
    receipt => {
      validateClaimedProxy(expectedProxyAddress, receipt)
    }
  )

  await runTest(
    'the claimed proxy is no longer owned by the contract',
    Pr000xy,
    'isAdmin',
    'call',
    [expectedProxyAddress],
    true,
    isAdmin => {
      assert.strictEqual(isAdmin, false)
    }
  )

  await runTest(
    'call to test on new proxy works if no new implementation is set',
    InitialProxyImplementation,
    'test',
    'call',
    [],
    true,
    yes => {
      assert.ok(yes)
    },
    originalAddress // Cannot call fallback function from the proxy admin
  )

  await runTest(
    'call to admin on new proxy succeeds when calling from admin address',
    UpgradeableProxyImplementation,
    'admin',
    'call',
    [],
    true,
    admin => {
      assert.strictEqual(admin, address)
    }    
  )

  await runTest(
    'call to upgradeTo fails if the implementation is not a contract',
    UpgradeableProxyImplementation,
    'upgradeTo',
    'send',
    [badAddress],
    false
  )

  InitializeableProxyImplementation = new web3.eth.Contract(
    InitializeableImplementationArtifact.abi,
    expectedProxyAddress
  )

  await runTest(
    'call to initialized on new proxy fails prior to calling upgradeTo',
    InitializeableProxyImplementation,
    'initialized',
    'call',
    [],
    false,
    {},
    originalAddress // Cannot call fallback function from the proxy admin
  )  

  await runTest(
    'call to upgradeTo on new proxy succeeds when calling from admin',
    UpgradeableProxyImplementation,
    'upgradeTo',
    'send',
    [
      InitializeableImplementation.options.address
    ],
    true,
    receipt => {
      assert.strictEqual(
        receipt.events.Upgraded.returnValues.implementation,
        InitializeableImplementation.options.address
      )
    }
  )

  await runTest(
    'call to initialized (fallback) on new proxy fails when called from admin',
    InitializeableProxyImplementation,
    'initialized',
    'send', // web3 bug with send?
    [],
    false
  )

  await runTest(
    'call to initialized on new proxy does not yet return true after upgradeTo',
    InitializeableProxyImplementation,
    'initialized',
    'call',
    [],
    true,
    initialized => {
      assert.strictEqual(initialized, false)
    },
    originalAddress // Cannot call fallback function from the proxy admin
  )

  await runTest(
    'call to upgradeToAndCall on new proxy succeeds when calling from admin',
    UpgradeableProxyImplementation,
    'upgradeToAndCall',
    'send',
    [
      InitializeableImplementation.options.address,
      web3.utils.keccak256("initialize()")
    ],
    true,
    receipt => {
      assert.strictEqual(
        receipt.events.Upgraded.returnValues.implementation,
        InitializeableImplementation.options.address
      )
    }
  )

  await runTest(
    'call to initialized on new proxy succeeds after upgradeToAndCall',
    InitializeableProxyImplementation,
    'initialized',
    'call',
    [],
    true,
    initialized => {
      assert.ok(initialized)
    },
    originalAddress // Cannot call fallback function from the proxy admin
  )

  await runTest(
    'call to test on new proxy fails once the new implementation is set',
    InitialProxyImplementation,
    'test',
    'call',
    [],
    false,
    {},
    originalAddress // Cannot call fallback function from the proxy admin
  )

  await runTest(
    'call to changeAdmin on new proxy succeeds when calling from admin',
    UpgradeableProxyImplementation,
    'changeAdmin',
    'send',
    [oneAddress]
  )

  await runTest(
    'call to admin on new proxy now fails (not calling from admin address)',
    UpgradeableProxyImplementation,
    'admin',
    'call',
    [],
    false
  )

  await runTest(
    'call to upgradeTo on new proxy now fails (not calling from admin)',
    UpgradeableProxyImplementation,
    'upgradeTo',
    'send',
    [Pr000xyRewards.options.address],
    false
  )

  await runTest(
    'call to upgradeToAndCall on new proxy now fails (not calling from admin)',
    UpgradeableProxyImplementation,
    'upgradeToAndCall',
    'send',
    [InitializeableImplementation.options.address, '0x8129fc1c'],
    false
  )

  await runTest(
    'call to changeAdmin on new proxy now fails (not calling from admin)',
    UpgradeableProxyImplementation,
    'changeAdmin',
    'send',
    [oneAddress],
    false
  )

  await runTest(
    'making an offer that tries to match upper-case against a digit reverts',
    Pr000xy,
    'makeOffer',
    'send',
    [
      '0x2000000000000000000000000000000000000000',
      nullAddress,
      nullAddress
    ],
    false
  )

  await runTest(
    'making an offer that tries to match lower-case against a digit reverts',
    Pr000xy,
    'makeOffer',
    'send',
    [
      '0x3000000000000000000000000000000000000000',
      nullAddress,
      nullAddress
    ],
    false
  )

  await runTest(
    'making an offer that tries to match preceding for first character reverts',
    Pr000xy,
    'makeOffer',
    'send',
    [
      '0xa000000000000000000000000000000000000000',
      nullAddress,
      nullAddress
    ],
    false
  )

  await runTest(
    'making an offer that tries to match initial for first character reverts',
    Pr000xy,
    'makeOffer',
    'send',
    [
      '0xb000000000000000000000000000000000000000',
      nullAddress,
      nullAddress
    ],
    false
  )

  await runTest(
    'making an offer on case-sensitive preceding for first character reverts',
    Pr000xy,
    'makeOffer',
    'send',
    [
      '0xc000000000000000000000000000000000000000',
      nullAddress,
      nullAddress
    ],
    false
  )

  await runTest(
    'making an offer on case-sensitive initial for first character reverts',
    Pr000xy,
    'makeOffer',
    'send',
    [
      '0xd000000000000000000000000000000000000000',
      nullAddress,
      nullAddress
    ],
    false
  )

  await runTest(
    'making an offer on upper-case range of only digits reverts',
    Pr000xy,
    'makeOffer',
    'send',
    [
      '0x6000000000000000000000000000000000000000',
      '0xa000000000000000000000000000000000000000',
      nullAddress
    ],
    false
  )

  await runTest(
    'making an offer on lower-case range of only digits reverts',
    Pr000xy,
    'makeOffer',
    'send',
    [
      '0x8000000000000000000000000000000000000000',
      '0xa000000000000000000000000000000000000000',
      nullAddress
    ],
    false
  )

  let offerID
  let searchSpace = '0x0123456789abcdef100000000000000000000000'
  let target = web3.utils.toChecksumAddress(
    '0x00aa45f7b9000000100000000000000000000000'
  )

  await runTest(
    'an offer with valid conditions can be made',
    Pr000xy,
    'makeOffer',
    'send',
    [
      searchSpace,
      target,
      nullAddress
    ],
    true,
    receipt => {
      const logs = receipt.events.OfferCreated.returnValues
      // TODO: calculate and validate logs.offerID
      offerID = logs.offerID
      assert.strictEqual(logs.offerer, address)
      assert.strictEqual(logs.reward, '1')
    },
    address,
    1
  )

  await runTest(
    'total offer count is incremented correctly',
    Pr000xy,
    'countOffers',
    'call',
    [],
    true,
    total => {
      assert.strictEqual(total, '1')
    }
  )  

  await runTest(
    'offer ID can be retrieved by index',
    Pr000xy,
    'getOfferID',
    'call',
    [0],
    true,
    id => {
      assert.strictEqual(id, offerID)
    }
  )

  await runTest(
    'check for offer details shows that details are all correct',
    Pr000xy,
    'getOffer',
    'call',
    [
      offerID
    ],
    true,
    offer => {
      assert.strictEqual(offer.amount, '1')
      assert.strictEqual(offer.expiration, '0')
      assert.strictEqual(offer.searchSpace, searchSpace)
      assert.strictEqual(offer.target, target)
      assert.strictEqual(offer.offerer, address)
      assert.strictEqual(offer.recipient, address)
    }
  )

  await runTest(
    'check for non-existent offer reverts',
    Pr000xy,
    'getOffer',
    'send',
    [
      0
    ],
    false
  )

  await runTest(
    'an address that correctly matches an offer can be identified',
    Pr000xy,
    'matchesOffer',
    'call',
    [
      '0xf0aa0f0aaaafffaa101010101010101010101114',
      offerID
    ],
    true,
    matches => {
      assert.ok(matches)
    }
  )

  await runTest(
    'an address that does not match an offer will not be identified as such',
    Pr000xy,
    'matchesOffer',
    'call',
    [
      '0xf0aa0f0aaaafffaa101010101010101010101010',
      offerID
    ],
    true,
    matches => {
      assert.strictEqual(matches, false)
    }
  )

  await runTest(
    'a match on a non-existent offer will revert',
    Pr000xy,
    'matchesOffer',
    'send',
    [
      '0xf0aa0f0aaaafffaa101010101010101010101010',
      0
    ],
    false
  )

  await runTest(
    'offer cannot be cancelled by offerer before scheduled for expiration',
    Pr000xy,
    'cancelOffer',
    'send',
    [
      offerID
    ],
    false
  )

  await runTest(
    'offer cannot be sheduled for expiration from account other than offerer',
    Pr000xy,
    'scheduleOfferExpiration',
    'send',
    [
      offerID
    ],
    false,
    {},
    originalAddress
  )

  let expiration
  await runTest(
    'an offer can be scheduled for expiration by offerer',
    Pr000xy,
    'scheduleOfferExpiration',
    'send',
    [
      offerID
    ],
    true,
    receipt => {
      const logs = receipt.events.OfferSetToExpire.returnValues
      assert.strictEqual(logs.offerID, offerID)
      assert.strictEqual(logs.offerer, address)
      expiration = logs.expiration
      const tomorrow = Math.floor(Date.now() / 1000) + 86400
      const marginOfError = 10 // seconds
      assert.ok(Math.abs(parseInt(expiration, 10) - tomorrow) < marginOfError)
    }
  )

  await runTest(
    'check for offer details shows that is scheduled for expiration',
    Pr000xy,
    'getOffer',
    'call',
    [
      offerID
    ],
    true,
    offer => {
      assert.strictEqual(offer.amount, '1')
      assert.strictEqual(offer.expiration, expiration)
      assert.strictEqual(offer.searchSpace, searchSpace)
      assert.strictEqual(offer.target, target)
      assert.strictEqual(offer.offerer, address)
      assert.strictEqual(offer.recipient, address)
    }
  )

  await runTest(
    'offer cannot be immediately be cancelled once scheduled for expiration',
    Pr000xy,
    'cancelOffer',
    'send',
    [
      offerID
    ],
    false
  )

  searchSpace = nullAddress
  target = nullAddress

  await runTest(
    'a blank offer can be made',
    Pr000xy,
    'makeOffer',
    'send',
    [
      searchSpace,
      target,
      address
    ],
    true,
    receipt => {
      const logs = receipt.events.OfferCreated.returnValues
      // TODO: calculate and validate logs.offerID
      offerID = logs.offerID
      assert.strictEqual(logs.offerer, address)
      assert.strictEqual(logs.reward, '2')
    },
    address,
    2
  )


  await runTest(
    'total offer count is incremented correctly',
    Pr000xy,
    'countOffers',
    'call',
    [],
    true,
    total => {
      assert.strictEqual(total, '2')
    }
  )  

  await runTest(
    'offer ID can be retrieved by index',
    Pr000xy,
    'getOfferID',
    'call',
    [1],
    true,
    id => {
      assert.strictEqual(id, offerID)
    }
  )

  await runTest(
    'check for offer details shows that details are all correct',
    Pr000xy,
    'getOffer',
    'call',
    [
      offerID
    ],
    true,
    offer => {
      assert.strictEqual(offer.amount, '2')
      assert.strictEqual(offer.expiration, '0')
      assert.strictEqual(offer.searchSpace, searchSpace)
      assert.strictEqual(offer.target, target)
      assert.strictEqual(offer.offerer, address)
      assert.strictEqual(offer.recipient, address)
    }
  )

  salt = address + '10abcdef'.padEnd(24, '0')
  expectedProxyAddress = getCreate2Address(
    Pr000xy.options.address,
    salt,
    proxyInitializationCode
  )

  await runTest(
    'the address of the proxy resulting from a given salt can be retrieved',
    Pr000xy,
    'findProxyCreationAddress',
    'call',
    [salt],
    true,
    proxy => {
      assert.strictEqual(proxy, expectedProxyAddress)
    }
  )

  await runTest(
    'the proper token value of the expected proxy address can be retrieved',
    Pr000xy,
    'getReward',
    'call',
    [expectedProxyAddress],
    true,
    reward => {
      assert.strictEqual(
        reward,
        getReward(getZeroes(expectedProxyAddress)).toString()
      )
    }
  )

  await runTest(
    'proxies can be created via createProxy',
    Pr000xy,
    'createProxy',
    'send',
    [salt],
    true,
    receipt => {
      validateCreatedProxy(salt, receipt)
    }
  )

  await runTest(
    'proxies and offers can be matched',
    Pr000xy,
    'matchOffer',
    'send',
    [
      expectedProxyAddress,
      offerID
    ],
    true,
    receipt => {
      validateClaimedProxy(expectedProxyAddress, receipt)
      const logs = receipt.events.OfferFulfilled.returnValues
      assert.strictEqual(logs.offerID, offerID)
      assert.strictEqual(logs.offerer, address)
      assert.strictEqual(logs.submitter, address)
      assert.strictEqual(logs.reward, '2')
    }
  )

  // check for matched offer details shows that it no longer exists

  // matches can be made on an offer scheduled for expiration but not expired

  // check for matched offer details shows that it no longer exists

  // new offer can be made and scheduled for expiration - then wait to expire

  // check for offer details shows that it is expired (fast-forward required!)

  // matches cannot be made on an expired offer

  // offer cannot be cancelled by account other than offerer once it has expired

  // offer can be cancelled by offerer once it has expired (with refund paid)

  // check for cancelled offer details shows that it no longer exists

  // check batch functions

  console.log(
    `completed ${passed + failed} test${passed + failed === 1 ? '' : 's'} ` +
    `with ${failed} failure${failed === 1 ? '' : 's'}.`
  )

  if (failed > 0) {
    process.exit(1)
  }

  // exit.
  return 0

}}

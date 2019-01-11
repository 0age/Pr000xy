var util = require('ethereumjs-util')  // yarn add ethereumjs-util
var workerpool = require('workerpool') // yarn add workerpool 
var Decimal = require('decimal.js')    // yarn add decimal.js
Decimal.config(
  {
    precision: 500,
    toExpNeg: -500
  }
)

const address = '0x000000006b9b8C1aC1392B2f53f02FC9085EbD6B'
const RopstenPr000xyAddress = '0x000000009a9fc3ac5280bA0D3eA852E57DD2ac1b'
const RopstenPr000xyInitHash = '0x112782ff5a98e1dc87d1eb49f1d499e5b065139bd000edbd7a80791598f622a4'
const searchSpace = '0x111111111100000000000000000000000000000'
const target = util.toChecksumAddress(
  '0x0000000000000000000000000000000000000000'
)
const processes = 10

function mine() {
  const oneAddress = '0x0000001010101010101010101010101010101010'
  r = new RegExp("^0{6}|^0{4}((.{2})*(00)){2}|^((.{2})*(00)){5}")
  if (!r.test(oneAddress.slice(-40))) {
    console.error('regex check not working.')
    process.exit(1)
  }

  console.log('*** preparing arguments and spawning threads... ***')

  var pool = workerpool.pool({minWorkers: processes});

  for (var i = 0; i < processes; i++) {
    salt = new Decimal('0xffffffffffffffffffffffff').mul(
      Decimal.random(30)
    ).toHex()

    salt = salt.padStart(14, '0').slice(0, 14)

    header = util.bufferToHex(
      Buffer.concat([
        Buffer.from('ff', 'hex'),
        util.toBuffer(RopstenPr000xyAddress),
        util.toBuffer(address),
        util.toBuffer(salt)
      ])
    )

    // offload a function to a worker
    pool.exec(compute, [header, RopstenPr000xyInitHash, address, searchSpace, target, salt, i])
      .then(function (result) {
        console.log(`\nfound match!\n  salt: ${result[2]}\n  creates: ${result[1]}\n  submitter: ${result[0]}`);
        pool.terminate(true);
        process.exit(0)
      })
      .catch(function (err) {})
  }

  console.log(pool.stats())
  console.log('salts for each thread:')
}

function compute(header, footer, address, searchSpace, target, salt, thread) {
  var util = require('ethereumjs-util')
  var fs = require('fs')

  function matches(address, searchSpace, target) {
    address = util.toChecksumAddress(address)
    target = target.toLowerCase()
    //address = util.toChecksumAddress(address)
    // iterate through each byte of the address, checking for constraints.
    const first = address[2]
    for (var i = 2; i < searchSpace.length; i++) {
      s = searchSpace[i]
      // if search space byte is equal to 0, skip this byte.
      if (s === '0') {
        continue;
      }
      p = (address[i])
      t = (target[i])
      prior = (address[i - 1])

      if (s === '1') {
        // 1: nibble must match, case insensitive.
        if (p.toLowerCase() !== t) {
          return false;
        }
      } else if (s === '2') {
       // 2: nibble must match and be upper-case.
        if (p.toLowerCase() !== t || p === p.toLowerCase()) {
          return false;
        }
      } else if (s === '3') {
       // 3: nibble must match and be lower-case.
        if (p.toLowerCase() !== t || p !== p.toLowerCase()) {
          return false;
        }
      } else if (s === '4') {
       // 4: nibble must be less than the target, case insensitive.
        if (p.toLowerCase() >= t) {
          return false;
        }
      } else if (s === '5') {
       // 5: nibble must be greater than the target, case insensitive.
        if (p.toLowerCase() <= t) {
          return false;
        }
      } else if (s === '6') {
       // 6: nibble must be less than the target and be upper-case or a digit.
        if (p.toLowerCase() >= t || p === p.toLowerCase()) {
          return false;
        }
      } else if (s === '7') {
       // 7: nibble must be greater than target and be upper-case or a digit.
        if (p.toLowerCase() <= t || p === p.toLowerCase()) {
          return false;
        }
      } else if (s === '8') {
       // 8: nibble must be less than the target and be lower-case or a digit.
        if (p.toLowerCase() >= t || p === p.toUpperCase()) {
          return false;
        }
      } else if (s === '9') {
       // 9: nibble must be greater than target and be lower-case or a digit.
        if (p.toLowerCase() <= t || p === p.toUpperCase()) {
          return false;
        }
      } else if (s === 'a') {
        // 10: nibble must equal prior nibble (case-insensitive).
        if (p.toLowerCase() !== address[i-1].toLowerCase()) {
          return false;
        }
      } else if (s === 'b') {
        // 11: nibble must equal initial nibble (case-insensitive).
        if (p.toLowerCase() !== first.toLowerCase()) {
          return false;
        }
      } else if (s === 'c') {
        // 12: nibble must equal prior nibble (case-sensitive).
        if (p !== address[i - 1]) {
          return false;
        }
      } else if (s === 'd') {
        // 13: nibble must equal initial nibble (case-sensitive).
        if (p !== first) {
          return false;
        }
      } else if (s === 'e') {
        // 14: nibble must not be an upper-case digit.
        if (p !== p.toLowerCase()) {
          return false;
        }
      } else if (s === 'f') {
        // 14: nibble must not be an lower-case digit.
        if (p !== p.toUpperCase()) {
          return false;
        }
      } else {
        // otherwise behavior is undefined - return a failure.
        return false;
      }
    }

    // return a successful match.
    return true;
  }

  function getReward(account) {
    total = 0
    leading = 0

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

    // iterate through each byte of the address and count the zero bytes found.
    for (i = 2; i < 42; i = i + 2) {
      if (account[i] + account[i+1] == '00') {
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

    reward = rewards[(leading * 20 + total).toString()]
    if (typeof reward === 'undefined') {
      reward = 0
    }

    return `${leading} & ${total}: ${reward}`
  }

  // sanity check
  if (
    !matches(
      '0x003450089012345678901234567890123A56b89A',
      '0x0011100100111111111111111111111111111001',
      '0x123456789012345678901234567890123a56B89a'
    )
  ) return false

  r = new RegExp("^0{6}|^0{4}((.{2})*(00)){2}|^((.{2})*(00)){5}")
  
  // sanity check
  const oneAddress = '0x0000001010101010101010101010101010101010'
  if (!r.test(oneAddress.slice(-40))) return false

  // sanity check
  if (getReward(oneAddress) != '3 & 3: 1') return false

  header = util.toBuffer(header)
  footer = util.toBuffer(footer)
  console.log(` ${thread}: ${salt}`)

  nonce = 0
  found = false
  encodedNonce = ''
  timestamp = +new Date
  while (!found) {
    nonce += 1
    encodedNonce = nonce.toString(16).padStart(12, '0').slice(0, 12)
    candidate = util.bufferToHex(
      util.keccak256(Buffer.concat([
        header,
        util.toBuffer('0x' + encodedNonce),
        footer
      ])).slice(-20)
    )
    
    if (r.test(candidate.slice(-40))) {
      valuableProxy = `${
        address + salt.slice(2) + encodedNonce
      } => ${
        util.toChecksumAddress(candidate)
      } (${getReward(candidate)})`

      console.log(valuableProxy)

      fs.appendFileSync('valuableProxies.txt', valuableProxy + '\n', (err) => {
        if (err) return console.error(err);
      });

        
      found = matches(candidate, searchSpace, target)
    }

    if (thread === 9 && nonce % 100000 === 0) {
      latestTimestamp = +new Date
      hashrate = Math.floor((100000 * 10 * 1000) / (latestTimestamp - timestamp))
      timestamp = latestTimestamp
      console.log(`${nonce * 10 / 1000000} million hashes (${Math.floor(hashrate/1000)} KH/s)`)
    }
  }

  console.log(header, footer, address, searchSpace, target, salt, thread)
  console.log('\n' + valuableProxy + '\n')

  return [
    util.toChecksumAddress(address),
    util.toChecksumAddress(candidate),
    address + salt.slice(2) + encodedNonce
  ]
}

mine()

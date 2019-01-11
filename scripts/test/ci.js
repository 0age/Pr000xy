const connectionConfig = require('../../truffle-config.js')

const connection = connectionConfig.networks['geth']

let web3Provider = connection.provider

// import tests
var testOriginalGeth = require('./testOriginal.js')
var testGeth = require('./test.js')

// run tests
async function runTests() {
	console.log('running standard test suite...')
	await testGeth.test(web3Provider, 'geth')
	console.log('running original test suite...')
	await testOriginalGeth.test(web3Provider, 'geth')
	process.exit(0)
}

runTests()

const connectionConfig = require('../../truffle-config.js')

const connection = connectionConfig.networks['geth']

let web3Provider = connection.provider

// import tests
var testGeth = require('./test.js')

// run tests
async function runTests() {
	await testGeth.test(web3Provider, 'geth')
	process.exit(0)
}

runTests()

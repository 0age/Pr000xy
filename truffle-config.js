var Web3 = require('web3')
var net = require('net')
const homedir = require('os').homedir()

module.exports = {
  networks: {
    development: {
      provider: new Web3('ws://localhost:8545'),
      network_id: "*", // Match any network id
      gasPrice: 10 ** 9,
      gas: 7900000
    },
    aleth: {
      provider: new Web3(`${homedir}/.ethereum/geth.ipc`, net),
      network_id: "*", // Match any network id
      gasPrice: 10 ** 9,
      gas: 7900000      
    },
    geth: {
      provider: new Web3('http://127.0.0.1:8545'),
      network_id: "*", // Match any network id
      gasPrice: 10 ** 9,
      gas: 7900000
    }
  },
  compilers: {
    solc: {
      version: "0.5.1",
      settings: {
        optimizer: {
          enabled: true,
          runs: 33333
        },
        evmVersion: "constantinople"
      }
    }
  }
}

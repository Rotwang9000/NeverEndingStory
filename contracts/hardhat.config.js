require("@nomicfoundation/hardhat-toolbox");

module.exports = {
	solidity: "0.8.17",
	paths: {
		sources: "./contracts",
		tests: "./test",
		cache: "./cache",
		artifacts: "./artifacts",
	},
	networks: {
		hardhat: {
			mining: {
				auto: true,
				interval: 1000,
			},
		},
	},
};

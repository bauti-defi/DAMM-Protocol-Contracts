# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

deploy-module-factory:
	DEPLOYMENT_CHAIN=arb forge script script/ArbStableFundConfig.s.sol:ArbStableFundConfig --broadcast --rpc-url ${ARBI_RPC_URL} --sig "deployModuleFactory()" --optimizer-runs 10000 -vvvv -l --mnemonic-indexes 1

deploy-hook-registry:
	DEPLOYMENT_CHAIN=arb forge script script/ArbStableFundConfig.s.sol:ArbStableFundConfig --broadcast --rpc-url ${ARBI_RPC_URL} --sig "deployHookRegistry()" --optimizer-runs 10000 -vvvv -l --mnemonic-indexes 1

deploy-trading-module:
	DEPLOYMENT_CHAIN=arb forge script script/ArbStableFundConfig.s.sol:ArbStableFundConfig --broadcast --rpc-url ${ARBI_RPC_URL} --sig "deployTradingModule()" --optimizer-runs 10000 -vvvv -l --mnemonic-indexes 1

deploy-uniswap-v3-hooks:
	DEPLOYMENT_CHAIN=arb forge script script/ArbStableFundConfig.s.sol:ArbStableFundConfig --broadcast --rpc-url ${ARBI_RPC_URL} --sig "deployUniswapV3Hooks()" --optimizer-runs 10000 -vvvv -l --mnemonic-indexes 1

deploy-aave-v3-hooks:
	DEPLOYMENT_CHAIN=arb forge script script/ArbStableFundConfig.s.sol:ArbStableFundConfig --broadcast --rpc-url ${ARBI_RPC_URL} --sig "deployAaveV3Hooks()" --optimizer-runs 10000 -vvvv -l --mnemonic-indexes 1

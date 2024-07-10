# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

deploy-module-lib:
	DEPLOYMENT_CHAIN=arb forge script script/$(SCRIPT).s.sol:$(SCRIPT) --broadcast --rpc-url ${ARBI_RPC_URL} --sig "deployModuleLib()" --optimizer-runs 1000 -vvvv -l --mnemonic-indexes 1

deploy-hook-registry:
	DEPLOYMENT_CHAIN=arb forge script script/$(SCRIPT).s.sol:$(SCRIPT) --broadcast --rpc-url ${ARBI_RPC_URL} --sig "deployHookRegistry()" --optimizer-runs 10000000 -vvvv -l --mnemonic-indexes 1

deploy-trading-module:
	DEPLOYMENT_CHAIN=arb forge script script/$(SCRIPT).s.sol:$(SCRIPT) --broadcast --rpc-url ${ARBI_RPC_URL} --sig "deployTradingModule()" --optimizer-runs 10000000 -vvvv -l --mnemonic-indexes 1

deploy-uniswap-v3-hooks:
	DEPLOYMENT_CHAIN=arb forge script script/$(SCRIPT).s.sol:$(SCRIPT) --broadcast --rpc-url ${ARBI_RPC_URL} --sig "deployUniswapV3Hooks()" --optimizer-runs 10000000 -vvvv -l --mnemonic-indexes 1

configure-uniswap-v3-assets:
	DEPLOYMENT_CHAIN=arb forge script script/$(SCRIPT).s.sol:$(SCRIPT) --broadcast --rpc-url ${ARBI_RPC_URL} --sig "configureUniswapAssets()" --optimizer-runs 10000000 -vvvv -l --mnemonic-indexes 1

set-uniswap-v3-hooks:
	DEPLOYMENT_CHAIN=arb forge script script/$(SCRIPT).s.sol:$(SCRIPT) --broadcast --rpc-url ${ARBI_RPC_URL} --sig "setUniswapHooks()" --optimizer-runs 10000000 -vvvv -l --mnemonic-indexes 1

remove-uniswap-v3-hooks:
	DEPLOYMENT_CHAIN=arb forge script script/$(SCRIPT).s.sol:$(SCRIPT) --broadcast --rpc-url ${ARBI_RPC_URL} --sig "removeUniswapHooks()" --optimizer-runs 10000000 -vvvv -l --mnemonic-indexes 1

approve-uniswap-v3:
	DEPLOYMENT_CHAIN=arb forge script script/$(SCRIPT).s.sol:$(SCRIPT) --broadcast --rpc-url ${ARBI_RPC_URL} --sig "approveUniswap()" --optimizer-runs 10000000 -vvvv -l --mnemonic-indexes 1

deploy-aave-v3-hooks:
	DEPLOYMENT_CHAIN=arb forge script script/$(SCRIPT).s.sol:$(SCRIPT) --broadcast --rpc-url ${ARBI_RPC_URL} --sig "deployAaveV3Hooks()" --optimizer-runs 10000000 -vvvv -l --mnemonic-indexes 1

configure-aave-v3-assets:
	DEPLOYMENT_CHAIN=arb forge script script/$(SCRIPT).s.sol:$(SCRIPT) --broadcast --rpc-url ${ARBI_RPC_URL} --sig "configureAaveAssets()" --optimizer-runs 10000000 -vvvv -l --mnemonic-indexes 1

set-aave-v3-hooks:
	DEPLOYMENT_CHAIN=arb forge script script/$(SCRIPT).s.sol:$(SCRIPT) --broadcast --rpc-url ${ARBI_RPC_URL} --sig "setAaveHooks()" --optimizer-runs 10000000 -vvvv -l --mnemonic-indexes 1

remove-aave-v3-hooks:
	DEPLOYMENT_CHAIN=arb forge script script/$(SCRIPT).s.sol:$(SCRIPT) --broadcast --rpc-url ${ARBI_RPC_URL} --sig "removeAaveHooks()" --optimizer-runs 10000000 -vvvv -l --mnemonic-indexes 1

approve-aave-v3:
	DEPLOYMENT_CHAIN=arb forge script script/$(SCRIPT).s.sol:$(SCRIPT) --broadcast --rpc-url ${ARBI_RPC_URL} --sig "approveAave()" --optimizer-runs 10000000 -vvvv -l --mnemonic-indexes 1

approve-all:
	DEPLOYMENT_CHAIN=arb forge script script/$(SCRIPT).s.sol:$(SCRIPT) --broadcast --rpc-url ${ARBI_RPC_URL} --sig "approveAll()" --optimizer-runs 10000 -vvvv -l --mnemonic-indexes 1

verify:
	DEPLOYMENT_CHAIN=arb forge script script/$(SCRIPT).s.sol:$(SCRIPT) --broadcast --rpc-url ${ARBI_RPC_URL} --sig "verify()" --optimizer-runs 10000000 -vvvv -l --mnemonic-indexes 1
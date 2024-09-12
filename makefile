# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

deploy-module-lib:
	DEPLOYMENT_CHAIN=arb forge script script/$(SCRIPT).s.sol:$(SCRIPT) --broadcast --rpc-url ${ARBI_RPC_URL} --sig "deployModuleLib()" --optimizer-runs 10000000 -vvvv -l --mnemonic-indexes 1

deploy-fund-factory:
	DEPLOYMENT_CHAIN=arb forge script script/$(SCRIPT).s.sol:$(SCRIPT) --broadcast --rpc-url ${ARBI_RPC_URL} --sig "deployFundFactory()" --optimizer-runs 10000000 -vvvv -l --mnemonic-indexes 1

deploy-fund:
	DEPLOYMENT_CHAIN=arb forge script script/$(SCRIPT).s.sol:$(SCRIPT) --broadcast --rpc-url ${ARBI_RPC_URL} --sig "deployFund()" --optimizer-runs 10000000 -vvvv -l --mnemonic-indexes 1

deploy-hook-registry:
	DEPLOYMENT_CHAIN=arb forge script script/$(SCRIPT).s.sol:$(SCRIPT) --broadcast --rpc-url ${ARBI_RPC_URL} --sig "deployHookRegistry()" --optimizer-runs 10000000 -vvvv -l --mnemonic-indexes 1

deploy-transaction-module:
	DEPLOYMENT_CHAIN=arb forge script script/$(SCRIPT).s.sol:$(SCRIPT) --broadcast --rpc-url ${ARBI_RPC_URL} --sig "deployTransactionModule()" --optimizer-runs 10000000 -vvvv -l --mnemonic-indexes 1

deploy-uniswap-v3-hooks:
	DEPLOYMENT_CHAIN=arb forge script script/$(SCRIPT).s.sol:$(SCRIPT) --broadcast --rpc-url ${ARBI_RPC_URL} --sig "deployUniswapV3CallValidator()" --optimizer-runs 10000000 -vvvv -l --mnemonic-indexes 1

configure-uniswap-v3-assets:
	DEPLOYMENT_CHAIN=arb forge script script/$(SCRIPT).s.sol:$(SCRIPT) --broadcast --rpc-url ${ARBI_RPC_URL} --sig "configureUniswapAssets()" --optimizer-runs 10000 -vvvv -l --mnemonic-indexes 1

set-uniswap-v3-hooks:
	DEPLOYMENT_CHAIN=arb forge script script/$(SCRIPT).s.sol:$(SCRIPT) --broadcast --rpc-url ${ARBI_RPC_URL} --sig "setUniswapHooks()" --optimizer-runs 10000 -vvvv -l --mnemonic-indexes 1

remove-uniswap-v3-hooks:
	DEPLOYMENT_CHAIN=arb forge script script/$(SCRIPT).s.sol:$(SCRIPT) --broadcast --rpc-url ${ARBI_RPC_URL} --sig "removeUniswapHooks()" --optimizer-runs 10000 -vvvv -l --mnemonic-indexes 1

approve-uniswap-v3:
	DEPLOYMENT_CHAIN=arb forge script script/$(SCRIPT).s.sol:$(SCRIPT) --broadcast --rpc-url ${ARBI_RPC_URL} --sig "approveUniswap()" --optimizer-runs 10000 -vvvv -l --mnemonic-indexes 1

configure-uniswap-v3: configure-uniswap-v3-assets set-uniswap-v3-hooks
	@echo "Configured Uniswap V3"

deploy-aave-v3-hooks:
	DEPLOYMENT_CHAIN=arb forge script script/$(SCRIPT).s.sol:$(SCRIPT) --broadcast --rpc-url ${ARBI_RPC_URL} --sig "deployAaveV3CallValidator()" --optimizer-runs 10000000 -vvvv -l --mnemonic-indexes 1

configure-aave-v3-assets:
	DEPLOYMENT_CHAIN=arb forge script script/$(SCRIPT).s.sol:$(SCRIPT) --broadcast --rpc-url ${ARBI_RPC_URL} --sig "configureAaveAssets()" --optimizer-runs 10000 -vvvv -l --mnemonic-indexes 1

set-aave-v3-hooks:
	DEPLOYMENT_CHAIN=arb forge script script/$(SCRIPT).s.sol:$(SCRIPT) --broadcast --rpc-url ${ARBI_RPC_URL} --sig "setAaveHooks()" --optimizer-runs 10000 -vvvv -l --mnemonic-indexes 1

configure-aave-v3: configure-aave-v3-assets set-aave-v3-hooks
	@echo "Configured Aave V3"
	
remove-aave-v3-hooks:
	DEPLOYMENT_CHAIN=arb forge script script/$(SCRIPT).s.sol:$(SCRIPT) --broadcast --rpc-url ${ARBI_RPC_URL} --sig "removeAaveHooks()" --optimizer-runs 10000 -vvvv -l --mnemonic-indexes 1

approve-aave-v3:
	DEPLOYMENT_CHAIN=arb forge script script/$(SCRIPT).s.sol:$(SCRIPT) --broadcast --rpc-url ${ARBI_RPC_URL} --sig "approveAave()" --optimizer-runs 10000 -vvvv -l --mnemonic-indexes 1

approve-all:
	DEPLOYMENT_CHAIN=arb forge script script/$(SCRIPT).s.sol:$(SCRIPT) --broadcast --rpc-url ${ARBI_RPC_URL} --sig "approveAll()" --optimizer-runs 10000 -vvvv -l --mnemonic-indexes 1

deploy-token-transfer-hooks:
	DEPLOYMENT_CHAIN=arb forge script script/$(SCRIPT).s.sol:$(SCRIPT) --broadcast --rpc-url ${ARBI_RPC_URL} --sig "deployTokenTransferCallValidator()" --optimizer-runs 10000000 -vvvv -l --mnemonic-indexes 1

set-token-transfer-hooks:
	DEPLOYMENT_CHAIN=arb forge script script/$(SCRIPT).s.sol:$(SCRIPT) --broadcast --rpc-url ${ARBI_RPC_URL} --sig "setTokenTransferCallValidator()" --optimizer-runs 10000 -vvvv -l --mnemonic-indexes 1

configure-token-transfer-assets:
	DEPLOYMENT_CHAIN=arb forge script script/$(SCRIPT).s.sol:$(SCRIPT) --broadcast --rpc-url ${ARBI_RPC_URL} --sig "configureTokenTransferAssets()" --optimizer-runs 10000 -vvvv -l --mnemonic-indexes 1

approve-mother:
	DEPLOYMENT_CHAIN=arb forge script script/$(SCRIPT).s.sol:$(SCRIPT) --broadcast --rpc-url ${ARBI_RPC_URL} --sig "approveMother()" --optimizer-runs 10000 -vvvv -l --mnemonic-indexes 1

verify:
	DEPLOYMENT_CHAIN=arb forge script script/$(SCRIPT).s.sol:$(SCRIPT) --broadcast --rpc-url ${ARBI_RPC_URL} --sig "verify()" --optimizer-runs 10000 -vvvv -l --mnemonic-indexes 1
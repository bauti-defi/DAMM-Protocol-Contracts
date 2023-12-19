# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

test-arb:
	forge test --fork-url ${ARBI_RPC_URL} --etherscan-api-key ${ARBISCAN_API_KEY} --fork-block-number 124240758

hot-test-arb:
	forge test -vvvv -w --fork-url ${ARBI_RPC_URL} --etherscan-api-key ${ARBISCAN_API_KEY} --fork-block-number 124240758
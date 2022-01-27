# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

# deps
update:; forge update

# Build & test
build  :; forge build
test   :; forge test --fork-url ${FORK_URL} --fork-block-number ${BLOCK_NUMBER}
test-match   :; forge test --fork-url ${FORK_URL} --fork-block-number ${BLOCK_NUMBER} -m ${MATCH} -vvv
trace   :; forge test --fork-url ${FORK_URL} --fork-block-number ${BLOCK_NUMBER} -vvvvv
clean  :; forge clean
snapshot :; forge snapshot
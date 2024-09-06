include .env

checkL1:
	@echo "Setting environment variable LIVE_DEPLOY_READ_FILE_NAME to $(file)"
	@export LIVE_DEPLOY_READ_FILE_NAME=$(file) && forge test --mp test/LiveDeploy.t.sol --fork-url=${L1_RPC_URL}

checkL2:
	@echo "Setting environment variable LIVE_DEPLOY_READ_FILE_NAME to $(file)"
	@export LIVE_DEPLOY_READ_FILE_NAME=$(file) && forge test --mp test/LiveDeploy.t.sol --fork-url=${L2_RPC_URL}
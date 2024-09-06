include .env

checkL1:
	@echo "Setting environment variable LIVE_DEPLOY_READ_FILE_NAME to $(file)"
	@export LIVE_DEPLOY_READ_FILE_NAME=$(file) && forge test --mp test/LiveDeploy.t.sol --fork-url=${L1_RPC_URL}

checkL2:
	@echo "Setting environment variable LIVE_DEPLOY_READ_FILE_NAME to $(file)"
	@export LIVE_DEPLOY_READ_FILE_NAME=$(file) && forge test --mp test/LiveDeploy.t.sol --fork-url=${L2_RPC_URL}

deployL1:
	@echo "Setting environment variable LIVE_DEPLOY_READ_FILE_NAME to $(file)"
	@export LIVE_DEPLOY_READ_FILE_NAME=$(file) && forge script script/deploy/deployAll.s.sol --sig "run(string)" $(file) --fork-url=${L1_RPC_URL}

deployL2:
	@echo "Setting environment variable LIVE_DEPLOY_READ_FILE_NAME to $(file)"
	@export LIVE_DEPLOY_READ_FILE_NAME=$(file) && forge script script/deploy/deployAll.s.sol --sig "run(string)" $(file) --fork-url=${L1_RPC_URL}

live-deployL1:
	@echo "Setting environment variable LIVE_DEPLOY_READ_FILE_NAME to $(file)"
	@export LIVE_DEPLOY_READ_FILE_NAME=$(file) && forge script script/deploy/deployAll.s.sol --sig "run(string)" $(file) --fork-url=${L1_RPC_URL} --private-key=$(PRIVATE_KEY) --broadcast --slow --verify

live-deployL2:
	@echo "Setting environment variable LIVE_DEPLOY_READ_FILE_NAME to $(file)"
	@export LIVE_DEPLOY_READ_FILE_NAME=$(file) && forge script script/deploy/deployAll.s.sol --sig "run(string)" $(file) --fork-url=${L1_RPC_URL} --private-key=$(PRIVATE_KEY) --broadcast --slow --verify


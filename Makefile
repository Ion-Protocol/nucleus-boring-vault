include .env

check-configs: 
	@echo "l1_file: ${l1_file} l2_file ${l2_file}"
	bun lzConfigCheck.cjs ${l1_file} ${l2_file}

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
	@export LIVE_DEPLOY_READ_FILE_NAME=$(file) && forge script script/deploy/deployAll.s.sol --sig "run(string)" $(file) --fork-url=${L2_RPC_URL}

live-deployL1:
	@echo "Setting environment variable LIVE_DEPLOY_READ_FILE_NAME to $(file)"
	@export LIVE_DEPLOY_READ_FILE_NAME=$(file) && forge script script/deploy/deployAll.s.sol --sig "run(string)" $(file) --fork-url=${L1_RPC_URL} --private-key=$(PRIVATE_KEY) --broadcast --slow --verify

live-deployL2:
	@echo "Setting environment variable LIVE_DEPLOY_READ_FILE_NAME to $(file)"
	@export LIVE_DEPLOY_READ_FILE_NAME=$(file) && forge script script/deploy/deployAll.s.sol --sig "run(string)" $(file) --fork-url=${L2_RPC_URL} --private-key=$(PRIVATE_KEY) --broadcast --slow --verify

prettier:
	prettier --write '**/*.{md,yml,yaml,ts,js}'

solhint:
	solhint -w 0 'src/**/*.sol'
    
slither: 
	slither src

prepare:
	husky

deploy-createx-l1: 
	forge script script/DeployCustomCreatex.s.sol --rpc-url ${L1_RPC_URL} --private-key ${PRIVATE_KEY} --slow --no-metadata

deploy-createx-l2:
	forge script script/DeployCustomCreatex.s.sol --rpc-url ${L2_RPC_URL} --private-key ${PRIVATE_KEY} --slow --no-metadata
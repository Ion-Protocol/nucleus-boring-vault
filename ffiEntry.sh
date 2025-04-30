#! /bin/bash

# Tags for all options to ffi
TAG_SIMULATOR_TEST="SIMTEST"

# Handle no-input
if [ $# -eq 0 ]; then
    echo "No arguments provided"
    exit 1
fi


# Function to handle simulation test
handleSimulatorTest(){
    SIMULATION_CONTRACT="$1"
    EXECUTOR_ADDRESS="$2"
    BORING_VAULT="$3"

    json_data='{
    "rpcURL": "https://ethereum-mainnet.core.chainstack.com/741def98b36a916887c60577d6439dae",
    "simulationContractAddress": "'${SIMULATION_CONTRACT}'",
    "simulationExecutorAddress": "'${EXECUTOR_ADDRESS}'",
    "boringVaultAddress": "'${BORING_VAULT}'",
    "manageCalls": [
        {
        "target": "0x4567890123456789012345678901234567890123",
        "data": "0xa9059cbb000000000000000000000000c872c31cd6ff75f08207d39515940a460f6c1b1a0000000000000000000000000000000000000000000000000000000005f5e100",
        "value": "0"
        }
    ],
    "trackedTokens": [
        "0x4567890123456789012345678901234567890123"
    ]
    }'
    echo "$json_data"

    output=$(curl -i -X POST 'https://e8cyl923qj.execute-api.us-east-1.amazonaws.com/staging/main' \
    -H 'Content-Type: application/json' \
    -d "$json_data")

    # print output
    echo "$output"
}


#--------------------------------
# Main loop
#--------------------------------
if [ "$1" == $TAG_SIMULATOR_TEST ]; then
    handleSimulatorTest "$2" "$3" "$4"
fi


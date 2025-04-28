package main

import (
  "fmt"
  "math/big"
  "encoding/json"
  "encoding/hex"
  "strings"
  "context"
  	
  "github.com/aws/aws-lambda-go/events"
  "github.com/aws/aws-lambda-go/lambda"

  "github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/ethereum/go-ethereum"

  "github.com/Ion-Protocol/management-token-balance-simulator/constants"
)

// Types
type SimulationRequestBody struct {
  rpcURL                    string            `json:"rpcURL"`
  simulationContractAddress *common.Address   `json:"simulationContractAddress`
  simulationExecutorAddress common.Address    `json:"simulationExecutorAddress"`
  BoringVaultAddress        common.Address    `json:"boringVaultAddress"`
  ManageCalls               []Call            `json:"manageCalls"`
  TrackedTokens             []common.Address  `json:"trackedTokens"` 
}

type Call struct {
  Target    string  `json:"target"`
  Data      string  `json:"data"`
  Value     string  `json:"value"`
}

type TokenBalancesRevertResponse struct {
  Tokens    []common.Address
  Balances  []*big.Int
}

type ManagementRevertError struct {
  Target      common.Address
  TargetData  []byte
  Value       *big.Int  
  Response    []byte
}

func Handler(request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
  // Get the request data
  var b SimulationRequestBody

  if err := json.Unmarshal([]byte(request.Body), &b); err != nil {
    return events.APIGatewayProxyResponse{Body: "Invalid Request Body", StatusCode:400}, nil
  }

   
  // Set up the ETH connection
  client, err := ethclient.Dial(b.rpcURL)

  if err != nil{
    return events.APIGatewayProxyResponse{Body: "Invalid Rpc URL", StatusCode:400}, nil
  }

  defer client.Close()

  
  // Encode function call
  args := []interface{}{
    b.BoringVaultAddress,
    b.ManageCalls,
    b.TrackedTokens,
  }

  abi, err := abi.JSON(strings.NewReader(constants.MANAGER_ABI))

  if err != nil {
    return events.APIGatewayProxyResponse{Body: "ABI Error", StatusCode: 500}, nil
  }

  packedData, err := abi.Pack("tokenBalancesNow", args...)

  if err != nil {
    return events.APIGatewayProxyResponse{Body: "ABI Packing Error", StatusCode: 500}, nil
  }

  // Create the TX object
  msg := ethereum.CallMsg{
    From:   b.simulationExecutorAddress,
    To:     b.simulationContractAddress,
    Data:   packedData,
  }
  
  // Execute the TX
  _, err = client.CallContract(context.Background(), msg, nil)
  if err == nil {
    return events.APIGatewayProxyResponse{Body:"Execution Resulted In Nil Error", StatusCode: 500}, nil
  }

  errorStr := err.Error()



  // Handle the error string
  if strings.Contains(errorStr, constants.TokenBalancesNowSelector){
    decodedTokenBalances, err := DecodeTokenBalancesNowError(errorStr)  
    if err != nil {
      return events.APIGatewayProxyResponse{Body: fmt.Sprintf("Error decoding tokenBalance response: %v", err), StatusCode: 500}, nil
    }

    jsonBytes, err := json.Marshal(decodedTokenBalances)
    if err != nil {
      return events.APIGatewayProxyResponse{Body: fmt.Sprintf("Error marshaling tokenBalance response: %v", err), StatusCode: 500}, nil
    }

    return events.APIGatewayProxyResponse{Body: string(jsonBytes), StatusCode:200, Headers: map[string]string{"Content-Type:": "application/json"}}, nil
  }

  if strings.Contains(errorStr, constants.ManagementErrorSelector){
    decodedManagementError, err := DecodeManagementError(errorStr) 
    if err != nil {
      return events.APIGatewayProxyResponse{Body: fmt.Sprintf("Error decoding manage error response: %v", err), StatusCode: 500}, nil
    }

    jsonBytes, err := json.Marshal(decodedManagementError)
    if err != nil {
      return events.APIGatewayProxyResponse{Body: fmt.Sprintf("Error marshaling manage error response: %v", err), StatusCode: 500}, nil
    }

    return events.APIGatewayProxyResponse{Body: string(jsonBytes), StatusCode:400, Headers: map[string]string{"Content-Type:": "application/json"}}, nil

  } 

  return events.APIGatewayProxyResponse{Body: "Execution completed without data unexpectedly", StatusCode: 500}, nil
}

// Helper to parse error data for decoding
func formatErrorString(errorStr string) string {
  startIdx := strings.Index(errorStr, constants.TokenBalancesNowSelector)
  endIdx := strings.Index(errorStr[startIdx:], "")

  if endIdx == -1 {
    endIdx = len(errorStr)
  } else {
    endIdx += startIdx
  }
  errorData := errorStr[startIdx:endIdx]

  
  // remove any leading or trailing whitespace 
  hexData := strings.TrimSpace(errorData)
  return hexData
} 

func DecodeTokenBalancesNowError(errorStr string) (TokenBalancesRevertResponse, error) {

  parsedAbi, err := abi.JSON(strings.NewReader(constants.MANAGER_ABI))

  if err != nil {
    return TokenBalancesRevertResponse{}, fmt.Errorf("Error unpacking ABI: %v", err)
  }

  var decodedTokenBalancesNowResponse TokenBalancesRevertResponse

  bytesdata, err := hex.DecodeString(formatErrorString(errorStr))

  if err != nil {
    return TokenBalancesRevertResponse{}, fmt.Errorf("Error decoding hex data: %v", err)
  }

  err = parsedAbi.UnpackIntoInterface(decodedTokenBalancesNowResponse, "TokenBalancesNow", bytesdata)

  if err != nil {
    return TokenBalancesRevertResponse{}, fmt.Errorf("Error unpacking hex data to interface: %v", err)
  }

  return decodedTokenBalancesNowResponse, nil
}

func DecodeManagementError(errorStr string) (ManagementRevertError, error) {

  parsedAbi, err := abi.JSON(strings.NewReader(constants.MANAGER_ABI))

  if err != nil {
    return ManagementRevertError{}, fmt.Errorf("Error unpacking ABI: %v", err)
  }

  var decodedManagementError ManagementRevertError
  
  bytesdata, err := hex.DecodeString(formatErrorString(errorStr))

  if err != nil {
    return ManagementRevertError{}, fmt.Errorf("Error decoding hex data: %v", err)
  }
  err = parsedAbi.UnpackIntoInterface(&decodedManagementError, "ManagerWithTokenBalanceVerification__ManagementError", bytesdata)

  if err != nil {
    return ManagementRevertError{}, fmt.Errorf("Error unpacking hex data to interface: %v", err)
  }

  return decodedManagementError, nil

}

// main entrypoint
func main() {
  lambda.Start(Handler)
}

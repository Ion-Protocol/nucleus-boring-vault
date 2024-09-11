```go
package main

import (
	"context"
	"html/template"
	"log"
	"math/big"
	"net/http"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/ethclient"
)

const (
	infuraURL       = "https://mainnet.infura.io/v3/YOUR_INFURA_PROJECT_ID"
	contractAddress = "0xYourERC20ContractAddress"
)

type TransferEvent struct {
	From   common.Address
	To     common.Address
	Tokens *big.Int
}

var transferEvents []TransferEvent

func main() {
	client, err := ethclient.Dial(infuraURL)
	if err != nil {
		log.Fatalf("Failed to connect to the Ethereum client: %v", err)
	}

	contractAbi, err := abi.JSON(strings.NewReader(`[{"anonymous":false,"inputs":[{"indexed":true,"name":"from","type":"address"},{"indexed":true,"name":"to","type":"address"},{"indexed":false,"name":"value","type":"uint256"}],"name":"Transfer","type":"event"}]`))
	if err != nil {
		log.Fatalf("Failed to parse contract ABI: %v", err)
	}

	query := ethereum.FilterQuery{
		Addresses: []common.Address{common.HexToAddress(contractAddress)},
	}

	logs := make(chan types.Log)
	sub, err := client.SubscribeFilterLogs(context.Background(), query, logs)
	if err != nil {
		log.Fatalf("Failed to subscribe to logs: %v", err)
	}

	go func() {
		for {
			select {
			case err := <-sub.Err():
				log.Fatalf("Subscription error: %v", err)
			case vLog := <-logs:
				var transferEvent TransferEvent
				err := contractAbi.UnpackIntoInterface(&transferEvent, "Transfer", vLog.Data)
				if err != nil {
					log.Printf("Failed to unpack log: %v", err)
					continue
				}
				transferEvent.From = common.HexToAddress(vLog.Topics[1].Hex())
				transferEvent.To = common.HexToAddress(vLog.Topics[2].Hex())
				transferEvents = append(transferEvents, transferEvent)
			}
		}
	}()

	http.HandleFunc("/home", func(w http.ResponseWriter, r *http.Request) {
		tmpl, err := template.New("home").Parse(`
			<!DOCTYPE html>
			<html>
			<head>
				<title>ERC20 Transfer Events</title>
			</head>
			<body>
				<h1>ERC20 Transfer Events</h1>
				<table border="1">
					<tr>
						<th>From</th>
						<th>To</th>
						<th>Tokens</th>
					</tr>
					{{range .}}
					<tr>
						<td>{{.From}}</td>
						<td>{{.To}}</td>
						<td>{{.Tokens}}</td>
					</tr>
					{{end}}
				</table>
			</body>
			</html>
		`)
		if err != nil {
			http.Error(w, "Internal Server Error", http.StatusInternalServerError)
			return
		}
		tmpl.Execute(w, transferEvents)
	})

	log.Println("Server started at :8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}
```

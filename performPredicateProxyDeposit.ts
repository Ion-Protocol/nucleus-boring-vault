import {
    createWalletClient,
    createPublicClient,
    http,
    Address,
    erc20Abi,
    parseAbi,
    encodeFunctionData,
    Hex
} from "viem";
import { privateKeyToAccount } from 'viem/accounts'
import { holesky } from "viem/chains";
import axios from 'axios';

// --- Configuration ---
const proxyAddress: Address = '0x4c8ad980c99df0Ba6dF05E4f20093fB0E3dEF829'; // Proxy contract address on holesky
const depositAsset: Address = '0x6B5817E7091BC0C747741E96820b0199388245EA';
const amountIn: bigint = 100n; // Deposit 1 hundred wei (adjust as needed)
const minimumMint: bigint = 1n; // Minimum shares expected (adjust as needed)
// Define who receives the vault shares after deposit
const recipientAddress: Address = '0x04354e44ed31022716e77eC6320C04Eda153010c';

const PREDICATE_API_URL = 'https://staging.api.predicate.io/v1/task';

const PRIVATE_KEY = (process.env.PRIVATE_KEY || '0x') as `0x${string}`;
const RPC_URL = process.env.HOLESKY_RPC_URL || 'https://holesky.drpc.org'; // Use default if not set

// --- Validation ---
if (!RPC_URL) {
    console.error("Error: HOLESKY_RPC_URL is not set (or using default).");
}
if (PRIVATE_KEY === '0x' || !privateKeyToAccount(PRIVATE_KEY)) {
    console.error("Error: PRIVATE_KEY is not set or invalid in the environment variables.");
    process.exit(1);
}

// --- ABIs ---

// ABI for the specific _deposit function signature we need to encode for the API
const underlyingDepositAbi = parseAbi([
    'function _deposit(address depositAsset, uint256 depositAmount, uint256 minimumMint)'
]);

// ABI for the Proxy's deposit function
const proxyDepositAbi = parseAbi([
    "function deposit(address depositAsset,uint256 depositAmount,uint256 minimumMint,address recipient,(string,uint256,address[],bytes[]) predicateMessage) external returns (uint256 shares)"
]);

// Type helper for the PredicateMessage tuple argument for writeContract
type PredicateMessageArgs = {
    policyId: string;
    expiration: bigint;
    signers: readonly Address[];
    signatures: readonly Hex[];
};

// Define the expected structure of the Predicate API response
interface PredicateApiResponse {
    is_compliant: boolean;
    task_id?: string;
    expiry_block?: number;
    signers?: Address[];
    signature?: Hex[];
    error?: string;
}

// --- Main Async Function ---
async function performDepositWithPredicate() {
    console.log("Starting deposit process via Predicate Proxy...");

    // 1. Create Wallet Client
    const account = privateKeyToAccount(PRIVATE_KEY);
    const client = createWalletClient({
        account: account,
        chain: holesky,
        transport: http(RPC_URL),
    });
    const publicClient = createPublicClient({
        chain: holesky,
        transport: http(RPC_URL),
    });
    const senderAddress = client.account.address;
    console.log(`Using account: ${senderAddress}`);
    console.log(`Target Proxy: ${proxyAddress}`);
    console.log(`Deposit Asset: ${depositAsset}`);
    console.log(`Amount (wei/smallest unit): ${amountIn.toString()}`);
    console.log(`Recipient of Shares: ${recipientAddress}`);

    try {
        // 2. Prepare and encode the underlying deposit arguments for the Predicate API
        console.log("\nEncoding underlying deposit data for Predicate API...");
        const encodedDepositData = encodeFunctionData({
            abi: underlyingDepositAbi,
            functionName: '_deposit',
            args: [depositAsset, amountIn, minimumMint]
        });
        console.log(`Encoded Data: ${encodedDepositData}`);

        // 3. Call the Predicate API
        console.log(`\nCalling Predicate API at ${PREDICATE_API_URL}...`);
        const apiPayload = {
            from: senderAddress,
            to: proxyAddress,
            data: encodedDepositData,
            msg_value: '0'
        };
        console.log("API Payload:", apiPayload);

        let predicateApiResponse: PredicateApiResponse;
        try {
            const response = await axios.post<PredicateApiResponse>(PREDICATE_API_URL, apiPayload);
            predicateApiResponse = response.data;
            console.log("Predicate API Response:", predicateApiResponse);
        } catch (apiError: any) {
             console.error(`Error calling Predicate API: ${apiError.message}`);
             if (axios.isAxiosError(apiError) && apiError.response) {
                 console.error("API Response Data:", apiError.response.data);
             }
             throw new Error(`Predicate API call failed: ${apiError.message}`);
        }


        // 4. Check Compliance and Extract Predicate Message Components
        if (!predicateApiResponse.is_compliant) {
            console.error("Predicate API indicated transaction is non-compliant.");
            console.error("Reason:", predicateApiResponse.error || "No specific error provided.");
            throw new Error("Transaction is not compliant according to Predicate API.");
        }

        // Ensure all necessary fields are present for the tuple
        if (
            predicateApiResponse.task_id === undefined ||
            predicateApiResponse.expiry_block === undefined ||
            predicateApiResponse.signers === undefined ||
            predicateApiResponse.signature === undefined
        ) {
            throw new Error("Predicate API response missing required fields for PredicateMessage.");
        }

        // Format the response into the tuple structure required by the contract
        const predicateMessageForContract: PredicateMessageArgs = {
            policyId: predicateApiResponse.task_id,
            expiration: BigInt(predicateApiResponse.expiry_block),
            signers: predicateApiResponse.signers,
            signatures: predicateApiResponse.signature,
        };
        console.log("\nFormatted Predicate Message for contract:", predicateMessageForContract);

        // 5. Approve Proxy contract to spend the depositAsset
        console.log(`\nApproving Proxy ${proxyAddress} to spend ${amountIn} of ${depositAsset}...`);
        const approveTxHash = await client.writeContract({
            address: depositAsset,
            abi: erc20Abi,
            functionName: 'approve',
            args: [proxyAddress, amountIn]
        });
        console.log(`Approval transaction sent: ${approveTxHash}. Waiting for confirmation...`);

        // 6. Call the deposit function on the Proxy contract
        console.log(`\nDepositing via Proxy contract ${proxyAddress}...`);

        const depositArgs = [
            depositAsset,
            amountIn,
            minimumMint,
            recipientAddress,
            predicateMessageForContract
        ] as const;

        const block = await publicClient.getBlock({ blockTag: "pending" });
        const baseFee   = BigInt(block.baseFeePerGas ?? 0);
        const priority  = 2n * 10n**9n;
        const maxFee    = baseFee * 2n + priority;// over‑bid baseFee×2 + tip

        const depositTxHash = await client.writeContract({
            address: proxyAddress,
            abi: proxyDepositAbi,
            functionName: 'deposit',
            args: [
                depositArgs[0], // depositAsset
                depositArgs[1], // amountIn
                depositArgs[2], // minimumMint,
                depositArgs[3], // recipientAddress
                [
                    predicateMessageForContract.policyId,
                    predicateMessageForContract.expiration,
                    predicateMessageForContract.signers,
                    predicateMessageForContract.signatures
                ] as [
                    string,
                    bigint,
                    Address[],
                    Hex[]
                ],
              ],
              maxFeePerGas: maxFee,
              maxPriorityFeePerGas: priority
        });

        console.log(`Proxy Deposit transaction sent: ${depositTxHash}`);
        console.log("\nDeposit process via Proxy finished successfully!");
        console.log(`Track transaction: https://holesky.etherscan.io/tx/${depositTxHash}`);


    } catch (error) {
        console.error("\nAn error occurred during the deposit process:");
        console.error(error);
        process.exit(1);
    }
}

performDepositWithPredicate();
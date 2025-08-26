import axios from 'axios';
import { Address, decodeAbiParameters} from 'viem';
import { privateKeyToAccount } from "viem/accounts";

// Define the types for the API response from i inch schema in docs (v6.0)
interface TokenInfo {
    address: Address;
    symbol: string;
    name: string;
    decimals: number;
    logoURI: string;
    tags: string[];
}

interface TransactionData {
    from: Address;
    to: Address;
    data: string;
    value: string;
    gasPrice: string;
    gas: number;
}

export interface QuoteResponse {
    srcToken: TokenInfo;
    dstToken: TokenInfo;
    dstAmount: string;
    protocols: Array<Array<{
        name: string;
        part: number;
        fromTokenAddress: Address;
        toTokenAddress: Address;
    }>>;
    tx: TransactionData;
}

export async function get1inchQuote(
    chainId: number,
    fromTokenAddress: Address,
    toTokenAddress: Address,
    amount: string,
    apiKey?: string,
    executor?: Address,
    privateKey?: string
): Promise<QuoteResponse> {
    const url = `https://api.1inch.dev/swap/v6.0/${chainId}/swap`;

    const account = privateKeyToAccount(privateKey ? privateKey as `0x${string}` : process.env.PRIVATE_KEY as `0x${string}`);


    const params = {
        fromTokenAddress,
        toTokenAddress,
        amount,
        includeTokensInfo: true,
        includeProtocols: true,
        disableEstimate: true,
        slippage: 0.05,
        origin: account.address,
        from: executor || process.env.EXECUTOR_ADDRESS as Address,
        compatibility: true,
        excludeProtocols: 'BALANCER_V2'
    };

    const headers = {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey || process.env.ONEINCH_API_KEY || ''}`,
    };

    try {
        const response = await axios.get<QuoteResponse>(url, { params, headers });
        return response.data;
    } catch (error) {
        if (axios.isAxiosError(error) && error.response) {
            console.error(`Error fetching quote from 1inch:`, error.response.data);
            throw new Error(`1inch API error: ${error.response.status} ${error.response.statusText}`);
        } else {
            console.error(`Error fetching quote from 1inch:`, error);
            throw error;
        }
    }
}

function safeBigIntConversion(value: any, fieldName: string): bigint {
    if (value === undefined) {
        throw new Error('Field ${fieldName} is undefined');
    }
    if (typeof value === 'bigint') {
        return value;
    } else if (typeof value === 'string' || typeof value === 'number') {
        return BigInt(value);
    } else if (typeof value === 'object' && value !== null && 'toString' in value) {
        return BigInt(value.toString());
    }
    throw new Error('Unable to convert ${typeof value} to BigInt for field ${fieldName}');
}

function customStringify(obj: any): string {
    return JSON.stringify(obj, (_, value) =>
        typeof value === 'bigint'
            ? value.toString()
            : value === undefined
                ? 'undefined'
                : value
        , 2);
}

function decodeOneInchSwap(inputData: Hex): OneInchSwapData {
    console.log('Input data length:', inputData.length);

    // Remove the function selector (first 4 bytes / 8 characters after '0x')
    const dataWithoutSelector = '0x' + inputData.slice(10);

    try {
        const decodedData = decodeAbiParameters(
            [
                { name: 'executor', type: 'address' },
                {
                    name: 'desc',
                    type: 'tuple',
                    components: [
                        { name: 'srcToken', type: 'address' },
                        { name: 'dstToken', type: 'address' },
                        { name: 'srcReceiver', type: 'address' },
                        { name: 'dstReceiver', type: 'address' },
                        { name: 'amount', type: 'uint256' },
                        { name: 'minReturnAmount', type: 'uint256' },
                        { name: 'flags', type: 'uint256' },
                    ],
                },
                { name: 'data', type: 'bytes' },
            ],
            dataWithoutSelector as `0x${string}`
        );

        console.log('Decoded data structure:', customStringify(decodedData));

        const [executor, desc, data] = decodedData;

        if (typeof desc !== 'object' || desc === null) {
            throw new Error(`Invalid 'desc' structure. Expected object, got: ${customStringify(desc)}`);
        }

        return {
            executor: executor as Address,
            desc: {
                srcToken: desc.srcToken as Address,
                dstToken: desc.dstToken as Address,
                srcReceiver: desc.srcReceiver as Address,
                dstReceiver: desc.dstReceiver as Address,
                amount: safeBigIntConversion(desc.amount, 'amount'),
                minReturnAmount: safeBigIntConversion(desc.minReturnAmount, 'minReturnAmount'),
                flags: safeBigIntConversion(desc.flags, 'flags'),
            },
            data: data as Hex,
        };
    } catch (error : any) {
        console.error('Error decoding OneInch swap data:', error);
        throw new Error(`Failed to decode OneInch swap data: ${error?.message}`);
    }
}

var resp = await get1inchQuote(1,"0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48","0x15700B564Ca08D9439C58cA5053166E8317aa138","100000000",process.env["ONE_INCH_API_KEY"],"0x5141B82f5fFDa4c6fE1E372978F1C5427640a190",process.env["PRIVATE_KEY"])
console.log(resp.tx.data)
console.log(decodeOneInchSwap(resp.tx.data))
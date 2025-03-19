const fs = require('fs');
const { execSync } = require('child_process');
const PocketBase = require('pocketbase/cjs');
const keccak256 = require('keccak256');

const pbUrl = process.env.POCKETBASE_URL || 'http://34.201.251.108:8090';
const pb = new PocketBase(pbUrl);

function computeSelector(signature) {
    // Compute the 4-byte selector using keccak256 (Ethereum's hashing algorithm)
    return '0x' + keccak256(signature).toString('hex').slice(0, 8);
}

function parseSolidityFile(filePath) {
    const content = fs.readFileSync(filePath, 'utf8');

    // Regular expression to match functions with @tag comments
    const functionPattern = new RegExp(
        '(//\\s*@desc\\s+.*?//\\s*@tag\\s+.*?)(function\\s+(\\w+)\\s*\\((.*?)\\))|' +
        '(//\\s*@tag\\s+.*?)(function\\s+(\\w+)\\s*\\((.*?)\\))',
        'gs'
    );

    const functionsData = [];
    let match;

    while ((match = functionPattern.exec(content)) !== null) {
        const docComment = match[1] || match[5];
        const functionName = match[3] || match[7];
        const params = match[4] || match[8];

        // Extract @desc and @tag tags
        const descMatch = /\/\/\s*@desc\s+(.*)/.exec(docComment);
        const description = descMatch ? descMatch[1].trim() : "";

        const tagMatches = [...docComment.matchAll(/\/\/\s*@tag\s+(\w+):([^:]+)(?::(.*))?/g)];
        const paramsList = tagMatches.map(([_, title, type, description]) => ({ 
            title, 
            type: type.trim(),
            description: description ? description.trim() : "" 
        }));

        // Clean the parameters to only include types (remove parameter names and whitespace)
        const cleanedParams = params.split(',')
            .map(param => {
                // Extract just the type from "type name" format
                const parts = param.trim().split(/\s+/);
                return parts[0]; // Return just the type
            })
            .join(',');

        // Compute the function selector with the cleaned signature
        const signature = `${functionName}(${cleanedParams})`;
        const selector = computeSelector(signature);
        console.log(`${signature} ${selector}`);

        functionsData.push({
            selector,
            description,
            params: paramsList,
            signature: signature
        });
    }

    return functionsData;
}

async function checkExistingSelectors(selectors) {
    const existingSelectors = [];
    
    for (const selector of selectors) {
        try {
            const result = await pb.collection('decoder_selectors').getFirstListItem(`selector="${selector}"`);
            if (result) {
                existingSelectors.push(selector);
            }
        } catch (error) {
            // Not found, which is what we want
        }
    }
    
    return existingSelectors;
}

async function main() {
    // Get file path and flags from command line arguments
    const args = process.argv.slice(2);
    
    // Check for --post flag
    const postIndex = args.indexOf('--post');
    const shouldPost = postIndex !== -1;
    
    // Remove the flag from args if present
    if (postIndex !== -1) {
        args.splice(postIndex, 1);
    }
    
    if (args.length === 0) {
        console.error('Error: Please provide a file path as an argument');
        console.error('Usage: node tag_parse.js <path_to_solidity_file> [--post]');
        console.error('  --post: Post the data to PocketBase (otherwise dry run)');
        process.exit(1);
    }
    
    const filePath = args[0];
    const tempFile = 'temp.sol';

    if (!fs.existsSync(filePath)) {
        console.error(`Error: File not found: ${filePath}`);
        process.exit(1);
    }

    console.log(`Processing file: ${filePath}`);
    if (!shouldPost) {
        console.log('DRY RUN MODE: Data will not be posted to PocketBase. Use --post flag to post data.');
    }

    // Authenticate before making requests
    await authenticatePocketBase();

    // Run forge flatten and create temp.sol
    try {
        execSync(`forge flatten ${filePath} > ${tempFile}`);
    } catch (error) {
        console.error('Error flattening the Solidity file:', error.message);
        process.exit(1);
    }

    // Parse the temp.sol file
    const functionsData = parseSolidityFile(tempFile);
    
    console.log(`Found ${functionsData.length} tagged functions`);
    
    // Print out the found functions
    functionsData.forEach(func => {
        console.log(`- ${func.signature} => ${func.selector}`);
        console.log(`  Description: ${func.description}`);
        console.log(`  Tags: ${JSON.stringify(func.params)}`);
    });

    // Delete the temp.sol file
    fs.unlinkSync(tempFile);

    // Check for existing selectors
    const selectorsToCheck = functionsData.map(func => func.selector);
    const existingSelectors = await checkExistingSelectors(selectorsToCheck);

    // Filter out functions with selectors that already exist
    const newFunctionsData = functionsData.filter(func => !existingSelectors.includes(func.selector));

    console.log(`Found ${existingSelectors.length} selectors that already exist in the database`);
    console.log(`Found ${newFunctionsData.length} new selectors to add`);

    // Only proceed with posting if --post flag is present
    if (!shouldPost) {
        console.log('Dry run complete. Use --post flag to post data to PocketBase.');
        return;
    }

    // If there are no new selectors to add, exit gracefully
    if (newFunctionsData.length === 0) {
        console.log('No new selectors to add. Exiting.');
        return;
    }

    console.log('Posting data to PocketBase...');

    // Create the requests array with proper data formatting
    const requests = newFunctionsData.map(data => ({
        method: 'POST',
        url: '/api/collections/decoder_selectors/records',
        body: {
            selector: data.selector,
            description: data.description,
            tags: JSON.stringify(data.params),
            signature: data.signature
        }
    }));

    // Make sure the request body is correctly structured
    const requestBody = {
        requests: requests
    };

    try {
        const result = await pb.send('/api/batch', {
            method: 'POST',
            body: requestBody
        });
        console.log('Batch create result:', result);
    } catch (error) {
        console.error('Error creating batch:', error);
        console.error('Error details:', error.response?.data || error.message);
    }
}

main().catch(error => {
    console.error('Unhandled error:', error);
    process.exit(1);
}); 
const fs = require('fs');
const crypto = require('crypto');
const { execSync } = require('child_process');
const PocketBase = require('pocketbase/cjs');

const pb = new PocketBase('http://127.0.0.1:8090');

function computeSelector(signature) {
    // Compute the 4-byte selector from the function signature
    return '0x' + crypto.createHash('sha3-256').update(signature).digest('hex').slice(0, 8);
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

        const tagMatches = [...docComment.matchAll(/\/\/\s*@tag\s+(\w+):(\w+)/g)];
        const paramsList = tagMatches.map(([_, title, type]) => ({ title, type }));

        // Compute the function selector
        const signature = `${functionName}(${params})`;
        const selector = computeSelector(signature);

        functionsData.push({
            selector,
            description,
            params: paramsList
        });
    }

    return functionsData;
}

async function main() {
    // Example file path
    const filePath = 'src/base/DecodersAndSanitizers/EarnETHSwellDecoderAndSanitizer.sol';
    const tempFile = 'temp.sol';

    if (!fs.existsSync(filePath)) {
        console.log(`File not found: ${filePath}`);
        return;
    }

    console.log(`forge flatten ${filePath} > ${tempFile}`)
    // Run forge flatten and create temp.sol
    execSync(`forge flatten ${filePath} > ${tempFile}`);

    // Parse the temp.sol file
    const functionsData = parseSolidityFile(tempFile);

    // Delete the temp.sol file
    fs.unlinkSync(tempFile);

    // Create a batch for PocketBase
    const batch = pb.createBatch();

    const dataObjects = functionsData.map(functionData => ({
        selector: functionData.selector,
        description: functionData.description,
        tags: JSON.stringify(functionData.params) // Convert params to JSON string
    }));

    // Test with a single record
    // const sampleData = dataObjects[0];
    // try {
    //     const record = await pb.collection('decoder_selectors').create({
    //         selector: sampleData.selector,
    //         description: sampleData.description,
    //         tags: sampleData.tags
    //     });
    //     console.log('Single record created successfully:', record);
    // } catch (error) {
    //     console.error('Error creating single record:', error);
    //     console.error('Error details:', error.response?.data || error.message);
    // }

    // Add debugging to check if dataObjects has content
    console.log('Number of data objects:', dataObjects.length);
    if (dataObjects.length > 0) {
        console.log('Sample data object:', dataObjects[0]);
    }

    // Create the requests array with proper data formatting
    const requests = dataObjects.map(data => ({
        method: 'POST',
        url: '/api/collections/decoder_selectors/records',
        body: {
            selector: data.selector,  // Make sure this matches the expected format
            description: data.description,
            tags: data.tags
        }
    }));

    // Check if requests array is properly formed
    console.log('Number of requests:', requests.length);
    if (requests.length > 0) {
        console.log('Sample request:', requests[0]);
    }

    // Make sure the request body is correctly structured
    const requestBody = {
        requests: requests
    };
    console.log('Request body structure:', JSON.stringify(requestBody, null, 2));

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

main(); 
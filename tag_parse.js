import fs from 'fs';
import { execSync } from 'child_process';
import PocketBase from 'pocketbase';
import keccak256 from 'keccak256';
import path from 'path';

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

// Function to find all Solidity files in the DecodersAndSanitizers directory
function findAllDecoderFiles() {
    const baseDir = 'src/base/DecodersAndSanitizers';
    
    try {
        const files = execSync(`find ${baseDir} -name "*.sol"`, { encoding: 'utf8' })
            .trim()
            .split('\n')
            .filter(file => file); // Remove any empty strings
        
        console.log(`Found ${files.length} Solidity files in ${baseDir}`);
        return files;
    } catch (error) {
        console.error('Error finding Solidity files:', error.message);
        return [];
    }
}

// Function to process a single file
async function processFile(filePath, shouldPost) {
    console.log(`\nProcessing file: ${filePath}`);
    const tempFile = `temp_${path.basename(filePath)}`;

    try {
        // Run forge flatten and create temp file
        execSync(`forge flatten ${filePath} > ${tempFile}`);
        
        // Parse the temp file
        const functionsData = parseSolidityFile(tempFile);
        
        console.log(`Found ${functionsData.length} tagged functions in ${filePath}`);
        
        // Print out the found functions
        functionsData.forEach(func => {
            console.log(`- ${func.signature} => ${func.selector}`);
            console.log(`  Description: ${func.description}`);
            console.log(`  Tags: ${JSON.stringify(func.params)}`);
        });

        // Delete the temp file
        fs.unlinkSync(tempFile);

        if (shouldPost && functionsData.length > 0) {
            // Check for existing selectors
            const selectorsToCheck = functionsData.map(func => func.selector);
            const existingSelectors = await checkExistingSelectors(selectorsToCheck);

            // Filter out functions with selectors that already exist
            const newFunctionsData = functionsData.filter(func => !existingSelectors.includes(func.selector));

            console.log(`Found ${existingSelectors.length} selectors that already exist in the database`);
            console.log(`Found ${newFunctionsData.length} new selectors to add`);

            // Only proceed with posting if there are new selectors to add
            if (newFunctionsData.length > 0) {
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
            } else {
                console.log('No new selectors to add for this file.');
            }
        } else if (!shouldPost) {
            console.log('DRY RUN MODE: Data will not be posted to PocketBase.');
        }

        return functionsData.length;
    } catch (error) {
        console.error(`Error processing file ${filePath}:`, error.message);
        // Try to clean up temp file if it exists
        if (fs.existsSync(tempFile)) {
            fs.unlinkSync(tempFile);
        }
        return 0;
    }
}

async function main() {
    // Get command line arguments
    const args = process.argv.slice(2);
    
    // Check for flags
    const postIndex = args.indexOf('--post');
    const shouldPost = postIndex !== -1;
    if (postIndex !== -1) {
        args.splice(postIndex, 1);
    }
    
    const allDecodersIndex = args.indexOf('--all-decoders');
    const processAllDecoders = allDecodersIndex !== -1;
    if (allDecodersIndex !== -1) {
        args.splice(allDecodersIndex, 1);
    }
    
    let filesToProcess = [];
    
    if (processAllDecoders) {
        // Process all decoder files
        filesToProcess = findAllDecoderFiles();
        console.log(`Will process all ${filesToProcess.length} decoder files`);
    } else if (args.length > 0) {
        // Process specific files provided as arguments
        filesToProcess = args;
        console.log(`Will process ${filesToProcess.length} specified files`);
    } else {
        console.error('Error: Please provide file paths as arguments or use --all-decoders flag');
        console.error('Usage: node tag_parse.js [file_paths...] [--post] [--all-decoders]');
        console.error('  --post: Post the data to PocketBase (otherwise dry run)');
        console.error('  --all-decoders: Process all files in src/base/DecodersAndSanitizers');
        process.exit(1);
    }
    
    // Process each file
    let totalFunctions = 0;
    for (const file of filesToProcess) {
        if (!fs.existsSync(file)) {
            console.error(`Error: File not found: ${file}`);
            continue;
        }
        
        const functionCount = await processFile(file, shouldPost);
        totalFunctions += functionCount;
    }
    
    console.log(`\nProcessing complete. Found ${totalFunctions} total tagged functions across ${filesToProcess.length} files.`);
}

// Execute the main function
main().catch(error => {
    console.error('Unhandled error:', error);
    process.exit(1);
}); 
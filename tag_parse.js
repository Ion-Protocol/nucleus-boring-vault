import fs from 'fs';
import { execSync } from 'child_process';
import PocketBase from 'pocketbase';
import keccak256 from 'keccak256';
import path from 'path';

const pbUrl = process.env.POCKETBASE_URL || 'http://34.201.251.108:8090';
const pb = new PocketBase(pbUrl);

// Object to store custom type mappings extracted from flattened files
const customTypeMapping = {};

// Extract struct definitions from a flattened Solidity file
function extractStructDefinitions(flattenedContent) {
    // Match contract and library definitions to extract their names
    const contractRegex = /(?:contract|library|interface)\s+(\w+)(?:\s+is\s+[^{]+)?{/g;
    const contractMatches = [...flattenedContent.matchAll(contractRegex)];
    
    // Extract all struct definitions
    const structRegex = /struct\s+(\w+)\s*\{([^}]+)\}/g;
    let structMatch;
    
    while ((structMatch = structRegex.exec(flattenedContent)) !== null) {
        const structName = structMatch[1];
        const structBody = structMatch[2];
        
        // Parse struct fields
        const fields = structBody.split(';')
            .map(field => field.trim())
            .filter(field => field !== '')
            .map(field => {
                // Extract just the type from field definitions
                const parts = field.split(/\s+/);
                return parts[0]; // Return just the type
            });
        
        // Create tuple representation
        const tupleRepresentation = `(${fields.join(',')})`;
        
        // Determine the parent contract/library for each struct
        // Find which contract/library this struct is defined in
        let parentContract = '';
        for (let i = contractMatches.length - 1; i >= 0; i--) {
            if (contractMatches[i].index < structMatch.index) {
                parentContract = contractMatches[i][1];
                break;
            }
        }
        
        // Add to mapping with various forms used in the codebase
        if (parentContract) {
            // Add the fully qualified name with the parent contract
            customTypeMapping[`${parentContract}.${structName}`] = tupleRepresentation;
            console.log(`Found struct (${parentContract}.${structName}): ${tupleRepresentation}`);
        }
        
        // Also map common formats like DecoderCustomTypes.X even if it's not the exact parent
        customTypeMapping[`DecoderCustomTypes.${structName}`] = tupleRepresentation;
        
        // Also add just the struct name for simple references
        customTypeMapping[structName] = tupleRepresentation;
    }
    
    console.log(`Total struct definitions found: ${Object.keys(customTypeMapping).length}`);
    console.log("Custom type mappings:", customTypeMapping);
}

function computeSelector(signature) {
    // Compute the 4-byte selector using keccak256 (Ethereum's hashing algorithm)
    return '0x' + keccak256(signature).toString('hex').slice(0, 8);
}

function expandCustomTypes(signature) {
    // Extract function name and parameter list
    const match = signature.match(/^(\w+)\((.*)\)$/);
    if (!match) return signature;
    
    const functionName = match[1];
    const params = match[2];
    
    if (!params) return signature; // No parameters to process
    
    // Split parameters and process each one
    const processedParams = params.split(',').map(param => {
        const trimmedParam = param.trim();
        
        // Skip empty params
        if (!trimmedParam) return '';
        
        // Check for direct match in customTypeMapping
        if (customTypeMapping[trimmedParam]) {
            console.log(`Found exact match for ${trimmedParam} => ${customTypeMapping[trimmedParam]}`);
            return customTypeMapping[trimmedParam];
        }
        
        // Try without any modifiers (calldata, memory, storage)
        const cleanPattern = /^(.*?)(?:\s+(?:calldata|memory|storage))?(?:\s+\w+)?$/;
        const cleanMatch = trimmedParam.match(cleanPattern);
        
        if (cleanMatch) {
            const cleanType = cleanMatch[1].trim();
            
            // Check if this cleaned type is in our mapping
            if (customTypeMapping[cleanType]) {
                console.log(`Found cleaned match for ${trimmedParam} (${cleanType}) => ${customTypeMapping[cleanType]}`);
                return customTypeMapping[cleanType];
            }
            
            // Check for "DecoderCustomTypes.X" format
            if (cleanType.includes(".")) {
                const parts = cleanType.split(".");
                if (parts.length === 2 && parts[0] === "DecoderCustomTypes") {
                    const structName = parts[1];
                    const lookupKey = `DecoderCustomTypes.${structName}`;
                    
                    if (customTypeMapping[lookupKey]) {
                        console.log(`Found DecoderCustomTypes match for ${cleanType} => ${customTypeMapping[lookupKey]}`);
                        return customTypeMapping[lookupKey];
                    }
                }
            }
        }
        
        // Last resort: look for any key that ends with the same structure name
        const lastDotIndex = trimmedParam.lastIndexOf(".");
        if (lastDotIndex !== -1) {
            const structName = trimmedParam.substring(lastDotIndex + 1);
            
            // See if we have this struct by itself
            if (customTypeMapping[structName]) {
                console.log(`Found partial match for ${trimmedParam} (${structName}) => ${customTypeMapping[structName]}`);
                return customTypeMapping[structName];
            }
        }
        
        // If no custom type match found, return the original parameter
        return trimmedParam;
    }).join(',');
    
    return `${functionName}(${processedParams})`;
}

function parseSolidityFile(filePath) {
    const content = fs.readFileSync(filePath, 'utf8');
    
    // Extract struct definitions first
    extractStructDefinitions(content);

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

        // Get the raw signature with parameter types and names
        const rawSignature = `${functionName}(${params})`;
        
        // First, extract just the types for the canonical signature
        const cleanedParams = params.split(',')
            .map(param => {
                // Extract just the type from "type name" format
                const parts = param.trim().split(/\s+/);
                return parts[0]; // Return just the type
            })
            .join(',');
            
        // Get a simplified signature with just types (no parameter names)
        const typeSignature = `${functionName}(${cleanedParams})`;
        
        // Now expand any custom types to their tuple representations
        const expandedSignature = expandCustomTypes(typeSignature);
        
        // Compute the function selector with the expanded signature
        const selector = computeSelector(expandedSignature);
        
        console.log(`Original: ${rawSignature}`);
        console.log(`Simplified: ${typeSignature}`);
        console.log(`Expanded: ${expandedSignature}`);
        console.log(`Selector: ${selector}`);

        functionsData.push({
            selector,
            description,
            params: paramsList,
            signature: expandedSignature,
            originalSignature: rawSignature
        });
    }

    return functionsData;
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
            console.log(`- ${func.originalSignature} => ${func.signature} => ${func.selector}`);
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
                        signature: data.signature,
                        originalSignature: data.originalSignature
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
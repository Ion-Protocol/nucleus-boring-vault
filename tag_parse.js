import fs from 'fs';
import { execSync } from 'child_process';
import PocketBase from 'pocketbase';
import keccak256 from 'keccak256';
import path from 'path';

const pbUrl = process.env.POCKETBASE_URL || 'http://34.201.251.108:8090';
const pb = new PocketBase(pbUrl);

// Function to compute the 4-byte selector using keccak256
function computeSelector(signature) {
    return '0x' + keccak256(signature).toString('hex').slice(0, 8);
}

// Function to flatten struct types into tuples with their actual component types
function flattenType(input) {
    // If it's not a tuple/struct, return the type directly
    if (input.type !== 'tuple' && !input.type.startsWith('tuple[')) {
        return input.type;
    }
    
    // Handle arrays of tuples
    const isArray = input.type.includes('[');
    const arrayNotation = isArray ? input.type.substring(input.type.indexOf('[')) : '';
    
    // Process the components recursively
    const flattenedComponents = input.components.map(component => {
        if (component.components) {
            // This is a nested struct/tuple
            return flattenType(component);
        }
        return component.type;
    });
    
    // Return the tuple notation with flattened component types
    return `(${flattenedComponents.join(',')})${arrayNotation}`;
}

// Parse source file for @desc and @tag comments
function parseSourceFile(filePath) {
    try {
        // Create a temporary flattened file to parse
        const tempFile = `temp_${path.basename(filePath)}`;
        execSync(`forge flatten ${filePath} > ${tempFile}`);
        
        const content = fs.readFileSync(tempFile, 'utf8');
        fs.unlinkSync(tempFile); // Clean up temp file
        
        // Regular expression to match functions with @tag and @desc comments
        const functionPattern = new RegExp(
            '(//\\s*@desc\\s+.*?//\\s*@tag\\s+.*?)(function\\s+(\\w+)\\s*\\((.*?)\\))|' +
            '(//\\s*@tag\\s+.*?)(function\\s+(\\w+)\\s*\\((.*?)\\))',
            'gs'
        );
        
        const functionDocs = {};
        let match;
        
        while ((match = functionPattern.exec(content)) !== null) {
            const docComment = match[1] || match[5];
            const functionName = match[3] || match[7];
            
            // Extract @desc tag
            const descMatch = /\/\/\s*@desc\s+(.*)/.exec(docComment);
            const description = descMatch ? descMatch[1].trim() : "";
            
            // Extract @tag tags
            const tagMatches = [...docComment.matchAll(/\/\/\s*@tag\s+(\w+):([^:]+)(?::(.*))?/g)];
            const tags = tagMatches.map(([_, title, type, description]) => ({ 
                title, 
                type: type.trim(),
                description: description ? description.trim() : "" 
            }));
            
            functionDocs[functionName] = {
                description,
                tags
            };
        }
        
        return functionDocs;
    } catch (error) {
        console.error(red(`Error parsing source file ${filePath}: ${error}`));
        return {};
    }
}

// Process contract ABI and source file to extract function information
function processContract(filePath, shouldPost = false) {
    try {
        // Get the output directory and contract name
        const fileBasename = path.basename(filePath, '.sol');
        const outputPath = path.join('out', fileBasename+".sol", `${fileBasename}.json`);
        
        // Check if the output file exists
        if (!fs.existsSync(outputPath)) {
            console.error(red(`Output file not found: ${outputPath}`));
            console.error(red(`Try running 'forge build' first.`));
            return 0;
        }
        
        // Extract docs from source file
        const functionDocs = parseSourceFile(filePath);
        
        // Read and parse the ABI JSON file
        const fileContent = fs.readFileSync(outputPath, 'utf8');
        const jsonData = JSON.parse(fileContent);
        
        if (!jsonData.abi) {
            console.error(red(`ABI not found in the JSON file: ${outputPath}`));
            return 0;
        }
        
        // Filter for function entries only
        const functions = jsonData.abi.filter(item => item.type === 'function');
        
        // Process each function
        const functionsData = [];
        
        functions.forEach(func => {
            // Skip if no documentation found
            if (!functionDocs[func.name]) {
                return;
            }
            
            // Build parameter list with flattened types
            const params = func.inputs.map(input => flattenType(input));
            
            // Construct function signature
            const signature = `${func.name}(${params.join(',')})`;
            
            // Compute function selector
            const selector = computeSelector(signature);
            
            // Get documentation
            const docs = functionDocs[func.name];
            
            functionsData.push({
                selector,
                description: docs.description || '',
                params: docs.tags || [],
                signature: signature
            });
        });
        
        if (shouldPost && functionsData.length > 0) {
            return postToPocketBase(functionsData);
        }
        
        return functionsData.length;
    } catch (error) {
        console.error(red(`Error processing contract ${filePath}: ${error}`));
        return 0;
    }
}

// Check for existing selectors in the database
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

// Post function data to PocketBase
async function postToPocketBase(functionsData) {
    try {
        let successCount = 0;
        
        // Process each record individually instead of using batch
        for (const data of functionsData) {
            try {
                // First check if this selector already exists
                try {
                    await pb.collection('decoder_selectors').getFirstListItem(`selector="${data.selector}"`);
                    // If we get here, selector exists - skip this record
                    continue;
                } catch (notFoundError) {
                    // This is good - the record doesn't exist, so we can create it
                }
                
                // Create the new record
                await pb.collection('decoder_selectors').create({
                    selector: data.selector,
                    description: data.description,
                    tags: JSON.stringify(data.params),
                    signature: data.signature
                });
                
                // If we got here, the creation was successful
                successCount++;
            } catch (error) {
                // Log error but continue with other records
                console.error(red(`Error processing selector ${data.selector}: ${error.message}`));
            }
        }
        
        return successCount;
    } catch (error) {
        console.error(red(`Error posting to PocketBase: ${error}`));
        return 0;
    }
}

// Function to find all Solidity files in the DecodersAndSanitizers directory
function findAllDecoderFiles(includeSubdirs = false) {
    const baseDir = 'src/base/DecodersAndSanitizers';
    
    try {
        // Use -maxdepth 1 to limit search to only the specified directory
        const depthOption = includeSubdirs ? '' : '-maxdepth 1';
        const files = execSync(`find ${baseDir} ${depthOption} -name "*.sol"`, { encoding: 'utf8' })
            .trim()
            .split('\n')
            .filter(file => file); // Remove any empty strings
        
        return files;
    } catch (error) {
        console.error(red(`Error finding Solidity files: ${error.message}`));
        return [];
    }
}

// Helper function to print text in color
function colorText(text, colorCode) {
    return `\x1b[${colorCode}m${text}\x1b[0m`;
}

// Convenience function for red text (for errors)
function red(text) {
    return colorText(text, 31);
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
    
    // Add subdirectory option
    const includeSubdirsIndex = args.indexOf('--include-subdirs');
    const includeSubdirs = includeSubdirsIndex !== -1;
    if (includeSubdirsIndex !== -1) {
        args.splice(includeSubdirsIndex, 1);
    }
    
    let filesToProcess = [];
    
    if (processAllDecoders) {
        // Process all decoder files
        filesToProcess = findAllDecoderFiles(includeSubdirs);
    } else if (args.length > 0) {
        // Process specific files provided as arguments
        filesToProcess = args;
    } else {
        console.error(red('Error: Please provide file paths as arguments or use --all-decoders flag'));
        console.error(red('Usage: node tag_parse.js [file_paths...] [--post] [--all-decoders] [--include-subdirs]'));
        console.error(red('  --post: Post the data to PocketBase (otherwise dry run)'));
        console.error(red('  --all-decoders: Process all files in src/base/DecodersAndSanitizers'));
        console.error(red('  --include-subdirs: Include files in subdirectories when using --all-decoders'));
        process.exit(1);
    }
    
    // Process each file
    let totalFunctions = 0;
    for (const file of filesToProcess) {
        if (!fs.existsSync(file)) {
            console.error(red(`Error: File not found: ${file}`));
            continue;
        }
        
        const functionCount = await processContract(file, shouldPost);
        totalFunctions += functionCount;
    }
}

// Execute the main function
main().catch(error => {
    console.error(red(`Unhandled error: ${error}`));
    process.exit(1);
}); 
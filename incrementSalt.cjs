const fs = require('fs').promises;
const crypto = require('crypto');
require('dotenv').config();

// SALT requirements
// 1. deployer protected (first 20 bytes = ETH_FROM address)
// 2. NOT cross-chain protected (21st byte = 0x00)
// 3. random 11 bytes for entropy

const args = process.argv.slice(2);
if (args.length < 1) {
    console.error("Usage: node incrementSalt.cjs <fileName1> [fileName2] ...");
    process.exit(1);
}

// Read ETH_FROM environment variable
const ethFrom = process.env.ETH_FROM;
if (!ethFrom) {
    console.error("Error: ETH_FROM environment variable is required");
    process.exit(1);
}

// Validate ETH_FROM is a valid Ethereum address
if (!ethFrom.match(/^0x[a-fA-F0-9]{40}$/)) {
    console.error("Error: ETH_FROM must be a valid Ethereum address (0x followed by 40 hex characters)");
    process.exit(1);
}

console.log(`Using ETH_FROM address: ${ethFrom}`);

const fileNames = args;

// Generate a new deployer protected salt
const generateDeployerProtectedSalt = () => {
    // Remove 0x prefix from ETH_FROM and pad to 20 bytes
    const deployerAddress = ethFrom.slice(2).toLowerCase().padStart(40, '0');
    
    // Generate 11 random bytes for entropy
    const randomBytes = crypto.randomBytes(11);
    const randomHex = randomBytes.toString('hex');
    
    // Construct salt: deployer address (20 bytes) + 0x00 (1 byte) + random bytes (11 bytes)
    const salt = '0x' + deployerAddress + '00' + randomHex;
    
    return salt;
};

// Collect all unique salt field paths from all files
const collectSaltPaths = (obj, keyPath = '', saltPaths = new Set()) => {
    for (let key in obj) {
        const currentPath = keyPath ? `${keyPath}.${key}` : key;
        
        if (typeof obj[key] === 'string' && obj[key].startsWith('0x') && key.toLowerCase().includes('salt')) {
            saltPaths.add(currentPath);
        } else if (typeof obj[key] === 'object') {
            collectSaltPaths(obj[key], currentPath, saltPaths);
        }
    }
    return saltPaths;
};

// Update salts in an object using the provided salt map
const updateSalts = (obj, saltMap, keyPath = '') => {
    for (let key in obj) {
        const currentPath = keyPath ? `${keyPath}.${key}` : key;
        
        if (typeof obj[key] === 'string' && obj[key].startsWith('0x') && key.toLowerCase().includes('salt')) {
            if (saltMap.has(currentPath)) {
                obj[key] = saltMap.get(currentPath);
                console.log(`Updated salt for key '${currentPath}': ${saltMap.get(currentPath)}`);
            }
        } else if (typeof obj[key] === 'object') {
            updateSalts(obj[key], saltMap, currentPath);
        }
    }
};

// Main processing function
(async () => {
    try {
        // Step 1: Read all files and collect unique salt field paths
        console.log('\nStep 1: Collecting salt field paths from all files...');
        const allSaltPaths = new Set();
        
        for (const fileName of fileNames) {
            const filePath = 'deployment-config/' + fileName;
            try {
                const data = await fs.readFile(filePath, 'utf8');
                const jsonData = JSON.parse(data);
                collectSaltPaths(jsonData, '', allSaltPaths);
            } catch (err) {
                console.error(`Error reading file ${fileName}:`, err);
                process.exit(1);
            }
        }
        
        console.log(`Found ${allSaltPaths.size} unique salt field path(s):`);
        allSaltPaths.forEach(path => console.log(`  - ${path}`));
        
        // Step 2: Generate one salt per unique field path
        console.log('\nStep 2: Generating salts for each unique field path...');
        const saltMap = new Map();
        for (const path of allSaltPaths) {
            const salt = generateDeployerProtectedSalt();
            saltMap.set(path, salt);
            console.log(`  ${path}: ${salt}`);
        }
        
        // Step 3: Apply the same salts to all files
        console.log('\nStep 3: Applying salts to all files...');
        for (let i = 0; i < fileNames.length; i++) {
            const fileName = fileNames[i];
            const filePath = 'deployment-config/' + fileName;
            
            console.log(`\n[${i + 1}/${fileNames.length}] Processing file: ${fileName}`);
            
            try {
                const data = await fs.readFile(filePath, 'utf8');
                const jsonData = JSON.parse(data);
                
                updateSalts(jsonData, saltMap);
                
                await fs.writeFile(filePath, JSON.stringify(jsonData, null, 2), 'utf8');
                console.log(`✓ File ${fileName} successfully updated with deployer protected salts`);
            } catch (err) {
                console.error(`Error processing file ${fileName}:`, err);
                process.exit(1);
            }
        }
        
        console.log('\n✓ All files updated successfully with identical salts for matching fields!');
    } catch (err) {
        console.error('Error:', err);
        process.exit(1);
    }
})();
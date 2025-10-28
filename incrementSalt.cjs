const fs = require('fs');
const crypto = require('crypto');
require('dotenv').config();

// SALT requirements
// 1. deployer protected (first 20 bytes = ETH_FROM address)
// 2. NOT cross-chain protected (21st byte = 0x00)
// 3. random 11 bytes for entropy

const args = process.argv.slice(2);
if (args.length < 1) {
    console.error("Usage: node incrementSalt.cjs <fileName>");
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

const [fileName] = args;
const filePath = 'deployment-config/'+fileName;

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

fs.readFile(filePath, 'utf8', (err, data) => {
    if (err) {
        console.error('Error reading file:', err);
        return;
    }

    let jsonData = JSON.parse(data);

    const updateSalts = (obj, keyPath = '') => {
        for (let key in obj) {
            const currentPath = keyPath ? `${keyPath}.${key}` : key;
            
            if (typeof obj[key] === 'string' && obj[key].startsWith('0x') && key.toLowerCase().includes('salt')) {
                const newSalt = generateDeployerProtectedSalt();
                obj[key] = newSalt;
                console.log(`Updated salt for key '${currentPath}': ${newSalt}`);
            } else if (typeof obj[key] === 'object') {
                updateSalts(obj[key], currentPath);
            }
        }
    };

    updateSalts(jsonData);

    fs.writeFile(filePath, JSON.stringify(jsonData, null, 2), 'utf8', (err) => {
        if (err) {
            console.error('Error writing file:', err);
            return;
        }
        console.log('File successfully updated with deployer protected salts');
    });
});
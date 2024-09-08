const fs = require('fs');


const args = process.argv.slice(2);
if (args.length < 1) {
    console.error("Usage: node incrementSalt.cjs <fileName>");
    process.exit(1);
}

const [fileName] = args;
const filePath = 'deployment-config/'+fileName;

fs.readFile(filePath, 'utf8', (err, data) => {
    if (err) {
        console.error('Error reading file:', err);
        return;
    }

    let jsonData = JSON.parse(data);

    const incrementHex = (hex) => {
        let num = BigInt(hex);
        num += 1n;
        return '0x' + num.toString(16);
    };

    const incrementSalts = (obj) => {
        for (let key in obj) {
            if (typeof obj[key] === 'string' && obj[key].startsWith('0x') && key.toLowerCase().includes('salt')) {
                obj[key] = incrementHex(obj[key]);
            } else if (typeof obj[key] === 'object') {
                incrementSalts(obj[key]);
            }
        }
    };

    incrementSalts(jsonData);

    fs.writeFile(filePath, JSON.stringify(jsonData, null, 2), 'utf8', (err) => {
        if (err) {
            console.error('Error writing file:', err);
            return;
        }
        console.log('File successfully updated');
    });
});
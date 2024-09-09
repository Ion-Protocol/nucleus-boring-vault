import { log } from 'console';

const fs = require('fs');
const readline = require('readline');

// Function to load the DVN JSON data
function loadDvns() {
    const data = fs.readFileSync('./deployment-config/layerzero/dvn-deployments.json', 'utf8');
    return JSON.parse(data);
}

// Function to find an address in the JSON data
function findAddressInJson(addresses, jsonData, searchKey = "") {
    const results = [];
    const lowerCaseAddresses = addresses.map(a => a.toLowerCase());

    for (const [parentKey, parentValue] of Object.entries(jsonData)) {
        for (const [key, value] of Object.entries(parentValue)) {
            if (lowerCaseAddresses.includes(value.toLowerCase())) {
                results.push([parentKey, key, value]);
            }
        }
    }

    if (searchKey === "") {
        if (results.length === 1) {
            const [parentKey, key, value] = results[0];
            return [true, key, parentKey];
        } else {
            return [false, null, null];
        }
    } else {
        for (const [parentKey, key, value] of results) {
            if (key === searchKey) {
                return [true, key, parentKey];
            }
        }
        return [false, null, null];
    }
}

// Function to get findings from a config file
function getFindingsInConfig(configName) {
    const dvnJsonData = loadDvns();
    const data = fs.readFileSync(`./deployment-config/${configName}`, 'utf8');
    const configJsonData = JSON.parse(data);

    const required = configJsonData.teller.dvnIfNoDefault.required;
    const optional = configJsonData.teller.dvnIfNoDefault.optional;
    const addresses = [...required, ...optional];

    let chain = "";
    for (const address of addresses) {
        const [found, key, parentKey] = findAddressInJson([address], dvnJsonData);
        if (found) {
            chain = key;
            break;
        }
    }

    if (chain === "") {
        throw new Error("❌ All provided configs have duplicates or are not found in the DVN registry");
    }

    const findings = [];
    for (const address of addresses) {
        const [found, key, parentKey] = findAddressInJson([address], dvnJsonData, chain);
        if (found) {
            findings.push({ address, chain: key, provider: parentKey });
        } else {
            console.log("Not Found ", address);
        }
    }

    return {
        findings,
        requiredCount: required.length,
        optionalCount: optional.length,
        confirmations: configJsonData.teller.dvnIfNoDefault.blockConfirmationsRequiredIfNoDefault,
        threshold: configJsonData.teller.dvnIfNoDefault.optionalThreshold
    };
}

function assert(statement, message){
    if(!statement){
        throw new Error("❌ "+message)
    }
}

// Main function
async function main() {
    const args = process.argv.slice(2);

    if (args.length != 2) {
        console.error("Usage: node script.js <file1Name> <file2Name>");
        process.exit(1);
    }

    const [file1Name, file2Name] = args;

    try {
        const findings1 = getFindingsInConfig(file1Name);
        const findings2 = getFindingsInConfig(file2Name);

        assert(findings1.confirmations == findings2.confirmations, "Confirmations do not match");
        assert(findings1.threshold == findings2.threshold, "thresholds do not match");
        assert(findings1.requiredCount == findings2.requiredCount, "required DVNs count does not match");
        assert(findings1.optionalCount == findings2.optionalCount, "optional DVNs count does not match");

        const chain1 = findings1.findings[0].chain;
        const providers1 = findings1.findings.map(finding => finding.provider);
        for (const finding of findings1.findings) {
            assert(finding.chain == chain1, "Networks do not match for "+finding)
        }

        const chain2 = findings2.findings[0].chain;
        const providers2 = findings2.findings.map(finding => finding.provider);
        for (const finding of findings2.findings) {
            assert(providers1.includes(finding.provider), "Provider: "+finding.provider+" does not have a matching provider in the first config");
            assert(finding.chain == chain2, "Networks do not match for: "+finding);
        }

        console.log('chain1', chain1);
        console.log('providers1', providers1);
        console.log('chain2', chain2);
        console.log('providers2', providers2);

        console.log("✅ Config check passed");
    } catch (error) {
        console.error(error.message);
    }
}

main();

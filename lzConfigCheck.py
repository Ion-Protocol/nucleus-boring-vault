import json

def load_dvns():
    # Load the JSON data from the dvns file
    with open('./deployment-config/layerzero/dvn-deployments.json', 'r') as file:
        dvn_json_data = json.load(file)
    return dvn_json_data

def find_address_in_json(addresses, json_data, searchKey=""):
    results = []

    for parent_key, parent_value in json_data.items():
        for key, value in parent_value.items():
            addresses = [a.lower() for a in addresses]
            if value.lower() in addresses:
                results.append((parent_key, key, value))

    if searchKey == "":
        if len(results) == 1:
            parent_key, key, value = results[0]
            return True, key, parent_key
        else:
            return False, None, None
    else:
        for result in results:
            parent_key, key, value = result
            if key == searchKey:
                return True, key, parent_key

        return False, None, None
    
def get_findings_in_config(config_name):
    dvn_json_data = load_dvns()

    with open("./deployment-config/"+config_name, 'r') as file:
        config_json_data = json.load(file)

    # Example addresses to search for
    required = config_json_data['teller']['dvnIfNoDefault']['required']
    optional = config_json_data['teller']['dvnIfNoDefault']['optional']
    addresses = required + optional

    # first use find_address_in_json to find the chain
    chain = ""
    for address in addresses:
        found, key, parent_key = find_address_in_json([address], dvn_json_data)
        if found:
            chain = key
            break

    if chain == "":
        raise Exception("All provided configs have duplicates or are not found in the DVN registry")

    # second create a findings array
    findings = []

    for address in addresses:
        found, key, parent_key = find_address_in_json([address], dvn_json_data, chain)
        if found:
            findings.append({'address': address, 'chain': key, 'provider': parent_key})
        else:
            print("Not Found ",address)

    return {'findings': findings, 'requiredCount': len(required), 'optionalCount': len(optional), 'confirmations': config_json_data['teller']['dvnIfNoDefault']['blockConfirmationsRequiredIfNoDefault'], 'threshold': config_json_data['teller']['dvnIfNoDefault']['optionalThreshold']}


def main():
    file1Name = input("enter the name of the first config deployment file in deployment-config/ (ex. exampleL1.json):\n")
    file2Name = input("enter the name of the first config deployment file in deployment-config/ (ex. exampleL2.json):\n")
    # file1Name = "exampleL1.json"
    # file2Name = "exampleL2.json"

    findings1 = get_findings_in_config(file1Name)
    
    findings2 = get_findings_in_config(file2Name)

    assert(findings1['confirmations'] == findings2['confirmations'])
    assert(findings1['threshold'] == findings2['threshold'])
    assert(findings1['requiredCount'] == findings2['requiredCount'])
    assert(findings1['optionalCount'] == findings2['optionalCount'])

    chain1 = findings1['findings'][0]['chain']
    providers1 = []
    for finding in findings1['findings']:
        providers1.append(finding['provider'])
        assert(finding['chain'] == chain1)

    chain2 = findings2['findings'][0]['chain']
    for finding in findings2['findings']:
        assert(finding['provider'] in providers1)
        assert(finding['chain'] == chain2)

    print("✅ Config check passed")


if __name__ == "__main__":
    main()
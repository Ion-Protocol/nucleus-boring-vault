contract BaseTokenStandIn {
    uint8 public immutable decimals;
    string public name;

    constructor(string memory _name, uint8 _decimals) {
        name = _name;
        decimals = _decimals;
    }
}

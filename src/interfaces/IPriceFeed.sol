pragma solidity ^0.8.0;

interface IPriceFeed {
    /**
     * @notice The precision of the value being returned from the price feed.
     */
    function decimals() external view returns (uint8);

    /**
     * @notice Return oracle data for Chainlink or Redstone price feeds.
     */
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    function description() external view returns (string memory);

    function getDataFeedId() external view returns (bytes32);
}

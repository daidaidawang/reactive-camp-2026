// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IReactive} from "@reactive/src/interfaces/IReactive.sol";
import {ISystemContract} from "@reactive/src/interfaces/ISystemContract.sol";
import {AbstractReactive} from "@reactive/src/base/AbstractReactive.sol";

/// @notice Bounded Cron100 experiment. It requests no more than maxRuns callbacks.
contract BoundedCronReactive is AbstractReactive {
    address public constant LEGACY_SYSTEM_ADDRESS = 0x0000000000000000000000000000000000fffFfF;
    uint256 public constant CRON100_TOPIC_0 = 0xb49937fb8970e19fd46d48f7e3fb00d659deac0347f79cd7cb542f0fc1503c70;
    uint64 public constant CALLBACK_GAS_LIMIT = 100_000;

    address public immutable owner;
    uint256 public immutable destinationChainId;
    uint256 public immutable maxRuns;

    address public recipient;
    uint256 public cronRuns;
    bool public started;
    bool public stopped;

    mapping(bytes32 => bool) public seenCronLogs;

    event CronCallbackRequested(uint256 indexed run, uint256 indexed sourceBlock, uint256 txHash, uint256 logIndex);
    event CronSubscriptionStopped(uint256 totalRuns);

    error NotOwner(address caller);
    error InvalidConfiguration();
    error AlreadyStarted();
    error NotStarted();
    error RecipientAlreadySet();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner(msg.sender);
        _;
    }

    constructor(uint256 destinationChainId_, uint256 maxRuns_) payable {
        if (destinationChainId_ == 0 || maxRuns_ == 0) revert InvalidConfiguration();
        owner = msg.sender;
        destinationChainId = destinationChainId_;
        maxRuns = maxRuns_;
    }

    function setRecipient(address recipient_) external onlyOwner {
        if (started || recipient != address(0) || recipient_ == address(0)) revert RecipientAlreadySet();
        recipient = recipient_;
    }

    function start() external onlyOwner {
        if (started || stopped) revert AlreadyStarted();
        if (recipient == address(0)) revert InvalidConfiguration();
        started = true;
        _subscribe();
    }

    function stop() external onlyOwner {
        if (!started || stopped) revert NotStarted();
        stopped = true;
        _unsubscribe();
        emit CronSubscriptionStopped(cronRuns);
    }

    /// @inheritdoc IReactive
    function react(LogRecord memory log_) external onlySystem {
        if (
            !started || stopped || cronRuns >= maxRuns || log_.chainId != block.chainid
                || log_.contractAddress != LEGACY_SYSTEM_ADDRESS || log_.topic0 != CRON100_TOPIC_0
        ) return;

        bytes32 logKey =
            keccak256(abi.encode(log_.chainId, log_.contractAddress, log_.blockHash, log_.txHash, log_.logIndex));
        if (seenCronLogs[logKey]) return;
        seenCronLogs[logKey] = true;

        uint256 run = ++cronRuns;
        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: destinationChainId,
                recipient: recipient,
                gasLimit: CALLBACK_GAS_LIMIT,
                payload: abi.encodeWithSignature(
                    "recordTick(address,uint256,uint256)", address(0), run, log_.blockNumber
                )
            })
        );
        emit CronCallbackRequested(run, log_.blockNumber, log_.txHash, log_.logIndex);

        if (cronRuns == maxRuns) {
            stopped = true;
            _unsubscribe();
            emit CronSubscriptionStopped(cronRuns);
        }
    }

    function _subscribe() internal {
        SYSTEM.subscribe(
            block.chainid, LEGACY_SYSTEM_ADDRESS, CRON100_TOPIC_0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE
        );
    }

    function _unsubscribe() internal {
        SYSTEM.unsubscribe(
            block.chainid, LEGACY_SYSTEM_ADDRESS, CRON100_TOPIC_0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE
        );
    }
}

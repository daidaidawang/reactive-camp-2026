// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IReactive} from "@reactive/src/interfaces/IReactive.sol";
import {ISystemContract} from "@reactive/src/interfaces/ISystemContract.sol";
import {AbstractReactive} from "@reactive/src/base/AbstractReactive.sol";

/// @notice Omni event -> evidence -> optional explanation -> deterministic callback.
contract AgentSentinel is AbstractReactive {
    uint256 internal constant RISK_TOPIC = uint256(keccak256("RiskAlert(uint256,address,bytes32,uint256,uint256)"));
    uint64 internal constant CALLBACK_GAS_LIMIT = 1_000_000;
    uint256 public constant VERDICT_TIMEOUT = 5 minutes;
    uint256 public constant RETRY_DELAY = 1 minutes;
    address public immutable _OWNER;
    uint256 public immutable ORIGIN_CHAIN_ID;
    address public immutable EXECUTOR;
    address public recipient;
    bool public aiMode;

    struct Alert {
        address agent;
        bytes32 capId;
        uint256 amount;
        uint256 maxSpend;
        bool open;
        uint256 observedAt;
    }
    mapping(uint256 => Alert) public alerts;
    mapping(uint256 => bool) public seen;
    mapping(uint256 => uint256) public lastDispatchAt;
    event AlertObserved(
        uint256 indexed receiptId,
        address indexed agent,
        bytes32 indexed capId,
        uint256 amount,
        uint256 maxSpend,
        bool aiMode
    );
    event VerdictAccepted(uint256 indexed receiptId, uint256 level, address indexed judge, string reason);
    event Dispatched(uint256 indexed receiptId, address indexed agent, uint256 level);
    event DispatchFailed(uint256 indexed receiptId);
    event RecipientSet(address indexed recipient);
    event AiModeSet(bool enabled);

    modifier onlyOwner() {
        require(msg.sender == _OWNER, "not owner");
        _;
    }

    constructor(uint256 originChainId_, address executor_) payable {
        require(originChainId_ > 0 && executor_ != address(0), "invalid origin");
        _OWNER = msg.sender;
        ORIGIN_CHAIN_ID = originChainId_;
        EXECUTOR = executor_;
        SYSTEM.subscribe(originChainId_, executor_, RISK_TOPIC, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
    }

    // One-time configuration, including across the two-chain deployment gap.
    function setRecipient(address value) external onlyOwner {
        require(recipient == address(0) && value != address(0), "invalid recipient");
        recipient = value;
        emit RecipientSet(value);
    }

    function setAiMode(bool enabled) external onlyOwner {
        aiMode = enabled;
        emit AiModeSet(enabled);
    }

    function coverDebt() external onlyOwner {
        _coverDebt();
    }

    function react(LogRecord memory log_) external onlySystem {
        if (log_.chainId != ORIGIN_CHAIN_ID || log_.contractAddress != EXECUTOR || log_.topic0 != RISK_TOPIC) return;
        if (log_.data.length != 64 || log_.topic1 == 0 || log_.topic2 == 0 || log_.topic2 > type(uint160).max) return;
        uint256 id = log_.topic1;
        if (seen[id]) return;
        (uint256 amount, uint256 maxSpend) = abi.decode(log_.data, (uint256, uint256));
        if (amount <= maxSpend) return;
        seen[id] = true;
        alerts[id] = Alert(address(uint160(log_.topic2)), bytes32(log_.topic3), amount, maxSpend, true, block.timestamp);
        emit AlertObserved(id, alerts[id].agent, alerts[id].capId, amount, maxSpend, aiMode);
        // Keep evidence pending if deployment wiring is not complete yet.
        if (!aiMode && recipient != address(0)) _dispatch(id);
    }

    function submitVerdict(uint256 id, uint256 level, string calldata reason) external onlyOwner {
        require(seen[id] && alerts[id].open, "not pending");
        require(level == 3, "cannot downgrade hard violation");
        require(bytes(reason).length > 0 && bytes(reason).length <= 512, "invalid reason");
        emit VerdictAccepted(id, level, msg.sender, reason);
        _dispatch(id);
    }

    /// @notice Permissionless liveness fallback; somebody must send this transaction.
    function dispatchExpired(uint256 id) external {
        require(seen[id] && alerts[id].open, "not pending");
        require(!aiMode || block.timestamp >= alerts[id].observedAt + VERDICT_TIMEOUT, "verdict window open");
        _dispatch(id);
    }

    /// @notice Dispatch is not delivery. Owner can retry the same immutable evidence.
    function retryDispatch(uint256 id) external onlyOwner {
        require(seen[id] && !alerts[id].open, "not dispatched");
        require(block.timestamp >= lastDispatchAt[id] + RETRY_DELAY, "retry too soon");
        _dispatch(id);
    }

    function _dispatch(uint256 id) internal {
        require(recipient != address(0), "recipient not set");
        Alert storage a = alerts[id];
        try SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: ORIGIN_CHAIN_ID,
                recipient: recipient,
                gasLimit: CALLBACK_GAS_LIMIT,
                payload: abi.encodeWithSignature(
                    "onSentinelVerdict(address,address,bytes32,uint256,uint256)",
                    address(0),
                    a.agent,
                    a.capId,
                    id,
                    uint256(3)
                )
            })
        ) {
            a.open = false;
            lastDispatchAt[id] = block.timestamp;
            emit Dispatched(id, a.agent, 3);
        } catch {
            // Preserve the observation so funding/service failures can be retried.
            emit DispatchFailed(id);
        }
    }
}

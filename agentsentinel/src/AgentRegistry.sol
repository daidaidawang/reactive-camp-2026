// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title AgentRegistry — AI 智能体身份注册表（Base/Sepolia 侧）
/// @notice 被守护对象的身份与运行状态。状态是守护管线处置的载体之一。
contract AgentRegistry {
    enum Status { None, Active, Suspended, Revoked }

    struct Agent {
        string did;
        Status status;
        uint256 registeredAt;
        uint256 lastChangedAt;
    }

    address public owner;
    address public operator; // 处置执行者（跨链回调目标合约）
    mapping(address => Agent) public agents;

    event AgentRegistered(address indexed agent, string did);
    event AgentStatusChanged(address indexed agent, Status indexed status, uint256 at, string reason);
    event OperatorSet(address indexed operator);

    error NotOwner(address caller);
    error NotOperator(address caller);
    error NotRegistered(address agent);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner(msg.sender);
        _;
    }

    /// @notice owner 或 operator（跨链回调落点）均可变更状态。
    modifier onlyOwnerOrOperator() {
        if (msg.sender != owner && msg.sender != operator) revert NotOperator(msg.sender);
        _;
    }

    modifier registered(address agent_) {
        if (agents[agent_].status == Status.None) revert NotRegistered(agent_);
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /// @notice 授权处置执行者（SentinelCallbackTarget）可变更 Agent 状态。
    function setOperator(address operator_) external onlyOwner {
        operator = operator_;
        emit OperatorSet(operator_);
    }

    function registerAgent(address agent_, string calldata did_) external onlyOwner {
        require(agents[agent_].status == Status.None, "already registered");
        agents[agent_] = Agent({ did: did_, status: Status.Active, registeredAt: block.timestamp, lastChangedAt: block.timestamp });
        emit AgentRegistered(agent_, did_);
    }

    /// @notice 状态变更：Active / Suspended / Revoked。撤权处置最终落点之一。
    function setStatus(address agent_, Status status_, string calldata reason_)
        external
        onlyOwnerOrOperator
        registered(agent_)
    {
        agents[agent_].status = status_;
        agents[agent_].lastChangedAt = block.timestamp;
        emit AgentStatusChanged(agent_, status_, block.timestamp, reason_);
    }

    function isActive(address agent_) external view returns (bool) {
        return agents[agent_].status == Status.Active;
    }
}

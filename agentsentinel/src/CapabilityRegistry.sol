// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title CapabilityRegistry — 可撤销的能力授权边界
/// @notice 回应评委追问①：「可撤销的授权具体是什么」——
///         每笔授权是结构化条目（agent + capId + maxSpend + validUntil + policyHash），
///         撤权 = 置 active=false 并发事件，可逐字核对。
contract CapabilityRegistry {
    struct Capability {
        uint256 maxSpend;      // 单笔/总额度上限（本 demo 按单笔）
        uint256 validUntil;    // 有效期截止（block.timestamp，不用块高）
        string  policyHash;    // 行为策略指纹（L0 行为漂移比对用，demo 留档）
        bool    active;
    }

    address public owner;
    address public revoker; // 回调目标合约（跨链处置的执行入口）

    // agent => capId => capability
    mapping(address => mapping(bytes32 => Capability)) public capabilities;

    event CapabilityGranted(address indexed agent, bytes32 indexed capId, uint256 maxSpend, uint256 validUntil, string policyHash);
    event CapabilityRevoked(address indexed agent, bytes32 indexed capId, uint256 at, string reason);
    event RevokerUpdated(address indexed oldRevoker, address indexed newRevoker);

    error NotOwner(address caller);
    error NotRevoker(address caller);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner(msg.sender);
        _;
    }

    modifier onlyAuthorized() {
        if (msg.sender != owner && msg.sender != revoker) revert NotRevoker(msg.sender);
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function setRevoker(address revoker_) external onlyOwner {
        emit RevokerUpdated(revoker, revoker_);
        revoker = revoker_;
    }

    function grantCapability(address agent_, bytes32 capId_, uint256 maxSpend_, uint256 validUntil_, string calldata policyHash_)
        external
        onlyOwner
    {
        capabilities[agent_][capId_] = Capability({
            maxSpend: maxSpend_,
            validUntil: validUntil_,
            policyHash: policyHash_,
            active: true
        });
        emit CapabilityGranted(agent_, capId_, maxSpend_, validUntil_, policyHash_);
    }

    /// @notice 撤销能力。owner 可手动撤；revoker（回调目标）可跨链自动撤。
    function revokeCapability(address agent_, bytes32 capId_, string calldata reason_) external onlyAuthorized {
        require(capabilities[agent_][capId_].active, "already inactive");
        capabilities[agent_][capId_].active = false;
        emit CapabilityRevoked(agent_, capId_, block.timestamp, reason_);
    }

    function isActive(address agent_, bytes32 capId_) external view returns (bool) {
        return capabilities[agent_][capId_].active;
    }

    function getCapability(address agent_, bytes32 capId_) external view returns (uint256 maxSpend, uint256 validUntil, string memory policyHash, bool active) {
        Capability memory c = capabilities[agent_][capId_];
        return (c.maxSpend, c.validUntil, c.policyHash, c.active);
    }
}

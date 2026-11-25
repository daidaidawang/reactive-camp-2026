// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title CapabilityRegistry — 可撤销的能力授权边界
/// @notice 每笔授权包含单笔额度、有效期和策略标签；撤权置 active=false。
contract CapabilityRegistry {
    struct Capability {
        uint256 maxSpend; // 单笔 wei 上限，不限制累计支出
        uint256 validUntil; // 有效期截止（block.timestamp，不用块高）
        string policyHash; // 策略标签，仅留档，不执行语义校验
        bool active;
    }

    address public owner;
    address public revoker; // 回调目标合约（跨链处置的执行入口）

    // agent => capId => capability
    mapping(address => mapping(bytes32 => Capability)) public capabilities;

    event CapabilityGranted(
        address indexed agent, bytes32 indexed capId, uint256 maxSpend, uint256 validUntil, string policyHash
    );
    event CapabilityRevoked(address indexed agent, bytes32 indexed capId, uint256 timestamp, string reason);
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

    function grantCapability(
        address agent_,
        bytes32 capId_,
        uint256 maxSpend_,
        uint256 validUntil_,
        string calldata policyHash_
    ) external onlyOwner {
        require(agent_ != address(0) && maxSpend_ > 0 && validUntil_ > block.timestamp, "invalid capability");
        capabilities[agent_][capId_] =
            Capability({maxSpend: maxSpend_, validUntil: validUntil_, policyHash: policyHash_, active: true});
        emit CapabilityGranted(agent_, capId_, maxSpend_, validUntil_, policyHash_);
    }

    /// @notice 撤销能力。owner 可手动撤；revoker（回调目标）可跨链自动撤。
    function revokeCapability(address agent_, bytes32 capId_, string calldata reason_) external onlyAuthorized {
        if (!capabilities[agent_][capId_].active) return;
        capabilities[agent_][capId_].active = false;
        emit CapabilityRevoked(agent_, capId_, block.timestamp, reason_);
    }

    function isActive(address agent_, bytes32 capId_) external view returns (bool) {
        Capability storage c = capabilities[agent_][capId_];
        return c.active && block.timestamp < c.validUntil;
    }

    function getCapability(address agent_, bytes32 capId_)
        external
        view
        returns (uint256 maxSpend, uint256 validUntil, string memory policyHash, bool active)
    {
        Capability memory c = capabilities[agent_][capId_];
        return (c.maxSpend, c.validUntil, c.policyHash, c.active);
    }
}

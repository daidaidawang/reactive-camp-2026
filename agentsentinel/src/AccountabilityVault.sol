// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title AccountabilityVault — 保证金金库（风险可定价的经济闭环）
/// @notice Agent 质押保证金；L3 终止处置时由授权方（回调目标合约）罚没。
///         罚没即处置，也即「风险可定价」：承保方未来可据此对 Agent 行为定价。
contract AccountabilityVault {
    address public owner;
    address public slasher; // 回调目标合约

    mapping(address => uint256) public stakes;

    event Staked(address indexed agent, uint256 amount);
    event Slashed(address indexed agent, uint256 amount, string reason);

    error NotOwner(address caller);
    error NotSlasher(address caller);
    error NothingStaked(address agent);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner(msg.sender);
        _;
    }

    modifier onlySlasher() {
        if (msg.sender != slasher) revert NotSlasher(msg.sender);
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function setSlasher(address slasher_) external onlyOwner {
        slasher = slasher_;
    }

    /// @notice Agent 质押保证金。
    function stake() external payable {
        require(msg.value > 0, "zero stake");
        stakes[msg.sender] += msg.value;
        emit Staked(msg.sender, msg.value);
    }

    /// @notice 罚没：L3 终止处置的链上落点。全额罚没，语义清晰便于演示。
    function slash(address agent_, string calldata reason_) external onlySlasher {
        uint256 amount = stakes[agent_];
        if (amount == 0) revert NothingStaked(agent_);
        stakes[agent_] = 0;
        emit Slashed(agent_, amount, reason_);
    }

    /// @notice 未被罚没的余额可自主取出。
    function withdraw() external {
        uint256 amount = stakes[msg.sender];
        require(amount > 0, "nothing to withdraw");
        stakes[msg.sender] = 0;
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "withdraw failed");
    }
}

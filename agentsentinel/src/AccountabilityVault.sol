// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @notice Fixed-policy demo bond, locked atomically with a rejected request.
contract AccountabilityVault {
    address public immutable owner = msg.sender;
    address public executor;
    address public slasher;
    uint256 public totalStaked;
    uint256 public forfeited;
    mapping(address => uint256) public stakes;
    mapping(address => bool) public locked;

    event Staked(address indexed agent, uint256 amount);
    event BondLocked(address indexed agent);
    event Slashed(address indexed agent, uint256 amount, string reason);
    event Withdrawn(address indexed agent, uint256 amount);
    event ForfeitureClaimed(address indexed recipient, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    function setExecutor(address value) external onlyOwner {
        require(executor == address(0) && value.code.length > 0, "invalid executor");
        executor = value;
    }

    function setSlasher(address value) external onlyOwner {
        require(slasher == address(0) && value.code.length > 0, "invalid slasher");
        slasher = value;
    }

    function stake() external payable {
        require(msg.value > 0 && !locked[msg.sender], "invalid stake");
        stakes[msg.sender] += msg.value;
        totalStaked += msg.value;
        emit Staked(msg.sender, msg.value);
    }

    function lock(address agent) external {
        require(msg.sender == executor, "not executor");
        require(stakes[agent] > 0 && !locked[agent], "invalid bond");
        locked[agent] = true;
        emit BondLocked(agent);
    }

    function slash(address agent, string calldata reason) external {
        require(msg.sender == slasher, "not slasher");
        require(locked[agent], "bond not locked");
        uint256 amount = stakes[agent];
        stakes[agent] = 0;
        locked[agent] = false;
        totalStaked -= amount;
        forfeited += amount;
        emit Slashed(agent, amount, reason);
    }

    function withdraw() external {
        require(!locked[msg.sender], "pending disposition");
        uint256 amount = stakes[msg.sender];
        require(amount > 0, "nothing to withdraw");
        stakes[msg.sender] = 0;
        totalStaked -= amount;
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "withdraw failed");
        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Penalties are claimable by the sponsor, not burned or priced insurance.
    function claimForfeiture(address payable recipient) external onlyOwner {
        require(recipient != address(0), "zero recipient");
        uint256 amount = forfeited;
        require(amount > 0, "nothing forfeited");
        forfeited = 0;
        (bool ok,) = recipient.call{value: amount}("");
        require(ok, "claim failed");
        emit ForfeitureClaimed(recipient, amount);
    }
}

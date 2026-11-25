// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {AgentRegistry} from "./AgentRegistry.sol";
import {CapabilityRegistry} from "./CapabilityRegistry.sol";
import {AccountabilityVault} from "./AccountabilityVault.sol";

/// @notice Sponsor-funded ETH orders to one fixed merchant. Only this escrow is protected.
contract SentinelExecutor {
    AgentRegistry public immutable agentRegistry;
    CapabilityRegistry public immutable capabilityRegistry;
    AccountabilityVault public immutable vault;
    address public immutable owner = msg.sender;
    address payable public immutable merchant;
    uint256 public immutable minimumBond;
    uint256 public immutable totalSpendLimit;
    uint256 public totalSpent;
    address public resolver;
    uint256 public availableBudget;
    uint256 public merchantCredit;
    uint256 public receiptSeq;
    mapping(address => uint256) public pendingReceipt;

    struct Receipt {
        address agent;
        bytes32 capId;
        uint256 amount;
        uint256 maxSpend;
        bool overLimit;
        bool settled;
    }
    mapping(uint256 => Receipt) public receipts;

    event ActionReceipt(
        uint256 indexed receiptId,
        address indexed agent,
        bytes32 indexed capId,
        uint256 amount,
        uint256 maxSpend,
        bool overLimit,
        uint256 timestamp
    );
    event RiskAlert(
        uint256 indexed receiptId, address indexed agent, bytes32 indexed capId, uint256 amount, uint256 maxSpend
    );
    event OrderAccepted(uint256 indexed receiptId, address indexed merchant, uint256 amount);
    event OrderBlocked(uint256 indexed receiptId);
    event BudgetFunded(uint256 amount);
    event BudgetWithdrawn(address indexed recipient, uint256 amount);
    event MerchantPaid(uint256 amount);
    event ReceiptSettled(uint256 indexed receiptId);

    constructor(
        address registry_,
        address capabilities_,
        address vault_,
        address payable merchant_,
        uint256 minimumBond_,
        uint256 totalSpendLimit_
    ) {
        require(
            registry_.code.length > 0 && capabilities_.code.length > 0 && vault_.code.length > 0, "invalid dependency"
        );
        require(merchant_ != address(0) && minimumBond_ > 0 && totalSpendLimit_ > 0, "invalid policy");
        agentRegistry = AgentRegistry(registry_);
        capabilityRegistry = CapabilityRegistry(capabilities_);
        vault = AccountabilityVault(vault_);
        merchant = merchant_;
        minimumBond = minimumBond_;
        totalSpendLimit = totalSpendLimit_;
    }

    function setResolver(address value) external {
        require(msg.sender == owner && resolver == address(0) && value.code.length > 0, "invalid resolver");
        resolver = value;
    }

    function fund() external payable {
        require(msg.sender == owner && msg.value > 0, "invalid funding");
        availableBudget += msg.value;
        emit BudgetFunded(msg.value);
    }

    function executeOrder(bytes32 capId, uint256 amount) external returns (uint256 id) {
        require(resolver != address(0) && vault.executor() == address(this) && vault.slasher() == resolver, "not wired");
        require(agentRegistry.isActive(msg.sender), "agent not active");
        require(pendingReceipt[msg.sender] == 0, "pending disposition");
        require(vault.stakes(msg.sender) >= minimumBond, "insufficient bond");
        (uint256 maxSpend, uint256 validUntil,, bool active) = capabilityRegistry.getCapability(msg.sender, capId);
        require(active && block.timestamp < validUntil, "inactive or expired capability");
        require(amount > 0, "zero amount");
        bool overLimit = amount > maxSpend;
        id = ++receiptSeq;
        receipts[id] = Receipt(msg.sender, capId, amount, maxSpend, overLimit, false);
        emit ActionReceipt(id, msg.sender, capId, amount, maxSpend, overLimit, block.timestamp);
        if (overLimit) {
            pendingReceipt[msg.sender] = id;
            vault.lock(msg.sender);
            emit OrderBlocked(id);
            emit RiskAlert(id, msg.sender, capId, amount, maxSpend);
        } else {
            require(availableBudget >= amount, "insufficient budget");
            // Lifetime limit across all agents/capabilities. Funding and claims never reset it.
            require(amount <= totalSpendLimit - totalSpent, "total spend limit exceeded");
            totalSpent += amount;
            availableBudget -= amount;
            merchantCredit += amount;
            emit OrderAccepted(id, merchant, amount);
        }
    }

    function withdrawBudget(address payable recipient, uint256 amount) external {
        require(msg.sender == owner && recipient != address(0), "invalid budget withdrawal");
        require(amount > 0 && amount <= availableBudget, "insufficient available budget");
        availableBudget -= amount;
        (bool ok,) = recipient.call{value: amount}("");
        require(ok, "budget withdrawal failed");
        emit BudgetWithdrawn(recipient, amount);
    }

    function settle(uint256 id) external {
        require(msg.sender == resolver, "not resolver");
        Receipt storage r = receipts[id];
        require(r.overLimit && !r.settled && pendingReceipt[r.agent] == id, "invalid receipt");
        r.settled = true;
        pendingReceipt[r.agent] = 0;
        emit ReceiptSettled(id);
    }

    function claimPayment() external {
        require(msg.sender == merchant, "not merchant");
        uint256 amount = merchantCredit;
        require(amount > 0, "nothing to claim");
        merchantCredit = 0;
        (bool ok,) = merchant.call{value: amount}("");
        require(ok, "payment failed");
        emit MerchantPaid(amount);
    }
}

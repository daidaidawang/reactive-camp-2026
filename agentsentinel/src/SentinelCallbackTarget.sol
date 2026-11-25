// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IPayable} from "@reactive/src/interfaces/IPayable.sol";
import {AbstractCallback} from "@reactive/src/base/AbstractCallback.sol";
import {AgentRegistry} from "./AgentRegistry.sol";
import {CapabilityRegistry} from "./CapabilityRegistry.sol";
import {AccountabilityVault} from "./AccountabilityVault.sol";
import {SentinelExecutor} from "./SentinelExecutor.sol";

/// @notice Authenticate both proxy and reactive sender, then verify source-local evidence.
contract SentinelCallbackTarget is AbstractCallback {
    AgentRegistry public immutable agentRegistry;
    CapabilityRegistry public immutable capabilityRegistry;
    AccountabilityVault public immutable vault;
    SentinelExecutor public immutable executor;
    mapping(uint256 => bool) public processed;
    event DispositionExecuted(
        uint256 indexed receiptId, address indexed agent, bytes32 indexed capId, uint256 level, string action
    );
    event DuplicateIgnored(uint256 indexed receiptId);

    constructor(IPayable proxy_, address sender_, address executor_) payable AbstractCallback(proxy_, sender_) {
        require(
            address(proxy_).code.length > 0 && sender_ != address(0) && executor_.code.length > 0,
            "invalid configuration"
        );
        executor = SentinelExecutor(executor_);
        agentRegistry = executor.agentRegistry();
        capabilityRegistry = executor.capabilityRegistry();
        vault = executor.vault();
    }

    function onSentinelVerdict(address reactive_, address agent_, bytes32 capId_, uint256 receiptId_, uint256 level_)
        external
        onlyServiceProvider
        onlyCallbackSender(reactive_)
    {
        require(level_ == 3, "unsupported disposition");
        (address agent, bytes32 capId, uint256 amount, uint256 maxSpend, bool overLimit,) =
            executor.receipts(receiptId_);
        require(agent == agent_ && capId == capId_ && overLimit && amount > maxSpend, "evidence mismatch");
        if (processed[receiptId_]) {
            emit DuplicateIgnored(receiptId_);
            return;
        }
        processed[receiptId_] = true;
        capabilityRegistry.revokeCapability(agent, capId, "L3: blocked overspend request");
        vault.slash(agent, "L3: fixed-policy bond forfeiture");
        agentRegistry.setStatus(agent, AgentRegistry.Status.Revoked, "L3: agent revoked");
        executor.settle(receiptId_);
        emit DispositionExecuted(receiptId_, agent, capId, 3, "revoke+slash+revokeIdentity");
    }
}

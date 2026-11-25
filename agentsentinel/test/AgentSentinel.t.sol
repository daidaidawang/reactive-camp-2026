// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IReactive} from "@reactive/src/interfaces/IReactive.sol";
import {ISystemContract} from "@reactive/src/interfaces/ISystemContract.sol";
import {IPayable} from "@reactive/src/interfaces/IPayable.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {CapabilityRegistry} from "../src/CapabilityRegistry.sol";
import {AccountabilityVault} from "../src/AccountabilityVault.sol";
import {SentinelExecutor} from "../src/SentinelExecutor.sol";
import {SentinelCallbackTarget} from "../src/SentinelCallbackTarget.sol";
import {AgentSentinel} from "../src/AgentSentinel.sol";

contract MockSystem {
    bytes public payload;
    address public recipient;
    address public sender;
    uint256 public chainId;
    uint256 public requests;
    bool public fail;
    function subscribe(uint256, address, uint256, uint256, uint256, uint256) external {}

    function setFail(bool value) external {
        fail = value;
    }

    function requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0 memory c) external {
        require(!fail, "system unavailable");
        requests++;
        payload = c.payload;
        recipient = c.recipient;
        chainId = c.chainId;
        sender = msg.sender;
    }
}

contract MockProxy {
    function deliver(address recipient, address sender, bytes memory payload) external {
        // Omni replaces the first ABI argument, not the selector.
        assembly { mstore(add(payload, 36), sender) }
        (bool ok, bytes memory result) = recipient.call(payload);
        if (!ok) assembly { revert(add(result, 32), mload(result)) }
    }
}

contract AgentSentinelTest is Test {
    address constant SYSTEM = 0x8888888888888888888888888888888888888888;
    uint256 constant ORIGIN = 11155111;
    bytes32 constant CAP = keccak256("purchase");
    bytes32 constant RISK = keccak256("RiskAlert(uint256,address,bytes32,uint256,uint256)");
    address agent = address(0xA11CE);
    address payable merchant = payable(address(0xB0B));
    AgentRegistry registry;
    CapabilityRegistry caps;
    AccountabilityVault vault;
    SentinelExecutor executor;
    AgentSentinel sentinel;
    SentinelCallbackTarget callback;
    MockSystem system;
    MockProxy proxy;

    function setUp() public {
        vm.warp(1000);
        vm.deal(address(this), 100 ether);
        vm.deal(agent, 5 ether);
        vm.etch(SYSTEM, address(new MockSystem()).code);
        system = MockSystem(SYSTEM);
        proxy = new MockProxy();
        registry = new AgentRegistry();
        caps = new CapabilityRegistry();
        vault = new AccountabilityVault();
        executor = new SentinelExecutor(address(registry), address(caps), address(vault), merchant, 1 ether, 20 ether);
        sentinel = new AgentSentinel(ORIGIN, address(executor));
        callback = new SentinelCallbackTarget(IPayable(payable(address(proxy))), address(sentinel), address(executor));
        registry.setOperator(address(callback));
        caps.setRevoker(address(callback));
        vault.setExecutor(address(executor));
        vault.setSlasher(address(callback));
        executor.setResolver(address(callback));
        sentinel.setRecipient(address(callback));
        registry.registerAgent(agent, "did:demo:alice");
        caps.grantCapability(agent, CAP, 1 ether, block.timestamp + 1 days, "fixed-policy-v2");
        vm.prank(agent);
        vault.stake{value: 1 ether}();
        executor.fund{value: 10 ether}();
    }

    function risk(uint256 id) internal view returns (IReactive.LogRecord memory l) {
        l.chainId = ORIGIN;
        l.contractAddress = address(executor);
        l.topic0 = uint256(RISK);
        l.topic1 = id;
        l.topic2 = uint256(uint160(agent));
        l.topic3 = uint256(CAP);
        l.data = abi.encode(2 ether, 1 ether);
    }

    function observe(IReactive.LogRecord memory l) internal {
        vm.prank(SYSTEM);
        sentinel.react(l);
    }

    function deliver() internal {
        proxy.deliver(system.recipient(), system.sender(), system.payload());
    }

    function violation() internal returns (uint256 id) {
        vm.prank(agent);
        id = executor.executeOrder(CAP, 2 ether);
    }

    function testEndToEndFromActualEventAndMerchantPayment() public {
        vm.prank(agent);
        executor.executeOrder(CAP, 1 ether);
        assertEq(executor.merchantCredit(), 1 ether);
        vm.prank(merchant);
        executor.claimPayment();
        assertEq(merchant.balance, 1 ether);
        vm.recordLogs();
        uint256 id = violation();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter == address(executor) && logs[i].topics[0] == RISK) {
                IReactive.LogRecord memory l = risk(id);
                l.topic1 = uint256(logs[i].topics[1]);
                l.topic2 = uint256(logs[i].topics[2]);
                l.topic3 = uint256(logs[i].topics[3]);
                l.data = logs[i].data;
                observe(l);
                found = true;
            }
        }
        assertTrue(found);
        assertEq(system.chainId(), ORIGIN);
        assertEq(system.recipient(), address(callback));
        assertEq(executor.availableBudget(), 9 ether); // rejected request never spends
        assertTrue(vault.locked(agent));
        deliver();
        assertFalse(registry.isActive(agent));
        assertFalse(caps.isActive(agent, CAP));
        assertEq(vault.stakes(agent), 0);
        assertEq(vault.forfeited(), 1 ether);
        assertEq(executor.pendingReceipt(agent), 0);
        assertTrue(callback.processed(id));
        vault.claimForfeiture(payable(address(0xCAFE)));
        assertEq(address(0xCAFE).balance, 1 ether);
        vm.expectRevert("agent not active");
        vm.prank(agent);
        executor.executeOrder(CAP, 1);
    }

    function testPendingBlocksWithdrawalAndFurtherOrders() public {
        violation();
        vm.startPrank(agent);
        vm.expectRevert("pending disposition");
        vault.withdraw();
        vm.expectRevert("pending disposition");
        executor.executeOrder(CAP, 1);
        vm.expectRevert("invalid stake");
        vault.stake{value: 1 wei}();
        vm.stopPrank();
    }

    function testWithdrawBeforeRequestCannotEvadeBond() public {
        vm.startPrank(agent);
        vault.withdraw();
        vm.expectRevert("insufficient bond");
        executor.executeOrder(CAP, 2 ether);
        vm.stopPrank();
        assertEq(executor.receiptSeq(), 0);
    }

    function testDuplicateRiskAndCallbackAreIdempotent() public {
        uint256 id = violation();
        observe(risk(id));
        observe(risk(id));
        assertEq(system.requests(), 1);
        deliver();
        deliver();
        assertEq(vault.forfeited(), 1 ether);
    }

    function testManualRevocationDoesNotBreakCallback() public {
        uint256 id = violation();
        caps.revokeCapability(agent, CAP, "manual");
        registry.setStatus(agent, AgentRegistry.Status.Revoked, "manual");
        observe(risk(id));
        deliver();
        assertEq(vault.forfeited(), 1 ether);
    }

    function testRevocationIsTerminalAndCannotEraseIdentity() public {
        vm.expectRevert("cannot erase registration");
        registry.setStatus(agent, AgentRegistry.Status.None, "erase");
        registry.setStatus(agent, AgentRegistry.Status.Revoked, "revoke");
        vm.expectRevert("revocation is terminal");
        registry.setStatus(agent, AgentRegistry.Status.Active, "restore");
    }

    function testExpiryBoundaryAndZeroOrder() public {
        vm.expectRevert("zero amount");
        vm.prank(agent);
        executor.executeOrder(CAP, 0);
        vm.warp(block.timestamp + 1 days);
        assertFalse(caps.isActive(agent, CAP));
        vm.expectRevert("inactive or expired capability");
        vm.prank(agent);
        executor.executeOrder(CAP, 1);
    }

    function testInsufficientBudgetRollsBackReceipt() public {
        caps.grantCapability(agent, CAP, 11 ether, block.timestamp + 1 days, "test");
        vm.expectRevert("insufficient budget");
        vm.prank(agent);
        executor.executeOrder(CAP, 11 ether);
        assertEq(executor.receiptSeq(), 0);
        assertEq(executor.merchantCredit(), 0);
    }

    function testSponsorCanRecoverOnlyUnspentBudget() public {
        vm.prank(agent);
        executor.executeOrder(CAP, 1 ether);
        vm.expectRevert("insufficient available budget");
        executor.withdrawBudget(merchant, 10 ether);
        executor.withdrawBudget(payable(address(0xCAFE)), 9 ether);
        assertEq(address(executor).balance, 1 ether);
        vm.prank(merchant);
        executor.claimPayment();
        assertEq(merchant.balance, 1 ether);
        assertEq(address(executor).balance, 0);
    }

    function testNormalOrderAtSingleLimitSucceeds() public {
        vm.prank(agent);
        executor.executeOrder(CAP, 1 ether);
        assertEq(executor.totalSpent(), 1 ether);
        assertEq(executor.merchantCredit(), 1 ether);
        assertEq(executor.availableBudget(), 9 ether);
        assertEq(system.requests(), 0);
    }

    function testSingleLimitBlocksPaymentAndPreservesEvidence() public {
        vm.prank(agent);
        uint256 id = executor.executeOrder(CAP, 1 ether + 1);
        assertEq(executor.totalSpent(), 0);
        assertEq(executor.merchantCredit(), 0);
        assertEq(executor.availableBudget(), 10 ether);
        assertEq(executor.pendingReceipt(agent), id);
        assertTrue(vault.locked(agent));
    }

    function testTotalLimitCannotBeBypassedBySplittingFundingOrNewCapability() public {
        executor.fund{value: 20 ether}();
        for (uint256 i; i < 20; i++) {
            vm.prank(agent);
            executor.executeOrder(CAP, 1 ether);
        }
        assertEq(executor.totalSpent(), executor.totalSpendLimit());
        vm.prank(merchant);
        executor.claimPayment();
        executor.fund{value: 1 ether}();
        bytes32 otherCap = keccak256("another-capability");
        caps.grantCapability(agent, otherCap, 1 ether, block.timestamp + 1 days, "new-policy");
        vm.expectRevert("total spend limit exceeded");
        vm.prank(agent);
        executor.executeOrder(otherCap, 1);
        assertEq(executor.receiptSeq(), 20);
        assertEq(executor.totalSpent(), 20 ether);
        assertEq(executor.merchantCredit(), 0);
        assertEq(executor.availableBudget(), 11 ether);
        assertFalse(vault.locked(agent));
    }

    function testTotalLimitIsSharedAcrossAgents() public {
        executor.fund{value: 20 ether}();
        caps.grantCapability(agent, CAP, 20 ether, block.timestamp + 1 days, "test");
        vm.prank(agent);
        executor.executeOrder(CAP, 20 ether);
        address secondAgent = address(0xA22CE);
        registry.registerAgent(secondAgent, "did:demo:second");
        caps.grantCapability(secondAgent, CAP, 1 ether, block.timestamp + 1 days, "test");
        vm.deal(secondAgent, 1 ether);
        vm.prank(secondAgent);
        vault.stake{value: 1 ether}();
        vm.expectRevert("total spend limit exceeded");
        vm.prank(secondAgent);
        executor.executeOrder(CAP, 1);
        assertEq(executor.totalSpent(), 20 ether);
    }

    function testEmptyBudgetStopsAndFundingResumesBelowTotalLimit() public {
        for (uint256 i; i < 10; i++) {
            vm.prank(agent);
            executor.executeOrder(CAP, 1 ether);
        }
        vm.prank(merchant);
        executor.claimPayment();
        assertEq(address(executor).balance, 0);
        vm.expectRevert("insufficient budget");
        vm.prank(agent);
        executor.executeOrder(CAP, 1 ether);
        assertEq(executor.receiptSeq(), 10);
        executor.fund{value: 1 ether}();
        vm.prank(agent);
        executor.executeOrder(CAP, 1 ether);
        assertEq(executor.totalSpent(), 11 ether);
        assertEq(executor.merchantCredit(), 1 ether);
    }

    function testUntrustedReactionRejected() public {
        vm.expectRevert();
        sentinel.react(risk(1));
    }

    function testWrongOriginAndMalformedLogsIgnored() public {
        IReactive.LogRecord memory l = risk(1);
        l.chainId++;
        observe(l);
        l = risk(1);
        l.contractAddress = agent;
        observe(l);
        l = risk(1);
        l.topic0++;
        observe(l);
        l = risk(1);
        l.data = hex"01";
        observe(l);
        l = risk(1);
        l.topic2 = type(uint256).max;
        observe(l);
        l = risk(1);
        l.data = abi.encode(1 ether, 1 ether);
        observe(l);
        assertFalse(sentinel.seen(1));
        assertEq(system.requests(), 0);
    }

    function testCallbackAuthenticatesProxyAndSender() public {
        uint256 id = violation();
        observe(risk(id));
        vm.expectRevert();
        callback.onSentinelVerdict(address(sentinel), agent, CAP, id, 3);
        bytes memory payload = system.payload();
        vm.expectRevert();
        proxy.deliver(address(callback), agent, payload);
        assertTrue(vault.locked(agent));
    }

    function testCallbackRejectsInventedOrMismatchedReceipt() public {
        vm.startPrank(address(proxy));
        vm.expectRevert("evidence mismatch");
        callback.onSentinelVerdict(address(sentinel), agent, CAP, 999, 3);
        vm.stopPrank();
        uint256 id = violation();
        vm.startPrank(address(proxy));
        vm.expectRevert("evidence mismatch");
        callback.onSentinelVerdict(address(sentinel), merchant, CAP, id, 3);
        vm.expectRevert("unsupported disposition");
        callback.onSentinelVerdict(address(sentinel), agent, CAP, id, 2);
        vm.stopPrank();
    }

    function testCallbackCannotPunishValidOrder() public {
        vm.prank(agent);
        uint256 id = executor.executeOrder(CAP, 1 ether);
        vm.expectRevert("evidence mismatch");
        vm.prank(address(proxy));
        callback.onSentinelVerdict(address(sentinel), agent, CAP, id, 3);
        assertEq(vault.stakes(agent), 1 ether);
    }

    function testAiCannotDowngradeAndTimeoutFallbackWorks() public {
        sentinel.setAiMode(true);
        uint256 id = violation();
        observe(risk(id));
        vm.expectRevert("cannot downgrade hard violation");
        sentinel.submitVerdict(id, 0, "ignore evidence");
        vm.expectRevert("verdict window open");
        sentinel.dispatchExpired(id);
        vm.warp(block.timestamp + sentinel.VERDICT_TIMEOUT());
        vm.prank(agent);
        sentinel.dispatchExpired(id);
        deliver();
        assertTrue(callback.processed(id));
    }

    function testAiVerdictAndDuplicateVerdict() public {
        sentinel.setAiMode(true);
        uint256 id = violation();
        observe(risk(id));
        vm.expectRevert("not owner");
        vm.prank(agent);
        sentinel.submitVerdict(id, 3, "overspend");
        sentinel.submitVerdict(id, 3, "overspend");
        vm.expectRevert("not pending");
        sentinel.submitVerdict(id, 3, "again");
        deliver();
    }

    function testCallbackFailureRollsBackAllEffectsAndCanRetry() public {
        uint256 id = violation();
        observe(risk(id));
        registry.setOperator(address(0));
        bytes memory payload = system.payload();
        vm.expectRevert();
        proxy.deliver(address(callback), address(sentinel), payload);
        assertFalse(callback.processed(id));
        assertTrue(caps.isActive(agent, CAP));
        assertEq(vault.stakes(agent), 1 ether);
        assertEq(vault.forfeited(), 0);
        registry.setOperator(address(callback));
        vm.expectRevert("retry too soon");
        sentinel.retryDispatch(id);
        vm.warp(block.timestamp + sentinel.RETRY_DELAY());
        sentinel.retryDispatch(id);
        deliver();
        assertTrue(callback.processed(id));
    }

    function testRequestFailurePreservesPendingAlert() public {
        sentinel.setAiMode(true);
        uint256 id = violation();
        observe(risk(id));
        system.setFail(true);
        sentinel.submitVerdict(id, 3, "overspend");
        (,,,, bool open,) = sentinel.alerts(id);
        assertTrue(open);
        system.setFail(false);
        sentinel.submitVerdict(id, 3, "retry");
        deliver();
    }

    function testDeploymentGapKeepsEvidence() public {
        AgentSentinel other = new AgentSentinel(ORIGIN, address(executor));
        vm.prank(SYSTEM);
        other.react(risk(1));
        assertTrue(other.seen(1));
        other.setRecipient(address(callback));
        other.dispatchExpired(1);
        assertEq(system.requests(), 1);
        vm.expectRevert("invalid recipient");
        other.setRecipient(agent);
    }

    function testRulesModeRequestFailureKeepsObservationForRecovery() public {
        uint256 id = violation();
        system.setFail(true);
        observe(risk(id));
        assertTrue(sentinel.seen(id));
        (,,,, bool open,) = sentinel.alerts(id);
        assertTrue(open);
        system.setFail(false);
        sentinel.dispatchExpired(id);
        deliver();
        assertTrue(callback.processed(id));
    }

    function testPublicCannotMutateEnforcementOrFunds() public {
        vm.startPrank(agent);
        vm.expectRevert();
        vault.lock(agent);
        vm.expectRevert();
        vault.slash(agent, "attack");
        vm.expectRevert();
        vault.claimForfeiture(payable(agent));
        vm.expectRevert();
        executor.settle(1);
        vm.expectRevert();
        executor.setResolver(agent);
        vm.expectRevert();
        executor.claimPayment();
        vm.expectRevert();
        executor.withdrawBudget(payable(agent), 1);
        vm.expectRevert();
        registry.setStatus(agent, AgentRegistry.Status.Revoked, "attack");
        vm.expectRevert();
        caps.grantCapability(agent, CAP, 100 ether, block.timestamp + 1 days, "attack");
        vm.stopPrank();
    }

    function testFuzzOrderBoundaryAndAccounting(uint256 amount) public {
        amount = bound(amount, 1, 10 ether);
        vm.prank(agent);
        uint256 id = executor.executeOrder(CAP, amount);
        if (amount <= 1 ether) {
            assertEq(executor.merchantCredit(), amount);
            assertEq(executor.availableBudget(), 10 ether - amount);
            assertFalse(vault.locked(agent));
        } else {
            assertEq(executor.merchantCredit(), 0);
            assertEq(executor.pendingReceipt(agent), id);
            assertTrue(vault.locked(agent));
        }
        assertEq(address(executor).balance, executor.availableBudget() + executor.merchantCredit());
        assertEq(address(vault).balance, vault.totalStaked() + vault.forfeited());
    }

    function testFuzzSequenceConservesEscrowAndBonds(uint8[24] memory actions) public {
        for (uint256 i; i < actions.length; i++) {
            uint256 op = actions[i] % 6;
            if (op == 0) {
                vm.prank(agent);
                try executor.executeOrder(CAP, 0.1 ether) {} catch {}
            }
            if (op == 1) {
                vm.prank(agent);
                try executor.executeOrder(CAP, 2 ether) {} catch {}
            }
            if (op == 2) {
                vm.prank(agent);
                try vault.withdraw() {} catch {}
            }
            if (op == 3) {
                vm.prank(merchant);
                try executor.claimPayment() {} catch {}
            }
            if (op == 4 && executor.pendingReceipt(agent) > 0) {
                observe(risk(executor.pendingReceipt(agent)));
                deliver();
            }
            if (op == 5) try vault.claimForfeiture(payable(address(0xCAFE))) {} catch {}
            assertEq(address(executor).balance, executor.availableBudget() + executor.merchantCredit());
            assertEq(address(vault).balance, vault.totalStaked() + vault.forfeited());
            assertEq(vault.totalStaked(), vault.stakes(agent));
            assertLe(executor.totalSpent(), executor.totalSpendLimit());
            if (vault.locked(agent)) assertGt(executor.pendingReceipt(agent), 0);
        }
    }
}

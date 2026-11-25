// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {IReactive} from "@reactive/src/interfaces/IReactive.sol";
import {ISystemContract} from "@reactive/src/interfaces/ISystemContract.sol";
import {IPayable} from "@reactive/src/interfaces/IPayable.sol";
import {BoundedCronReactive} from "../src/BoundedCronReactive.sol";
import {BoundedCronCallback} from "../src/BoundedCronCallback.sol";

contract CronMockSystem {
    uint256 public subscribeCalls;
    uint256 public unsubscribeCalls;
    uint256 public callbackRequests;
    uint256 public subscribedChainId;
    address public subscribedContract;
    uint256 public subscribedTopic0;
    uint256 public unsubscribedChainId;
    address public unsubscribedContract;
    uint256 public unsubscribedTopic0;
    uint256 public callbackChainId;
    address public callbackRecipient;
    address public callbackSender;
    bytes public callbackPayload;

    function subscribe(uint256 chainId_, address contract_, uint256 topic0_, uint256, uint256, uint256) external {
        subscribeCalls++;
        subscribedChainId = chainId_;
        subscribedContract = contract_;
        subscribedTopic0 = topic0_;
    }

    function unsubscribe(uint256 chainId_, address contract_, uint256 topic0_, uint256, uint256, uint256) external {
        unsubscribeCalls++;
        unsubscribedChainId = chainId_;
        unsubscribedContract = contract_;
        unsubscribedTopic0 = topic0_;
    }

    function requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0 memory config_) external {
        callbackRequests++;
        callbackChainId = config_.chainId;
        callbackRecipient = config_.recipient;
        callbackPayload = config_.payload;
        callbackSender = msg.sender;
    }
}

contract CronMockProxy {
    function deliver(address recipient_, address sender_, bytes memory payload_) external {
        assembly {
            mstore(add(payload_, 36), sender_)
        }
        (bool success, bytes memory result) = recipient_.call(payload_);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }
}

contract BoundedCronTest is Test {
    address internal constant SYSTEM = 0x8888888888888888888888888888888888888888;
    address internal constant LEGACY = 0x0000000000000000000000000000000000fffFfF;
    uint256 internal constant LASNA = 5318007;
    uint256 internal constant DESTINATION = 11155111;
    uint256 internal constant CRON100 = 0xb49937fb8970e19fd46d48f7e3fb00d659deac0347f79cd7cb542f0fc1503c70;

    CronMockSystem internal system;
    CronMockProxy internal proxy;
    BoundedCronReactive internal reactive;
    BoundedCronCallback internal callback;

    function setUp() public {
        vm.chainId(LASNA);
        vm.etch(SYSTEM, address(new CronMockSystem()).code);
        system = CronMockSystem(SYSTEM);
        proxy = new CronMockProxy();
        reactive = new BoundedCronReactive(DESTINATION, 2);
        callback = new BoundedCronCallback(IPayable(payable(address(proxy))), address(reactive), 2);
        reactive.setRecipient(address(callback));
        reactive.start();
        assertEq(system.subscribedChainId(), LASNA);
        assertEq(system.subscribedContract(), LEGACY);
        assertEq(system.subscribedTopic0(), CRON100);
    }

    function _cron(uint256 sourceBlock_, uint256 txHash_, uint256 logIndex_)
        internal
        pure
        returns (IReactive.LogRecord memory log_)
    {
        log_.chainId = LASNA;
        log_.contractAddress = LEGACY;
        log_.topic0 = CRON100;
        log_.blockNumber = sourceBlock_;
        log_.blockHash = sourceBlock_ + 1000;
        log_.txHash = txHash_;
        log_.logIndex = logIndex_;
    }

    function _react(IReactive.LogRecord memory log_) internal {
        vm.prank(SYSTEM);
        reactive.react(log_);
    }

    function _deliver() internal {
        proxy.deliver(system.callbackRecipient(), system.callbackSender(), system.callbackPayload());
    }

    function testCron100SubscribesAndRequestsTwoAuthenticatedCallbacksThenStops() public {
        assertEq(system.subscribeCalls(), 1);

        _react(_cron(100, 1, 0));
        assertEq(reactive.cronRuns(), 1);
        assertEq(system.callbackRequests(), 1);
        assertEq(system.callbackChainId(), DESTINATION);
        assertEq(system.callbackRecipient(), address(callback));
        _deliver();
        assertTrue(callback.processed(1));
        assertEq(callback.lastRun(), 1);

        _react(_cron(200, 2, 0));
        assertEq(reactive.cronRuns(), 2);
        assertTrue(reactive.stopped());
        assertEq(system.unsubscribeCalls(), 1);
        assertEq(system.unsubscribedChainId(), LASNA);
        assertEq(system.unsubscribedContract(), LEGACY);
        assertEq(system.unsubscribedTopic0(), CRON100);
        _deliver();
        assertTrue(callback.processed(2));
        assertEq(callback.processedRuns(), 2);

        _react(_cron(300, 3, 0));
        assertEq(reactive.cronRuns(), 2);
        assertEq(system.callbackRequests(), 2);
    }

    function testWrongCronSourceAndTopicAreIgnoredWithoutRevert() public {
        IReactive.LogRecord memory wrongChain = _cron(100, 1, 0);
        wrongChain.chainId = DESTINATION;
        _react(wrongChain);

        IReactive.LogRecord memory wrongAddress = _cron(100, 2, 0);
        wrongAddress.contractAddress = address(0x1234);
        _react(wrongAddress);

        IReactive.LogRecord memory wrongTopic = _cron(100, 3, 0);
        wrongTopic.topic0 = 1;
        _react(wrongTopic);

        assertEq(reactive.cronRuns(), 0);
        assertEq(system.callbackRequests(), 0);
    }

    function testDuplicateCronLogAndDuplicateCallbackAreIdempotent() public {
        IReactive.LogRecord memory log_ = _cron(100, 1, 0);
        _react(log_);
        _react(log_);
        assertEq(reactive.cronRuns(), 1);
        assertEq(system.callbackRequests(), 1);

        _deliver();
        _deliver();
        assertEq(callback.processedRuns(), 1);
        assertTrue(callback.processed(1));
    }

    function testOnlySystemCanDeliverCronAndOnlyProxyCanDeliverCallback() public {
        vm.expectRevert();
        reactive.react(_cron(100, 1, 0));

        bytes memory payload = abi.encodeWithSignature("recordTick(address,uint256,uint256)", address(0), 1, 100);
        vm.expectRevert();
        callback.recordTick(address(reactive), 1, 100);

        vm.expectRevert();
        proxy.deliver(address(callback), address(0xBAD), payload);
    }

    function testCallbackRejectsRunAboveHardMaximum() public {
        bytes memory payload = abi.encodeWithSignature("recordTick(address,uint256,uint256)", address(0), 3, 300);
        vm.expectRevert(abi.encodeWithSelector(BoundedCronCallback.InvalidRun.selector, 3));
        proxy.deliver(address(callback), address(reactive), payload);
    }

    function testOwnerCanStopBeforeLimit() public {
        _react(_cron(100, 1, 0));
        reactive.stop();
        assertTrue(reactive.stopped());
        assertEq(system.unsubscribeCalls(), 1);
        _react(_cron(200, 2, 0));
        assertEq(system.callbackRequests(), 1);
    }
}

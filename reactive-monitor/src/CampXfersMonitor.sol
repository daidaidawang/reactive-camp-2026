// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";

/**
 * @title CampXfersMonitor
 * @notice Reactive Builder Camp 第 1 周第 3 天练习（Omni 版）。
 *         订阅 Sepolia 上指定 ERC-20 的 Transfer 事件，
 *         单笔金额 >= 阈值才计数（用 return 过滤，不用 revert），
 *         达到处理上限后自动取消订阅。
 */
contract CampXfersMonitor is AbstractReactive {
    /// @notice 一笔符合条件的转账被处理时触发。
    /// @param token_ 代币合约地址。
    /// @param from_ 转出方（来自 topic1）。
    /// @param to_ 接收方（来自 topic2）。
    /// @param amount_ 单笔金额。
    /// @param matchedCount_ 累计命中次数。
    event Matched(
        address indexed token_,
        address indexed from_,
        address indexed to_,
        uint256 amount_,
        uint256 matchedCount_
    );

    /// @notice 用于解码 Transfer 事件 payload 的结构体。
    struct Transfer {
        uint256 tokens;
    }

    /// @notice Sepolia 链 ID。
    uint256 private constant SEPOLIA_CHAIN_ID = 11155111;

    /// @notice ERC-20 Transfer(address,address,uint256) 的 topic0。
    uint256 private constant ERC20_TRANSFER_TOPIC_0 =
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;

    /// @notice opCode == 3 表示标准日志事件。
    uint256 private constant OPCODE_LOG = 3;

    /// @notice 合约部署者。
    address public immutable _OWNER;

    /// @notice 被监控的 Sepolia 代币地址（订阅条件之一，写死在订阅里）。
    address public immutable _TOKEN;

    /// @notice 单笔金额阈值：低于它的转账只 return，不计数。
    uint256 public immutable _THRESHOLD;

    /// @notice 剩余可处理次数，减到 0 时自动退订。
    uint256 public _limit;

    /// @notice 已命中（计数）的转账笔数。
    uint256 public _matchedCount;

    /// @notice 最近一次处理的交易哈希。
    uint256 public _lastTxHash;

    /// @notice 最近一次 react() 所在的 Reactive 区块号。
    uint256 public _lastReactBlockNumber;

    /// @param token_ 要监控的 Sepolia 代币地址。
    /// @param threshold_ 单笔金额阈值（wei）。
    /// @param limit_ 处理次数上限，达到后自动退订。
    /// @dev payable：部署时直接充值，避免欠款导致 react() 停止执行。
    constructor(
        address token_,
        uint256 threshold_,
        uint256 limit_
    ) payable {
        require(token_ != address(0), "token is zero");
        require(limit_ > 0, "limit is zero");
        _OWNER = msg.sender;
        _TOKEN = token_;
        _THRESHOLD = threshold_;
        _limit = limit_;
        _sub();
    }

    /// @inheritdoc IReactive
    function react(LogRecord memory log_) external onlySystem {
        // 不是标准日志（opCode != 3）：过滤，直接 return。
        if (log_.opCode != OPCODE_LOG) {
            return;
        }
        // 不是目标代币的 Transfer：过滤，直接 return。
        if (log_.contractAddress != _TOKEN) {
            return;
        }

        Transfer memory xfer = abi.decode(log_.data, (Transfer));

        // 单笔金额低于阈值：过滤，直接 return（绝不 revert，revert 也会被记账收费）。
        if (xfer.tokens < _THRESHOLD) {
            return;
        }

        _lastTxHash = log_.txHash;
        _lastReactBlockNumber = block.number;
        _matchedCount += 1;

        emit Matched(
            log_.contractAddress,
            address(uint160(log_.topic1)),
            address(uint160(log_.topic2)),
            xfer.tokens,
            _matchedCount
        );

        // 次数上限到达后自动取消订阅，六个参数必须与 subscribe 完全一致。
        if (--_limit == 0) {
            _unsub();
        }
    }

    /// @notice 订阅 Sepolia 上 _TOKEN 的全部 Transfer 事件，topic1-3 用 REACTIVE_IGNORE 放行。
    function _sub() internal {
        SYSTEM.subscribe(
            SEPOLIA_CHAIN_ID,
            _TOKEN,
            ERC20_TRANSFER_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
    }

    /// @notice 取消订阅，参数与 _sub() 严格一致。
    function _unsub() internal {
        SYSTEM.unsubscribe(
            SEPOLIA_CHAIN_ID,
            _TOKEN,
            ERC20_TRANSFER_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
    }
}

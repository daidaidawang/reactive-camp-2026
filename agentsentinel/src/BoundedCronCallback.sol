// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IPayable} from "@reactive/src/interfaces/IPayable.sol";
import {AbstractCallback} from "@reactive/src/base/AbstractCallback.sol";

/// @notice Records authenticated, uniquely numbered Cron callbacks without moving funds.
contract BoundedCronCallback is AbstractCallback {
    uint256 public immutable maxRuns;
    mapping(uint256 => bool) public processed;
    uint256 public processedRuns;
    uint256 public lastRun;

    event TickRecorded(uint256 indexed run, uint256 indexed sourceBlock);
    event DuplicateIgnored(uint256 indexed run);

    error InvalidConfiguration();
    error InvalidRun(uint256 run);

    constructor(IPayable proxy_, address reactiveSender_, uint256 maxRuns_)
        payable
        AbstractCallback(proxy_, reactiveSender_)
    {
        if (address(proxy_).code.length == 0 || reactiveSender_.code.length == 0 || maxRuns_ == 0) {
            revert InvalidConfiguration();
        }
        maxRuns = maxRuns_;
    }

    function recordTick(address reactive_, uint256 run_, uint256 sourceBlock_)
        external
        onlyServiceProvider
        onlyCallbackSender(reactive_)
    {
        if (run_ == 0 || run_ > maxRuns) revert InvalidRun(run_);
        if (processed[run_]) {
            emit DuplicateIgnored(run_);
            return;
        }

        processed[run_] = true;
        processedRuns += 1;
        if (run_ > lastRun) lastRun = run_;
        emit TickRecorded(run_, sourceBlock_);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

/// @title MockERC20
/// @notice 练习用最小 ERC-20：仅部署者可 mint，用于在 Sepolia 制造可预期的 Transfer 事件。
contract MockERC20 {
    string public name = "Camp Test Token";
    string public symbol = "CTT";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    address public immutable owner;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner_, address indexed spender, uint256 value);

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    function mint(uint256 amount_) external onlyOwner {
        totalSupply += amount_;
        balanceOf[msg.sender] += amount_;
        emit Transfer(address(0), msg.sender, amount_);
    }

    function transfer(address to_, uint256 amount_) external returns (bool) {
        _transfer(msg.sender, to_, amount_);
        return true;
    }

    function approve(address spender_, uint256 amount_) external returns (bool) {
        allowance[msg.sender][spender_] = amount_;
        emit Approval(msg.sender, spender_, amount_);
        return true;
    }

    function transferFrom(address from_, address to_, uint256 amount_) external returns (bool) {
        uint256 allowed = allowance[from_][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= amount_, "insufficient allowance");
            allowance[from_][msg.sender] = allowed - amount_;
        }
        _transfer(from_, to_, amount_);
        return true;
    }

    function _transfer(address from_, address to_, uint256 amount_) internal {
        require(balanceOf[from_] >= amount_, "insufficient balance");
        balanceOf[from_] -= amount_;
        balanceOf[to_] += amount_;
        emit Transfer(from_, to_, amount_);
    }
}

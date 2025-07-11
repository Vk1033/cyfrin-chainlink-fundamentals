// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IRouterClient} from "@chainlink/contracts@1.3.0/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts@1.3.0/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@chainlink/contracts@1.3.0/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@chainlink/contracts@1.3.0/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts@5.2.0/access/Ownable.sol";

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES HARDCODED VALUES FOR CLARITY.
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */
contract CCIPChallenge is Ownable {
    using SafeERC20 for IERC20;

    error CCIPChallenge__InsufficientBalance(IERC20 token, uint256 currentBalance, uint256 requiredAmount);
    error CCIPChallenge__NothingToWithdraw();

    // https://docs.chain.link/ccip/supported-networks/v1_2_0/testnet#ethereum-testnet-sepolia
    IRouterClient private constant CCIP_ROUTER = IRouterClient(0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59);
    // https://docs.chain.link/resources/link-token-contracts#ethereum-testnet-sepolia
    IERC20 private constant LINK_TOKEN = IERC20(0x779877A7B0D9E8603169DdbD7836e478b4624789);
    // https://docs.chain.link/ccip/directory/testnet/chain/ethereum-testnet-sepolia-base-1

    event TokenTransferred(
        bytes32 messageId,
        uint64 indexed destinationChainSelector,
        address indexed receiver,
        uint256 amount,
        uint256 ccipFee,
        address token
    );

    constructor() Ownable(msg.sender) {}

    function transferTokens(
        address _receiver,
        uint256 _amount,
        address _token,
        uint64 _destinationChainSelector
    )
        external
        returns (bytes32 messageId)
    {
        IERC20 TOKEN = IERC20(_token);
        if (_amount > TOKEN.balanceOf(msg.sender)) {
            revert CCIPChallenge__InsufficientBalance(TOKEN, TOKEN.balanceOf(msg.sender), _amount);
        }
        Client.EVMTokenAmount[]
            memory tokenAmounts = new Client.EVMTokenAmount[](1);
        Client.EVMTokenAmount memory tokenAmount = Client.EVMTokenAmount({
            token: address(TOKEN),
            amount: _amount
        });
        tokenAmounts[0] = tokenAmount;

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(_receiver),
            data: "",
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 0})
            ),
            feeToken: address(LINK_TOKEN)
        });

        uint256 ccipFee = CCIP_ROUTER.getFee(
            _destinationChainSelector,
            message
        );

        if (ccipFee > LINK_TOKEN.balanceOf(address(this))) {
            revert CCIPChallenge__InsufficientBalance(LINK_TOKEN, LINK_TOKEN.balanceOf(address(this)), ccipFee);
        }

        LINK_TOKEN.approve(address(CCIP_ROUTER), ccipFee);

        TOKEN.safeTransferFrom(msg.sender, address(this), _amount);
        TOKEN.approve(address(CCIP_ROUTER), _amount);

        // Send CCIP Message
        messageId = CCIP_ROUTER.ccipSend(_destinationChainSelector, message);

        emit TokenTransferred(
            messageId,
            _destinationChainSelector,
            _receiver,
            _amount,
            ccipFee,
            _token
        );
    }

    function withdrawToken(
        address _beneficiary,
        address _token
    ) public onlyOwner {
        IERC20 TOKEN = IERC20(_token);
        uint256 amount = IERC20(TOKEN).balanceOf(address(this));
        if (amount == 0) revert CCIPChallenge__NothingToWithdraw();
        IERC20(TOKEN).transfer(_beneficiary, amount);
    }
}
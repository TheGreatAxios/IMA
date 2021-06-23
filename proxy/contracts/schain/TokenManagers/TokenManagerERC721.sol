// SPDX-License-Identifier: AGPL-3.0-only

/**
 *   TokenManager.sol - SKALE Interchain Messaging Agent
 *   Copyright (C) 2019-Present SKALE Labs
 *   @author Artem Payvin
 *
 *   SKALE IMA is free software: you can redistribute it and/or modify
 *   it under the terms of the GNU Affero General Public License as published
 *   by the Free Software Foundation, either version 3 of the License, or
 *   (at your option) any later version.
 *
 *   SKALE IMA is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *   GNU Affero General Public License for more details.
 *
 *   You should have received a copy of the GNU Affero General Public License
 *   along with SKALE IMA.  If not, see <https://www.gnu.org/licenses/>.
 */

pragma solidity 0.8.4;

import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import "../../Messages.sol";
import "../tokens/ERC721OnChain.sol";
import "../TokenManager.sol";


/**
 * @title Token Manager
 * @dev Runs on SKALE Chains, accepts messages from mainnet, and instructs
 * TokenFactory to create clones. TokenManager mints tokens via
 * LockAndDataForSchain*. When a user exits a SKALE chain, TokenFactory
 * burns tokens.
 */
contract TokenManagerERC721 is TokenManager {
    using AddressUpgradeable for address;

    // address of ERC721 on Mainnet => ERC721 on Schain
    mapping(address => ERC721OnChain) public clonesErc721;

    event ERC721TokenAdded(address indexed erc721OnMainnet, address indexed erc721OnSchain);

    event ERC721TokenCreated(address indexed erc721OnMainnet, address indexed erc721OnSchain);

    event ERC721TokenReceived(address indexed erc721OnMainnet, address indexed erc721OnSchain, uint256 tokenId);

    function exitToMainERC721(
        address contractOnMainnet,
        address to,
        uint256 tokenId
    )
        external
    {
        communityLocker.checkAllowedToSendMessage(to);
        _exit(MAINNET_HASH, depositBox, contractOnMainnet, to, tokenId);
    }

    function transferToSchainERC721(
        string calldata targetSchainName,
        address contractOnMainnet,
        address to,
        uint256 tokenId
    ) 
        external
        rightTransaction(targetSchainName, to)
    {
        bytes32 targetSchainHash = keccak256(abi.encodePacked(targetSchainName));
        _exit(targetSchainHash, tokenManagers[targetSchainHash], contractOnMainnet, to, tokenId);
    }

    /**
     * @dev Allows MessageProxy to post operational message from mainnet
     * or SKALE chains.
     * 
     * Emits an {Error} event upon failure.
     *
     * Requirements:
     * 
     * - MessageProxy must be the sender.
     * - `fromSchainName` must exist in TokenManager addresses.
     */
    function postMessage(
        bytes32 fromChainHash,
        address sender,
        bytes calldata data
    )
        external
        override
        onlyMessageProxy
        checkReceiverChain(fromChainHash, sender)
        returns (address)
    {
        Messages.MessageType operation = Messages.getMessageType(data);
        address receiver = address(0);
        if (
            operation == Messages.MessageType.TRANSFER_ERC721_AND_TOKEN_INFO ||
            operation == Messages.MessageType.TRANSFER_ERC721
        ) {
            receiver = _sendERC721(data);
        } else {
            revert("MessageType is unknown");
        }
        return receiver;
    }

    /**
     * @dev Allows Schain owner to add an ERC721 token to LockAndDataForSchainERC721.
     */
    function addERC721TokenByOwner(
        address erc721OnMainnet,
        ERC721OnChain erc721OnSchain
    )
        external
        onlyTokenRegistrar
    {
        require(address(erc721OnSchain).isContract(), "Given address is not a contract");
        clonesErc721[erc721OnMainnet] = erc721OnSchain;
        emit ERC721TokenAdded(erc721OnMainnet, address(erc721OnSchain));
    }

    function initialize(
        string memory newChainName,
        MessageProxyForSchain newMessageProxy,
        TokenManagerLinker newIMALinker,
        CommunityLocker newCommunityLocker,
        address newDepositBox
    )
        public
    {
        TokenManager.initializeTokenManager(
            newChainName,
            newMessageProxy,
            newIMALinker,
            newCommunityLocker,
            newDepositBox
        );
    }    

    // private

    /**
     * @dev Allows TokenManager to send ERC721 tokens.
     *  
     * Emits a {ERC721TokenCreated} event if to address = 0.
     */
    function _sendERC721(bytes calldata data) private returns (address) {
        Messages.MessageType messageType = Messages.getMessageType(data);
        address receiver;
        address token;
        uint256 tokenId;
        ERC721OnChain contractOnSchain;
        if (messageType == Messages.MessageType.TRANSFER_ERC721){
            Messages.TransferErc721Message memory message = Messages.decodeTransferErc721Message(data);
            receiver = message.receiver;
            token = message.token;
            tokenId = message.tokenId;
            contractOnSchain = clonesErc721[token];
        } else {
            Messages.TransferErc721AndTokenInfoMessage memory message =
                Messages.decodeTransferErc721AndTokenInfoMessage(data);
            receiver = message.baseErc721transfer.receiver;
            token = message.baseErc721transfer.token;
            tokenId = message.baseErc721transfer.tokenId;
            contractOnSchain = clonesErc721[token];
            if (address(contractOnSchain) == address(0)) {
                require(automaticDeploy, "Automatic deploy is disabled");
                contractOnSchain = new ERC721OnChain(message.tokenInfo.name, message.tokenInfo.symbol);           
                clonesErc721[token] = contractOnSchain;
                emit ERC721TokenCreated(token, address(contractOnSchain));
            }
        }
        contractOnSchain.mint(receiver, tokenId);
        emit ERC721TokenReceived(token, address(contractOnSchain), tokenId);
        return receiver;
    }

    function _exit(
        bytes32 chainHash,
        address messageReceiver,
        address contractOnMainnet,
        address to,
        uint256 tokenId
    )
        private
    {
        ERC721BurnableUpgradeable contractOnSchain = clonesErc721[contractOnMainnet];
        require(address(contractOnSchain).isContract(), "No token clone on schain");
        require(contractOnSchain.getApproved(tokenId) == address(this), "Not allowed ERC721 Token");
        contractOnSchain.transferFrom(msg.sender, address(this), tokenId);
        contractOnSchain.burn(tokenId);
        bytes memory data = Messages.encodeTransferErc721Message(contractOnMainnet, to, tokenId);    
        messageProxy.postOutgoingMessage(chainHash, messageReceiver, data);
    }
}

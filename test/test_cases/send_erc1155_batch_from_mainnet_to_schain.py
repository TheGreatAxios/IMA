#   SPDX-License-Identifier: AGPL-3.0-only
#   -*- coding: utf-8 -*-
#
#   This file is part of SKALE IMA.
#
#   Copyright (C) 2019-Present SKALE Labs
#
#   SKALE IMA is free software: you can redistribute it and/or modify
#   it under the terms of the GNU Affero General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   SKALE IMA is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU Affero General Public License for more details.
#
#   You should have received a copy of the GNU Affero General Public License
#   along with SKALE IMA.  If not, see <https://www.gnu.org/licenses/>.

from time import sleep

from tools.test_case import TestCase
from tools.test_pool import test_pool


class SendERC1155BatchToSchain(TestCase):
    erc1155 = None
    tokenIds = [1, 2, 3]
    tokenAmounts = [3, 2, 1]

    def __init__(self, config):
        super().__init__('Send ERC1155 Batch to schain', config)

    def _prepare(self):
        sleep(5)

        self.erc1155 = self.blockchain.deploy_erc1155_on_mainnet(self.config.mainnet_key, 'elv1155')
        sleep(5)
        address = self.blockchain.key_to_address(self.config.mainnet_key)
        mint_txn = self.erc1155.functions.mintBatch(address, self.tokenIds, self.tokenAmounts, "0x")\
            .buildTransaction({
                'gas': 8000000,
                'nonce': self.blockchain.get_transactions_count_on_mainnet(address)})

        signed_txn = self.blockchain.web3_mainnet.eth.account.signTransaction(mint_txn,
                                                                              private_key=self.config.mainnet_key)
        self.blockchain.web3_mainnet.eth.sendRawTransaction(signed_txn.rawTransaction)
        self.blockchain.disableWhitelistERC1155(self.config.mainnet_key, self.config.schain_name)
        self.blockchain.enableAutomaticDeployERC1155(self.config.schain_key, "Mainnet")

    def _execute(self):

        sleep(5)

        self.agent.transfer_erc1155_batch_from_mainnet_to_schain(
            self.erc1155,
            self.config.mainnet_key,
            self.config.schain_key,
            self.tokenIds,
            self.tokenAmounts,
            0,
            self.timeout
        )

        erc1155 = self.blockchain.get_erc1155_on_schain("Mainnet", self.erc1155.address)
        destination_address = self.blockchain.key_to_address(self.config.mainnet_key)
        new_amounts = erc1155.functions.balanceOfBatch([destination_address] * len(self.tokenIds), self.tokenIds).call()
        if self.tokenAmounts == new_amounts:
            self._mark_passed()

test_pool.register_test(SendERC1155BatchToSchain)


from web3 import Web3
from pathlib import Path
import json
import asyncio
import logging
from typing import Optional
from .video_generator import VideoGenerator

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class ChainListener:
    def __init__(self, 
                 contract_address: str,
                 rpc_url: str,
                 abi_path: str,
                 video_generator: VideoGenerator):
        self.web3 = Web3(Web3.HTTPProvider(rpc_url))
        self.contract_address = Web3.toChecksumAddress(contract_address)
        self.video_generator = video_generator

        with open(abi_path) as f:
            self.abi = json.load(f)

        self.contract = self.web3.eth.contract(address=self.contract_address, abi=self.abi)

    async def listen_for_events(self):
        event_filter = self.contract.events.RoundFinalized.createFilter(fromBlock='latest')
        while True:
            for event in event_filter.get_new_entries():
                await self.handle_event(event)
            await asyncio.sleep(10)

    async def handle_event(self, event):
        logger.info(f"New event: {event}")
        round_id = event['args']['roundId']
        prompt_id = event['args']['winningPromptId']
        prompt_text = event['args']['text']
        await self.video_generator.generate_video(round_id, prompt_id, prompt_text)

if __name__ == "__main__":
    contract_address = "0xYourContractAddress"
    rpc_url = "https://mainnet.infura.io/v3/your-infura-project-id"
    abi_path = Path(__file__).parent / "abi.json"
    video_generator = VideoGenerator()

    listener = ChainListener(contract_address, rpc_url, abi_path, video_generator)
    asyncio.run(listener.listen_for_events())
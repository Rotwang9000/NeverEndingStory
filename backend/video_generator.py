import os
import replicate
from typing import Optional
from pathlib import Path
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class VideoGenerator:
    def __init__(self, api_token: Optional[str] = None):
        self.api_token = api_token or os.environ.get("REPLICATE_API_TOKEN")
        if not self.api_token:
            raise ValueError("REPLICATE_API_TOKEN must be provided")
        
        self.client = replicate.Client(api_token=self.api_token)

    async def generate_video_from_prompt(self, prompt: str, output_dir: Path) -> str:
        """Generate a video from a text prompt using Replicate's Stable Video Diffusion."""
        try:
            logger.info(f"Generating video for prompt: {prompt}")
            
            # Using Stable Video Diffusion model
            output = self.client.run(
                "stability-ai/stable-video-diffusion:3d4c3ddc4ec6c9a2dfa8dc8c613583cedec5251b90f4ac046d186791a1a91d1e",
                input={
                    "prompt": prompt,
                    "video_length": "14_frames_with_svd",
                    "fps": 7,
                    "motion_bucket_id": 127,
                    "cond_aug": 0.02,
                }
            )
            
            # Output will be a video URL that we can download
            video_url = output[0]
            logger.info(f"Video generated successfully: {video_url}")
            
            return video_url

        except Exception as e:
            logger.error(f"Error generating video: {str(e)}")
            raise

    def stitch_videos(self, video_urls: list[str], output_path: Path) -> Path:
        """
        Stitch multiple videos together (placeholder - implement with ffmpeg or similar)
        """
        # TODO: Implement video stitching
        pass

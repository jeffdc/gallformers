import boto3
from botocore.config import Config
from utils.logger import logger

class AWS:
    def __init__(self):
        self._s3_client = None
        self._backup_bucket = None

    def get_s3_client(self):
        if not self._s3_client:
            config = Config(
                retries = dict(
                    max_attempts = 3
                )
            )
            self._s3_client = boto3.client('s3', config=config)
        return self._s3_client

    def get_backup_bucket(self):
        if not self._backup_bucket:
            from config.env import env
            self._backup_bucket = env.get('S3_BUCKET')
            if not self._backup_bucket:
                raise ValueError("S3_BUCKET environment variable is not set")
        return self._backup_bucket

# Create singleton instance
aws = AWS() 
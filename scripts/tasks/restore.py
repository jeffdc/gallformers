import os
import pathlib
import shutil
import zipfile
from datetime import datetime
from typing import Dict, Any

from config.aws import aws
from utils.logger import logger
from config.env import env
from utils.database import db

class RestoreResult:
    def __init__(self, success: bool):
        self.success = success

    def __str__(self) -> str:
        return f"RestoreResult(success={self.success})"

class RestoreTask:
    def __init__(self):
        self.backup_dir = pathlib.Path.cwd() / 'backups'
        self.backup_dir.mkdir(exist_ok=True)

    async def execute(self, s3_key: str = None) -> RestoreResult:
        try:
            # Load environment variables
            env.load()

            if not s3_key:
                raise ValueError('S3 key is required')

            timestamp = datetime.now().isoformat().replace(':', '-').replace('.', '-')
            backup_path = self.backup_dir / f'restore-{timestamp}.sqlite'

            # Download from S3
            logger.info('Downloading backup from S3', s3_key=s3_key)
            s3_client = aws.get_s3_client()
            bucket = aws.get_backup_bucket()

            # Download the file from S3
            s3_client.download_file(bucket, s3_key, str(backup_path))

            # If the file is a zip, extract it
            if str(backup_path).endswith('.zip'):
                temp_dir = self.backup_dir / f'temp_extract_{timestamp}'
                temp_dir.mkdir(exist_ok=True)
                
                with zipfile.ZipFile(backup_path, 'r') as zip_ref:
                    zip_ref.extractall(temp_dir)
                
                # Find the SQLite file in the extracted directory
                sqlite_files = list(temp_dir.glob('*.sqlite'))
                if not sqlite_files:
                    raise FileNotFoundError('No SQLite file found in the backup zip')
                
                # Use the first SQLite file found
                extracted_sqlite = sqlite_files[0]
                
                # Restore database
                logger.info('Restoring database from backup', backup_path=str(extracted_sqlite))
                db.restore(str(extracted_sqlite))
                
                # Clean up
                os.remove(backup_path)
                shutil.rmtree(temp_dir)
            else:
                # Restore database directly
                logger.info('Restoring database from backup', backup_path=str(backup_path))
                db.restore(str(backup_path))
                
                # Clean up local backup
                os.remove(backup_path)

            logger.info('Restore completed successfully', s3_bucket=bucket, s3_key=s3_key)

            return RestoreResult(success=True)
        except Exception as error:
            logger.error('Restore failed', error=str(error))
            raise

if __name__ == '__main__':
    import asyncio
    import sys
    
    if len(sys.argv) < 2:
        print('Usage: python restore.py <s3-key>')
        sys.exit(1)
        
    s3_key = sys.argv[1]
    
    try:
        asyncio.run(RestoreTask().execute(s3_key))
    except Exception as error:
        print('Restore failed:', error)
        sys.exit(1) 
import os
import pathlib
from datetime import datetime
from typing import Dict, Any, Optional

from config.aws import aws
from utils.logger import logger
from config.env import env
from utils.database import db

class RefreshStagingResult:
    def __init__(self, success: bool, backup_key: str = None):
        self.success = success
        self.backup_key = backup_key

    def __str__(self) -> str:
        return f"RefreshStagingResult(success={self.success}, backup_key='{self.backup_key}')"

class RefreshStagingTask:
    def __init__(self):
        self.backup_dir = pathlib.Path.cwd() / 'backups'
        self.backup_dir.mkdir(exist_ok=True)

    async def execute(self, _args: Any = None) -> RefreshStagingResult:
        try:
            # Load environment variables
            env.load()

            # Find the latest backup in S3
            latest_backup_key = self._find_latest_backup()
            if not latest_backup_key:
                raise ValueError("No backups found in S3")

            logger.info('Found latest backup', s3_key=latest_backup_key)

            # Download and restore the latest backup
            timestamp = datetime.now().isoformat().replace(':', '-').replace('.', '-')
            temp_backup_path = self.backup_dir / f'staging_restore_{timestamp}.zip'

            # Download from S3
            logger.info('Downloading latest backup from S3', s3_key=latest_backup_key)
            s3_client = aws.get_s3_client()
            bucket = aws.get_backup_bucket()
            s3_client.download_file(bucket, latest_backup_key, str(temp_backup_path))

            # Extract and restore database
            if str(temp_backup_path).endswith('.zip'):
                import zipfile
                temp_dir = self.backup_dir / f'temp_extract_{timestamp}'
                temp_dir.mkdir(exist_ok=True)
                
                with zipfile.ZipFile(temp_backup_path, 'r') as zip_ref:
                    zip_ref.extractall(temp_dir)
                
                # Find the SQLite file in the extracted directory
                sqlite_files = list(temp_dir.glob('*.sqlite'))
                if not sqlite_files:
                    raise FileNotFoundError('No SQLite file found in the backup zip')
                
                extracted_sqlite = sqlite_files[0]
                
                # Restore database
                logger.info('Restoring staging database from backup', backup_path=str(extracted_sqlite))
                db.restore(str(extracted_sqlite))
                
                # Clean up
                import shutil
                os.remove(temp_backup_path)
                shutil.rmtree(temp_dir)
            else:
                # Restore database directly
                logger.info('Restoring staging database from backup', backup_path=str(temp_backup_path))
                db.restore(str(temp_backup_path))
                os.remove(temp_backup_path)

            logger.info('Staging database refreshed successfully', s3_key=latest_backup_key)
            return RefreshStagingResult(success=True, backup_key=latest_backup_key)

        except Exception as error:
            logger.error('Failed to refresh staging database', error=str(error))
            raise

    def _find_latest_backup(self) -> Optional[str]:
        """Find the most recent backup file in S3"""
        try:
            s3_client = aws.get_s3_client()
            bucket = aws.get_backup_bucket()
            
            # List all objects in the backups folder
            response = s3_client.list_objects_v2(
                Bucket=bucket,
                Prefix='backups/',
                MaxKeys=1000  # Should be more than enough for backup files
            )
            
            if 'Contents' not in response or not response['Contents']:
                logger.warning('No backup files found in S3')
                return None
            
            # Sort by last modified date (newest first)
            backup_objects = sorted(
                response['Contents'], 
                key=lambda x: x['LastModified'], 
                reverse=True
            )
            
            # Return the key of the most recent backup
            latest_backup = backup_objects[0]['Key']
            logger.info('Latest backup found', key=latest_backup, last_modified=backup_objects[0]['LastModified'])
            return latest_backup
            
        except Exception as error:
            logger.error('Failed to find latest backup in S3', error=str(error))
            raise

if __name__ == '__main__':
    import asyncio
    try:
        asyncio.run(RefreshStagingTask().execute())
    except Exception as error:
        print('Refresh staging failed:', error)
        exit(1)
import os
import pathlib
import zipfile
from datetime import datetime
from typing import Dict, Any

from config.aws import aws
from utils.logger import logger
from config.env import env
from utils.database import db

class BackupResult:
    def __init__(self, success: bool, backup_path: str, s3_path: str = None):
        self.success = success
        self.backup_path = backup_path
        self.s3_path = s3_path

    def __str__(self) -> str:
        return f"BackupResult(success={self.success}, backup_path='{self.backup_path}', s3_path='{self.s3_path}')"

class BackupTask:
    def __init__(self):
        self.backup_dir = pathlib.Path.cwd() / 'backups'
        self.backup_dir.mkdir(exist_ok=True)

    async def execute(self, _args: Any = None) -> BackupResult:
        try:
            # Load environment variables
            env.load()

            timestamp = datetime.now().isoformat().replace(':', '-').replace('.', '-')
            backup_filename = f'gallformers_{timestamp}.zip'
            backup_path = self.backup_dir / backup_filename

            # Create temporary SQLite backup
            temp_sqlite_path = self.backup_dir / f'temp_backup_{timestamp}.sqlite'
            logger.info('Creating temporary SQLite backup', temp_path=str(temp_sqlite_path))
            db.backup(str(temp_sqlite_path))

            # Create zip file with the SQLite backup
            logger.info('Creating zip backup', backup_path=str(backup_path))
            with zipfile.ZipFile(backup_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
                zipf.write(temp_sqlite_path, arcname='database.sqlite')

            # Clean up temporary SQLite file
            os.remove(temp_sqlite_path)

            # Upload to S3
            s3_path = None
            try:
                s3_client = aws.get_s3_client()
                bucket = aws.get_backup_bucket()
                s3_key = f'backups/{backup_filename}'
                
                logger.info('Uploading backup to S3', bucket=bucket, key=s3_key)
                s3_client.upload_file(str(backup_path), bucket, s3_key)
                s3_path = f's3://{bucket}/{s3_key}'
                logger.info('Backup uploaded to S3 successfully', s3_path=s3_path)
            except Exception as s3_error:
                logger.error('Failed to upload backup to S3', error=str(s3_error))
                # Continue execution even if S3 upload fails

            logger.info('Backup completed successfully', backup_path=str(backup_path), s3_path=s3_path)

            return BackupResult(success=True, backup_path=str(backup_path), s3_path=s3_path)
        except Exception as error:
            logger.error('Backup failed', error=str(error))
            raise

if __name__ == '__main__':
    import asyncio
    try:
        asyncio.run(BackupTask().execute())
    except Exception as error:
        print('Backup failed:', error)
        exit(1) 
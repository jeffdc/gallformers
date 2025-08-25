import os
import shutil
import sqlite3
import subprocess
from pathlib import Path
from typing import Optional

from config.env import env
from utils.logger import logger

class Database:
    def __init__(self):
        # Use the DB_PATH environment variable
        db_path = env.get('DB_PATH')
        if not db_path:
            raise ValueError("DB_PATH environment variable is not set")
        
        self.db_path = Path(db_path)
        logger.info(f"Using database at {self.db_path}")

    def backup(self, backup_path: str) -> str:
        """
        Create a backup of the SQLite database.
        
        Args:
            backup_path: Path where the backup should be stored
            
        Returns:
            The path to the backup file
            
        Raises:
            FileNotFoundError: If the database file doesn't exist
            sqlite3.Error: If there's an error during the backup process
        """
        if not self.db_path.exists():
            raise FileNotFoundError(f"Database file not found at {self.db_path}")

        # Ensure backup directory exists
        backup_dir = Path(backup_path).parent
        backup_dir.mkdir(parents=True, exist_ok=True)

        # Create backup using SQLite's backup API
        try:
            # First, ensure the database is in a consistent state
            with sqlite3.connect(self.db_path) as src_conn:
                src_conn.execute("PRAGMA wal_checkpoint(FULL)")
                
            # Now create the backup
            with sqlite3.connect(self.db_path) as src_conn, sqlite3.connect(backup_path) as dst_conn:
                src_conn.backup(dst_conn)
                
            # Verify the backup
            self.verify_backup(backup_path)
            
            return backup_path
            
        except sqlite3.Error as e:
            logger.error(f"Failed to create database backup: {str(e)}")
            raise

    def restore(self, backup_path: str) -> None:
        """
        Restore the SQLite database from a backup.
        
        Args:
            backup_path: Path to the backup file
            
        Raises:
            FileNotFoundError: If the backup file doesn't exist
            sqlite3.Error: If there's an error during the restore process
        """
        if not os.path.exists(backup_path):
            raise FileNotFoundError(f"Backup file not found at {backup_path}")

        # Verify the backup before restoring
        self.verify_backup(backup_path)

        # Create a temporary path for the restore
        temp_db_path = self.db_path.parent / f"{self.db_path.name}.temp"
        
        try:
            # Restore to a temporary file first
            with sqlite3.connect(backup_path) as src_conn, sqlite3.connect(temp_db_path) as dst_conn:
                src_conn.backup(dst_conn)
            
            # Verify the restored database
            self.verify_backup(temp_db_path)
            
            # If verification passes, replace the original database
            if self.db_path.exists():
                # Create a backup of the current database
                current_backup = self.db_path.parent / f"{self.db_path.name}.bak"
                shutil.copy2(self.db_path, current_backup)
                logger.info(f"Created backup of current database at {current_backup}")
            
            # Replace the original database with the restored one
            shutil.move(temp_db_path, self.db_path)
            logger.info(f"Database restored successfully from {backup_path}")
            
        except sqlite3.Error as e:
            logger.error(f"Failed to restore database: {str(e)}")
            # Clean up temporary file if it exists
            if os.path.exists(temp_db_path):
                os.remove(temp_db_path)
            raise

    def verify_backup(self, backup_path: str) -> None:
        """
        Verify the integrity of a database backup.
        
        Args:
            backup_path: Path to the backup file to verify
            
        Raises:
            sqlite3.Error: If the backup verification fails
        """
        try:
            # Run SQLite's integrity check
            result = subprocess.run(
                ['sqlite3', backup_path, 'PRAGMA integrity_check;'],
                capture_output=True,
                text=True,
                check=True
            )
            
            if result.stdout.strip() != 'ok':
                raise sqlite3.Error(f"Database integrity check failed: {result.stdout}")
                
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to verify database backup: {str(e)}")
            raise sqlite3.Error(f"Failed to verify database: {e.stderr}")

# Create singleton instance
db = Database() 
import os
import pathlib
import re
from typing import List, Set
from dotenv import load_dotenv, dotenv_values
from utils.logger import logger

class Env:
    def __init__(self):
        self._loaded = False
        self._loaded_vars: Set[str] = set()
        self._env = os.getenv('NODE_ENV', 'development')
        # Get the root directory (parent of scripts)
        self._root_dir = pathlib.Path.cwd().parent

    def load(self):
        if not self._loaded:
            # Load shared environment variables first
            self._load_file(self._root_dir / 'env/.env.shared')

            # Load environment-specific variables
            self._env = os.getenv('NODE_ENV', 'development')  # Refresh env value
            self._load_file(self._root_dir / f'env/.env.{self._env}')

            # Load local overrides last
            if (self._root_dir / 'env/.env.local').exists():
                self._load_file(self._root_dir / 'env/.env.local', override=True)

            # Expand all environment variables that reference other environment variables
            self._expand_env_vars()

            self._validate_required()
            self._loaded = True
            logger.info("Environment variables loaded")

    def _load_file(self, file_path: pathlib.Path, override: bool = False) -> None:
        logger.debug(f"Attempting to load {file_path.name} from {file_path}")
        
        if file_path.exists():
            logger.debug(f"Found {file_path.name}")
            env_config = dotenv_values(file_path)
            
            for key, value in env_config.items():
                # Only consider a variable as loaded if it has a non-empty value
                if override or key not in self._loaded_vars or not os.getenv(key):
                    os.environ[key] = value
                    if value:
                        # Only mark as loaded if the value is non-empty
                        self._loaded_vars.add(key)
                        logger.debug(f"Loaded {key} = {value[:3]}...")
                else:
                    logger.debug(f"Skipped {key} (already loaded with non-empty value)")
        else:
            logger.debug(f"File {file_path.name} not found")

    def _expand_env_vars(self) -> None:
        """
        Expand environment variables that reference other environment variables.
        For example, if APP_PATH=/path/to/app and DB_PATH=$APP_PATH/db.sqlite,
        this will expand DB_PATH to /path/to/app/db.sqlite.
        """
        # Get all environment variables
        env_vars = dict(os.environ)
        
        # Find all variables that reference other variables
        for key, value in env_vars.items():
            if '$' in value:
                # Replace all environment variable references
                expanded_value = self._expand_value(value, env_vars)
                if expanded_value != value:
                    os.environ[key] = expanded_value
                    logger.debug(f"Expanded {key} = {expanded_value[:3]}...")

    def _expand_value(self, value: str, env_vars: dict) -> str:
        """
        Expand environment variable references in a value.
        
        Args:
            value: The value to expand
            env_vars: Dictionary of environment variables
            
        Returns:
            The expanded value
        """
        # First, expand shell variables like $HOME
        expanded_value = os.path.expandvars(value)
        
        # Then find all environment variable references
        pattern = r'\$([A-Za-z0-9_]+)'
        matches = re.findall(pattern, expanded_value)
        
        # Replace each reference with its value
        for match in matches:
            if match in env_vars:
                expanded_value = expanded_value.replace(f'${match}', env_vars[match])
        
        return expanded_value

    def _validate_required(self) -> None:
        required = [
            'DATABASE_URL',
            'AWS_REGION',
            'AWS_ACCESS_KEY_ID',
            'AWS_SECRET_ACCESS_KEY',
            'S3_BUCKET',
            'S3_PUT_AWS_ACCESS_KEY_ID',
            'S3_PUT_AWS_SECRET_ACCESS_KEY',
            'S3_BACKUP_PATH',
            'EMAIL_TO',
            'AUTH0_CLIENT_ID',
            'AUTH0_SECRET',
            'AUTH0_DOMAIN',
            'NEXTAUTH_SECRET',
            'SECRET',
            'MONITOR_EMAIL',
            'APP_PATH',
            'BACKUP_PATH',
            'LOG_PATH',
            'DB_PATH',
        ]

        missing = [key for key in required if not os.getenv(key)]
        if missing:
            raise ValueError(f"Missing required environment variables: {', '.join(missing)}")

    def get(self, key: str, default: str = None) -> str:
        if not self._loaded:
            self.load()
        return os.getenv(key, default)

# Create singleton instance
env = Env() 
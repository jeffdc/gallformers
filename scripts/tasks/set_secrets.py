import os
import subprocess
from typing import Dict, Any, List
from pathlib import Path

from config.env import env
from utils.logger import logger

class SetSecretsResult:
    def __init__(self, success: bool, secrets_set: List[str] = None, errors: List[str] = None):
        self.success = success
        self.secrets_set = secrets_set or []
        self.errors = errors or []

    def __str__(self) -> str:
        return f"SetSecretsResult(success={self.success}, secrets_set={len(self.secrets_set)}, errors={len(self.errors)})"

class SetSecretsTask:
    def __init__(self):
        pass

    async def execute(self, app_name: str = None) -> SetSecretsResult:
        try:
            if not app_name:
                raise ValueError("App name is required (e.g., 'gallformers-staging' or 'gallformers-prod')")

            logger.info('Setting Fly.io secrets', app=app_name)

            # Get only the variables loaded from our env/ files (not system env)
            secrets_to_set = self._get_managed_env_vars()
            
            if not secrets_to_set:
                logger.warning('No secrets found in env/ files to set')
                return SetSecretsResult(success=True, secrets_set=[])

            logger.info(f'Found {len(secrets_to_set)} secrets to set')

            # Set secrets in Fly.io
            secrets_set = []
            errors = []

            for key, value in secrets_to_set.items():
                try:
                    logger.info(f'Setting secret: {key}')
                    
                    # Use flyctl to set the secret
                    result = subprocess.run([
                        'flyctl', 'secrets', 'set', 
                        f'{key}={value}', 
                        '--app', app_name
                    ], capture_output=True, text=True, check=True)
                    
                    secrets_set.append(key)
                    logger.info(f'✓ Successfully set {key}')
                    
                except subprocess.CalledProcessError as e:
                    error_msg = f'✗ Failed to set {key}: {e.stderr.strip()}'
                    errors.append(error_msg)
                    logger.error(error_msg)

            if errors:
                logger.error(f'Failed to set {len(errors)} secrets', errors=errors)
                return SetSecretsResult(success=False, secrets_set=secrets_set, errors=errors)
            
            logger.info(f'✅ All {len(secrets_set)} secrets set successfully!')
            logger.info('You can verify the secrets with: flyctl secrets list --app ' + app_name)
            
            return SetSecretsResult(success=True, secrets_set=secrets_set)

        except Exception as error:
            logger.error('Failed to set secrets', error=str(error))
            raise

    def _get_managed_env_vars(self) -> Dict[str, str]:
        """
        Get environment variables from our managed env/ files using the existing env loader.
        Only returns variables explicitly defined in env/ files, not system environment.
        """
        # Load environment variables using our existing env module
        env.load()
        
        # Get all the variables that were loaded from our env/ files
        # The env module tracks loaded variables in _loaded_vars
        managed_vars = {}
        
        for var_name in env._loaded_vars:
            value = env.get(var_name)
            if value and value.strip():  # Only include non-empty values
                managed_vars[var_name] = value
                logger.debug(f'Including managed env var: {var_name}')
        
        logger.info(f'Found {len(managed_vars)} managed environment variables from env/ files')
        return managed_vars

if __name__ == '__main__':
    import asyncio
    import sys
    
    if len(sys.argv) < 2:
        print('Usage: python set_secrets.py <app-name>')
        print('Example: python set_secrets.py gallformers-staging')
        sys.exit(1)
        
    app_name = sys.argv[1]
    
    try:
        asyncio.run(SetSecretsTask().execute(app_name))
    except Exception as error:
        print('Set secrets failed:', error)
        sys.exit(1)
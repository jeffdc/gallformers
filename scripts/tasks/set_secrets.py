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
            # Load environment variables
            env.load()

            if not app_name:
                raise ValueError("App name is required (e.g., 'gallformers-staging' or 'gallformers-prod')")

            logger.info('Setting Fly.io secrets', app=app_name)

            # Get all environment variables from the loaded env
            env_vars = dict(os.environ)
            
            # Filter out system variables and empty values
            secrets_to_set = self._filter_secrets(env_vars)
            
            if not secrets_to_set:
                logger.warning('No secrets found to set')
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

    def _filter_secrets(self, env_vars: Dict[str, str]) -> Dict[str, str]:
        """
        Filter environment variables to only include secrets that should be set in Fly.io.
        Excludes system variables, empty values, and development-only variables.
        """
        # Variables to exclude from secrets (system vars, development-only, etc.)
        exclude_patterns = [
            'PATH', 'HOME', 'USER', 'SHELL', 'PWD', 'OLDPWD', 'TERM', 'LANG', 'LC_',
            'TMPDIR', 'XDG_', 'DISPLAY', 'SSH_', 'SUDO_', '_', 'SHLVL',
            'GITHUB_', 'CI', 'RUNNER_', 'ACTIONS_',  # GitHub Actions vars
            'NODE_', 'NPM_', 'YARN_',  # Node.js vars that shouldn't be secrets
        ]
        
        # Variables that are definitely secrets/config (include these)
        include_patterns = [
            'DATABASE_URL', 'AWS_', 'S3_', 'AUTH0_', 'NEXTAUTH_', 'SECRET',
            'EMAIL_', 'MONITOR_', 'APP_PATH', 'BACKUP_PATH', 'LOG_PATH', 'DB_PATH'
        ]
        
        filtered = {}
        
        for key, value in env_vars.items():
            # Skip empty values
            if not value or value.strip() == '':
                continue
                
            # Skip system variables
            if any(key.startswith(pattern) for pattern in exclude_patterns):
                continue
                
            # Include if matches include patterns or doesn't match exclude patterns
            if any(key.startswith(pattern) for pattern in include_patterns) or key.upper() == key:
                # Only include uppercase variables or those matching include patterns
                # This helps filter out local shell variables
                filtered[key] = value
                
        return filtered

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
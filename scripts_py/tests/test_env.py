import os
import pathlib
import pytest
from unittest.mock import patch, mock_open
from config.env import Env

@pytest.fixture
def env_instance():
    # Create a fresh instance for each test
    return Env()

@pytest.fixture
def temp_env_files(tmp_path):
    # Create temporary environment files with all required variables
    shared_content = """
    DATABASE_URL=postgresql://user:pass@localhost:5432/db
    AWS_REGION=us-east-1
    S3_BUCKET=test-bucket
    S3_PUT_AWS_ACCESS_KEY_ID=test-put-key
    S3_PUT_AWS_SECRET_ACCESS_KEY=test-put-secret
    S3_BACKUP_PATH=/backups
    EMAIL_TO=test@example.com
    AUTH0_CLIENT_ID=test-client-id
    AUTH0_SECRET=test-secret
    AUTH0_DOMAIN=test.auth0.com
    NEXTAUTH_SECRET=test-nextauth-secret
    SECRET=test-secret
    MONITOR_EMAIL=monitor@example.com
    APP_PATH=/app
    BACKUP_PATH=/backups
    LOG_PATH=/logs
    DB_PATH=/db
    """
    
    dev_content = """
    NODE_ENV=development
    AWS_ACCESS_KEY_ID=dev-key
    AWS_SECRET_ACCESS_KEY=dev-secret
    """
    
    local_content = """
    AWS_ACCESS_KEY_ID=local-key
    AWS_SECRET_ACCESS_KEY=local-secret
    """
    
    # Create the files
    (tmp_path / ".env.shared").write_text(shared_content)
    (tmp_path / ".env.development").write_text(dev_content)
    (tmp_path / ".env.local").write_text(local_content)
    
    return tmp_path

def test_env_initialization(env_instance):
    """Test that the Env class initializes correctly"""
    assert env_instance._loaded == False
    assert isinstance(env_instance._loaded_vars, set)
    assert env_instance._env == 'development'  # Default value

def test_load_environment_files(env_instance, temp_env_files, monkeypatch):
    """Test loading environment files in the correct order"""
    # Change to the temporary directory
    monkeypatch.chdir(temp_env_files)
    
    # Load the environment
    env_instance.load()
    
    # Check that variables are loaded in the correct order
    assert os.getenv('DATABASE_URL') == 'postgresql://user:pass@localhost:5432/db'
    assert os.getenv('AWS_REGION') == 'us-east-1'
    assert os.getenv('NODE_ENV') == 'development'
    
    # Local overrides should take precedence
    assert os.getenv('AWS_ACCESS_KEY_ID') == 'local-key'
    assert os.getenv('AWS_SECRET_ACCESS_KEY') == 'local-secret'

def test_validate_required_variables(env_instance, temp_env_files, monkeypatch):
    """Test validation of required environment variables"""
    # Change to the temporary directory
    monkeypatch.chdir(temp_env_files)
    
    # Load the environment
    env_instance.load()
    
    # Check that validation passes with all required variables
    # This should not raise an exception
    env_instance._validate_required()
    
    # Now remove a required variable and check that validation fails
    with patch.dict(os.environ, {}, clear=True):
        with pytest.raises(ValueError) as excinfo:
            env_instance._validate_required()
        assert "Missing required environment variables" in str(excinfo.value)

def test_get_environment_variable(env_instance, temp_env_files, monkeypatch):
    """Test getting environment variables"""
    # Change to the temporary directory
    monkeypatch.chdir(temp_env_files)
    
    # Load the environment
    env_instance.load()
    
    # Test getting an existing variable
    assert env_instance.get('DATABASE_URL') == 'postgresql://user:pass@localhost:5432/db'
    
    # Test getting a non-existent variable with default
    assert env_instance.get('NON_EXISTENT', 'default') == 'default'
    
    # Test getting a non-existent variable without default
    assert env_instance.get('NON_EXISTENT') is None

def test_loaded_vars_tracking(env_instance, temp_env_files, monkeypatch):
    """Test that loaded variables are tracked correctly"""
    # Change to the temporary directory
    monkeypatch.chdir(temp_env_files)
    
    # Load the environment
    env_instance.load()
    
    # Check that loaded variables are tracked
    assert 'DATABASE_URL' in env_instance._loaded_vars
    assert 'AWS_REGION' in env_instance._loaded_vars
    assert 'AWS_ACCESS_KEY_ID' in env_instance._loaded_vars
    
    # Check that empty variables are not tracked
    assert 'EMPTY_VAR' not in env_instance._loaded_vars

def test_environment_specific_loading(env_instance, temp_env_files, monkeypatch):
    """Test loading environment-specific variables"""
    # Set a different environment
    monkeypatch.setenv('NODE_ENV', 'production')
    
    # Create a production environment file with all required variables
    prod_content = """
    NODE_ENV=production
    AWS_ACCESS_KEY_ID=prod-key
    AWS_SECRET_ACCESS_KEY=prod-secret
    DATABASE_URL=postgresql://user:pass@localhost:5432/db
    AWS_REGION=us-east-1
    S3_BUCKET=test-bucket
    S3_PUT_AWS_ACCESS_KEY_ID=test-put-key
    S3_PUT_AWS_SECRET_ACCESS_KEY=test-put-secret
    S3_BACKUP_PATH=/backups
    EMAIL_TO=test@example.com
    AUTH0_CLIENT_ID=test-client-id
    AUTH0_SECRET=test-secret
    AUTH0_DOMAIN=test.auth0.com
    NEXTAUTH_SECRET=test-nextauth-secret
    SECRET=test-secret
    MONITOR_EMAIL=monitor@example.com
    APP_PATH=/app
    BACKUP_PATH=/backups
    LOG_PATH=/logs
    DB_PATH=/db
    """
    (temp_env_files / ".env.production").write_text(prod_content)
    
    # Remove the local file to prevent overrides
    (temp_env_files / ".env.local").unlink()
    
    # Change to the temporary directory
    monkeypatch.chdir(temp_env_files)
    
    # Load the environment
    env_instance.load()
    
    # Check that production variables are loaded
    assert os.getenv('NODE_ENV') == 'production'
    assert os.getenv('AWS_ACCESS_KEY_ID') == 'prod-key'
    assert os.getenv('AWS_SECRET_ACCESS_KEY') == 'prod-secret' 
"""Provider configuration: load YAML config and resolve provider/model specs."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

import yaml


@dataclass(frozen=True)
class ProviderConfig:
    """Resolved provider configuration ready for API use."""

    base_url: str
    api_key: str
    model: str
    no_system_role: bool = False


def load_config(config_path: str) -> dict:
    """Load and validate a providers YAML config file.

    Returns the inner ``providers`` dict (provider name -> settings).

    Raises:
        FileNotFoundError: If the config file does not exist.
        ValueError: If the YAML is missing the top-level ``providers`` key.
    """
    path = Path(config_path)
    if not path.exists():
        raise FileNotFoundError(f"Config file not found: {config_path}")

    with path.open() as f:
        raw = yaml.safe_load(f)

    if not isinstance(raw, dict) or "providers" not in raw:
        raise ValueError(f"Config file must contain a top-level 'providers' key: {config_path}")

    return raw["providers"]


def resolve_model(model_spec: str, config: dict) -> ProviderConfig:
    """Parse a ``provider/model`` spec and resolve it against the config.

    Args:
        model_spec: A string in ``provider/model`` format (e.g. ``deepseek/deepseek-chat``).
        config: The providers dict returned by :func:`load_config`.

    Returns:
        A :class:`ProviderConfig` with base_url, api_key, and model name.

    Raises:
        ValueError: On invalid format, unknown provider/model, or missing env var.
    """
    if "/" not in model_spec:
        raise ValueError(
            f"Model spec must be in provider/model format (e.g. deepseek/deepseek-chat), "
            f"got: {model_spec!r}"
        )

    provider_name, model_name = model_spec.split("/", 1)

    if provider_name not in config:
        available = ", ".join(sorted(config.keys()))
        raise ValueError(f"Unknown provider {provider_name!r}. Available providers: {available}")

    provider = config[provider_name]

    if model_name not in provider["models"]:
        available = ", ".join(provider["models"])
        raise ValueError(
            f"Unknown model {model_name!r} for provider {provider_name!r}. "
            f"Available models: {available}"
        )

    env_key = provider["env_key"]
    api_key = os.environ.get(env_key)
    if not api_key:
        raise ValueError(
            f"Environment variable {env_key} is not set. Set it to your {provider_name} API key."
        )

    return ProviderConfig(
        base_url=provider["base_url"],
        api_key=api_key,
        model=model_name,
        no_system_role=provider.get("no_system_role", False),
    )

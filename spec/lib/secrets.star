# Addi Platform - Starlark Standard Library
# spec/lib/secrets.star
#
# Secret reference constructors for ExternalSecrets Operator (ESO).
# Returns dicts that the generator converts to ExternalSecret manifests.
# Secrets are NEVER stored in Git - only references to their keys.
#
# Usage:
#   load("@addi//lib:secrets.star", "secrets_manager", "ssm")


def secrets_manager(key, field=None, version="AWSCURRENT"):
    """Reference a secret stored in AWS Secrets Manager.

    The generator creates an ExternalSecret resource that pulls the value
    from AWS Secrets Manager at runtime using Pod Identity (no long-lived keys).

    Args:
        key: secret key name in Secrets Manager,
             e.g. "DB_PASSWORD" or "payments/prod/stripe-key"
        field: optional JSON field within a JSON-valued secret
        version: Secrets Manager version stage (default: "AWSCURRENT")

    Returns:
        dict with secret provider configuration

    Example:
        secrets = [
            secrets_manager("DB_PASSWORD"),
            secrets_manager("STRIPE_API_KEY"),
            secrets_manager("payments/certs", field="tls.crt"),
        ]
    """
    ref = {
        "provider": "aws-secrets-manager",
        "key": key,
        "version": version,
    }
    if field != None:
        ref["field"] = field
    return ref


def ssm(key, with_decryption=True):
    """Reference a parameter stored in AWS SSM Parameter Store.

    The generator creates an ExternalSecret resource pulling the value
    from SSM using Pod Identity.

    Args:
        key: SSM parameter path, e.g. "/addi/payments/prod/feature-flag"
        with_decryption: decrypt SecureString parameters (default: True)

    Returns:
        dict with secret provider configuration

    Example:
        secrets = [
            ssm("/addi/payments/prod/db-host"),
            ssm("/addi/payments/prod/feature-flags"),
        ]
    """
    return {
        "provider": "aws-ssm",
        "key": key,
        "with_decryption": with_decryption,
    }

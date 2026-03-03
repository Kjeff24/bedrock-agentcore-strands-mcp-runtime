# Getting JWT Tokens for AgentCore Gateway Authentication

## Overview

When your gateway uses `authorizer_type=CUSTOM_JWT`, you need a JWT token from an identity provider to authenticate.

## Option 1: Amazon Cognito (Recommended for AWS)

### Setup
```bash
# Create Cognito user pool and app client via AWS Console or CLI
aws cognito-idp create-user-pool --pool-name agentcore-users
aws cognito-idp create-user-pool-client \
  --user-pool-id us-east-1_xxxxx \
  --client-name agentcore-client \
  --generate-secret
```

### Get Token
```python
import boto3
import base64
import hmac
import hashlib

def get_cognito_token(username, password, client_id, client_secret, user_pool_id):
    """Get JWT token from Cognito"""
    client = boto3.client('cognito-idp')
    
    # Calculate secret hash
    message = username + client_id
    secret_hash = base64.b64encode(
        hmac.new(
            client_secret.encode(),
            message.encode(),
            hashlib.sha256
        ).digest()
    ).decode()
    
    # Authenticate
    response = client.initiate_auth(
        ClientId=client_id,
        AuthFlow='USER_PASSWORD_AUTH',
        AuthParameters={
            'USERNAME': username,
            'PASSWORD': password,
            'SECRET_HASH': secret_hash
        }
    )
    
    return response['AuthenticationResult']['IdToken']

# Usage
token = get_cognito_token(
    username='user@example.com',
    password='Password123!',
    client_id='your-client-id',
    client_secret='your-client-secret',
    user_pool_id='us-east-1_xxxxx'
)
```

### Using AWS CLI
```bash
aws cognito-idp initiate-auth \
  --client-id your-client-id \
  --auth-flow USER_PASSWORD_AUTH \
  --auth-parameters USERNAME=user@example.com,PASSWORD=Password123!

# Extract IdToken from response
export JWT_TOKEN=$(aws cognito-idp initiate-auth ... | jq -r '.AuthenticationResult.IdToken')
```

## Option 2: Google OAuth

### Setup
1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Create OAuth 2.0 Client ID
3. Add callback URL: `https://bedrock-agentcore.{region}.amazonaws.com/identities/oauth2/callback`

### Get Token
```python
from google.oauth2 import id_token
from google.auth.transport import requests

def get_google_token(client_id, client_secret, refresh_token):
    """Get JWT token from Google"""
    import requests as req
    
    response = req.post(
        'https://oauth2.googleapis.com/token',
        data={
            'client_id': client_id,
            'client_secret': client_secret,
            'refresh_token': refresh_token,
            'grant_type': 'refresh_token'
        }
    )
    
    return response.json()['id_token']
```

## Option 3: Auth0

### Setup
1. Create Auth0 account and application
2. Configure callback URLs
3. Get domain, client ID, and client secret

### Get Token
```python
import requests

def get_auth0_token(domain, client_id, client_secret, username, password):
    """Get JWT token from Auth0"""
    response = requests.post(
        f'https://{domain}/oauth/token',
        json={
            'grant_type': 'password',
            'username': username,
            'password': password,
            'client_id': client_id,
            'client_secret': client_secret,
            'audience': f'https://{domain}/api/v2/',
            'scope': 'openid profile email'
        }
    )
    
    return response.json()['id_token']

# Usage
token = get_auth0_token(
    domain='your-tenant.auth0.com',
    client_id='your-client-id',
    client_secret='your-client-secret',
    username='user@example.com',
    password='Password123!'
)
```

### Using curl
```bash
curl --request POST \
  --url https://your-tenant.auth0.com/oauth/token \
  --header 'content-type: application/json' \
  --data '{
    "grant_type":"password",
    "username":"user@example.com",
    "password":"Password123!",
    "client_id":"your-client-id",
    "client_secret":"your-client-secret",
    "audience":"https://your-tenant.auth0.com/api/v2/",
    "scope":"openid profile email"
  }' | jq -r '.id_token'
```

## Option 4: GitHub OAuth

### Setup
1. Create GitHub OAuth App
2. Get Client ID and Client Secret

### Get Token
```bash
# Step 1: Get authorization code (requires browser)
https://github.com/login/oauth/authorize?client_id=YOUR_CLIENT_ID&scope=user

# Step 2: Exchange code for token
curl -X POST https://github.com/login/oauth/access_token \
  -d "client_id=YOUR_CLIENT_ID" \
  -d "client_secret=YOUR_CLIENT_SECRET" \
  -d "code=AUTHORIZATION_CODE" \
  -H "Accept: application/json"
```

## Option 5: Custom JWT (for testing)

### Generate Test JWT
```python
import jwt
import datetime

def create_test_jwt(secret_key='your-secret'):
    """Create a test JWT token"""
    payload = {
        'sub': 'user123',
        'iss': 'https://your-issuer.com',
        'aud': 'your-audience',
        'exp': datetime.datetime.utcnow() + datetime.timedelta(hours=1),
        'iat': datetime.datetime.utcnow()
    }
    
    token = jwt.encode(payload, secret_key, algorithm='HS256')
    return token

# Usage
test_token = create_test_jwt()
```

## Storing Tokens Securely

### In AWS Secrets Manager
```bash
# Store token
aws secretsmanager create-secret \
  --name gateway-jwt-token \
  --secret-string "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..."

# Retrieve in code
import boto3

def get_jwt_from_secrets():
    client = boto3.client('secretsmanager')
    response = client.get_secret_value(SecretId='gateway-jwt-token')
    return response['SecretString']
```

### In Environment Variable
```bash
# .env file
JWT_TOKEN=eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
```

## Token Refresh

JWT tokens expire. Implement refresh logic:

```python
import os
import time
import jwt

class TokenManager:
    def __init__(self, get_token_func):
        self.get_token_func = get_token_func
        self.token = None
        self.expires_at = 0
    
    def get_valid_token(self):
        """Get token, refreshing if expired"""
        if time.time() >= self.expires_at - 60:  # Refresh 1 min before expiry
            self.token = self.get_token_func()
            # Decode to get expiry
            decoded = jwt.decode(self.token, options={"verify_signature": False})
            self.expires_at = decoded.get('exp', time.time() + 3600)
        
        return self.token

# Usage in agent
token_manager = TokenManager(lambda: get_cognito_token(...))
JWT_TOKEN = token_manager.get_valid_token()
```

## Recommended Approach

**For Production:**
1. Use Amazon Cognito (easiest AWS integration)
2. Store tokens in AWS Secrets Manager
3. Implement token refresh logic
4. Use IAM roles for Runtime to access Secrets Manager

**For Development:**
1. Use Cognito or Auth0
2. Store token in `.env` file (not committed to git)
3. Manually refresh when expired

**Example Production Setup:**
```python
import boto3
import os

def get_jwt_token():
    """Get JWT from Secrets Manager or environment"""
    if os.environ.get('JWT_TOKEN'):
        return os.environ['JWT_TOKEN']
    
    # Fallback to Secrets Manager
    client = boto3.client('secretsmanager')
    response = client.get_secret_value(SecretId='gateway-jwt-token')
    return response['SecretString']

JWT_TOKEN = get_jwt_token()
```

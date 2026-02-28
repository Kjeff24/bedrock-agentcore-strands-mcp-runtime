#!/usr/bin/env python3
"""
Invoke AgentCore Runtime with a prompt.

Usage:
    python invoke.py "What is the weather today?" --runtime-arn <arn>
    python invoke.py "Hello" --runtime-arn <arn> --session-id user123

Environment variables:
    AWS_REGION - AWS region (default: eu-west-1)
"""

import argparse
import json
import boto3
import uuid


def invoke_runtime(runtime_arn: str, prompt: str, session_id: str = None, region: str = "eu-west-1"):
    """Invoke AgentCore Runtime with a prompt."""
    
    client = boto3.client("bedrock-agentcore", region_name=region)
    
    # Generate session ID if not provided (must be 33+ characters)
    if not session_id:
        session_id = str(uuid.uuid4()).replace("-", "") + "000"
    else:
        session_id = session_id.ljust(33, "0")
    
    print(f"Invoking runtime: {runtime_arn}")
    print(f"Prompt: {prompt}")
    print(f"Session: {session_id}")
    print("-" * 80)
    
    try:
        response = client.invoke_agent_runtime(
            agentRuntimeArn=runtime_arn,
            runtimeSessionId=session_id,
            payload=json.dumps({"input": {"prompt": prompt}}).encode()
        )
        
        # Parse response
        result = json.loads(response["response"].read())
        
        # Print response
        if "output" in result:
            print("\nResponse:")
            print(json.dumps(result["output"], indent=2))
        elif "response" in result:
            print("\nResponse:")
            print(result["response"])
        else:
            print("\nFull Response:")
            print(json.dumps(result, indent=2))
        
        print(f"\nSession ID: {session_id}")
        
        return result
        
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
        raise


def main():
    parser = argparse.ArgumentParser(description="Invoke AgentCore Runtime")
    parser.add_argument("prompt", help="Prompt to send to the agent")
    parser.add_argument("--runtime-arn", "-a", required=True, help="AgentCore Runtime ARN")
    parser.add_argument("--session-id", "-s", help="Session ID for conversation continuity (min 33 chars)")
    parser.add_argument("--region", default="eu-west-1", help="AWS region (default: eu-west-1)")
    
    args = parser.parse_args()
    
    invoke_runtime(
        runtime_arn=args.runtime_arn,
        prompt=args.prompt,
        session_id=args.session_id,
        region=args.region
    )


if __name__ == "__main__":
    main()

#!/bin/bash
# Run from project root
set -e

# Configuration
REGION="${AWS_REGION:-eu-west-1}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REPO_NAME="${ECR_REPO_NAME:-agentvault_agent}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPO_NAME}"

echo "Building and pushing Docker image to ECR..."
echo "Region: $REGION"
echo "Repository: $REPO_NAME"
echo "Tag: $IMAGE_TAG"

# Authenticate Docker to ECR
echo "Authenticating Docker to ECR..."
aws ecr get-login-password --region "$REGION" | \
  docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

# Build image for ARM64
echo "Building Docker image..."
docker build --platform linux/arm64 -t "$REPO_NAME:$IMAGE_TAG" .

# Tag image
echo "Tagging image..."
docker tag "$REPO_NAME:$IMAGE_TAG" "$ECR_URI:$IMAGE_TAG"

# Push image
echo "Pushing image to ECR..."
docker push "$ECR_URI:$IMAGE_TAG"

echo ""
echo "✅ Image pushed successfully!"
echo "Image URI: $ECR_URI:$IMAGE_TAG"
echo ""
echo "Use this URI in Terraform:"
echo "terraform apply -var=\"container_image_uri=$ECR_URI:$IMAGE_TAG\""

#!/usr/bin/env bash
set -xeuo pipefail

ECR_REPO_URL="${ecr_repo_url}"
AWS_REGION="${region}"
CONTAINER_NAME="${container_name}"
HOST_PORT="${host_port}"
CONTAINER_PORT="${container_port}"
IMAGE_TAG="${image_tag}"

dnf -y install docker awscli
systemctl enable docker
systemctl start docker

attempt=0
while true; do
  if aws ecr get-login-password --region "$${AWS_REGION}" \
     | docker login --username AWS --password-stdin "$${ECR_REPO_URL}"; then
    break
  fi
  attempt=$(expr "$attempt" + 1)
  if [ "$attempt" -ge 20 ]; then
    echo "ECR login failed after $attempt attempts."
    exit 1
  fi
  echo "ECR login failed. Retrying in 10s..."
  sleep 10
done

attempt=0
while true; do
  if docker pull "$${ECR_REPO_URL}:$${IMAGE_TAG}"; then
    break
  fi
  attempt=$(expr "$attempt" + 1)
  if [ "$attempt" -ge 60 ]; then
    echo "docker pull failed after $attempt attempts."
    exit 1
  fi
  echo "Image not available yet. Retrying in 10s..."
  sleep 10
done

if docker ps -a --format '{{.Names}}' | grep -Eq "^$${CONTAINER_NAME}$"; then
  docker rm -f "$${CONTAINER_NAME}" || true
fi

docker run -d \
  --name "$${CONTAINER_NAME}" \
  --restart unless-stopped \
  -p "$${HOST_PORT}:$${CONTAINER_PORT}" \
  "$${ECR_REPO_URL}:$${IMAGE_TAG}"

echo "Container launched."

# Data Generator

Generates mortgage applications, payment history, and credit scores for the workshop.

Pre-built image: `ghcr.io/ahmedszamzam/datagen:latest`

## Rebuilding after code changes

```bash
# Log in to ghcr.io (need a GitHub PAT with write:packages scope)
echo YOUR_PAT | docker login ghcr.io -u YOUR_USERNAME --password-stdin

# Build and push multi-platform image
docker buildx create --name multiarch --use 2>/dev/null || docker buildx use multiarch
docker buildx build --platform linux/amd64,linux/arm64 \
  -t ghcr.io/ahmedszamzam/datagen:latest --push .
```

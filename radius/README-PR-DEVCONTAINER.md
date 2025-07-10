# Radius PR Dev Container Workflow

This workflow automatically watches the [radius-project/radius](https://github.com/radius-project/radius) repository for new Pull Requests and builds dev containers that include:

- The PR branch source code
- A running k3d Kubernetes cluster
- Radius deployed and configured on the cluster
- All necessary development tools

## How it works

1. **Automated Monitoring**: The workflow runs every 30 minutes to check for new PRs in the radius-project/radius repository
2. **Manual Trigger**: You can manually trigger the workflow for a specific PR number
3. **Container Building**: For each new PR, a dev container is built with:
   - The PR branch checked out
   - Radius built from source
   - k3d cluster pre-configured
   - Radius deployed and ready to use
4. **GHCR Publishing**: The container is published to GitHub Container Registry (GHCR) with tags:
   - `pr-{PR_NUMBER}` (e.g., `pr-123`)
   - `pr-{PR_NUMBER}-{COMMIT_SHA}` (e.g., `pr-123-abc1234`)

## Using the Dev Containers

### Pull and Run a PR Dev Container

```bash
# Pull the container for PR #123
docker pull ghcr.io/brooke-hamilton/dotfiles/radius-pr-devcontainer:pr-123

# Run the container with privileged mode (required for k3d)
docker run -it --privileged -p 8081:8081 ghcr.io/brooke-hamilton/dotfiles/radius-pr-devcontainer:pr-123
```

### Container Features

Once the container starts, you'll have:

- **Radius UI**: Available at http://localhost:8081
- **k3d cluster**: Named `k3d-k3s-default`
- **Radius workspace**: Pre-configured as `kubernetes/k3d`
- **Source Code**: PR branch in `/workspace/radius`
- **Built Binaries**: `rad` CLI available in PATH

### Useful Commands

```bash
# Check Radius version
rad version

# List workspaces
rad workspace list

# Check cluster status
kubectl get nodes
kubectl get pods -A

# Navigate to source code
cd /workspace/radius
```

## Manual Workflow Trigger

You can manually trigger the workflow for a specific PR:

1. Go to the [Actions tab](../../actions/workflows/radius-pr-devcontainer.yml)
2. Click "Run workflow"
3. Enter the PR number you want to build
4. Click "Run workflow"

## Container Registry

All built containers are available at:
- **Registry**: `ghcr.io/brooke-hamilton/dotfiles/radius-pr-devcontainer`
- **Tags**: `pr-{PR_NUMBER}` and `pr-{PR_NUMBER}-{COMMIT_SHA}`

## Requirements

- Docker with privileged mode support
- At least 4GB RAM available for the container
- Port 8081 available on the host

## Troubleshooting

### Container won't start
- Ensure Docker is running in privileged mode: `docker run --privileged ...`
- Check that port 8081 is not already in use

### k3d cluster issues
- The container automatically sets up the k3d cluster on startup
- If there are issues, you can manually run: `setup_k3d.sh`

### Radius not responding
- Check if the cluster is ready: `kubectl get nodes`
- Verify Radius pods are running: `kubectl get pods -A`
- Re-run setup if needed: `setup_radius_debugging.sh`

## Development

The workflow and container configuration files are located in:
- `.github/workflows/radius-pr-devcontainer.yml` - GitHub Actions workflow
- `radius/Dockerfile.pr-devcontainer` - Container build configuration
- `radius/setup_k3d_pr.sh` - Enhanced k3d setup script
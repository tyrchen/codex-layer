# Codex CLI Lambda Layer

AWS Lambda Layer that bundles the [Codex CLI](https://github.com/openai/codex) (from [tyrchen/codex](https://github.com/tyrchen/codex) fork with Lambda compatibility patches) along with common CLI tools for code analysis workloads.

## What's in the layer

| Binary | Source | Description |
|--------|--------|-------------|
| `codex` | [tyrchen/codex](https://github.com/tyrchen/codex) | Codex CLI (aarch64 musl static binary) |
| `rg` | [BurntSushi/ripgrep](https://github.com/BurntSushi/ripgrep) | Fast regex search |
| `jq` | [jqlang/jq](https://github.com/jqlang/jq) | JSON processor |
| `tree` | Amazon Linux 2023 | Directory listing |
| `git` | Amazon Linux 2023 | Git (with libexec helpers) |

Shared libraries (`libpcre2-8`, `libexpat`) required by the AL2023 binaries are also included.

All binaries target **aarch64** (ARM64) to match Lambda Graviton instances.

## Download the layer

```bash
# Latest build
gh release download latest --repo tyrchen/codex-layer -p 'codex-layer.zip'

# Specific version
gh release download v0.107.0-alpha.8 --repo tyrchen/codex-layer -p 'codex-layer.zip'
```

## Use in another project

Download the layer ZIP and publish it to your AWS account:

```bash
gh release download latest --repo tyrchen/codex-layer -p 'codex-layer.zip'

aws lambda publish-layer-version \
  --layer-name codex-cli \
  --compatible-architectures arm64 \
  --zip-file fileb://codex-layer.zip \
  --description "Codex CLI Lambda Layer"
```

In a Lambda function, the layer contents are available under `/opt`:

```bash
/opt/bin/codex
/opt/bin/rg
/opt/bin/jq
/opt/bin/tree
/opt/bin/git
```

## Build

### Via GitHub Actions (recommended)

```bash
make build      # trigger CI, wait for completion, download the ZIP
```

This triggers the `build-layer` workflow on an ARM64 runner, then downloads the resulting release artifact.

### Locally

Requires `yq`, `gh`, `curl`, `zip`, and Docker or Podman:

```bash
make build-local
```

### Download only (skip build)

```bash
make download   # grab the latest release without rebuilding
```

### Publish to AWS Lambda

```bash
make publish AWS_PROFILE=my-profile AWS_REGION=us-east-2
```

### All targets

```
make build        Trigger CI build, wait, and download the release artifact
make download     Download the latest release artifact (no rebuild)
make build-local  Build the layer locally (requires yq, gh, docker/podman)
make publish      Publish the layer ZIP to AWS Lambda
make inspect      List contents of the built layer ZIP
make clean        Remove local layer artifacts
```

## Adding a new asset

All assets are declared in [`assets.yaml`](assets.yaml). Edit that file and push — the CI workflow picks up changes automatically.

### Add a GitHub Release binary

Add an entry under `tools:`:

```yaml
tools:
  - name: fd
    repo: sharkdp/fd
    version: "10.2.0"
    tag: "v{version}"
    asset: "fd-v{version}-aarch64-unknown-linux-gnu.tar.gz"
    strip: 1
    extract_path: "fd-v{version}-aarch64-unknown-linux-gnu/fd"
```

Fields:

| Field | Required | Description |
|-------|----------|-------------|
| `name` | yes | Binary name in the layer (`/opt/bin/<name>`) |
| `repo` | yes | GitHub `owner/repo` |
| `version` | yes | Release version |
| `tag` | no | Git tag pattern (default: `v{version}`). Use `{version}` placeholder. |
| `asset` | yes | Release asset filename. Use `{version}` placeholder. |
| `strip` | no | `tar --strip-components` value (default: `0`) |
| `extract_path` | no | Extract only this path from the tarball |

### Add an Amazon Linux 2023 system package

```yaml
system:
  packages:
    - my-package        # dnf package name
  bins:
    - my-binary         # binary to copy from /usr/bin
  libs:
    - "libfoo.so*"      # shared libraries from /usr/lib64
```

## Versioning

Releases are tagged by the codex binary version (e.g. `v0.107.0-alpha.8`). A rolling `latest` tag always points to the most recent build.

## Project structure

```
.github/workflows/build-layer.yml   GitHub Actions workflow (ARM64 runner)
assets.yaml                         Declarative asset manifest
scripts/build-layer.sh              Build script (used by CI and local builds)
Makefile                            Developer interface
```

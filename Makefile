.DEFAULT_GOAL := help

LAYER_DIR  := /tmp/codex-layer
LAYER_ZIP  := /tmp/codex-layer.zip

AWS_PROFILE ?= need-provide
AWS_REGION  ?= us-east-2
LAYER_NAME  ?= codex-cli

# ============================================================================
# Build
# ============================================================================

build: ## Trigger CI build, wait, and download the release artifact
	@echo "==> Triggering build-layer workflow..."
	@gh workflow run build-layer.yml
	@echo "==> Waiting for workflow to start..."
	@sleep 5
	@RUN_ID=$$(gh run list --workflow=build-layer.yml --limit=1 --json databaseId --jq '.[0].databaseId'); \
	echo "==> Waiting for run $$RUN_ID to complete..."; \
	gh run watch "$$RUN_ID" --exit-status; \
	echo "==> Downloading layer from latest release..."; \
	rm -f $(LAYER_ZIP); \
	gh release download latest --pattern 'codex-layer.zip' --output $(LAYER_ZIP); \
	echo "==> Layer downloaded to $(LAYER_ZIP)"; \
	du -sh $(LAYER_ZIP)

download: ## Download the latest release artifact (no rebuild)
	@echo "==> Downloading layer from latest release..."
	@rm -f $(LAYER_ZIP)
	@gh release download latest --pattern 'codex-layer.zip' --output $(LAYER_ZIP)
	@echo "==> Layer downloaded to $(LAYER_ZIP)"
	@du -sh $(LAYER_ZIP)

build-local: ## Build the layer locally (requires yq, gh, docker/podman)
	@scripts/build-layer.sh

# ============================================================================
# Publish
# ============================================================================

publish: ## Publish the layer ZIP to AWS Lambda
	@test -f $(LAYER_ZIP) || { echo "ERROR: $(LAYER_ZIP) not found. Run 'make build' or 'make build-local' first."; exit 1; }
	aws lambda publish-layer-version \
	  --layer-name $(LAYER_NAME) \
	  --compatible-architectures arm64 \
	  --zip-file fileb://$(LAYER_ZIP) \
	  --description "Codex CLI Lambda Layer (codex + rg + jq + tree + git)" \
	  --profile $(AWS_PROFILE) \
	  --region $(AWS_REGION)
	@echo "==> Layer published!"

# ============================================================================
# Utilities
# ============================================================================

inspect: ## List contents of the built layer ZIP
	@test -f $(LAYER_ZIP) || { echo "ERROR: $(LAYER_ZIP) not found."; exit 1; }
	@unzip -l $(LAYER_ZIP)
	@echo ""
	@du -sh $(LAYER_ZIP)

clean: ## Remove local layer artifacts
	rm -rf $(LAYER_DIR) $(LAYER_ZIP) /tmp/codex-artifact /tmp/codex-layer-dl

# ============================================================================
# Help
# ============================================================================

help: ## Show this help message
	@awk 'BEGIN {FS = ":.*##"; printf "Usage: make \033[36m<target>\033[0m\n\n"} \
		/^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

.PHONY: build download build-local publish inspect clean help

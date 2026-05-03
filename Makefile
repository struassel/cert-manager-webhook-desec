GO ?= $(shell which go)
OS ?= $(shell $(GO) env GOOS)
ARCH ?= $(shell $(GO) env GOARCH)
OUT ?= $(shell pwd)/_out

IMAGE_NAME := "ghcr.io/struassel/cert-manager-webhook-desec"
IMAGE_TAG := "latest"
CHART_NAME := "cert-manager-webhook-desec"

# FIXME: Required to set the environment variables below. Remove when fixed.
ENVTEST_K8S_VERSION=1.35.0

HELM_FOLDER := "charts/desec-webhook"
HELM_FILES := $(shell find $(HELM_FOLDER))

TEST_ZONE_NAME ?= "example.com"
export TEST_ZONE_NAME


# Detect whether podman or docker is installed
DOCKER := $(shell \
    if command -v podman >/dev/null 2>&1; then \
        echo podman; \
    elif command -v docker >/dev/null 2>&1; then \
        echo docker; \
    else \
        echo none; \
    fi)

ifeq ($(DOCKER),none)
	$(error "Neither podman nor docker is installed. Please install one to continue.")
endif


.PHONY: all
all: build image chart

# FIXME: The environment variables are required by the test helper in cert-manager, but not required to run the tests.
test: setup-envtest
	TEST_ASSET_ETCD=$(LOCALBIN)/k8s/$(ENVTEST_K8S_VERSION)-$(OS)-$(ARCH)/etcd \
	TEST_ASSET_KUBE_APISERVER=$(LOCALBIN)/k8s/$(ENVTEST_K8S_VERSION)-$(OS)-$(ARCH)/kube-apiserver \
	TEST_ASSET_KUBECTL=$(LOCALBIN)/k8s/$(ENVTEST_K8S_VERSION)-$(OS)-$(ARCH)/kubectl \
	$(GO) test -v .


.PHONY: upgrade_deps
upgrade_deps: 
	$(GO) get -u ./... && $(GO) mod tidy

.PHONY: clean
clean:
	chmod -R u+w $(LOCALBIN) $(OUT) 2>/dev/null || true
	rm -rf $(LOCALBIN) $(OUT)

.PHONY: image
image:
	$(DOCKER) build --arch $(ARCH) -t "$(IMAGE_NAME):$(IMAGE_TAG)" .

.PHONY: build
build: $(OUT)/webhook

$(OUT)/webhook: $(OUT)
	CGO_ENABLED=0 $(GO) build -v -o $(OUT)/webhook -ldflags '-w -extldflags "-static"' .

.PHONY: lint
lint:
	helm lint $(HELM_FOLDER)

.PHONY: chart
chart: lint
	helm package $(HELM_FOLDER) -d $(OUT)

.PHONY: rendered-manifest.yaml
rendered-manifest.yaml: $(OUT)/rendered-manifest.yaml

$(OUT)/rendered-manifest.yaml: $(HELM_FILES) | $(OUT)
	helm template \
	    --name $(CHART_NAME) \
            --set image.repository=$(IMAGE_NAME) \
            --set image.tag=$(IMAGE_TAG) \
            $(HELM_FOLDER) > $@

## Location to install dependencies to
LOCALBIN ?= $(shell pwd)/bin
$(LOCALBIN):
	mkdir -p "$(LOCALBIN)"

## Tool Binaries

ENVTEST ?= $(LOCALBIN)/setup-envtest

#ENVTEST_VERSION is the version of controller-runtime release branch to fetch the envtest setup script (i.e. release-0.20)
ENVTEST_VERSION ?= $(shell v='$(call gomodver,sigs.k8s.io/controller-runtime)'; \
  [ -n "$$v" ] || { echo "Set ENVTEST_VERSION manually (controller-runtime replace has no tag)" >&2; exit 1; }; \
  printf '%s\n' "$$v" | sed -E 's/^v?([0-9]+)\.([0-9]+).*/release-\1.\2/')

#ENVTEST_K8S_VERSION is the version of Kubernetes to use for setting up ENVTEST binaries (i.e. 1.31)
ENVTEST_K8S_VERSION ?= $(shell v='$(call gomodver,k8s.io/api)'; \
  [ -n "$$v" ] || { echo "Set ENVTEST_K8S_VERSION manually (k8s.io/api replace has no tag)" >&2; exit 1; }; \
  printf '%s\n' "$$v" | sed -E 's/^v?[0-9]+\.([0-9]+).*/1.\1/')

.PHONY: setup-envtest
setup-envtest: envtest ## Download the binaries required for ENVTEST in the local bin directory.
	@echo "Setting up envtest binaries for Kubernetes version $(ENVTEST_K8S_VERSION)..."
	@"$(ENVTEST)" use $(ENVTEST_K8S_VERSION) --bin-dir "$(LOCALBIN)" -p path || { \
		echo "Error: Failed to set up envtest binaries for version $(ENVTEST_K8S_VERSION)."; \
		exit 1; \
	}

.PHONY: envtest
envtest: $(ENVTEST) ## Download setup-envtest locally if necessary.
$(ENVTEST): $(LOCALBIN)
	$(call go-install-tool,$(ENVTEST),sigs.k8s.io/controller-runtime/tools/setup-envtest,$(ENVTEST_VERSION))

# go-install-tool will 'go install' any package with custom target and name of binary, if it doesn't exist
# $1 - target path with name of binary
# $2 - package url which can be installed
# $3 - specific version of package
define go-install-tool
@[ -f "$(1)-$(3)" ] && [ "$$(readlink -- "$(1)" 2>/dev/null)" = "$(1)-$(3)" ] || { \
set -e; \
package=$(2)@$(3) ;\
echo "Downloading $${package}" ;\
rm -f "$(1)" ;\
GOBIN="$(LOCALBIN)" go install $${package} ;\
mv "$(LOCALBIN)/$$(basename "$(1)")" "$(1)-$(3)" ;\
} ;\
ln -sf "$$(realpath "$(1)-$(3)")" "$(1)"
endef

define gomodver
$(shell go list -m -f '{{if .Replace}}{{.Replace.Version}}{{else}}{{.Version}}{{end}}' $(1) 2>/dev/null)
endef

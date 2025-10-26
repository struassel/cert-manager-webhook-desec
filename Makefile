GO ?= $(shell which go)
OS ?= $(shell $(GO) env GOOS)
ARCH ?= $(shell $(GO) env GOARCH)
OUT ?= $(shell pwd)/_out
TEST ?= $(shell pwd)/_test
KUBEBUILDER_VERSION ?= 1.28.0

IMAGE_NAME := "ghcr.io/struassel/desec-webhook"
IMAGE_TAG := "latest"
CHART_NAME := "cert-manager-webhook-desec"

HELM_FOLDER := "deploy/desec-webhook"
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

test: $(TEST)/kubebuilder-$(KUBEBUILDER_VERSION)-$(OS)-$(ARCH)/etcd $(TEST)/kubebuilder-$(KUBEBUILDER_VERSION)-$(OS)-$(ARCH)/kube-apiserver $(TEST)/kubebuilder-$(KUBEBUILDER_VERSION)-$(OS)-$(ARCH)/kubectl
	TEST_ASSET_ETCD=$(TEST)/kubebuilder-$(KUBEBUILDER_VERSION)-$(OS)-$(ARCH)/etcd \
	TEST_ASSET_KUBE_APISERVER=$(TEST)/kubebuilder-$(KUBEBUILDER_VERSION)-$(OS)-$(ARCH)/kube-apiserver \
	TEST_ASSET_KUBECTL=$(TEST)/kubebuilder-$(KUBEBUILDER_VERSION)-$(OS)-$(ARCH)/kubectl \
	$(GO) test -v .

$(TEST)/kubebuilder-$(KUBEBUILDER_VERSION)-$(OS)-$(ARCH).tar.gz: | $(TEST)
	curl -fsSL https://go.kubebuilder.io/test-tools/$(KUBEBUILDER_VERSION)/$(OS)/$(ARCH) -o $@

$(TEST)/kubebuilder-$(KUBEBUILDER_VERSION)-$(OS)-$(ARCH)/etcd $(TEST)/kubebuilder-$(KUBEBUILDER_VERSION)-$(OS)-$(ARCH)/kube-apiserver $(TEST)/kubebuilder-$(KUBEBUILDER_VERSION)-$(OS)-$(ARCH)/kubectl: $(TEST)/kubebuilder-$(KUBEBUILDER_VERSION)-$(OS)-$(ARCH).tar.gz | $(TEST)/kubebuilder-$(KUBEBUILDER_VERSION)-$(OS)-$(ARCH)
	tar xfO $< kubebuilder/bin/$(notdir $@) > $@ && chmod +x $@

.PHONY: clean
clean:
	rm -rf $(TEST) $(OUT)

.PHONY: image
image:
	$(DOCKER) build --arch $(ARCH) -t "$(IMAGE_NAME):$(IMAGE_TAG)" .

.PHONY: build
build: $(OUT)/webhook

$(OUT)/webhook: $(OUT)
	CGO_ENABLED=0 go build -v -o $(OUT)/webhook -ldflags '-w -extldflags "-static"' .

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

$(TEST) $(OUT) $(TEST)/kubebuilder-$(KUBEBUILDER_VERSION)-$(OS)-$(ARCH):
	mkdir -p $@
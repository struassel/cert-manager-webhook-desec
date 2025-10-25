GO ?= $(shell which go)
OS ?= $(shell $(GO) env GOOS)
ARCH ?= $(shell $(GO) env GOARCH)
OUT ?= $(shell pwd)/_out
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

test: _test/kubebuilder-$(KUBEBUILDER_VERSION)-$(OS)-$(ARCH)/etcd _test/kubebuilder-$(KUBEBUILDER_VERSION)-$(OS)-$(ARCH)/kube-apiserver _test/kubebuilder-$(KUBEBUILDER_VERSION)-$(OS)-$(ARCH)/kubectl
	TEST_ASSET_ETCD=_test/kubebuilder-$(KUBEBUILDER_VERSION)-$(OS)-$(ARCH)/etcd \
	TEST_ASSET_KUBE_APISERVER=_test/kubebuilder-$(KUBEBUILDER_VERSION)-$(OS)-$(ARCH)/kube-apiserver \
	TEST_ASSET_KUBECTL=_test/kubebuilder-$(KUBEBUILDER_VERSION)-$(OS)-$(ARCH)/kubectl \
	$(GO) test -v .

_test/kubebuilder-$(KUBEBUILDER_VERSION)-$(OS)-$(ARCH).tar.gz: | _test
	curl -fsSL https://go.kubebuilder.io/test-tools/$(KUBEBUILDER_VERSION)/$(OS)/$(ARCH) -o $@

_test/kubebuilder-$(KUBEBUILDER_VERSION)-$(OS)-$(ARCH)/etcd _test/kubebuilder-$(KUBEBUILDER_VERSION)-$(OS)-$(ARCH)/kube-apiserver _test/kubebuilder-$(KUBEBUILDER_VERSION)-$(OS)-$(ARCH)/kubectl: _test/kubebuilder-$(KUBEBUILDER_VERSION)-$(OS)-$(ARCH).tar.gz | _test/kubebuilder-$(KUBEBUILDER_VERSION)-$(OS)-$(ARCH)
	tar xfO $< kubebuilder/bin/$(notdir $@) > $@ && chmod +x $@

.PHONY: clean
clean:
	rm -r _test $(OUT)

.PHONY: build
build:
	$(DOCKER) build --arch $(ARCH) -t "$(IMAGE_NAME):$(IMAGE_TAG)" .

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

_test $(OUT) _test/kubebuilder-$(KUBEBUILDER_VERSION)-$(OS)-$(ARCH):
	mkdir -p $@

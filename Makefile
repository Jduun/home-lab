.PHONY: up scan-image-vuln down health install-k3d cluster deploy

PORT ?= 18080
CLUSTER_NAME ?= home-lab
CONTEXT := k3d-$(CLUSTER_NAME)

install-k3d:
	@if ! command -v k3d >/dev/null 2>&1; then \
		bash -o pipefail -c 'curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash'; \
	fi

cluster:
	@clusters=$$(k3d cluster list --no-headers) && \
	if printf '%s\n' "$$clusters" | awk -v name="$(CLUSTER_NAME)" '$$1 == (name "") { found = 1 } END { exit !found }'; then \
		k3d cluster start "$(CLUSTER_NAME)" && \
		k3d kubeconfig merge "$(CLUSTER_NAME)" --kubeconfig-merge-default --kubeconfig-switch-context; \
	else \
		k3d cluster create "$(CLUSTER_NAME)"; \
	fi

scan-image-vuln:
	image=$$(awk '$$1 == "image:" { print $$2 }' manifests/01-deployment.yaml) && \
		docker run --rm docker.io/aquasec/trivy:0.76.2 \
			image --image-src remote --scanners vuln --exit-code 1 "$$image"

deploy:
	kubectl --context="$(CONTEXT)" apply -f manifests/
	kubectl --context="$(CONTEXT)" -n nginx rollout status deployment/nginx --timeout=120s
	kubectl --context="$(CONTEXT)" -n nginx port-forward service/nginx "$(PORT):80"

up: install-k3d
	$(MAKE) cluster
	$(MAKE) scan-image-vuln
	$(MAKE) deploy

health:
	@if curl --fail --silent --head --max-time 3 http://127.0.0.1:$(PORT)/ >/dev/null; then \
		printf '%s\n' 'healthy'; \
	else \
		printf '%s\n' 'unhealthy'; \
		exit 1; \
	fi

down:
	kubectl --context="$(CONTEXT)" delete -f manifests/ --ignore-not-found

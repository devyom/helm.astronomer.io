# Public repository for charts.
DOMAIN ?= helm.astronomer.io
URL ?= https://${DOMAIN}
BUCKET ?= gs://${DOMAIN}

# List of charts to build
CHARTS := airflow astronomer nginx grafana prometheus alertmanager elasticsearch kibana fluentd kube-state

# Output directory
OUTPUT := repository

# Temp directory
TEMP := /tmp/${DOMAIN}

.PHONY: lint
.ONESHELL:
lint:
	set -xe
	rm -rf ${TEMP}/astronomer-platform || true
	mkdir -p ${TEMP}
	cp -R ../helm.astronomer.io ${TEMP}/astronomer-platform
	mv ${TEMP}/astronomer-platform/charts/airflow ${TEMP}/airflow
	helm lint ${TEMP}/astronomer-platform
	# Airflow chart is linted separately
	mv ${TEMP}/airflow ${TEMP}/astronomer-platform/charts/airflow
	helm lint ${TEMP}/astronomer-platform/charts/airflow
	# Lint the Prometheus alerts configuration
	helm template -x ${TEMP}/astronomer-platform/charts/prometheus/templates/prometheus-alerts-configmap.yaml ${TEMP}/astronomer-platform > ${TEMP}/prometheus_alerts.yaml
	# Parse the alerts.yaml data from the config map resource
	python3 -c "import yaml; from pathlib import Path; alerts = yaml.safe_load(Path('${TEMP}/prometheus_alerts.yaml').read_text())['data']['alerts.yaml']; Path('${TEMP}/prometheus_alerts.yaml').write_text(alerts)"
	promtool check rules  ${TEMP}/prometheus_alerts.yaml
	rm -rf ${TEMP}/astronomer-platform
	rm ${TEMP}/prometheus_alerts.yaml

.PHONY: build
build: update-version
	mkdir -p ${OUTPUT}
	for chart in ${CHARTS} ; do \
		helm package --version ${ASTRONOMER_VERSION} -d ${OUTPUT} charts/$${chart} || exit 1; \
	done; \
	$(MAKE) build-index

.PHONY: build-index
build-index:
	wget ${DOMAIN}/index.yaml -O ${TEMP}
	helm repo index ${OUTPUT} --url ${URL} --merge ${TEMP}

.PHONY: push
push: build
	@read -p "Are you sure you want to push a production release? Ctrl+c to abort." ans;
	$(MAKE) push-repo

.PHONY: push-repo
push-repo:
	for chart in ${CHARTS} ; do \
		gsutil cp -a public-read ${OUTPUT}/$${chart}-${ASTRONOMER_VERSION}.tgz ${BUCKET} || exit 1; \
	done; \
	$(MAKE) push-index

.PHONY: push-index
push-index: build-index
	gsutil cp -a public-read ${OUTPUT}/index.yaml ${BUCKET}

.PHONY: clean
clean:
	for chart in ${CHARTS} ; do \
		rm ${OUTPUT}/$${chart}-${ASTRONOMER_VERSION}.tgz || exit 1; \
	done; \

.PHONY: update-image-tags
update-image-tags: check-env
	find charts -name 'values.yaml' -exec sed -i -E 's/tag: (0|[1-9][[:digit:]]*)\.(0|[1-9][[:digit:]]*)\.(0|[1-9][[:digit:]]*)(-(0|[1-9][[:digit:]]*|[[:digit:]]*[a-zA-Z-][0-9a-zA-Z-]*)(\.(0|[1-9][[:digit:]]*|[[:digit:]]*[a-zA-Z-][0-9a-zA-Z-]*))*)?(\+[0-9a-zA-Z-]+(\.[0-9a-zA-Z-]+)*)?/tag: ${ASTRONOMER_VERSION}/g' {} \;

.PHONY: update-chart-versions
update-chart-versions: check-env
	find . -name Chart.yaml -exec sed -i -E 's/(0|[1-9][[:digit:]]*)\.(0|[1-9][[:digit:]]*)\.(0|[1-9][[:digit:]]*)(-(0|[1-9][[:digit:]]*|[[:digit:]]*[a-zA-Z-][0-9a-zA-Z-]*)(\.(0|[1-9][[:digit:]]*|[[:digit:]]*[a-zA-Z-][0-9a-zA-Z-]*))*)?(\+[0-9a-zA-Z-]+(\.[0-9a-zA-Z-]+)*)?/${ASTRONOMER_VERSION}/g' {} \;

.PHONY: update-version
update-version: check-env update-image-tags update-chart-versions

.PHONY: check-env
check-env:
ifndef ASTRONOMER_VERSION
	$(error ASTRONOMER_VERSION is not set)
endif

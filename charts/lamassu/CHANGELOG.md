
<a name="lamassu-3.8.1"></a>
## [lamassu-3.8.1](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-3.8.0...lamassu-3.8.1) (2026-09-21)



### Chores


* Release chart lamassu 3.8.1


<a name="lamassu-3.8.0"></a>
## [lamassu-3.8.0](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-3.7.0...lamassu-3.8.0) (2026-06-12)



### Features


* Add CA-to-KMS key migration pre-upgrade hook ([#72](https://github.com/lamassuiot/lamassu-helm/issues/72))



### Bug Fixes


* Upgrades TLS maxVersion to 1.3 for enhanced security



### Other


* Merge pull request #75 from lamassuiot/task/74-upgrade-third-party-imgs

fix: upgrade fast-lane third-party images (PostgreSQL, RabbitMQ, Keycloak)

* Update Chart.yaml, values.yaml CHANGELOG and RELEASE-NOTES for chart lamassu 3.8.0

* Update Chart.yaml, values.yaml CHANGELOG and RELEASE-NOTES for chart lamassu 3.8.0


<a name="lamassu-3.7.0"></a>
## [lamassu-3.7.0](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-3.6.1...lamassu-3.7.0) (2026-02-04)



### Other


* Add new kms as firstclass svc ([#66](https://github.com/lamassuiot/lamassu-helm/issues/66))

* Update Chart.yaml, values.yaml CHANGELOG and RELEASE-NOTES for chart lamassu 3.7.0

* Update Chart.yaml, values.yaml CHANGELOG and RELEASE-NOTES for chart lamassu 3.7.0

* Fix/release420 ([#69](https://github.com/lamassuiot/lamassu-helm/issues/69))

* fix: update migration image reference and job hook annotations


* fix: remove special characters from generated passwords in lamassu-fast-lane.sh


* fix: add missing namespace field to migration job template


* Apply suggestion from @Copilot

Co-authored-by: Copilot <175728472+Copilot@users.noreply.github.com>

---------

Co-authored-by: Copilot <175728472+Copilot@users.noreply.github.com>

* Update Chart.yaml, values.yaml CHANGELOG and RELEASE-NOTES for chart lamassu 3.7.0


<a name="lamassu-3.6.1"></a>
## [lamassu-3.6.1](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-3.6.0...lamassu-3.6.1) (2025-10-13)



### Bug Fixes


* Enhance pre-upgrade migration logic to support multiple databases (va, kms) ([#64](https://github.com/lamassuiot/lamassu-helm/issues/64))



### Other


* Update Chart.yaml, values.yaml CHANGELOG and RELEASE-NOTES for chart lamassu 3.6.1

* Uncomment database creation command in migration script

* Specify database for CREATE DATABASE command


<a name="lamassu-3.6.0"></a>
## [lamassu-3.6.0](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-3.5.2...lamassu-3.6.0) (2025-10-09)



### Bug Fixes


* Fix tmp dir ([#63](https://github.com/lamassuiot/lamassu-helm/issues/63))





### Other


* Update Chart.yaml, values.yaml CHANGELOG and RELEASE-NOTES for chart lamassu 3.6.0


<a name="lamassu-3.5.2"></a>
## [lamassu-3.5.2](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-3.5.1...lamassu-3.5.2) (2025-09-26)



### Other


* Add dlq to templates ([#61](https://github.com/lamassuiot/lamassu-helm/issues/61))



* Update Chart.yaml, values.yaml CHANGELOG and RELEASE-NOTES for chart lamassu 3.5.2


<a name="lamassu-3.5.1"></a>
## [lamassu-3.5.1](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-3.5.0...lamassu-3.5.1) (2025-09-24)



### Other


* Update Chart.yaml, values.yaml CHANGELOG and RELEASE-NOTES for chart lamassu 3.5.1


<a name="lamassu-3.5.0"></a>
## [lamassu-3.5.0](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-3.4.0...lamassu-3.5.0) (2025-09-24)



### Features


* Update to 3.5.0 backend and 4.0.2 UI ([#60](https://github.com/lamassuiot/lamassu-helm/issues/60))



### Other


* Update Chart.yaml, values.yaml CHANGELOG and RELEASE-NOTES for chart lamassu 3.5.0


<a name="lamassu-3.4.0"></a>
## [lamassu-3.4.0](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-3.3.1...lamassu-3.4.0) (2025-06-04)



### Features


* Simplify jwks uri definition ([#54](https://github.com/lamassuiot/lamassu-helm/issues/54))

* Disable key migration ([#59](https://github.com/lamassuiot/lamassu-helm/issues/59))



### Bug Fixes


* Rename crypto_monitoring attribute to certificate_monitoring_job to match backend expected config ([#57](https://github.com/lamassuiot/lamassu-helm/issues/57))



### Other


* Improve documentation for upgrading from 3.0.0 to 3.2.0 ([#55](https://github.com/lamassuiot/lamassu-helm/issues/55))

* Update Chart.yaml, values.yaml CHANGELOG and RELEASE-NOTES for chart lamassu 3.4.0


<a name="lamassu-3.3.1"></a>
## [lamassu-3.3.1](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-3.3.0...lamassu-3.3.1) (2025-03-25)



### Features


* Add VA configuration and persistent volume ([#47](https://github.com/lamassuiot/lamassu-helm/issues/47))

* Support multiple oidc providers ([#48](https://github.com/lamassuiot/lamassu-helm/issues/48))



### Bug Fixes


* Db va creation using helm job ([#51](https://github.com/lamassuiot/lamassu-helm/issues/51))



### Other


* Update Chart.yaml, values.yaml CHANGELOG and RELEASE-NOTES for chart lamassu 3.3.1


<a name="lamassu-3.3.0"></a>
## [lamassu-3.3.0](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-3.2.1...lamassu-3.3.0) (2025-03-19)



### Features


* Ingress to envoy gateway ([#46](https://github.com/lamassuiot/lamassu-helm/issues/46))



### Other


* Update Chart.yaml, values.yaml CHANGELOG and RELEASE-NOTES for chart lamassu 3.3.0


<a name="lamassu-3.2.1"></a>
## [lamassu-3.2.1](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-3.2.0...lamassu-3.2.1) (2025-01-29)



### Other


* Document 3.0 -> 3.1 migration ([#43](https://github.com/lamassuiot/lamassu-helm/issues/43))

* Improve 3.2.0 version with automatic db migration schema init by helm ([#44](https://github.com/lamassuiot/lamassu-helm/issues/44))



* Update Chart.yaml, values.yaml CHANGELOG and RELEASE-NOTES for chart lamassu 3.2.1


<a name="lamassu-3.2.0"></a>
## [lamassu-3.2.0](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-3.1.1...lamassu-3.2.0) (2025-01-27)



### Other


* Update config maps from core services to new format for 3.X lamassu versions ([#42](https://github.com/lamassuiot/lamassu-helm/issues/42))

Co-authored-by: Juan Jose Rodriguez <jjrodriguez@lksnext.com>

* Update Chart.yaml, values.yaml CHANGELOG and RELEASE-NOTES for chart lamassu 3.2.0


<a name="lamassu-3.1.1"></a>
## [lamassu-3.1.1](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-3.1.0...lamassu-3.1.1) (2024-12-19)



### Other


* Update Chart.yaml, values.yaml CHANGELOG and RELEASE-NOTES for chart lamassu 3.1.1


<a name="lamassu-3.1.0"></a>
## [lamassu-3.1.0](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-3.0.0...lamassu-3.1.0) (2024-10-25)



### Other


* Add new ENV vars for UI 3.1 ([#39](https://github.com/lamassuiot/lamassu-helm/issues/39))



* Update Chart.yaml, values.yaml CHANGELOG and RELEASE-NOTES for chart lamassu 3.1.0


<a name="lamassu-3.0.0"></a>
## [lamassu-3.0.0](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-2.6.3...lamassu-3.0.0) (2024-10-02)



### Bug Fixes


* Fix ci release





### Other


* Update Chart.yaml, values.yaml CHANGELOG and RELEASE-NOTES for chart lamassu 2.6.3

* Update Chart.yaml, values.yaml CHANGELOG and RELEASE-NOTES for chart lamassu 2.7.0

* Deocupling Keycloak from Lamassu's chart. Adding it as an external chart ([#30](https://github.com/lamassuiot/lamassu-helm/issues/30))

* Update Chart.yaml, values.yaml CHANGELOG and RELEASE-NOTES for chart lamassu 3.0.0

* Update Chart.yaml, values.yaml CHANGELOG and RELEASE-NOTES for chart lamassu 3.0.0


<a name="lamassu-2.6.3"></a>
## [lamassu-2.6.3](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-2.6.2...lamassu-2.6.3) (2024-08-29)



### Other


* Bumping image version



* Honor certificate duration for CertManager-controled RootCA  ([#31](https://github.com/lamassuiot/lamassu-helm/issues/31))

* Update Chart.yaml, CHANGELOG and RELEASE-NOTES for chart lamassu 2.6.3

* Update Chart.yaml, CHANGELOG and RELEASE-NOTES for chart lamassu 2.6.3

* Update Chart.yaml, values.yaml CHANGELOG and RELEASE-NOTES for chart lamassu 2.6.3

* Update Chart.yaml, values.yaml CHANGELOG and RELEASE-NOTES for chart lamassu 2.6.3

* Fix release process ([#36](https://github.com/lamassuiot/lamassu-helm/issues/36))


<a name="lamassu-2.6.2"></a>
## [lamassu-2.6.2](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-2.6.1...lamassu-2.6.2) (2024-07-16)



### Other


* Bumping image version




<a name="lamassu-2.6.1"></a>
## [lamassu-2.6.1](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-2.6.0...lamassu-2.6.1) (2024-06-27)



### Other


* Full chain in TLS handshake + add root to DMS CACerts ([#28](https://github.com/lamassuiot/lamassu-helm/issues/28))

* adding root ca extraction


* modifying base image for init container


* fixing tls script


* using toolbox with openssl


* fixing root cert extractor


* fixing api gw init tls


* fixing hcheck for keycloak


* fixing config ref


* using shared dir for init-container and main container resource sharing


* adding missing shared dir


* adding missing shared dir


* adding missing shared dir


* bumping chart version


* fix policy engine to allow new root well-known EST


* rm path_prefix_rewrite for toplevel well-known est to DMS


---------




<a name="lamassu-2.6.0"></a>
## [lamassu-2.6.0](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-2.5.3...lamassu-2.6.0) (2024-06-21)



### Bug Fixes


* Fixing certManager options



* Fixing linting errs



* Fixing services



* Fixing AWS creds and bumping images

* Fixing livnessprobe





### Other


* Adding support for external tls certs to fastlane + fix helmchart



* Merge pull request #25 from lamassuiot/feat/tls-external

Improve TLS support

* Adding templates



* Removing virtual services



* Removing simtools from envoy



* Bumping chart version



* Merge pull request #27 from lamassuiot/feat/tls-external

Fixing TLS  options + Livness probe + AWS Connector credentials fix


<a name="lamassu-2.5.3"></a>
## [lamassu-2.5.3](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-2.5.2...lamassu-2.5.3) (2024-05-10)



### Other


* Allow controlling pull policy in values



* Adding more flexibility to helm chart



* Adding configurable imagePullPolicy



* New event bus pub/sub config name in services yaml files



* Adding non-standard port installation



* Bump chart version



* Removing trailing spaces



* Merge pull request #22 from lamassuiot/feature/custom-apigw-service-type

New API Gateway deployment mode using NodePorts + Bump to lamassuiot 2.5.1


<a name="lamassu-2.5.2"></a>
## [lamassu-2.5.2](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-2.5.1...lamassu-2.5.2) (2024-03-25)



### Chores


* Add workflow for chart testing



### Other


* Fix chart linter issues



* Merge pull request #15 from lamassuiot/wf-test

Enable CI workflow for chart testing on PR

* Adding first helm chart test



* Adding ui and gw checks



* Bumping UI docker image version




<a name="lamassu-2.5.1"></a>
## [lamassu-2.5.1](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-2.5.0...lamassu-2.5.1) (2024-02-22)



### Other


* Bumping to 2.5 version




<a name="lamassu-2.5.0"></a>
## [lamassu-2.5.0](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-2.4.7...lamassu-2.5.0) (2024-02-16)



### Other


* Bumping to 2.5 version which allows dynamic UI config




<a name="lamassu-2.4.7"></a>
## [lamassu-2.4.7](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-2.4.6...lamassu-2.4.7) (2024-02-13)



### Other


* Bumping chart version to 2.4.6




<a name="lamassu-2.4.6"></a>
## [lamassu-2.4.6](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-2.4.5...lamassu-2.4.6) (2024-02-10)



### Other


* Bumping images tags to v2.4.5



* Merge branch 'main' of https://github.com/lamassuiot/lamassu-helm

* Bumping chart version




<a name="lamassu-2.4.5"></a>
## [lamassu-2.4.5](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-2.4.4...lamassu-2.4.5) (2024-02-09)



### Other


* Enable aws-connector only when awsConnector.enabled is true



* Bump chart version to 2.4.5




<a name="lamassu-2.4.4"></a>
## [lamassu-2.4.4](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-2.4.3...lamassu-2.4.4) (2024-02-05)



### Other


* Bumping images tags to v2.4.4




<a name="lamassu-2.4.3"></a>
## [lamassu-2.4.3](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-2.4.2...lamassu-2.4.3) (2024-01-31)



### Other


* Bumping to v2.4.3



* Mend


<a name="lamassu-2.4.2"></a>
## [lamassu-2.4.2](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-2.4.1...lamassu-2.4.2) (2024-01-30)



### Bug Fixes


* Fixing new event_bus config + updating to v2.4.2 services





### Other


* Merge branch 'main' of https://github.com/lamassuiot/lamassu-helm


<a name="lamassu-2.4.1"></a>
## [lamassu-2.4.1](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-2.3.6...lamassu-2.4.1) (2023-12-16)



### Other


* Starting 2.4.0 refactor

* Addjusring chart for 2.4.0 release



* Update Lamassu Chart.yaml


<a name="lamassu-2.3.6"></a>
## [lamassu-2.3.6](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-2.3.5...lamassu-2.3.6) (2023-10-31)



### Other


* Bumping CA image tag


<a name="lamassu-2.3.5"></a>
## [lamassu-2.3.5](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-2.3.4...lamassu-2.3.5) (2023-10-26)



### Bug Fixes


* Fixed CA image from values.yaml


<a name="lamassu-2.3.4"></a>
## [lamassu-2.3.4](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-2.3.3...lamassu-2.3.4) (2023-10-25)



### Bug Fixes


* Fixed CA image from values.yaml


<a name="lamassu-2.3.3"></a>
## [lamassu-2.3.3](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-2.3.2...lamassu-2.3.3) (2023-10-23)



### Other


* Adding jitp customization


<a name="lamassu-2.3.2"></a>
## [lamassu-2.3.2](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-2.3.1...lamassu-2.3.2) (2023-10-23)



### Other


* Adding 2.3.1 release


<a name="lamassu-2.3.1"></a>
## [lamassu-2.3.1](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-2.2.0...lamassu-2.3.1) (2023-10-04)



### Bug Fixes


* Fix ca http protocol



### Other


* Release 2.3.0

* Fiex installation instructions


<a name="lamassu-2.2.0"></a>
## [lamassu-2.2.0](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-0.1.5...lamassu-2.2.0) (2023-07-27)



### Other


* Bumping to 2.2


<a name="lamassu-0.1.5"></a>
## [lamassu-0.1.5](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-0.1.4...lamassu-0.1.5) (2023-07-17)



### Other


* Adding ingress annotations + default ingress

* Bumping helm version


<a name="lamassu-0.1.4"></a>
## [lamassu-0.1.4](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-0.1.3...lamassu-0.1.4) (2023-07-13)



### Other


* Adding ingress annotations


<a name="lamassu-0.1.3"></a>
## [lamassu-0.1.3](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-0.1.2...lamassu-0.1.3) (2023-07-11)



### Other


* Adding ingress class annotation


<a name="lamassu-0.1.2"></a>
## [lamassu-0.1.2](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-0.1.1...lamassu-0.1.2) (2023-07-10)



### Other


* Updating aws connector docker image repo


<a name="lamassu-0.1.1"></a>
## [lamassu-0.1.1](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-0.1.0...lamassu-0.1.1) (2023-07-10)



### Bug Fixes


* Fix helm syntax


<a name="lamassu-0.1.0"></a>
## [lamassu-0.1.0](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-0.0.8...lamassu-0.1.0) (2023-07-10)



### Other


* Bumping docker image versions to 2.1.0


<a name="lamassu-0.0.8"></a>
## [lamassu-0.0.8](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-0.0.7...lamassu-0.0.8) (2023-07-07)



### Bug Fixes


* Fix dmsmanager tls


<a name="lamassu-0.0.7"></a>
## [lamassu-0.0.7](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-0.0.6...lamassu-0.0.7) (2023-07-07)



### Bug Fixes


* Fix dmsmanager tls


<a name="lamassu-0.0.6"></a>
## [lamassu-0.0.6](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-0.0.5...lamassu-0.0.6) (2023-07-07)



### Bug Fixes


* Fix dmsmanager tls


<a name="lamassu-0.0.5"></a>
## [lamassu-0.0.5](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-0.0.4...lamassu-0.0.5) (2023-07-07)



### Bug Fixes


* Fixing chart tls


<a name="lamassu-0.0.4"></a>
## [lamassu-0.0.4](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-0.0.3...lamassu-0.0.4) (2023-07-07)



### Other


* Resolving merge with main

* Merge pull request #7 from lamassuiot/improve-helm-chart

Improve helm chart

* Bumping chart release version

* Merge pull request #8 from lamassuiot/improve-helm-chart

bumping chart release version


<a name="lamassu-0.0.3"></a>
## [lamassu-0.0.3](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-0.0.2...lamassu-0.0.3) (2023-07-05)



### Bug Fixes


* Fixing aws connector and gateway env vars





### Other


* Decoupling postgres


<a name="lamassu-0.0.2"></a>
## [lamassu-0.0.2](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-0.0.1...lamassu-0.0.2) (2023-06-29)



### Bug Fixes


* Fix jaeger path

* Removed jaeger pvc path

* Fix ui template 'Values' ref

* Fix questions - values refs

* Helm value key in db deployment

* Fix vault cert + added jaeger

* Fix helm value key in jaeger deployment

* Fixing chart version



### Tests


* Testing gh action



* Testing auto release



### Other


* V1

* Added k8s resources

* Added k8s resources

* Added official vault and consul charts as subcharts

* Added missing subcharts deps with 'helm dependency build'

* Added vault init job

* Updated vualt init job to attend dynamic release name

* Updated vualt init job generated k8s secret

* Updated vualt init job generated k8s secret

* Updated vualt init job generated k8s secret

* Updated vualt init job generated k8s secret

* Added api-gw, auth and db

* Updating certificate generation mechanism

* Updating missing secretName in CertManger Certificate

* Adding jaeger

* Pre-release 1.0

* Simulation tools + alerts

* Removing rancher support

* Updating charts lock



* Removing lock to fix gh-action





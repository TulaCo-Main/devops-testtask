# Solution

MFA role access and EKS/CoreDNS availability were confirmed in `eu-central-1`. Public endpoint validation remains pending.

By request, Gateway + HTTPRoute replaces the assessment's Ingress requirement. [Ingress is frozen but remains supported](https://kubernetes.io/docs/concepts/services-networking/ingress/); the retired project is [ingress-nginx](https://kubernetes.io/blog/2026/04/22/kubernetes-v1-36-release/), which this repository did not use.

## Run

Tools: Terraform **>= 1.10**, Helm **3.x**, kubectl **1.36.x**, AWS CLI **v2**, Docker with Compose **v2**. Run from the repo root on Linux/WSL with the `CandidateDevOpsTest` role assumed.

Before `terraform init`, create the S3 bucket `devops-test-tfstate-056300054271-eu-central-1` in `eu-central-1` for Terraform state. Its name is already set in `terraform/backend.tf`.

For the first deployment, run these in order. Set your public egress IP as a `/32` in `terraform.tfvars`.

```bash
cp -n terraform/terraform.tfvars.example terraform/terraform.tfvars
vi terraform/terraform.tfvars

terraform -chdir=terraform init
terraform -chdir=terraform apply

bash build.sh
bash install.sh

terraform -chdir=terraform apply

curl -i https://nodeapp.tulaco.click/
curl -i https://nodeapp.tulaco.click/health
```

`build.sh` pushes the image to ECR; `install.sh` installs the controller and application. The second apply creates the DNS alias after the ALB exists. Both URLs should return 200 once DNS propagates.

Run the scripts as your normal user; `build.sh` uses `sudo` for Docker.

## Changes

- The loopback-only listener was unreachable through the Pod IP. It now defaults to all interfaces.
- Every `/` request retained a 32 MiB buffer in an unbounded array. Removed this unused collector to prevent memory exhaustion.
- Signal handlers exited immediately. Shutdown now stops accepting connections, drains active requests and has a bounded deadline aligned with Kubernetes termination settings.
- Dependencies are installed with `npm ci` on Node 24; the runtime uses distroless Node 24 as non-root on `linux/amd64`. Explicit `COPY` permissions fix the startup failure after rsync. The image tag is `v2`; `preStop` uses Kubernetes' sleep hook because the image has no shell.
- The workload profile selected `default`, while the application used `nodeapp`; the system profile selected only CoreDNS, leaving the load balancer controller unscheduled. Profiles now cover the intended Pods in private subnets.
- Removed duplicate `public-data` subnets. Their NAT routes already made them private despite their names; profiles now use the module's private subnets. Public API access requires an operator CIDR allowlist.
- Added public subnet discovery tags, corrected the controller's IRSA service-account subject and selected IP targets for the ALB. The controller retains explicit region and VPC configuration because Fargate has no IMDS.
- Pinned EKS 1.36, EKS module 21.29.0 and AWS provider 6.70.0. CoreDNS uses Fargate; EC2 networking add-ons are excluded from managed configuration. Kubeconfig uses AWS CLI authentication rather than a stored short-lived token.
- Terraform manages AWS resources only. `install.sh` installs the controller with Helm and applies Gateway API and application manifests. `build.sh` builds and pushes the image through Compose.
- Terraform manages the ACM wildcard certificate, DNS validation and ALB alias in the existing `tulaco.click` zone. A second apply after `install.sh` discovers the ALB and creates the alias. The HTTPS listener discovers the certificate by hostname; no Kubernetes certificate secret is needed. HTTP 80 remains enabled for the original ALB URL requirement.
- Two single-replica Deployments select separate single-subnet Fargate profiles, placing one application replica in each AZ. Both use the same Service, resources, probes and controlled rolling updates. `install.sh` creates the Service and TargetGroupBinding before application Pods so ALB readiness gates are injected.
- ECR now enforces immutable tags, retains tagged releases for rollback and refuses forced deletion of a non-empty repository.

## Architecture

**1. Subnets.** Public subnets contain the internet-facing ALB and NAT gateways; private subnets contain Fargate Pods, with outbound access through NAT in the same AZ. This prevents direct internet routing to application Pods while permitting image pulls and AWS API calls. Production would keep this separation, size private ranges for one IP per Pod, and isolate any databases further.

**2. NAT availability.** Each of the two AZs has a NAT gateway in its public subnet. Private subnet routes use the local NAT, so losing one AZ does not remove outbound access from the other. This costs more than a shared NAT but removes the shared egress dependency and avoids cross-AZ NAT traffic.

**3. IAM.** The Fargate execution role serves infrastructure tasks such as image pulls; it does not grant application containers credentials. IRSA gives the controller its own scoped AWS permissions through an annotated service account. Its role must trust the cluster OIDC provider, `sts:AssumeRoleWithWebIdentity`, audience `sts.amazonaws.com` and the exact `system:serviceaccount:kube-system:aws-load-balancer-controller` subject.

**4. Subnet discovery.** The controller uses public subnets tagged `kubernetes.io/role/elb`, choosing eligible subnets across AZs with sufficient free IPs. Discovery failures leave the Gateway without a working ALB; I would inspect Gateway conditions, events, controller logs, tags, routes, IP capacity and IAM denials. Explicit tags avoid relying on version-dependent fallback discovery by route reachability.

**5. Fargate versus nodes.** Fargate removes worker-node maintenance and isolates each Pod, but charges for rounded per-Pod resources and excludes DaemonSets and Arm workloads. Managed node groups offer more scheduling and hardware choices, with node patching and capacity management to own. [AWS recommends separate single-subnet profiles for even placement](https://docs.aws.amazon.com/eks/latest/userguide/fargate-profile.html): Fargate does not apply affinity/anti-affinity or support topology-spread constraints. Each application Deployment selects its profile explicitly. Losing one AZ leaves one replica; the pinned replacement waits for its AZ to recover.

**6. Secrets.** No application secret is needed here. Production could use Secrets Manager through the AWS SDK with a dedicated IRSA role restricted to that secret and KMS key, including caching and rotation. Trust the exact application service account, keep credentials out of images/Git/state/logs, and avoid Secrets Store CSI or EKS Pod Identity, which Fargate does not support.

**7. Upgrades.** Check deprecated APIs and component compatibility in staging, upgrade the control plane one supported minor at a time, then update compatible add-ons and recreate Fargate Pods. For production, add a PDB for voluntary evictions alongside replicas, readiness gates and draining; a PDB is not included here and cannot guarantee zero downtime during failures or forced replacement. Stateful workloads additionally require tested backup restoration, replicated storage and database-specific failover, plus backward-compatible schema migrations before rolling application upgrades.

**8. Observability.** Proposed production coverage is structured application logs without sensitive payloads, Fargate log forwarding, ALB access logs and metrics, control-plane logs, Pod restarts and external checks of both endpoints. A starting availability SLO is 99.9% successful eligible requests over 30 days; page on combined ALB-generated and target 5xx above 1% for five minutes with at least 100 requests, using synthetic checks for low traffic. Add latency/error-budget alerts and a dashboard before production; these integrations and thresholds are proposals, not deployed monitoring or measured results.

## Self-review and remaining work

I would defend the routing, scoped controller identity, reproducible images and bounded shutdown. CoreDNS and controller Pods still share a two-subnet profile, so their AZ spread is not enforced. Operational monitoring is not configured. Next steps are deployment, state handover and verifying failure handling.

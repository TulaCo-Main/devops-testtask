# Deployment

Run from the repository root on Linux or WSL with the assumed `CandidateDevOpsTest` role.
Tools: Terraform >= 1.10, AWS CLI v2, kubectl 1.36, Helm 3 and Docker with Compose.

This checkout targets account `056300054271`, region `eu-central-1`, cluster `devops-test-eks` and hostname `nodeapp.tulaco.click`.

## 1. AWS infrastructure

Create the S3 bucket `devops-test-tfstate-056300054271-eu-central-1` in `eu-central-1` yourself. Its name, region and state key are already in `terraform/backend.tf`. Terraform does not manage this bucket.

Copy the variables file and replace `203.0.113.10/32` with your public egress IP:

```bash
cp -n terraform/terraform.tfvars.example terraform/terraform.tfvars
vi terraform/terraform.tfvars
terraform -chdir=terraform init
terraform -chdir=terraform plan -out=deployment.tfplan
terraform -chdir=terraform apply deployment.tfplan
```

This creates the VPC, Fargate-only EKS cluster, controller IAM role, ECR repository and ACM wildcard certificate. ACM validates `*.tulaco.click` through Route53; Terraform waits for issuance.

Each AZ has its own NAT gateway. The application uses two single-subnet Fargate profiles: `apps-a` and `apps-b`, one per AZ.

The ECR repository is `056300054271.dkr.ecr.eu-central-1.amazonaws.com/devops-test/nodeapp`. The EKS module attaches `AmazonEKSFargatePodExecutionRolePolicy` to each Fargate profile's execution role, including permission to pull images. No image-pull secret is needed. The controller has a separate IRSA role for ALB operations.

## 2. Build and install

```bash
bash build.sh
bash install.sh
```

`build.sh` logs Docker into ECR, then runs `docker compose build` and `docker compose push`. Compose and both Deployments use the `v2` tag. ECR tags are immutable: for a new release, change the tag in `compose.yaml` and in both Deployments in `k8s/deployment.yaml` before building.

`install.sh` configures kubeconfig, adds the EKS Helm repository and runs `helm install` for the controller. It then applies the Gateway, HTTPRoute and application manifests. The controller creates the public ALB from the Gateway and connects it to Pod IPs. The script waits for the target-group binding before creating Pods so their ALB readiness gates are injected.

`nodeapp-a` selects `apps-a`; `nodeapp-b` selects `apps-b`. Each Deployment runs one replica, and the shared Service sends traffic to both. If an AZ is unavailable, its replica stays pending; the other AZ retains its replica.

The install script is for the first installation. After updating the tag for later releases:

```bash
export KUBECONFIG="$PWD/.kubeconfig"
bash build.sh
kubectl apply -f k8s/
kubectl rollout status deployment/nodeapp-a -n nodeapp --timeout=600s
kubectl rollout status deployment/nodeapp-b -n nodeapp --timeout=600s
```

If the old single Deployment was installed, remove it after both new Deployments are ready: `kubectl delete deployment nodeapp -n nodeapp --ignore-not-found`.

For local use:

```bash
docker compose up --build
# http://localhost:3000 and http://localhost:3000/health
```

## 3. DNS

After installation, apply Terraform again to create the `nodeapp.tulaco.click` ALB alias in the existing `tulaco.click` zone:

```bash
terraform -chdir=terraform apply
```

Terraform finds the ALB by its cluster and Gateway tags. On the first apply there is no ALB, so only certificate validation records are created. The existing hosted zone is read as a data source; Terraform manages the certificate and records, not the shared zone itself.

The HTTPS listener discovers the ACM wildcard certificate by hostname. HTTP remains enabled for the assignment's ALB URL requirement. After DNS propagates:

```bash
curl -i https://nodeapp.tulaco.click/
curl -i https://nodeapp.tulaco.click/health
```

Both paths must return 200. Share the hostname, ALB URL, image tag, `terraform output` and read access to the state bucket/key. Update `SOLUTION.md` with the actual deployment result. Leave the cluster running for review.

When eventually removing the deployment, delete the Gateway and wait for ALB deletion before removing the controller or cluster.

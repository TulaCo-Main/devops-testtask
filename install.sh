#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

region=eu-central-1
cluster_name=devops-test-eks
role_arn=arn:aws:iam::056300054271:role/devops-test-eks-alb-controller
export KUBECONFIG="$PWD/.kubeconfig"

aws eks update-kubeconfig --name "$cluster_name" --region "$region"
vpc_id=$(terraform -chdir=terraform output -raw vpc_id)

kubectl apply --server-side -f \
  https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.0/standard-install.yaml

helm repo add eks https://aws.github.io/eks-charts
helm repo update eks
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --version 3.6.1 --namespace kube-system \
  --set clusterName="$cluster_name" \
  --set region="$region" \
  --set vpcId="$vpc_id" \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn=$role_arn" \
  --set featureGates.ALBGatewayAPI=true \
  --set featureGates.NLBGatewayAPI=false \
  --wait --timeout 10m

kubectl apply -f k8s/namespace.yaml -f k8s/service.yaml
kubectl apply -f k8s/gateway.yaml -f k8s/httproute.yaml
# The binding must exist before Pods are created for ALB readiness gate injection.
kubectl wait --for=create targetgroupbindings.elbv2.k8s.aws --all -n nodeapp --timeout=600s
kubectl apply -f k8s/deployment.yaml
kubectl rollout status deployment/nodeapp-a -n nodeapp --timeout=600s
kubectl rollout status deployment/nodeapp-b -n nodeapp --timeout=600s
kubectl get gateway nodeapp -n nodeapp

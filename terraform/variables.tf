variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-central-1"
}

variable "project" {
  description = "Short project identifier, used as a tag and a name prefix."
  type        = string
  default     = "devops-test"
}

variable "environment" {
  description = "Environment label."
  type        = string
  default     = "test"
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
  default     = "devops-test-eks"
}

variable "cluster_version" {
  description = "Kubernetes minor version for the EKS control plane."
  type        = string
  default     = "1.36"
}

variable "coredns_version" {
  description = "Pinned EKS CoreDNS add-on version compatible with cluster_version."
  type        = string
  default     = "v1.14.7-eksbuild.10"
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "Public IPv4 CIDRs allowed to access the Kubernetes API."
  type        = list(string)

  validation {
    condition = length(var.cluster_endpoint_public_access_cidrs) > 0 && alltrue([
      for cidr in var.cluster_endpoint_public_access_cidrs : can(cidrnetmask(cidr)) && !endswith(cidr, "/0")
    ])
    error_message = "Provide at least one valid IPv4 CIDR; unrestricted /0 access is not allowed."
  }
}

variable "vpc_cidr" {
  description = "Primary CIDR block for the VPC."
  type        = string
  default     = "10.40.0.0/16"
}

variable "app_namespace" {
  description = "Kubernetes namespace the Node.js application is deployed into."
  type        = string
  default     = "nodeapp"
}

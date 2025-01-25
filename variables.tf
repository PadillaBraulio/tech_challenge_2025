variable "cluster_version" {
  description = "Kubernetes cluster version."
  type        = string
  default     = "1.31"
}

variable "instance_type" {
  description = "Instance type for the worker nodes."
  type        = string
  default     = "m5.large"
}

variable "karpenter_chart_version" {
  description = "Version of the Karpenter Helm chart."
  type        = string
  default     = "v0.20.0"
}

variable "region" {
  description = "AWS region where the resources will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "node_group_min_size" {
  description = "Minimum size of the node group."
  type        = number
  default     = 1
}

variable "node_group_max_size" {
  description = "Maximum size of the node group."
  type        = number
  default     = 3
}

variable "node_group_desired_size" {
  description = "Desired size of the node group."
  type        = number
  default     = 2
}



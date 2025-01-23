# Karpenter deployment

This challenge was based on the [example](https://github.com/terraform-aws-modules/terraform-aws-eks/tree/master/examples/karpenter) from the [Community module](https://github.com/terraform-aws-modules/terraform-aws-eks) for EKS. 


Configuration in this directory creates an AWS EKS cluster with [Karpenter](https://karpenter.sh/) provisioned for managing compute resource scaling. In the example provided, Karpenter is provisioned on top of an EKS Managed Node Group.

## Prerrequisites
1. **Required Tools:**
   - Terraform (>= 1.3.2)
   - `awscli` (to interact with EKS and update `kubeconfig`)
   -  AWS credentials should be configured locally (e.g., with `aws configure`).
   - `kubectl` (to manage Kubernetes resources)

2. **AWS Permissions:**
   - You need an AWS user or role with sufficient permissions to create and manage the following resources:
     - **EKS Cluster**: 
     - **EC2 Instances**: 
     - **IAM Roles and Policies**:
     - **Elastic Load Balancers**: 
     - **S3 Buckets** 
     - **KMS Keys** 
   - These permissions are typically included in a user with `AdministratorAccess` in AWS. However, for production environments, it is recommended to follow the **principle of least privilege** by tailoring policies to the specific resources being created.


2. **VPC Requirements:**
   - This configuration assumes an **existing VPC**, which is passed via the `terraform.tfvars` file. Ensure that:
     - The VPC includes private subnets properly tagged for Karpenter discovery.
     - The `terraform.tfvars` file contains the necessary VPC and subnet IDs.
   - AWS credentials should be configured locally (e.g., with `aws configure`).

## Usage

To provision the provided configurations you need to execute:

```bash
$ git clone https://github.com/PadillaBraulio/tech_challenge_2025.git
$ cd tech_challenge_2025
$ terraform init
$ terraform plan
$ terraform apply --auto-approve
```

Once the cluster is up and running, you can check that Karpenter is functioning as intended with the following command:

```bash
# First, make sure you have updated your local kubeconfig
aws eks --region us-east-1 update-kubeconfig --name ex-karpenter

# If you want to Karpenter to decide which architecture to use do
cd karpenter_deploy_examples
kubectl apply -f inflate.yaml

# If you want to Karpenter to use amd64 arch do:
cd karpenter_deploy_examples
kubectl apply -f inflateamd64.yaml

# You can watch Karpenter's controller logs with
kubectl logs -f -n kube-system -l app.kubernetes.io/name=karpenter -c controller
```

Validate if the Amazon EKS Addons Pods are running in the Managed Node Group and the `inflate` application Pods are running on Karpenter provisioned Nodes.

```bash
kubectl get nodes -L karpenter.sh/registered
```

```text
NAME                                        STATUS   ROLES    AGE   VERSION               REGISTERED
ip-10-0-13-51.eu-west-1.compute.internal    Ready    <none>   29s   v1.31.1-eks-1b3e656   true
ip-10-0-41-242.eu-west-1.compute.internal   Ready    <none>   35m   v1.31.1-eks-1b3e656
ip-10-0-8-151.eu-west-1.compute.internal    Ready    <none>   35m   v1.31.1-eks-1b3e656
```

### Tear Down & Clean-Up

Because Karpenter manages the state of node resources outside of Terraform, Karpenter created resources will need to be de-provisioned first before removing the remaining resources with Terraform.

1. Remove the example deployment created above and any nodes created by Karpenter

```bash
cd karpenter_deploy_examples
kubectl delete deployment -f inflate.yaml

kubectl delete deployment -f inflate64.yaml
```

2. Remove the resources created by Terraform

```bash
terraform destroy --auto-approve
```

Note that this example may create resources which cost money. Run `terraform destroy` when you don't need these resources.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3.2 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.83 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 2.7 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 5.83 |
| <a name="provider_aws.virginia"></a> [aws.virginia](#provider\_aws.virginia) | >= 5.83 |
| <a name="provider_helm"></a> [helm](#provider\_helm) | >= 2.7 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_eks"></a> [eks](#module\_eks) | ../.. | n/a |
| <a name="module_karpenter"></a> [karpenter](#module\_karpenter) | ../../modules/karpenter | n/a |
| <a name="module_karpenter_disabled"></a> [karpenter\_disabled](#module\_karpenter\_disabled) | ../../modules/karpenter | n/a |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | terraform-aws-modules/vpc/aws | ~> 5.0 |

## Resources

| Name | Type |
|------|------|
| [helm_release.karpenter](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_ecrpublic_authorization_token.token](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ecrpublic_authorization_token) | data source |

## Inputs

No inputs.

## Outputs

No outputs.
<!-- END_TF_DOCS -->

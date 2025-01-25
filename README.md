# Karpenter deployment

This challenge was based on the [example](https://github.com/terraform-aws-modules/terraform-aws-eks/tree/master/examples/karpenter) from the [Community module](https://github.com/terraform-aws-modules/terraform-aws-eks) for EKS. 


Configuration in this directory creates an AWS EKS cluster with [Karpenter](https://karpenter.sh/) provisioned for managing compute resource scaling. In the example provided, Karpenter is provisioned on top of an EKS Managed Node Group.

## Prerrequisites
1. **Required Tools:**
   - `Terraform (= 1.3.2)`
   - AWS account
        - For testing you will have to change the backend configuration (or delete it)
            - S3 bucket name 
            - Dynamodb 
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
   - This example assumes you have a vpc deployed in terraform and you have access to its state file.
     You will have to change this code in the main.tf file in order to the process to work

        ```
            data "terraform_remote_state" "vpc" {
            backend = "s3"
            config = {
                bucket = "challengeterraformstate"  
                key    = "challenge/vpc_statefile"  
                region = local.region
            }
            }
        ```

## Usage

To provision the provided configurations you need to execute:

```bash
$ git clone https://github.com/PadillaBraulio/tech_challenge_2025.git
$ cd tech_challenge_2025
$ terraform init
$ terraform plan
$ terraform apply --auto-approve
```

Once the cluster is up and running install karpenter running the following commands:

```bash
# First, make sure you have updated your local kubeconfig
aws eks --region us-east-1 update-kubeconfig --name ex-karpenter

# Deploy the karpenter config file
cd karpenter_conf_files
kubectl apply -f karpenter.yaml
cd ..

```

### ARCHITECTURE DEPLOYING EXAMPLE

```
# If you want to Karpenter to decide which architecture to use do

cd karpenter_deploy_examples
kubectl apply -f inflate.yaml


# If you want to Karpenter to use amd64 arch do:
cd karpenter_deploy_examples
kubectl apply -f inflateamd64.yaml

# You can watch Karpenter's controller logs with
kubectl logs -f -n kube-system -l app.kubernetes.io/name=karpenter -c controller
```

### Validation:

Validate if the Amazon EKS Addons Pods are running in the Managed Node Group and the `inflate` application Pods are running on Karpenter provisioned Nodes.

```bash
kubectl get nodes -L karpenter.sh/registered
```

```text
NAME                                        STATUS   ROLES    AGE   VERSION               REGISTERED
ip-10-0-13-51.us-east-1.compute.internal    Ready    <none>   29s   v1.31.1-eks-1b3e656   true
ip-10-0-41-242.us-east-1.compute.internal   Ready    <none>   35m   v1.31.1-eks-1b3e656
ip-10-0-8-151.us-east-1.compute.internal    Ready    <none>   35m   v1.31.1-eks-1b3e656
```


### GPU SLICING RESEARCH AND TESTING

GPU Slicing is a technology provided by NVIDIA GPUs that allows multiple workloads to share GPU resources efficiently. It works similarly to how CPUs handle processes, where each process is allocated a small slice of time to access and utilize the GPU's computational power. This approach ensures that the GPU's resources are maximized by enabling time-sharing among processes, making it possible to run multiple jobs on a single GPU instance simultaneously.

For this test we are using a g5.xlarge instances, since they are cheap and enough for functionaltiy demostration.

In order to test we added a helm chart deployment in our terraform module.

```
resource "helm_release" "nvidia_device_plugin" {
  name       = "nvdp"
  chart      = "nvidia-device-plugin"
  repository = "https://nvidia.github.io/k8s-device-plugin"
  namespace  = "nvidia-device-plugin"
  create_namespace = true

  version = "0.17.0"

  set {
    name  = "config.name"
    value = "nvidia-device-plugin"
  }


  depends_on = [ module.eks ]
}
```

The above helm chart will deploy a deamon set that contains the nvidia device plugin binary that is in charge of making the configuration for the time slice feature. Important thing to note is that we are passing a variable config.name = nvidia-device-plugin, so after we deploy our terraform script we will deploy the config map stored in the karpenter_conf_files directory

```
cd tech_challenge_2025
cd karpenter_conf_files
kubectl apply -f configmap.yaml
```

That configmap set the GPU to have 5 replicas, basically allowing 5 different jobs to connect to your GPU.

```
apiVersion: v1
kind: ConfigMap
metadata:
  name: nvidia-device-plugin
  namespace: nvidia-device-plugin
data:
  any: |-
    version: v1
    flags:
      migStrategy: none
    sharing:
      timeSlicing:
        resources:
        - name: nvidia.com/gpu
          replicas: 5
```

In order to launch that type of instance we need to add a new NodePool, We used the below nodepool that resides in the karpenter.yaml file.

```
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: gpu-nodepool
spec:
  template:
    metadata:
      labels:
        nvidia.com/gpu.present: 'true' # Needed to match what is set in the helm chart https://github.com/NVIDIA/k8s-device-plugin/blob/main/deployments/helm/nvidia-device-plugin/values.yaml#L84
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      requirements:
        - key: "karpenter.sh/capacity-type"
          operator: In
          values: ["on-demand"]
        - key: "kubernetes.io/arch"
          operator: In
          values: ["amd64"] 
        - key: "node.kubernetes.io/instance-type"
          operator: In
          values: [ "g5.xlarge" ] # NVIDIA GPU INSTANCES
        - key: "topology.kubernetes.io/zone"
          operator: In
          values: ["us-east-1a"] 
  limits:
    cpu: 64  
  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 30s
```
To every node created by this NodePool we will attach specific labels so we make sure the deamonset is succesfully launched on it.

After its deployed you should be able to run:

```
 kubectl get nodes -o json | jq -r '.items[] | select(.status.capacity."nvidia.com/gpu" != null) | {name: .metadata.name, capacity: .status.capacity}'

{
  "name": "ip-10-0-10-89.ec2.internal",
  "capacity": {
    "cpu": "4",
    "ephemeral-storage": "20414Mi",
    "hugepages-1Gi": "0",
    "hugepages-2Mi": "0",
    "memory": "16140132Ki",
    "nvidia.com/gpu": "5",
    "pods": "58"
  }
}
```
And as you can see, you have 5 GPU , so that means you can launch 5 different jobs even though the server only has 1 GPU.
To test you can deploy using the inflateamdgpu.yaml file

```
cd karpenter_deploy_examples
kubectl apply -f inflateamdgpu.yaml
```

And you should see 3 different pods running

```
kubectl get all   --all-namespaces 
NAMESPACE              NAME                                  READY   STATUS    RESTARTS   AGE
default                pod/inflategpu-7bdcbc4d5d-5c7dr       1/1     Running   0          55m
default                pod/inflategpu-7bdcbc4d5d-jrmqv       1/1     Running   0          43m
default                pod/inflategpu-7bdcbc4d5d-w6tjd       1/1     Running   0          43m
kube-system            pod/aws-node-g54dx                    2/2     Running   0          88m
```
And only new GPU server added:

```
kubectl get nodes -o wide

NAME                         STATUS   ROLES    AGE     VERSION               INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                                       KERNEL-VERSION   CONTAINER-RUNTIME
ip-10-0-10-89.ec2.internal   Ready    <none>   8m     v1.31.3-eks-7636447   10.0.10.89    <none>        Bottlerocket OS 1.31.0 (aws-k8s-1.31-nvidia)   6.1.119          containerd://1.7.24+bottlerocket
ip-10-0-17-10.ec2.internal   Ready    <none>   3h17m   v1.31.3-eks-7636447   10.0.17.10    <none>        Bottlerocket OS 1.31.0 (aws-k8s-1.31)          6.1.119          containerd://1.7.24+bottlerocket
ip-10-0-2-94.ec2.internal    Ready    <none>   3h17m   v1.31.3-eks-7636447   10.0.2.94     <none>        Bottlerocket OS 1.31.0 (aws-k8s-1.31)          6.1.119          containerd://1.7.24+bottlerocket
```

#### References

https://aws.amazon.com/blogs/containers/gpu-sharing-on-amazon-eks-with-nvidia-time-slicing-and-accelerated-ec2-instances/

https://github.com/NVIDIA/k8s-device-plugin

https://github.com/NVIDIA/k8s-device-plugin/tree/main/deployments/helm/nvidia-device-plugin

https://github.com/bottlerocket-os/bottlerocket


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

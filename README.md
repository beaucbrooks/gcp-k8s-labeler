# GCP Kubernetes Cluster Creation and Label Modification

This project automates the process of creating a Google Cloud Platform (GCP) Kubernetes cluster, along with the necessary PowerShell scripts to modify the labels of that cluster after its creation.

## Project Overview

This project is divided into two main components:

1. **Terraform Infrastructure**: Creates the necessary infrastructure for a GCP Kubernetes cluster, including the VPC, subnet, firewall rules, and the Kubernetes cluster itself.
2. **PowerShell Scripts**: Provides PowerShell scripts that can be used to modify the labels of the Kubernetes cluster after it has been created.

## Requirements

- [Terraform](https://www.terraform.io/downloads.html) (v1.0+)
- Google Cloud Platform (GCP) account
- [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) (for authentication)
- [PowerShell](https://docs.microsoft.com/en-us/powershell/scripting/overview) (for label modification scripts)
- [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) (to interact with your Kubernetes cluster)

## Project Setup

### 1. **Terraform Configuration**

#### Clone the repository:

```bash
git clone https://github.com/your-username/gcp-k8s-cluster.git
cd gcp-k8s-cluster

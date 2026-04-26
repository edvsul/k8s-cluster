terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
  }
  backend "s3" {
    bucket       = "edvinas-tfstate-backup"
    key          = "homelab/staging/tfstate"
    region       = "eu-west-1"
    use_lockfile = true
    profile      = "tgtg-playground-edvinas"
  }
}

provider "aws" {
  region  = var.region
  profile = var.aws_profile
}

provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kubeconfig_context
}

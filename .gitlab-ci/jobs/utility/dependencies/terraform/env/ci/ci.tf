terraform {
  backend "s3" {
    bucket               = "umbrella-tf-states"
    key                  = "terraform.tfstate"
    region               = "us-gov-west-1"
    dynamodb_table       = "umbrella-tf-states-lock"
    workspace_key_prefix = "utility"
  }
}


data "terraform_remote_state" "networking" {
  backend = "s3"
  config = {
    bucket               = "umbrella-tf-states"
    key                  = "terraform.tfstate"
    region               = "us-gov-west-1"
    workspace_key_prefix = "aws-networking"
  }
  workspace = var.env
}

module "ci" {
  source = "../../main"
  env       = "ci"
  vpc_id    = data.terraform_remote_state.networking.outputs.vpc_id
  subnet_id = data.terraform_remote_state.networking.outputs.private_subnets[0]
}
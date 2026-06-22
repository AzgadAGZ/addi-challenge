terraform {
  backend "s3" {
    bucket         = "addi-terraform-state-dev"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "addi-terraform-locks-dev"
  }
}

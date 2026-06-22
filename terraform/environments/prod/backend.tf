terraform {
  backend "s3" {
    bucket         = "addi-terraform-state-prod"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "addi-terraform-locks-prod"
  }
}

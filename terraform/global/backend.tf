terraform {
  backend "s3" {
    bucket         = "addi-terraform-state-global"
    key            = "global/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "addi-terraform-locks-global"
  }
}

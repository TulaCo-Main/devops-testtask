terraform {
  backend "s3" {
    bucket       = "devops-test-tfstate-056300054271-eu-central-1"
    key          = "devops-test/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}

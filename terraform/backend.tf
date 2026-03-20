terraform {
  backend "s3" {
    bucket       = "terraform-statefile-bucket-123456789"
    key          = "dev/todo-app/terraform.tfstate"
    region       = "ap-south-1"
    use_lockfile = true
    encrypt      = true
  }
}
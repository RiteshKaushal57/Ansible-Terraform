module "vpc" {
  source = "./modules/vpc"
  vpc_cidr = var.vpc_cidr
  public_subnet_1_cidr = var.public_subnet_1_cidr
  public_subnet_2_cidr = var.public_subnet_2_cidr
  private_subnet_cidr = var.private_subnet_cidr
  az_1 = var.az_1
  az_2 = var.az_2
  environment = var.environment
  your_ip = var.your_ip
}
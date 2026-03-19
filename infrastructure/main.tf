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

module "compute" {
  source = "./modules/compute"
  instance_type = var.instance_type
  key_name = var.key_name
  public_subnet_1_id = module.vpc.public_subnet_1_id
  private_subnet_id = module.vpc.private_subnet_id
  bastion_sg_id = module.vpc.bastion_sg_id
  web_server_sg_id = module.vpc.web_server_sg_id
  mongodb_sg_id = module.vpc.mongodb_sg_id
  environment = var.environment
}

module "alb" {
  source = "./modules/alb"
  vpc_id = module.vpc.vpc_id
  subnets = [module.vpc.public_subnet_1_id, module.vpc.public_subnet_2_id]
  alb_sg_id = module.vpc.alb_sg_id
  web_server_ids = module.compute.web_server_ids
  environment = var.environment
}
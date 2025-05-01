module "vpc" {
  source = "./modules/vpc"
}

module "s3" {
  source = "./modules/s3"
  vpc_id = module.vpc.id
  route_table_id = module.vpc.route_table_id
}

module "efs" {
  source = "./modules/efs"
  public_subnet_id = module.vpc.public_subnet_id
}
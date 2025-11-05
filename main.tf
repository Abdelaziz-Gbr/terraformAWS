module "network"{
  source = "./modules/network"
  vpc_cidr = var.vpc_cidr
  vpc_name = var.vpc_name
  availability_zones = var.AZs
  public_subnet_cidrs = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs

}

module "eks" {
  source = "./modules/eks"

  cluster_name       = "my-cluster"
  cluster_version    = "1.30"
  private_subnet_ids = module.network.private_subnet_ids
  vpc_id             = module.network.vpc_id
  node_desired_size  = 2
  node_max_size      = 3
  node_min_size      = 1
  node_instance_types = ["t2.micro"]
}
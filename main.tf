module "network"{
  source = "./modules/network"
  vpc_cidr = var.vpc_cidr
  vpc_name = var.vpc_name
  availability_zones = var.AZs
  public_subnet_cidrs = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs

}

module "eks" {
  depends_on = [module.network]
  source = "./modules/eks"

  cluster_name       = "my-cluster"
  cluster_version    = "1.30"
  private_subnet_ids = module.network.private_subnet_ids
  vpc_id             = module.network.vpc_id
  node_desired_size  = 2
  node_max_size      = 3
  node_min_size      = 1
  node_instance_types = ["t3.medium"]
  oidc_provider_arn  = module.eks.oidc_provider_arn
}

resource "null_resource" "update_kubeconfig" {
  depends_on = [module.eks]

  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --name my-cluster --region us-east-1"
  }
}

resource "helm_release" "argocd" {
  name = "argocd"

  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "3.35.4"

  values = [file("values/argocd.yaml")]
  depends_on = [module.eks, null_resource.update_kubeconfig]
}
resource "helm_release" "updater" {
  name = "updater"

  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argocd-image-updater"
  namespace        = "argocd"
  create_namespace = true
  version          = "0.8.4"

  values = [file("values/image-updater.yaml")]
  depends_on = [module.eks, null_resource.update_kubeconfig]
}

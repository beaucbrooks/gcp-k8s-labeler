data "google_compute_subnetwork" "gke_subnet" {
  name   = var.subnet_name
  region = var.region
}

data "google_compute_network" "vpc_network" {
  name = var.vpc_name
}
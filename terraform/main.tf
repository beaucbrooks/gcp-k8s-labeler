resource "google_container_cluster" "primary" {
  name               = var.cluster_name
  location           = var.region
  enable_autopilot   = true # Enables GKE Autopilot mode
  initial_node_count = 1

  # Make the cluster public
  private_cluster_config {
    enable_private_nodes    = false
    enable_private_endpoint = false
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = var.allowed_ip
      display_name = "Allowed IP"
    }
  }

  node_config {
    machine_type = "e2-medium"
    disk_size_gb = 40

    tags = var.node_tags
  }

  # Optional network settings
  network    = data.google_compute_network.vpc_network.name
  subnetwork = data.google_compute_subnetwork.gke_subnet.name
}

resource "google_compute_firewall" "k8s_firewall" {
  name    = "k8s-cluster-firewall"
  network = data.google_compute_network.vpc_network.name

  // Allow traffic between nodes
  allow {
    protocol = "icmp"
  }
  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  // Allow traffic from the specified subnet
  source_ranges = [
    data.google_compute_subnetwork.gke_subnet.ip_cidr_range,
    var.allowed_ip
  ]

  // Target the firewall rule to all nodes attached to the network
  target_tags = var.node_tags

  // Optional: Set priority (lower value = higher priority)
  priority = 1000

  // Optional: Set direction to ingress (for incoming traffic)
  direction = "INGRESS"
}
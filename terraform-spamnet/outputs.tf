locals {
  # Collect all module instances that were created
  all_modules = {
    us_west_2      = length(module.us_west_2) > 0 ? module.us_west_2[0] : null
    eu_central_1   = length(module.eu_central_1) > 0 ? module.eu_central_1[0] : null
    us_east_1      = length(module.us_east_1) > 0 ? module.us_east_1[0] : null
    ap_northeast_1 = length(module.ap_northeast_1) > 0 ? module.ap_northeast_1[0] : null
    sa_east_1      = length(module.sa_east_1) > 0 ? module.sa_east_1[0] : null
  }
  
  # Filter out null modules
  active_modules = {
    for k, v in local.all_modules : k => v if v != null
  }
}

output "instances" {
  description = "Detailed information about each instance"
  value = flatten([
    for region_key, deployment in local.active_modules : [
      for i in range(length(deployment.instance_ids)) : {
        instance_id   = deployment.instance_ids[i]
        public_ip     = deployment.public_ips[i]
        private_ip    = deployment.private_ips[i]
        region        = deployment.availability_zones[i]
        volume_id     = deployment.volume_ids[i]
        instance_type = deployment.instance_types[i]
        name          = deployment.instance_names[i]
      }
    ]
  ])
}

output "deployment_summary" {
  description = "Summary of the deployment"
  value = {
    total_instances      = length(var.regions) * var.instances_per_region
    regions              = var.regions
    instances_per_region = var.instances_per_region
    instance_type        = var.instance_type
  }
}

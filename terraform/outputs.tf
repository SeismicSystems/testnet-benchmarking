output "instances" {
  description = "Detailed information about each instance"
  value = [
    for i, instance in aws_instance.multi : {
      instance_id   = instance.id
      public_ip     = instance.public_ip
      private_ip    = instance.private_ip
      region        = instance.availability_zone
      volume_id     = instance.root_block_device[0].volume_id
      instance_type = instance.instance_type
      name          = instance.tags["Name"]
    }
  ]
}

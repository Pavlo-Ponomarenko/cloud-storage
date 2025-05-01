output "id" {
  value = aws_vpc.main_vpc.id
}

output "route_table_id" {
  value = aws_route_table.public_rt.id
}

output "public_subnet_id" {
  value = aws_subnet.public_subnet.id
}
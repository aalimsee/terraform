# Terraform AWS Infra Setup
Setup of ASG (web and db) in public and private network. ALB and NLB used to balance the load on ASGs. NAT gateway included to pull installation package to DB servers. Route 54 deployed - http://aalimsee-tf.sctp-sandbox.com
# Software Tree
.
├── main.tf
├── nat-gateway.tf
├── provider.tf
└── variable.tf

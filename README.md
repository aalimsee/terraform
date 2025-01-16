# Terraform AWS Infra Setup
Setup of ASG (web and db) in public and private network. ALB and NLB used to balance the load on ASGs. NAT gateway included to pull installation package to DB servers. 
Route 53 deployed - http://aalimsee-tf-web.sctp-sandbox.com
Include boolean to switch between HTTP to HTTPS with -var="use_https=true" during plan and apply. https://aalimsee-tf-web.sctp-sandbox.com 

# Software Tree
.
├── main.tf
├── nat-gateway.tf
├── provider.tf
└── variable.tf

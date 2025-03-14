# README

This is a sample process to build a Cloud Run instance to run HAProxy as Load Balancer

## Local Test
To Run
```
docker buildx build -t haproxy-redirect .
docker run -d -p 8080:8080 -e PORT=8080 --name haproxy-test haproxy-redirect

```

To Debug
```
docker run -it -p 8080:8080 -e PORT=8080 --entrypoint /bin/sh haproxy-redirect
/entrypoint.sh

# open another terminal
curl -vL http://localhost:8080
```

## Prepare and deploy Cloud Run

```
SERVICE_NAME="haproxy-lb-service"
PROJECT_ID="my-project-id"
REGION="northamerica-northeast1"
BUCKET_NAME="my-gcsfuse-haproxy"

# Authenticate with Google Cloud
gcloud auth login
gcloud config set project $PROJECT_ID
gcloud config set compute/region $REGION

# make the bucket
gsutil mb -l $REGION gs://$BUCKET_NAME

# create GAR repo
gcloud artifacts repositories create haproxy-repo \
  --repository-format=docker \
  --location=${REGION} \
  --description="TTAN Lab repository" \
  --async

gcloud artifacts repositories list

gcloud auth configure-docker ${REGION}-docker.pkg.dev

IMAGE=${REGION}-docker.pkg.dev/${PROJECT_ID}/haproxy-repo/haproxy-redirect:latest
docker tag haproxy-redirect $IMAGE
docker push $IMAGE

gsutil cp haproxy.cfg gs://${BUCKET_NAME}/haproxy.cfg

SERVICE_NAME=haproxy-lb-service
gcloud beta run deploy --image $IMAGE $SERVICE_NAME \
--region $REGION \
--execution-environment gen2 --port 8080 \
--add-volume=name=html-volume,type=cloud-storage,bucket=${BUCKET_NAME},readonly=true \
--add-volume-mount=volume=html-volume,mount-path='/etc/haproxy' \
--ingress=all \
--allow-unauthenticated

```

### Test

Once the cloud run instance is deployed, we can test
```
curl -kvL https://haproxy-lb-service-gkfo4nx2kq-nn.a.run.app
```

Change the haproxy.cfg to replace google.com with tesla.com
```
# copy the updated haproxy.cfg to the GCS bucket
gsutil cp haproxy.cfg gs://${BUCKET_NAME}/haproxy.cfg
gsutil cat gs://${BUCKET_NAME}/haproxy.cfg

# Check again for the Cloud Run endpoint, it should point to tesla.com now
# https://haproxy-lb-service-gkfo4nx2kq-nn.a.run.app
```

## Use it as LB/Proxy for internal VPC services

### Prepare VPC, subnets and nat-gateway

```
# the main subnet is 10.10.10.0/24 and cloud_run_subnet is 10.11.0.0/28
VPC=ttan-lab-main-vpc
MAIN_SUBNET=ttan-lab-main-subnet
CLOUD_RUN_SUBNET=cloud-run-subnet

# Set your environment variables
export VPC=ttan-lab-main-vpc
export MAIN_SUBNET=ttan-lab-main-subnet
export CLOUD_RUN_SUBNET=cloud-run-subnet
export REGION=northamerica-northeast1
export PROJECT_ID=$(gcloud config get-value project)

# 1. Create the VPC network
gcloud compute networks create $VPC \
    --subnet-mode=custom \
    --bgp-routing-mode=regional \
    --project=$PROJECT_ID

# 2. Create the main subnet
gcloud compute networks subnets create $MAIN_SUBNET \
    --project=$PROJECT_ID \
    --network=$VPC \
    --region=$REGION \
    --range=10.10.10.0/24

# 3. Create the Cloud Run subnet (for VPC connector)
gcloud compute networks subnets create $CLOUD_RUN_SUBNET \
    --project=$PROJECT_ID \
    --network=$VPC \
    --region=$REGION \
    --range=10.11.0.0/28 \
    --purpose=VPC_CONNECTOR \
    --role=ACTIVE

# 4. Create a Cloud Router
export ROUTER_NAME=${VPC}-router
gcloud compute routers create $ROUTER_NAME \
    --project=$PROJECT_ID \
    --network=$VPC \
    --region=$REGION

# 5. Create a NAT gateway using the router
export NAT_NAME=${VPC}-nat
gcloud compute routers nats create $NAT_NAME \
    --router=$ROUTER_NAME \
    --region=$REGION \
    --nat-all-subnet-ip-ranges \
    --auto-allocate-nat-external-ips
```

### Create cloud-run vpc connector
```
gcloud compute networks vpc-access connectors create vpc-connector \
  --region $REGION \
  --subnet $CLOUD_RUN_SUBNET \
  --subnet-project $PROJECT_ID \
  --machine-type e2-micro

gcloud beta run services update $SERVICE_NAME \
  --region $REGION \
  --vpc-connector vpc-connector \
  --vpc-egress all


```

### Create a VM to test 

```
ZONE=$REGION-a
gcloud compute instances create nginx-vm \
  --zone $ZONE \
  --machine-type e2-micro \
  --subnet $MAIN_SUBNET \
  --network $VPC \
  --tags http-server \
  --image-family ubuntu-2204-lts \
  --image-project ubuntu-os-cloud \
  --metadata-from-file startup-script=<(cat << 'EOF'
#!/bin/bash
apt-get update
apt-get install -y nginx
echo "nginx hello world" > /var/www/html/index.html
systemctl enable nginx
systemctl restart nginx
EOF
)
```

### Update haproxy.cfg 

Update haproxy.cfg to use /site to redirect to the backend VM, everything else still forward to tesla.com or google.com

Because our backend doesn't have /site path, we use a 'set-path' to remove /site path before forward

```
# Define backend for your local nginx server
backend nginx_backend
    server nginx 10.10.10.5:80
    # Optional: Strip the /site prefix when forwarding to nginx
    http-request set-path %[path,regsub(^/site,/)]
```

### copy and test

```
gsutil cp haproxy.cfg gs://${BUCKET_NAME}/haproxy.cfg

curl -vL https://haproxy-lb-service-gkfo4nx2kq-nn.a.run.app
curl -vL https://haproxy-lb-service-gkfo4nx2kq-nn.a.run.app/site
```

## Conclusion

Use haproxy in cloud-run with its config file in GCS bucket is a variable solution for load balancers in GCP.

When we need to change the haproxy.cfg, we just need to copy the new file to the GCS bucket, the `/entrypoint.sh` will automatically reload haproxy to use it.
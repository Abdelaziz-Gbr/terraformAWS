1)infrastructre

export aws keys and region:
  'export AWS_ACCESS_KEY_ID=<your access key> \
export AWS_SECRET_ACCESS_KEY=<your secret key> \
export AWS_REGION=<default region>
'
run "terraform init && terraform apply -auto-approve"

2)jenkins
install helm if not available
  'curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash'



*important*set default storageclass: 
  kubectl patch storageclass gp2 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'



add jenkins repo to helm:
  'helm repo add jenkins https://charts.jenkins.io && helm repo update'
install jenkins:
  'helm install jenkins jenkins/jenkins \
  --namespace jenkins \
  --set controller.serviceType=LoadBalancer \
  --set controller.resources.requests.cpu=1000m \
  --set controller.resources.requests.memory=2Gi \
  --set controller.resources.limits.cpu=1250m \
  --set controller.resources.limits.memory=4Gi \
  --set persistence.enabled=true \
  --set persistence.size=3Gi \
  --create-namespace'

get jenkins pass:
  kubectl exec --namespace jenkins -it svc/jenkins -c jenkins -- /bin/cat /run/secrets/additional/chart-admin-password && echo

install aws credentials plugin in jenkins then store your credntials 
create the pipeline and configure it to use 'jenkinsfile' from this project

3)argocd and AIU
install argocd: 'helm install argocd argo/argo-cd -n argocd --create-namespace'
install argocd image updater: 'helm install argocd-image-updater argo/argocd-image-updater --version 0.8.4 -n argocd -f values/image-updater.yaml '

get argocd inital password:
    'kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d'

use port-forward to access argo-cd web ui:
  'kubectl port-forward service/argocd-server -n argocd 8080:80'

create the application ns: 'k create ns test'

apply argo application
  'kubectl apply -f manifists/argo-application/application.yaml

kubectl create secret docker-registry ecr-secret \
  --docker-username=AWS \
  --docker-password="$(aws ecr get-login-password --region us-east-1)" \
  --docker-server=579385932895.dkr.ecr.us-east-1.amazonaws.com \
  -n argocd



create the same key but under argocd namespace so the image updater can access the ecr: 'k create secret docker-registry ecr-secret --docker-username="AWS" --docker-password=$"aws ecr get-login-password --region us-east-1" --docker-server="579385932895.dkr.ecr.us-east-1.amazonaws.com" -n argocd'

create dockerhub secret so argocd-image-updater can access the repo and commit new tags: 'k apply -f manifists/secrets/github-secret.yaml'
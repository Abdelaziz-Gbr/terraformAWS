1)infrastructre

export aws keys and regoion:
  'export AWS_ACCESS_KEY_ID=<your access key> \
export AWS_SECRET_ACCESS_KEY=<your secret key> \
export AWS_REGION=<default region>
'
run "terraform init && terraform apply -auto-approve"

run "aws configure" to set up your aws cli with the same keys and region
run "aws eks --region <your region> update-kubeconfig --name <your cluster name>" to configure kubectl


2)jenkins
install helm if not available
  'curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash'



set default storageclass: 
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
add argocd lib to helm:
  'helm repo add argo https://argoproj.github.io/argo-helm && helm repo update'
install argocd:
 'helm install argocd argo/argo-cd -n argocd --create-namespace'

install argo image updater:
  'helm install argo-image-updater argo/argocd-image-updater -n argocd'

create the iam policy for the image updater to view the ecr:
  'aws iam create-policy \
  --policy-name ArgoImageUpdaterECRPolicy \
  --policy-document '{
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": [
            "ecr:DescribeImages",
            "ecr:GetAuthorizationToken",
            "ecr:BatchGetImage",
            "ecr:DescribeRepositories"
          ],
          "Resource": "*"
        }
      ]
  }'
'

then use the current sa and attach this policy:
  'eksctl create iamserviceaccount \
  --name argo-image-updater-argocd-image-updater \
  --namespace argocd \
  --cluster my-cluster \
  --attach-policy-arn arn:aws:iam::579385932895:policy/ArgoImageUpdaterECRPolicy \
  --approve'

**note double check the sa name thro "kubectl get deploy argo-image-updater-argocd-image-updater-controller -n argocd -o=jsonpath='{.spec.template.spec.serviceAccountName}'  "

then create a github personal access token (PAT) so the AIU can access and update the github repo

kubectl create secret generic argo-image-updater-git-creds -n argocd \
  --from-literal=username='<your-github-username>' \
  --from-literal=password='<PAT>'

kubectl set env deployment argo-image-updater-argocd-image-updater-controller -n argocd \
  --from=secret/argo-image-updater-git-creds



get argocd inital password:
    'kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d'

use port-forward to access argo-cd web ui:
  'kubectl port-forward service/argocd-server -n argocd 8080:443'


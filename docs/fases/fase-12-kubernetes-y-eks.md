# Fase 12 — Kubernetes y despliegue en la nube (EP3: IE2)

## Qué hay hoy
| Dónde | Qué hace | Cuándo corre |
|-------|----------|--------------|
| Job `4b` (kind) | Crea un cluster Kubernetes dentro del runner, aplica `k8s/` con la imagen del commit, hace smoke test, escala a 3 réplicas y verifica que Prometheus lea todas las réplicas | siempre (PR y push) |
| Job `4d` (AWS EKS) | Sube la misma imagen a ECR y aplica `k8s/` en un cluster EKS real, con la misma verificación de Prometheus | solo en push a `main` **si** existe la variable `EKS_CLUSTER_NAME` |

Manifiestos (`k8s/`): namespace, configmap, PostgreSQL, app (2 réplicas, probes startup/liveness/readiness, límites, usuario no root, filesystem de solo lectura, rolling update sin caída), HPA (2 a 5 réplicas por CPU 70 % / memoria 85 %), PodDisruptionBudget y **Prometheus** (`05-prometheus.yaml`).

## Observabilidad dentro del cluster
El Deployment de la app lleva las anotaciones `prometheus.io/scrape`, `prometheus.io/path` y `prometheus.io/port`. Prometheus (con un `Role` que solo permite leer pods de este namespace) descubre los pods con esa anotación, así que si el HPA agrega réplicas las empieza a leer solo. El pipeline comprueba que lea al menos 2 réplicas; si no, el despliegue falla.

Ver las métricas del cluster desde el computador:

```bash
kubectl -n order-manager port-forward svc/prometheus 9090:9090
# http://localhost:9090/targets  -> job order-manager-pods
```

## Dejar listo AWS EKS (una sola vez)
Ajusten región y nombres. **Cuesta plata mientras esté encendido: borren el cluster al terminar** (`eksctl delete cluster --name order-manager --region us-east-1`).

```bash
# 1) cluster y repositorio de imágenes
eksctl create cluster --name order-manager --region us-east-1 --nodes 2 --node-type t3.medium
aws ecr create-repository --repository-name order-manager --region us-east-1

# 2) metrics-server (lo necesita el HPA)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# 3) GitHub como proveedor OIDC (si la cuenta no lo tiene; sin llaves de AWS en GitHub)
aws iam create-open-id-connect-provider --url https://token.actions.githubusercontent.com --client-id-list sts.amazonaws.com
```

4) Crear un rol IAM (por ejemplo `github-actions-order-manager`) con esta política de confianza (cambien `ACCOUNT_ID`) y los permisos `AmazonEC2ContainerRegistryPowerUser` + `eks:DescribeCluster`:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
      "StringLike":   { "token.actions.githubusercontent.com:sub": "repo:CarlosBastias/order-manager:environment:production-eks" }
    }
  }]
}
```

```bash
# 5) darle al rol acceso al cluster (para laboratorio; en producción se usarían permisos más acotados)
eksctl create iamidentitymapping --cluster order-manager --region us-east-1 \
  --arn arn:aws:iam::ACCOUNT_ID:role/github-actions-order-manager --username github-actions --group system:masters
```

6) En GitHub: *Settings → Secrets and variables → Actions → Variables* crear:

| Variable | Valor de ejemplo |
|----------|------------------|
| `EKS_CLUSTER_NAME` | `order-manager` |
| `AWS_REGION` | `us-east-1` |
| `AWS_ROLE_ARN` | `arn:aws:iam::ACCOUNT_ID:role/github-actions-order-manager` |
| `ECR_REPOSITORY` | `order-manager` |

Con eso, el siguiente push a `main` ejecuta el job `4d`. Para ver la app: `kubectl -n order-manager get pods,svc,hpa`.

> Si al final no se usa AWS, el job `4d` se salta solo y el proyecto sigue funcionando con kind. En ese caso hay que decir en el informe que el despliegue es en un cluster Kubernetes efímero y por qué (no hay cuenta de nube disponible).

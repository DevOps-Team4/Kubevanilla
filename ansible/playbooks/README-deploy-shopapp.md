# Deploy ShopApp Playbook

Ansible playbook для деплою ShopApp (BookStore) застосунку до Kubernetes кластера через Helm chart.

## 📋 Опис

Цей playbook автоматизує повний процес деплою:
- Перевірка та встановлення Helm (якщо потрібно)
- Валідація Helm chart
- Створення namespace
- Деплой застосунку через Helm
- Перевірка статусу деплою

## 🚀 Використання

### Базовий запуск (production)

```bash
ansible-playbook -i inventory.ini playbooks/deploy-shopapp.yml \
  --vault-password-file .vault_pass
```

### Development environment

```bash
ansible-playbook -i inventory.ini playbooks/deploy-shopapp.yml \
  --vault-password-file .vault_pass \
  -e shopapp_environment=dev \
  -e shopapp_postgres_password=devpassword
```

### З кастомними параметрами

```bash
ansible-playbook -i inventory.ini playbooks/deploy-shopapp.yml \
  --vault-password-file .vault_pass \
  -e shopapp_namespace=my-shopapp \
  -e shopapp_release_name=my-release \
  -e shopapp_environment=production \
  -e shopapp_postgres_password=SecurePassword123!
```

## ⚙️ Змінні

| Змінна | Опис | За замовчуванням |
|--------|------|------------------|
| `shopapp_namespace` | Kubernetes namespace | `shopapp` |
| `shopapp_release_name` | Helm release name | `shopapp` |
| `shopapp_environment` | Environment (dev/prod) | `production` |
| `shopapp_postgres_password` | PostgreSQL password | `bookstoreadmin` |

## 📁 Структура

Playbook виконує наступні кроки:

1. **Check Prerequisites** - перевіряє наявність kubectl, helm
2. **Install Prerequisites** - встановлює Helm та kubernetes.core collection якщо потрібно
3. **Prepare Helm Chart** - валідує Helm chart
4. **Create Namespace** - створює namespace якщо не існує
5. **Deploy ShopApp with Helm** - деплоїть застосунок
6. **Verify Deployment** - перевіряє статус подів та сервісів
7. **Display Deployment Summary** - показує підсумок деплою

## 🔧 Вимоги

### На bastion host:
- `kubectl` - для роботи з Kubernetes
- `helm` - для деплою chart (встановлюється автоматично якщо відсутній)
- Доступ до Kubernetes кластера (kubeconfig налаштований)

### Ansible collections:
- `kubernetes.core` - встановлюється автоматично якщо відсутній

## 📝 Приклади

### Деплой в production

```bash
ansible-playbook -i inventory.ini playbooks/deploy-shopapp.yml \
  --vault-password-file .vault_pass \
  -e shopapp_environment=production \
  -e shopapp_postgres_password=$(openssl rand -base64 32)
```

### Деплой в development

```bash
ansible-playbook -i inventory.ini playbooks/deploy-shopapp.yml \
  --vault-password-file .vault_pass \
  -e shopapp_environment=dev
```

### Перевірка статусу після деплою

```bash
# З bastion
kubectl get pods -n shopapp
kubectl get svc -n shopapp
kubectl get ingress -n shopapp
```

## 🐛 Troubleshooting

### Helm не встановлений
Playbook автоматично встановить Helm, але якщо є проблеми:
```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### Kubernetes недоступний
Перевірте kubeconfig:
```bash
kubectl cluster-info
kubectl get nodes
```

### Помилки деплою
Перевірте логи:
```bash
kubectl describe pod -n shopapp -l component=backend
kubectl logs -n shopapp -l component=backend
```

## 📚 Додаткова інформація

- Helm chart знаходиться в `helm/shopapp/`
- Values файли: `values.yaml`, `values-dev.yaml`, `values-prod.yaml`
- Детальна документація chart: `helm/shopapp/README.md`


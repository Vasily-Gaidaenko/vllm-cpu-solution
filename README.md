# CPU-инференс Qwen через vLLM в Kubernetes

Проект запускает `Qwen/Qwen2.5-0.5B-Instruct` на CPU через vLLM 0.27.0.
Контейнер работает от пользователя `vllm` с UID 10001. Веса сохраняются
на PVC, настройки передаются через ConfigMap, токены — через Secret.

## Требования

Linux x86-64, Docker с доступом без `sudo`, Minikube, Bash, Python 3 и curl.
Проверено на Ubuntu 24.04 с 8 vCPU и 16 ГиБ RAM (арендовал сервер, т.к. локально не хватало оперативной памяти)

## Запуск

Все команды выполняются на машине с Docker и Minikube.

```bash
git clone https://github.com/Vasily-Gaidaenko/vllm-cpu-deploy.git
cd vllm-cpu-deploy

docker build -t vllm-cpu:pvc .
minikube start --driver=docker --cpus=6 --memory=12288
minikube image load vllm-cpu:pvc
```

Создайте Secret. Для публичной Qwen HF-токен можно пропустить, нажав Enter.
Сохраните эту сессию терминала: `API_TOKEN` понадобится для проверки API.

```bash
API_TOKEN=$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')
read -r -s -p 'HF-токен (Enter для публичной модели): ' HF_TOKEN
printf '\n'

minikube kubectl -- -n default create secret generic vllm-secrets \
  --from-env-file=<(printf 'VLLM_API_KEY=%s\nHF_TOKEN=%s\n' "$API_TOKEN" "$HF_TOKEN")

unset HF_TOKEN
```

Примените манифесты и дождитесь готовности:

```bash
minikube kubectl -- -n default apply -f k8s/
minikube kubectl -- -n default rollout status deployment/vllm --timeout=600s
```

При первом запуске модель скачивается на PVC. При последующих запусках
используется сохраненная копия.

## Проверка API

Во втором терминале на той же машине запустите:

```bash
minikube kubectl -- -n default port-forward service/vllm 8000:8000
```

В исходном терминале отправьте запрос:

```bash
curl -fsS --max-time 60 http://127.0.0.1:8000/v1/chat/completions \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "Qwen/Qwen2.5-0.5B-Instruct",
    "messages": [{"role": "user", "content": "What is 2 + 2? Answer briefly."}],
    "max_tokens": 24,
    "temperature": 0
  }' | python3 -m json.tool
```

Ответ модели находится в `choices[0].message.content`.
Запрос к `/v1/models` без токена должен вернуть `401`:

```bash
curl -sS --max-time 10 -o /dev/null -w '%{http_code}\n' \
  http://127.0.0.1:8000/v1/models
```

Если сессия терминала была закрыта, восстановить `API_TOKEN` можно так:

```bash
API_TOKEN=$(minikube kubectl -- -n default get secret vllm-secrets \
  -o 'jsonpath={.data.VLLM_API_KEY}' | base64 -d)
```

## Настройки и диагностика

Настройки инференса находятся в `k8s/vllm-config.yaml`.
После изменения примените ConfigMap и перезапустите Deployment:

```bash
minikube kubectl -- -n default apply -f k8s/vllm-config.yaml
minikube kubectl -- -n default rollout restart deployment/vllm
minikube kubectl -- -n default rollout status deployment/vllm --timeout=300s
```

Посмотреть состояние и логи:

```bash
minikube kubectl -- -n default get pods,pvc
minikube kubectl -- -n default logs deployment/vllm --tail=100
```

Логирование промптов и ответов отключено флагами
`--no-enable-log-requests` и `--no-enable-log-outputs`.
Факт обращения фиксируется в HTTP access log.

Остановить кластер с сохранением его состояния:

```bash
minikube stop
```

## Нагрузочное тестирование

Для замеров использовал `vllm bench serve`. Скрипт выполняет по три прогона
для коротких и длинных промптов. В каждом прогоне — два запроса прогрева
и 30 измеряемых запросов.

Запуск после развертывания приложения в namespace `default`:

```bash
bash scripts/bench.sh 2>&1 | tee /tmp/vllm-bench.log
```

Клиент запускается в том же Pod, что и сервер, и обращается через Service.
Он допускает до четырех одновременных запросов. На сервере задано
`max-num-seqs: 1`, поэтому измеренная задержка включает ожидание в очереди -- специально, для тестов

Заданным длинам входа 32 и 256 соответствовали 61 и 285 токенов
по счетчику бенчмарка (после служебных обозначений). Длина ответа фиксирована:
32 токена, `temperature=0`, ранняя остановка по EOS отключена.

### Результаты

TTFT — время до первого токена, E2EL — время до полного ответа (Latency).
p50 и p95 (медиана времени и 95 процентиль) рассчитаны отдельно для каждого прогона.
Throughput учитывает только сгенерированные токены.

| Повтор | Вход, токенов | TTFT p50, с | TTFT p95, с | E2EL p50, с | E2EL p95, с | Throughput, токенов/с |
|---:|---:|---:|---:|---:|---:|---:|
| 1 | 61 | 6,86 | 6,93 | 8,91 | 8,99 | 14,34 |
| 1 | 285 | 8,90 | 8,96 | 10,95 | 11,02 | 11,75 |
| 2 | 61 | 6,86 | 6,92 | 8,90 | 8,97 | 14,35 |
| 2 | 285 | 6,60 | 6,66 | 8,65 | 8,71 | 14,78 |
| 3 | 61 | 6,88 | 6,93 | 8,92 | 8,99 | 14,33 |
| 3 | 285 | 6,59 | 6,65 | 8,64 | 8,71 | 14,79 |

Все 180 измеряемых запросов завершились успешно.

На коротких входах throughput получился стабильным. На длинных первый
прогон оказался медленнее двух последующих. Причину разброса отдельно
не исследовал, поэтому эти результаты не позволяют уверенно определить
влияние длины входа на throughput. Клиент и сервер делили ресурсы Pod.

### Какие параметры стоит проверить

При большом потоке коротких запросов я бы начал с увеличения
`max-num-seqs` с 1 до 2 и 4. Это позволит серверу обрабатывать несколько
активных последовательностей в батче. Для каждого значения нужно сравнить
throughput, p95 задержки и расход памяти.

Для редких запросов с длинным входом сначала нужно обеспечить достаточный
лимит контекста (`max-model-len`) и память для KV-кэша. Это позволит
обрабатывать такие запросы. Для повышения throughput я бы проверил
несколько значений `max-num-batched-tokens` при включённом chunked prefill, 
этот параметр задает бюджет токенов на один шаг обработки. Сравнение
замеров покажет, какой размер порции лучше подходит нашему CPU.

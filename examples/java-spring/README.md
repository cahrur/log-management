# Java Spring Boot + Pantra

## Setup

1. Tambah dependency di `pom.xml`:
   ```xml
   <dependency>
     <groupId>net.logstash.logback</groupId>
     <artifactId>logstash-logback-encoder</artifactId>
     <version>7.4</version>
   </dependency>
   ```

2. Copy `logback-spring.xml` ke `src/main/resources/`

3. Set application name di `application.yml`:
   ```yaml
   spring:
     application:
       name: my-service
   ```

4. Start:
   ```bash
   docker compose up -d --build
   ```

## Structured Logging

Pakai SLF4J dengan structured arguments:

```java
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import static net.logstash.logback.argument.StructuredArguments.*;

Logger log = LoggerFactory.getLogger(MyService.class);

// Key-value pairs
log.info("User created", kv("userId", 123), kv("email", "user@example.com"));

// MDC untuk request context
MDC.put("requestId", requestId);
MDC.put("userId", userId);
log.info("Processing request");
MDC.clear();
```

## Output (Production)

```json
{"timestamp":"2024-01-01T12:00:00.000Z","level":"INFO","logger_name":"c.m.s.UserService","message":"User created","service":"my-service","env":"production","userId":123}
```

## Prometheus Metrics

Spring Boot Actuator expose metrics otomatis:
```yaml
management:
  endpoints:
    web:
      exposure:
        include: health,info,prometheus
```

Tambahkan di Prometheus config:
```yaml
- job_name: 'spring-api'
  metrics_path: '/actuator/prometheus'
  static_configs:
    - targets: ['spring-api:8080']
```

## Query di Grafana

```logql
{service="spring-api"} | json | level="ERROR"
{service="spring-api"} | json | logger_name=~".*Service.*"
{project="myapp"} | json | duration_ms > 2000
```

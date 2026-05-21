# Observability and Monitoring

## Logging

- Use structured logging (JSON format)
- Include correlation IDs for request tracing
- Log at appropriate levels: ERROR for failures needing action, WARN for degraded state, INFO for key events, DEBUG for development
- Never log sensitive information (passwords, tokens, PII)
- Implement log aggregation and centralization

## Metrics

- Follow the Four Golden Signals: latency, traffic, errors, saturation
- Use standard metric naming conventions
- Implement custom business metrics alongside technical metrics
- Define SLIs, SLOs, and error budgets

## Distributed Tracing

- Implement OpenTelemetry for vendor-neutral tracing
- Add spans for critical operations (DB queries, external API calls, queue operations)
- Include relevant context in span attributes
- Sample traces appropriately to balance observability and performance

## Alerting

- Alert on symptoms, not causes
- Define clear escalation policies
- Avoid alert fatigue with proper thresholds — if it pages, it must be actionable
- Include runbooks in alert descriptions
- Test alerts regularly

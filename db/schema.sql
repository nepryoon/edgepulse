openapi: 3.1.0
info:
  title: EdgePulse Anomaly API
  version: 0.1.0
  description: Multi-tenant time-series ingestion + anomaly detection.
servers:
  - url: https://api.example.com
security:
  - ApiKeyAuth: []
components:
  securitySchemes:
    ApiKeyAuth:
      type: apiKey
      in: header
      name: X-API-Key

  schemas:
    Error:
      type: object
      required: [error, message, request_id]
      properties:
        error: { type: string }
        message: { type: string }
        request_id: { type: string }

    IngestMetricPoint:
      type: object
      required: [name, ts, value]
      properties:
        name: { type: string, minLength: 1 }
        ts: { type: string, format: date-time }
        value: { type: number }
        unit: { type: string }

    IngestRequest:
      type: object
      required: [device_external_id, metrics]
      properties:
        device_external_id: { type: string, minLength: 1 }
        metrics:
          type: array
          minItems: 1
          items: { $ref: "#/components/schemas/IngestMetricPoint" }

    IngestResponse:
      type: object
      required: [batch_id, accepted, dropped]
      properties:
        batch_id: { type: string }
        accepted: { type: integer, minimum: 0 }
        dropped: { type: integer, minimum: 0 }

    Device:
      type: object
      required: [id, external_id, label]
      properties:
        id: { type: string, format: uuid }
        external_id: { type: string }
        label: { type: string }
        tags: { type: object }

    Metric:
      type: object
      required: [id, device_id, name]
      properties:
        id: { type: string, format: uuid }
        device_id: { type: string, format: uuid }
        name: { type: string }
        unit: { type: string }
        freq_hint: { type: integer, description: "Optional sampling frequency hint in seconds." }

    AnomalyScore:
      type: object
      required: [metric_id, window_end, score]
      properties:
        metric_id: { type: string, format: uuid }
        window_end: { type: string, format: date-time }
        score: { type: number }
        label: { type: string }
        explanation: { type: object }

    AlertRule:
      type: object
      required: [id, metric_id, condition, channels, enabled]
      properties:
        id: { type: string, format: uuid }
        metric_id: { type: string, format: uuid }
        condition: { type: object }
        channels: { type: object }
        enabled: { type: boolean }

    Webhook:
      type: object
      required: [id, url, enabled]
      properties:
        id: { type: string, format: uuid }
        url: { type: string }
        enabled: { type: boolean }

paths:
  /v1/health:
    get:
      security: []
      responses:
        "200":
          description: OK

  /v1/ingest:
    post:
      summary: Ingest time-series points for a device
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: "#/components/schemas/IngestRequest" }
      responses:
        "202":
          description: Accepted
          content:
            application/json:
              schema: { $ref: "#/components/schemas/IngestResponse" }
        "400":
          description: Bad Request
          content:
            application/json:
              schema: { $ref: "#/components/schemas/Error" }
        "401":
          description: Unauthorized
          content:
            application/json:
              schema: { $ref: "#/components/schemas/Error" }

  /v1/devices:
    get:
      summary: List devices
      responses:
        "200":
          description: OK
    post:
      summary: Create device
      responses:
        "201":
          description: Created

  /v1/metrics:
    get:
      summary: List metrics
      parameters:
        - in: query
          name: device_id
          schema: { type: string, format: uuid }
      responses:
        "200":
          description: OK
    post:
      summary: Create metric
      responses:
        "201":
          description: Created

  /v1/anomalies:
    get:
      summary: Query anomaly scores
      parameters:
        - in: query
          name: metric_id
          required: true
          schema: { type: string, format: uuid }
        - in: query
          name: from
          required: true
          schema: { type: string, format: date-time }
        - in: query
          name: to
          required: true
          schema: { type: string, format: date-time }
      responses:
        "200":
          description: OK

  /v1/alert-rules:
    get:
      summary: List alert rules
      responses:
        "200":
          description: OK
    post:
      summary: Create alert rule
      responses:
        "201":
          description: Created

  /v1/webhooks:
    get:
      summary: List webhooks
      responses:
        "200":
          description: OK
    post:
      summary: Create webhook
      responses:
        "201":
          description: Created

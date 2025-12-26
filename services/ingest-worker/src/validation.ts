import { z } from "zod";

export const MetricPointSchema = z.object({
  name: z.string().min(1),
  ts: z.string().datetime({ offset: true }),
  value: z.number(),
  unit: z.string().optional(),
});

export const IngestRequestSchema = z.object({
  device_external_id: z.string().min(1),
  metrics: z.array(MetricPointSchema).min(1),
});

export type IngestRequest = z.infer<typeof IngestRequestSchema>;

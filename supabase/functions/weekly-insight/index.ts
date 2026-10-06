// Supabase Edge Function: weekly-insight
//
// Receives the app's weekly summary (daily feature rows, event titles, cycle
// estimates), asks Claude for one insight + a 7-day forecast, stores ONLY the
// generated insight text, and returns the full JSON to the app.
//
// The summary itself is never written to the database or to logs.
//
// Secrets (set with `supabase secrets set`):
//   ANTHROPIC_API_KEY   - Claude API key (server-side only)
// Provided automatically by Supabase:
//   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY

import Anthropic from "npm:@anthropic-ai/sdk";
import { createClient } from "npm:@supabase/supabase-js@2";

const MODEL = "claude-sonnet-5-5";
const MAX_PAYLOAD_BYTES = 300_000;
const MAX_INSIGHTS_PER_DAY = 3;

const EXPERIMENTS = [
  "caffeine_cutoff_2pm",
  "no_alcohol_weeknights",
  "wind_down_30",
  "morning_walk_10",
  "meeting_free_block",
] as const;

const SYSTEM_PROMPT = `You write one short weekly insight for a woman taking part in a 3-week test of a personal health app. The app passively reads her Apple Health data, cycle and calendar. You receive a JSON summary of the last 4-8 weeks of daily rows plus her upcoming 7 days.

## Data you receive
- profile: age_range, cycle_status (natural | hormonal | no_period), focus (what she most wants to understand: sleep | energy | mood | focus), typical_cycle_length.
- days[]: one row per date. sleep_h (hours asleep for the night ending that morning), sleep_eff (0-1), hrv (SDNN ms, daily mean), rhr (bpm), steps, active_kcal, workouts, workout_min, temp_delta (wrist temperature vs her own baseline, degrees C), flow (period day), cycle_day, phase (menstrual | follicular | ovulatory | luteal | late_luteal; estimated, null if not tracked), events (timed calendar events), scheduled_h, evening_events (18-22h), late_events (after 22h), energy (her optional evening check-in: 1 low, 2 okay, 3 good; null if not given), ev (that day's events as {t: title id, part: morning|afternoon|evening|late, min: duration}).
- titles: map from title id to calendar event title. Silently classify each title as one of: work meeting, social/dinner, nightlife, exercise class, creative, travel, other. Use these types in your reasoning. Never quote a title that could contain a person's name; refer to types ("dinners", "work meetings") instead.
- upcoming[]: the next 7 days with cycle estimates and planned events.
- stats: averages the app already computed (by phase, by sleep length, by calendar load). Prefer these numbers; they are exact.
- previous_insights: titles she already saw and whether she found them useful. Do not repeat a previous insight; lean toward the kind she marked useful.
- active_experiment: an experiment she is running, if any.
- locale: "en" or "es". Write every text field in that language (Spanish: natural, neutral Spanish, tuteo).

## How to write the insight
- Calm, curious, adult. Never shame. Never use "should" (Spanish: never "deberías"/"debes"). No medical claims, no diagnoses, no mention of conditions or disorders.
- Always show the numbers behind the claim. Only cite numbers that are present in the data or stats, or that you counted directly from the rows (e.g. "on 4 of 5 nights").
- Distinguish correlation from causation: "tends to", "on 4 of 5 nights", "often came after". Never say one thing causes another.
- Frame any change as a small optional experiment, not a fix.
- If there is no strong pattern, say so honestly and set confidence to "low". A plain "No clear pattern yet" insight is better than a stretched one.
- Relate the insight to her focus when the data allows it. Energy check-ins are the best signal for energy; for mood or focus, say honestly that the app only sees indirect signals.
- insight_title: at most 8 words. insight_body: at most 60 words.
- Good example: "Your 3 lowest-energy days followed nights under 6.5h, and 2 were in the days before your period. Want to test a 30-min earlier wind-down this week?"

## Fields
- evidence: 2-4 items {label, value}, short, e.g. {"label": "Nights under 6.5h", "value": "5 of 28"}.
- chart_series: the numbers behind the claim as one small series (7-28 points). type "bar" for categories or days, "line" for trends. x is a short label (a date as "Mon 6" / "lun 6", or a category). Set highlight true on the points the insight talks about.
- confidence: "high" only for a pattern seen repeatedly with a clear gap; "medium" for a consistent but small-sample pattern; "low" otherwise.
- week_forecast: exactly one entry for each date in upcoming[], in order. risk is low | med | high based on HER OWN history (sleep, cycle phase, calendar load, evening and late events). Use "high" sparingly: only when two or more factors that went with her lower-energy days line up, usually 0-2 days a week. reason: max 12 words, factual, with numbers ("5 events and late luteal phase").
- suggested_experiment: pick the one experiment from this list that best fits the pattern, with a one-sentence reason (max 20 words, no "should"): caffeine_cutoff_2pm, no_alcohol_weeknights, wind_down_30, morning_walk_10, meeting_free_block. Use null if an experiment is already active or nothing fits.`;

const OUTPUT_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: [
    "insight_title",
    "insight_body",
    "evidence",
    "chart_series",
    "confidence",
    "week_forecast",
    "suggested_experiment",
  ],
  properties: {
    insight_title: { type: "string" },
    insight_body: { type: "string" },
    evidence: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["label", "value"],
        properties: { label: { type: "string" }, value: { type: "string" } },
      },
    },
    chart_series: {
      type: "object",
      additionalProperties: false,
      required: ["type", "y_label", "points"],
      properties: {
        type: { type: "string", enum: ["bar", "line"] },
        y_label: { type: "string" },
        points: {
          type: "array",
          items: {
            type: "object",
            additionalProperties: false,
            required: ["x", "y", "highlight"],
            properties: {
              x: { type: "string" },
              y: { type: "number" },
              highlight: { type: "boolean" },
            },
          },
        },
      },
    },
    confidence: { type: "string", enum: ["low", "medium", "high"] },
    week_forecast: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["date", "risk", "reason"],
        properties: {
          date: { type: "string" },
          risk: { type: "string", enum: ["low", "med", "high"] },
          reason: { type: "string" },
        },
      },
    },
    suggested_experiment: {
      anyOf: [
        { type: "null" },
        {
          type: "object",
          additionalProperties: false,
          required: ["id", "reason"],
          properties: {
            id: { type: "string", enum: [...EXPERIMENTS] },
            reason: { type: "string" },
          },
        },
      ],
    },
  },
};

type InsightOutput = {
  insight_title: string;
  insight_body: string;
  evidence: { label: string; value: string }[];
  chart_series: {
    type: "bar" | "line";
    y_label: string;
    points: { x: string; y: number; highlight: boolean }[];
  };
  confidence: "low" | "medium" | "high";
  week_forecast: { date: string; risk: "low" | "med" | "high"; reason: string }[];
  suggested_experiment: { id: string; reason: string } | null;
};

const anthropic = new Anthropic({ apiKey: Deno.env.get("ANTHROPIC_API_KEY") });

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  // 1. Who is calling? (The JWT is verified by the Supabase gateway.)
  const authHeader = req.headers.get("Authorization") ?? "";
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const userClient = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) return json({ error: "unauthorized" }, 401);

  const admin = createClient(supabaseUrl, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: participant } = await admin
    .from("participants")
    .select("id")
    .eq("auth_user_id", userData.user.id)
    .maybeSingle();
  if (!participant) return json({ error: "not_enrolled" }, 403);

  // 2. Simple cost guard.
  const since = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
  const { count } = await admin
    .from("insights")
    .select("id", { count: "exact", head: true })
    .eq("participant_id", participant.id)
    .gte("created_at", since);
  if ((count ?? 0) >= MAX_INSIGHTS_PER_DAY) return json({ error: "rate_limited" }, 429);

  // 3. Read the summary (kept in memory only).
  const raw = await req.text();
  if (raw.length > MAX_PAYLOAD_BYTES) return json({ error: "payload_too_large" }, 413);
  let summary: { week_start?: string; upcoming?: { date: string }[] };
  try {
    summary = JSON.parse(raw);
  } catch {
    return json({ error: "bad_json" }, 400);
  }
  const weekStart = typeof summary.week_start === "string" ? summary.week_start : null;
  if (!weekStart || !/^\d{4}-\d{2}-\d{2}$/.test(weekStart)) return json({ error: "bad_week_start" }, 400);

  // 4. Ask Claude.
  let output: InsightOutput;
  try {
    // `fallbacks: "default"` re-runs a request declined by a safety classifier
    // on Anthropic's recommended fallback model instead of failing.
    const params = {
      model: MODEL,
      max_tokens: 16000,
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      output_config: {
        effort: "medium",
        format: { type: "json_schema", schema: OUTPUT_SCHEMA },
      },
      system: SYSTEM_PROMPT,
      messages: [{ role: "user", content: raw }],
    };
    const message: { stop_reason: string | null; content: { type: string; text?: string }[] } =
      // deno-lint-ignore no-explicit-any
      await anthropic.beta.messages.create(params as any);
    if (message.stop_reason === "refusal") return json({ error: "declined" }, 502);
    if (message.stop_reason === "max_tokens") return json({ error: "truncated" }, 502);
    const text = message.content.find((b) => b.type === "text")?.text;
    if (!text) return json({ error: "empty_response" }, 502);
    output = JSON.parse(text) as InsightOutput;
  } catch (err) {
    if (err instanceof Anthropic.RateLimitError) return json({ error: "busy" }, 503);
    if (err instanceof Anthropic.APIError) {
      console.error("claude_api_error", err.status);
      return json({ error: "upstream" }, 502);
    }
    console.error("insight_failed", (err as Error).name);
    return json({ error: "internal" }, 500);
  }

  // 5. Keep only what the app expects.
  const upcomingDates = new Set((summary.upcoming ?? []).map((d) => d.date));
  output.week_forecast = output.week_forecast.filter((d) => upcomingDates.has(d.date));
  if (output.suggested_experiment && !EXPERIMENTS.includes(output.suggested_experiment.id as typeof EXPERIMENTS[number])) {
    output.suggested_experiment = null;
  }

  // 6. Store the generated text only (no evidence numbers, no chart, no summary).
  const { data: stored, error: insertError } = await admin
    .from("insights")
    .insert({
      participant_id: participant.id,
      week_start: weekStart,
      title: output.insight_title,
      body: output.insight_body,
      confidence: output.confidence,
      suggested_experiment: output.suggested_experiment?.id ?? null,
      model: MODEL,
    })
    .select("id")
    .single();
  if (insertError || !stored) {
    console.error("insight_insert_failed");
    return json({ error: "internal" }, 500);
  }

  return json({ id: stored.id, week_start: weekStart, ...output });
});

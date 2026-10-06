#!/usr/bin/env bash
# Exports the trial results to CSV files in ./results/.
#
# Usage:
#   export DATABASE_URL="postgresql://postgres:[PASSWORD]@db.[PROJECT-REF].supabase.co:5432/postgres"
#   ./scripts/export_results.sh
#
# Find the connection string in Supabase: Project Settings > Database > Connection string (URI).
set -euo pipefail

: "${DATABASE_URL:?Set DATABASE_URL to your Supabase Postgres connection string}"
out="results/$(date +%Y-%m-%d)"
mkdir -p "$out"

export_query() {
  local name="$1" query="$2"
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "\\copy (${query}) to '${out}/${name}.csv' with csv header"
  echo "wrote ${out}/${name}.csv"
}

export_query participant_summary "select * from admin.participant_summary"
export_query trial_summary       "select * from admin.trial_summary"
export_query insight_feedback    "select * from admin.insight_feedback"
export_query survey_answers      "select p.invite_code as participant, s.survey, s.question_id, s.answer, s.answered_at from public.survey_answers s join public.participants p on p.id = s.participant_id order by 1, 2, 3"
export_query events              "select p.invite_code as participant, e.name, e.properties, e.occurred_at, e.local_date from public.events e join public.participants p on p.id = e.participant_id order by 1, e.occurred_at"

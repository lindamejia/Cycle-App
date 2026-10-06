-- Cycle trial MVP: schema, row-level security, RPCs and admin views.
-- Run once in the Supabase SQL editor (or `supabase db push`).
--
-- Data rules (from the brief):
--   * Raw health data never reaches this database. The weekly summary sent for
--     analysis passes through the Edge Function and is NOT stored.
--   * Stored: participants (pseudonymous invite code), analytics events,
--     survey answers and the generated insight text.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table public.invite_codes (
  code        text primary key check (code = upper(code)),
  cohort      text not null default 'pilot',
  created_at  timestamptz not null default now()
);
comment on table public.invite_codes is
  'One code per tester. Never put names here; keep the code-to-person mapping offline.';

create table public.participants (
  id               uuid primary key default gen_random_uuid(),
  invite_code      text not null unique references public.invite_codes(code),
  auth_user_id     uuid unique references auth.users(id) on delete set null,
  enrolled_at      timestamptz not null default now(),
  consent_version  text,
  consent_at       timestamptz,
  locale           text,
  app_version      text
);

create table public.events (
  id               bigint generated always as identity primary key,
  participant_id   uuid not null references public.participants(id) on delete cascade,
  client_event_id  uuid not null unique,          -- makes client retries idempotent
  name             text not null check (name in (
                     'app_open','screen_view','insight_viewed','insight_feedback',
                     'energy_checkin','notification_opened',
                     'experiment_offered','experiment_started','experiment_checkin','experiment_completed',
                     'paywall_shown','paywall_subscribe_tap','paywall_dismiss',
                     'survey_answer','data_deleted')),
  properties       jsonb not null default '{}'::jsonb,
  occurred_at      timestamptz not null,
  local_date       date not null,                 -- tester's local calendar date
  received_at      timestamptz not null default now()
);
create index events_participant_name_idx on public.events (participant_id, name);

create table public.survey_answers (
  id              bigint generated always as identity primary key,
  participant_id  uuid not null references public.participants(id) on delete cascade,
  survey          text not null check (survey in ('intake','day21')),
  question_id     text not null,
  answer          text not null check (char_length(answer) <= 2000),
  answered_at     timestamptz not null default now(),
  unique (participant_id, survey, question_id)
);

create table public.insights (
  id                    uuid primary key default gen_random_uuid(),
  participant_id        uuid not null references public.participants(id) on delete cascade,
  week_start            date not null,
  title                 text not null,
  body                  text not null,
  confidence            text,
  suggested_experiment  text,
  model                 text,
  created_at            timestamptz not null default now()
);
create index insights_participant_idx on public.insights (participant_id, created_at desc);

-- Anonymous count of "delete all my data" so drop-outs stay visible after erasure.
create table public.deletion_log (
  id             bigint generated always as identity primary key,
  deleted_at     timestamptz not null default now(),
  days_enrolled  int
);

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------

alter table public.invite_codes   enable row level security;
alter table public.participants   enable row level security;
alter table public.events         enable row level security;
alter table public.survey_answers enable row level security;
alter table public.insights       enable row level security;
alter table public.deletion_log   enable row level security;

create or replace function public.current_participant_id()
returns uuid
language sql stable security definer
set search_path = public
as $$
  select id from public.participants where auth_user_id = auth.uid()
$$;

-- invite_codes, deletion_log: no policies -> no client access at all.

create policy participants_select_own on public.participants
  for select to authenticated using (auth_user_id = auth.uid());

create policy events_insert_own on public.events
  for insert to authenticated with check (participant_id = public.current_participant_id());
-- Needed for the app's idempotent insert (ON CONFLICT DO NOTHING); only own rows are visible.
create policy events_select_own on public.events
  for select to authenticated using (participant_id = public.current_participant_id());

create policy insights_select_own on public.insights
  for select to authenticated using (participant_id = public.current_participant_id());

-- survey_answers are written through submit_survey_answer() only.
-- insights are written by the Edge Function with the service role.

-- ---------------------------------------------------------------------------
-- RPCs called by the app
-- ---------------------------------------------------------------------------

-- Links the current anonymous user to an invite code. If the code was already
-- used (tester reinstalled the app), the participant is re-linked to the new
-- anonymous user so their history continues.
create or replace function public.redeem_invite(
  p_code text, p_locale text, p_app_version text, p_consent_version text, p_consent_at timestamptz)
returns table (participant_id uuid, invite_code text, enrolled_at timestamptz)
language plpgsql security definer
set search_path = public
as $$
declare
  v_code text := upper(trim(p_code));
  v_uid  uuid := auth.uid();
  v_pid  uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  if not exists (select 1 from public.invite_codes c where c.code = v_code) then
    raise exception 'invalid_code';
  end if;

  select p.id into v_pid from public.participants p where p.invite_code = v_code;

  if v_pid is null then
    insert into public.participants (invite_code, auth_user_id, consent_version, consent_at, locale, app_version)
    values (v_code, v_uid, p_consent_version, p_consent_at, p_locale, p_app_version)
    returning id into v_pid;
  else
    update public.participants p
       set auth_user_id = v_uid,
           consent_version = p_consent_version,
           consent_at = p_consent_at,
           locale = p_locale,
           app_version = p_app_version
     where p.id = v_pid;
  end if;

  return query
    select p.id, p.invite_code, p.enrolled_at from public.participants p where p.id = v_pid;
end;
$$;

create or replace function public.submit_survey_answer(p_survey text, p_question_id text, p_answer text)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_pid uuid := public.current_participant_id();
begin
  if v_pid is null then
    raise exception 'not_enrolled';
  end if;
  insert into public.survey_answers (participant_id, survey, question_id, answer)
  values (v_pid, p_survey, p_question_id, left(p_answer, 2000))
  on conflict (participant_id, survey, question_id)
  do update set answer = excluded.answer, answered_at = now();
end;
$$;

-- "Delete all my data": removes the participant (events, survey answers and
-- insights cascade) and the anonymous auth user. Leaves one anonymous row in
-- deletion_log with no identifier.
create or replace function public.delete_my_data()
returns void
language plpgsql security definer
set search_path = public, auth
as $$
declare
  v_uid uuid := auth.uid();
  v_pid uuid := public.current_participant_id();
  v_days int;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  if v_pid is not null then
    select greatest(0, (now()::date - p.enrolled_at::date)) into v_days
      from public.participants p where p.id = v_pid;
    insert into public.deletion_log (days_enrolled) values (v_days);
    delete from public.participants where id = v_pid;
  end if;
  delete from auth.users where id = v_uid;
end;
$$;

revoke all on function public.redeem_invite(text, text, text, text, timestamptz) from public, anon;
revoke all on function public.submit_survey_answer(text, text, text) from public, anon;
revoke all on function public.delete_my_data() from public, anon;
revoke all on function public.current_participant_id() from public, anon;
grant execute on function public.redeem_invite(text, text, text, text, timestamptz) to authenticated;
grant execute on function public.submit_survey_answer(text, text, text) to authenticated;
grant execute on function public.delete_my_data() to authenticated;
grant execute on function public.current_participant_id() to authenticated;

-- ---------------------------------------------------------------------------
-- Admin views (schema `admin` is not exposed through the API; query them in the
-- SQL editor or with psql using the database password).
-- ---------------------------------------------------------------------------

create schema if not exists admin;
revoke all on schema admin from public, anon, authenticated;

create or replace view admin.participant_summary as
with
p as (
  select id, invite_code, enrolled_at, locale from public.participants
),
ev as (
  select e.*, p.enrolled_at,
         floor(extract(epoch from (e.occurred_at - p.enrolled_at)) / 604800)::int + 1 as trial_week
    from public.events e join p on p.id = e.participant_id
),
last_feedback as (   -- latest Useful/Not useful tap per insight
  select distinct on (participant_id, properties->>'insight_id')
         participant_id, properties->>'value' as value
    from public.events
   where name = 'insight_feedback'
   order by participant_id, properties->>'insight_id', occurred_at desc, id desc
),
surveys as (
  select participant_id,
         max(answer) filter (where survey = 'intake' and question_id = 'age_range')      as age_range,
         max(answer) filter (where survey = 'intake' and question_id = 'cycle_status')   as cycle_status,
         max(answer) filter (where survey = 'intake' and question_id = 'changed_plans')  as changed_plans,
         max(answer) filter (where survey = 'intake' and question_id = 'tried_change')   as tried_change,
         max(answer) filter (where survey = 'intake' and question_id = 'focus')          as focus,
         max(answer) filter (where survey = 'day21'  and question_id = 'most_useful_insight') as most_useful_insight,
         max(answer) filter (where survey = 'day21'  and question_id = 'disappointment') as disappointment,
         max(answer) filter (where survey = 'day21'  and question_id = 'worth_paying_for') as worth_paying_for
    from public.survey_answers group by participant_id
)
select
  p.invite_code                                                       as participant,
  p.enrolled_at::date                                                 as enrolled_on,
  p.locale,
  (current_date - p.enrolled_at::date) + 1                            as trial_day,
  (select count(distinct local_date) from ev where ev.participant_id = p.id and ev.name = 'app_open') as days_active,
  (select count(*) from ev where ev.participant_id = p.id and ev.name = 'app_open')                   as total_opens,
  round((select count(*) from ev where ev.participant_id = p.id and ev.name = 'app_open')::numeric
        / greatest(1, ceil(((current_date - p.enrolled_at::date) + 1) / 7.0)), 1)                     as weekly_opens,
  (select count(*) from ev where ev.participant_id = p.id and ev.name = 'app_open' and trial_week = 1) as opens_week1,
  (select count(*) from ev where ev.participant_id = p.id and ev.name = 'app_open' and trial_week = 2) as opens_week2,
  (select count(*) from ev where ev.participant_id = p.id and ev.name = 'app_open' and trial_week = 3) as opens_week3,
  (select count(distinct properties->>'insight_id') from ev where ev.participant_id = p.id and ev.name = 'insight_viewed') as insights_viewed,
  (select count(*) from last_feedback f where f.participant_id = p.id)                                as insights_rated,
  (select round(100.0 * count(*) filter (where value = 'useful') / nullif(count(*), 0))
     from last_feedback f where f.participant_id = p.id)                                              as pct_useful,
  (select count(*) from ev where ev.participant_id = p.id and ev.name = 'energy_checkin')             as energy_checkins,
  (select count(*) from ev where ev.participant_id = p.id and ev.name = 'notification_opened')        as notifications_opened,
  exists (select 1 from ev where ev.participant_id = p.id and ev.name = 'experiment_started')         as experiment_started,
  (select count(*) from ev where ev.participant_id = p.id and ev.name = 'experiment_checkin')         as experiment_checkins,
  exists (select 1 from ev where ev.participant_id = p.id and ev.name = 'experiment_completed')       as experiment_finished,
  exists (select 1 from ev where ev.participant_id = p.id and ev.name = 'paywall_shown')              as paywall_shown,
  exists (select 1 from ev where ev.participant_id = p.id and ev.name = 'paywall_subscribe_tap')      as paywall_subscribe_tap,
  exists (select 1 from ev where ev.participant_id = p.id and ev.name = 'paywall_dismiss')            as paywall_dismissed,
  s.disappointment,
  s.most_useful_insight,
  s.worth_paying_for,
  s.age_range, s.cycle_status, s.changed_plans, s.tried_change, s.focus,
  (select max(occurred_at) from ev where ev.participant_id = p.id)                                    as last_seen
from p
left join surveys s on s.participant_id = p.id
order by p.enrolled_at;

-- Headline numbers for the whole cohort.
create or replace view admin.trial_summary as
select
  count(*)                                                          as participants,
  round(avg(days_active), 1)                                        as avg_days_active,
  count(*) filter (where opens_week3 > 0)                           as active_in_week3,
  round(avg(pct_useful))                                            as avg_pct_useful,
  count(*) filter (where experiment_started)                        as started_experiment,
  count(*) filter (where experiment_finished)                       as finished_experiment,
  count(*) filter (where paywall_shown)                             as saw_paywall,
  count(*) filter (where paywall_subscribe_tap)                     as tapped_subscribe,
  count(*) filter (where disappointment = 'very')                   as very_disappointed,
  (select count(*) from public.deletion_log)                        as deleted_their_data
from admin.participant_summary;

-- Insight text with its feedback, for reading what worked.
create or replace view admin.insight_feedback as
select p.invite_code as participant, i.week_start, i.title, i.body, i.confidence,
       i.suggested_experiment,
       (select e.properties->>'value' from public.events e
         where e.name = 'insight_feedback' and e.properties->>'insight_id' = i.id::text
         order by e.occurred_at desc, e.id desc limit 1) as feedback
  from public.insights i join public.participants p on p.id = i.participant_id
 order by p.invite_code, i.week_start;

revoke all on all tables in schema admin from public, anon, authenticated;

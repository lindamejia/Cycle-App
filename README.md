# Cycle App: 3-week trial MVP

Native iPhone app (SwiftUI, iOS 17+, English and Spanish) that passively reads Apple Health and the
calendar, writes one weekly AI insight, offers one 10-day experiment, and ends with a day-21 survey
and a fake-door €8/month paywall. Backend is Supabase (anonymous auth, 4 tables with row-level
security, one Edge Function that calls Claude).

```
  ios/
    Cycle.xcodeproj         Xcode 16+ project (folder-synced: new files in ios/Cycle are picked up automatically)
    project.yml             XcodeGen fallback, only if the .xcodeproj won't open
    Cycle/
      App/                  entry point, AppDelegate (notification actions), AppModel (all state + actions)
      Core/                 Config.swift (fill in), models, persistence, dates, localization helper
      Data/                 HealthKit, EventKit, demo data, cycle estimate, feature rows, forecast, weekly summary, experiment maths
      Backend/              Supabase client, analytics queue, insight call, notification scheduler
      Design/               monochrome design system, chart
      Views/                Onboarding, Today, Insights, Experiment, Settings, Day-21 survey + paywall
      Resources/            en.lproj / es.lproj strings
  supabase/
    migrations/…_init.sql   schema, RLS, RPCs, admin views
    seed_invite_codes.sql   creates 20 invite codes
    functions/weekly-insight/index.ts
  scripts/export_results.sh CSV export of the trial results
```

## What has and hasn't been checked

- The SQL migration was applied to a local Postgres 16 with Supabase-style `auth` stubs, and the
  RPCs, row-level security, admin views, re-install re-linking, delete-all and the CSV export
  script were exercised against it.
- The Edge Function type-checks with TypeScript (strict) against the current Anthropic and
  Supabase JS SDKs. It has not been called against the real Claude API yet.
- The Swift code parses cleanly and every localization key exists in both languages with matching
  placeholders, but it was written on Linux: **it has not been compiled in Xcode yet.** Expect a
  few compiler fixes on the first build.

## 1. Run it in the simulator (demo mode)

1. Open `ios/Cycle.xcodeproj` in Xcode 16 or newer.
2. Pick an iPhone simulator and press Run.
3. On the first screen tap **Try demo mode with sample data**. You land on trial day 10 with
   90 days of realistic data, three weekly insights, the experiment screen unlocked, and
   Settings > Demo > **Preview the day-21 screens** to see the survey and paywall.

Demo mode keeps its data separate from real data, never calls the backend and sends no analytics.
Switch it off in Settings to go back to the real onboarding.

## 2. Set up Supabase

1. Create a project at supabase.com. Choose an **EU region** (testers are in the EU).
2. Authentication > Sign In / Providers: turn on **Allow anonymous sign-ins**.
3. SQL editor: paste and run `supabase/migrations/20261006000000_init.sql`.
4. SQL editor: run `supabase/seed_invite_codes.sql`. Copy the 20 codes into your own offline
   sheet with who gets which. Names never go into the database.
5. Deploy the Edge Function with the Supabase CLI:
   ```sh
   supabase login
   supabase link --project-ref YOUR-PROJECT-REF
   supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
   supabase functions deploy weekly-insight
   ```
   The Claude API key lives only in Supabase secrets, never in the app. The function uses
   `claude-sonnet-5-5`, structured JSON output, and `fallbacks: "default"` so a request declined by
   a safety classifier is retried on Anthropic's recommended fallback model instead of failing.
   It allows at most 3 insights per tester per day.

## 3. Configure the app

1. `ios/Cycle/Core/Config.swift`: set `supabaseURL` and `supabaseAnonKey` (Project Settings > API),
   and `privacyPolicyURL`. The anon key is safe to ship; RLS protects the data.
2. Target > Signing & Capabilities: choose your Team, change the bundle identifier from
   `com.example.cycle`, and check that **HealthKit** is listed (the entitlements file is already
   there; Xcode registers the App ID capability when you pick the team).
3. Run on a real iPhone (HealthKit has no real data in the simulator). Enter an invite code,
   allow Health and Calendar, answer the 4 questions. The first insight appears within a minute.

## 4. TestFlight

1. In App Store Connect, create the app with the same bundle ID. Fill in the privacy policy URL
   and App Privacy answers (health data, product interaction; not linked to identity; no tracking).
2. Xcode: set the destination to *Any iOS Device*, Product > Archive, then Distribute App >
   App Store Connect > Upload.
3. In TestFlight, add the build to an **external** testing group (testers don't need App Store
   Connect accounts). External builds go through a short Beta App Review first. In the review
   notes, say it's a 3-week research trial, give one invite code for the reviewer, and explain
   that the day-21 "Subscribe" button is a fake door that takes no payment and says so.
4. Send each tester the public TestFlight link plus their own invite code.

Each new build needs a higher build number (`CURRENT_PROJECT_VERSION`). Local data survives
updates.

## 5. Export the trial results

Three views in the `admin` schema (not reachable through the API):

- `admin.participant_summary`: one row per tester: days active, total and weekly opens, opens in
  weeks 1/2/3, insights viewed and rated, % useful, energy check-ins, notifications opened,
  experiment started/finished, paywall shown/subscribe tap/dismiss, day-21 answers, intake answers.
- `admin.trial_summary`: cohort totals (active in week 3, tapped subscribe, very disappointed,
  deletions).
- `admin.insight_feedback`: every generated insight with its Useful / Not useful rating.

For CSV, either run `select * from admin.participant_summary` in the SQL editor and use its
CSV download, or run:

```sh
export DATABASE_URL="postgresql://postgres:PASSWORD@db.PROJECT-REF.supabase.co:5432/postgres"
./scripts/export_results.sh   # writes results/<date>/*.csv
```

## How it works

**Data flow.** On every app open the app reads 90 days of HealthKit (sleep, HRV, resting HR,
steps, active energy, workouts, wrist temperature, menstrual flow) and EventKit (title, start, end,
all-day; declined and cancelled events skipped), and builds one feature row per day on device.
Nothing raw is stored on the server.

**Weekly insight.** From Monday 08:00 local time, the next app open sends the last 8 weeks of
feature rows to the Edge Function: dates only, rounded numbers, event titles deduplicated into an
id table, time of day as morning/afternoon/evening/late, plus exact on-device statistics (by cycle
phase, by sleep length, by calendar load) so the model cites real numbers. Claude classifies the
event titles, writes one insight of 60 words or fewer with evidence and a chart series, a 7-day
forecast and one suggested experiment. The function stores only the title, body, confidence and
suggested experiment id; the summary is never written to the database or logs. The first insight
is generated right after onboarding.

**Today forecast.** Computed on device from last night's sleep, HRV and resting HR against her own
28-day baseline, cycle phase, and today's calendar (for example "Likely a lower-energy day: 6h
sleep, late luteal phase, 4 events"). The AI's 7-day forecast drives the week strip and the
day-before heads-up.

**Cycle.** Period starts come from Apple Health flow data (or its cycle-start marker), otherwise
from the onboarding answers plus the "My period started" button. Phase is estimated from cycle
length: menstrual days 1-5, ovulation around length minus 14, late luteal the last 5 days. With
hormonal birth control or no period, no phase is shown.

**Notifications.** At most 4 a week (Monday to Sunday), scheduled for two weeks ahead and
recomputed on each open. Priority when there are more candidates than slots: Monday insight,
heads-up before a high-risk day, experiment check-in, evening energy tap. Energy and experiment
notifications have buttons and save without opening the app.

**Experiments.** Unlocked on trial day 8. One active at a time, 10 days, one yes/no a day. The
result compares the 14 days before with the "yes" days (sleep and HRV from the next morning,
energy from the same evening). It needs at least 4 days on each side, and calls a difference
clear only if it is at least half a standard deviation of the baseline and above a minimum (15
minutes of sleep, 3 ms HRV, 0.3 energy points). Otherwise it says "Not enough difference to tell
yet".

**Analytics.** Events are queued on device and sent in batches with a client id so retries never
double count. The participant is identified only by the invite code. `data_deleted` is recorded
as an anonymous row in `deletion_log`, because the participant's events are erased with
everything else.

**Delete all my data** calls `delete_my_data()`, which removes the participant, their events,
survey answers and insights, and the anonymous auth user, then wipes every local file. If the
server can't be reached, the tester can choose to delete on the phone only.

## Defaults chosen where the brief was silent

- The invite code is entered in onboarding, right after consent.
- Day 21 shows the survey first, then the paywall. After that the app keeps working normally.
- Experiments open on day 8; after one finishes, another can be started.
- Spanish copy uses tú and feminine forms ("decepcionada").
- Notifications: a strict cap of 4 a week including energy taps and experiment check-ins (decided by Isamar). Experiment check-ins can always be answered in the app.

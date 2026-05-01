# Supabase Setup

The app uses Supabase for account auth and remote record sync.

## Project

- URL: `https://fzgoupebkrkjebogqmtb.supabase.co`
- Redirect URL: `com.albertc.habit://auth-callback`
- App URL scheme: `com.albertc.habit`
- iOS bundle ID: `com.albertc.habit`
- macOS bundle ID: `com.albertc.habit.mac`

The publishable key is stored in `SupabaseConfiguration`. This is safe to ship in the app; table access must be protected with Row Level Security.

## Auth

Enable these providers in Supabase Auth:

- Apple
- Google

Add `com.albertc.habit://auth-callback` to the Supabase Auth redirect allow list. The app uses native identity-token sign-in for Apple and Google, but the callback scheme remains registered so Supabase auth URLs can be handled if a provider flow needs one.

### Google (native)

Two OAuth clients are required in Google Cloud Console under the same project for the current checked-in configuration:

- **iOS client** (type: iOS, bundle ID `com.albertc.habit`) drives the native sign-in sheet. Its reverse-DNS form is registered as a `CFBundleURLSchemes` entry in `project.yml`.
- **Web client** is set as `serverClientID` on `GIDConfiguration` so the issued `idToken` audience matches the Web client. The Web client ID + secret are configured in Supabase Dashboard -> Auth -> Providers -> Google.

In Supabase Dashboard -> Auth -> Providers -> Google, add the iOS client ID to the "Authorized Client IDs" list so Supabase accepts ID tokens issued for the iOS client.

The native macOS app currently uses the same Google native client ID and reverse-client URL scheme as iOS. If Google Cloud rejects that for the separate Mac bundle ID, create an additional native client for `com.albertc.habit.mac`, add that client ID to Supabase's authorized client IDs, update `SupabaseConfiguration` to select the Mac client ID under `#if os(macOS)`, and add the Mac reverse-client URL scheme to the `HabitsMac` URL schemes in `project.yml`.

### Apple (native)

For native Apple sign-in, Supabase needs the app bundle IDs registered as Apple client IDs:

```text
com.albertc.habit
com.albertc.habit.mac
```

Keep the web Services ID and generated client secret only if a web app will also support Continue with Apple:

```text
com.albertc.habit.web
```

## Remote Sync Tables

The alpha database is resettable and is defined by [`supabase/schema.sql`](../supabase/schema.sql). It drops and recreates the record sync tables, indexes, triggers, and RLS policies for:

- `habits`
- `habit_completions`
- `things`

Apply it to the linked Supabase project from the repo root:

```bash
supabase db query --linked --file supabase/schema.sql
```

Force Sync uses the per-record tables. Sync pushes local dirty rows before pulling remote rows, resolves conflicts with per-row last-writer-wins by server `updated_at`, and keeps local/remote tombstones through `deleted_at`. Debounced and retry pushes capture the signed-in user ID when scheduled and are cancelled on sign-out so stale work cannot push rows into a later account session. Pulls apply remote pages against local lookup maps instead of refetching full tables per row. A pulled completion is only inserted when its parent habit is already local or can be fetched for the same user; the schema also enforces `(user_id, habit_id)` against `habits(user_id, id)`. The schema validates habit names, frequency/custom interval fields, goals, reminder times, thing titles, and thing completion state; invalid remote habit rows are rejected by the client instead of being silently coerced.

After a Thing has been acknowledged remotely, local title, due-date, completion, and deletion edits are tracked separately so a later rename does not clear a completion made on another device. New unsynced Things always send a full row, even if field-level dirty markers exist, so the database `is_completed`/`completed_at` check has a complete state. Acknowledged Things with only selected local field edits use `UPDATE` instead of sparse `UPSERT`, because Postgres still validates required insert columns such as `title` before conflict handling. The client does not send `updated_at` on push; Supabase triggers set it and returned rows are the source of truth. SQL `date` columns are encoded and decoded as `yyyy-MM-dd`, while `timestamptz` columns use ISO timestamps. Nullable columns are sent as explicit `null` when cleared so PostgREST writes do not retain stale values. `habit_completions` is one aggregate row per habit period; conflicting counter updates use LWW rather than sum/max. Replacing local data with account data snapshots the visible local data first and restores it if the remote pull fails after local deletion.

## Delete Account Edge Function

The iOS app calls `DELETE /functions/v1/delete-account` with the signed-in user's Supabase access token:

```http
Authorization: Bearer <access token>
```

The function derives the user ID from that JWT using Supabase Auth. It does not accept a user ID in the request body. On success it deletes rows for the authenticated user from:

- `habit_completions`
- `habits`
- `things`

It then hard-deletes the Auth user with Supabase admin deletion and returns:

```json
{ "deleted": true }
```

The implementation lives at `supabase/functions/delete-account/index.ts`.

### Required secret

`SUPABASE_SERVICE_ROLE_KEY` must be available to the Edge Function. Hosted Supabase Edge Functions normally expose this default secret automatically; confirm it is present in Dashboard -> Edge Functions -> Secrets, or set it explicitly if your environment does not provide it. Do not put this key in the iOS app.

```bash
supabase secrets set SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
```

`SUPABASE_URL` is provided automatically by Supabase Edge Functions.

### Deploy

From the repo root, link the Supabase project if needed, then deploy:

```bash
supabase link --project-ref fzgoupebkrkjebogqmtb
supabase functions deploy delete-account
```

### Manual verification

Sign into the app or otherwise obtain a valid user access token, then call:

```bash
curl -i -X DELETE \
  "https://fzgoupebkrkjebogqmtb.supabase.co/functions/v1/delete-account" \
  -H "Authorization: Bearer <access-token>"
```

Expected success:

```json
{ "deleted": true }
```

Expected error responses are JSON with HTTP `401`, `405`, or `500`.

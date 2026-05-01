begin;

drop table if exists public.habit_completions;
drop table if exists public.habits;
drop table if exists public.things;
drop table if exists public.sync_migrations;
drop table if exists public.habit_backups;
drop function if exists public.set_sync_updated_at();

create function public.set_sync_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table public.habits (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  frequency text not null,
  custom_interval_value int,
  custom_interval_unit text,
  times_to_complete int not null check (times_to_complete >= 1),
  start_date date not null,
  notifications_enabled bool not null,
  notification_hour int check (notification_hour is null or notification_hour between 0 and 23),
  notification_minute int check (notification_minute is null or notification_minute between 0 and 59),
  created_at timestamptz not null,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  client_id uuid not null,
  check (char_length(btrim(name)) between 1 and 100 and char_length(name) <= 100),
  check (frequency in ('Daily', 'Weekly', 'Monthly', 'Yearly', 'Custom')),
  check (times_to_complete between 1 and 9999),
  check (
    (
      frequency = 'Custom'
      and custom_interval_value between 1 and 365
      and custom_interval_unit in ('Days', 'Weeks', 'Months')
    )
    or (
      frequency <> 'Custom'
      and custom_interval_value is null
      and custom_interval_unit is null
    )
  )
);

alter table public.habits add constraint habits_user_id_id_unique unique (user_id, id);

create table public.things (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  due_date date not null,
  is_completed bool not null,
  completed_at timestamptz,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  client_id uuid not null,
  check (char_length(btrim(title)) between 1 and 400 and char_length(title) <= 400),
  check ((is_completed and completed_at is not null) or (not is_completed and completed_at is null))
);

create table public.habit_completions (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  habit_id uuid not null,
  period_start date not null,
  date timestamptz not null,
  count int not null check (count >= 0),
  created_at timestamptz not null,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  client_id uuid not null,
  foreign key (user_id, habit_id) references public.habits(user_id, id) on delete cascade,
  unique (user_id, habit_id, period_start)
);

create index habits_sync_cursor_idx on public.habits (user_id, updated_at, id);
create index habit_completions_sync_cursor_idx on public.habit_completions (user_id, updated_at, id);
create index things_sync_cursor_idx on public.things (user_id, updated_at, id);

create trigger set_habits_updated_at
before insert or update on public.habits
for each row execute function public.set_sync_updated_at();

create trigger set_habit_completions_updated_at
before insert or update on public.habit_completions
for each row execute function public.set_sync_updated_at();

create trigger set_things_updated_at
before insert or update on public.things
for each row execute function public.set_sync_updated_at();

alter table public.habits enable row level security;
alter table public.habit_completions enable row level security;
alter table public.things enable row level security;

create policy "Users can select own habits"
on public.habits for select to authenticated
using (auth.uid() = user_id);

create policy "Users can insert own habits"
on public.habits for insert to authenticated
with check (auth.uid() = user_id);

create policy "Users can update own habits"
on public.habits for update to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy "Users can select own habit completions"
on public.habit_completions for select to authenticated
using (auth.uid() = user_id);

create policy "Users can insert own habit completions"
on public.habit_completions for insert to authenticated
with check (auth.uid() = user_id);

create policy "Users can update own habit completions"
on public.habit_completions for update to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy "Users can select own things"
on public.things for select to authenticated
using (auth.uid() = user_id);

create policy "Users can insert own things"
on public.things for insert to authenticated
with check (auth.uid() = user_id);

create policy "Users can update own things"
on public.things for update to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

commit;

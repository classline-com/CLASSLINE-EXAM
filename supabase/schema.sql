-- CLASSLINE EXAM: initial Supabase schema
-- Important: Telegram initData must be verified by a trusted Edge Function.
-- Do not put the Telegram bot token or Supabase service_role key in browser code.
-- All tables have RLS enabled and intentionally have no public/anon policies.
-- Access should be mediated by authenticated Edge Functions using server-side credentials.

create extension if not exists pgcrypto;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists public.profiles (
  id uuid primary key default gen_random_uuid(),
  telegram_user_id bigint not null unique,
  telegram_username text,
  first_name text,
  last_name text,
  role text not null default 'student' check (role in ('student','admin')),
  created_at timestamptz not null default now()
);

create table if not exists public.exams (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  status text not null default 'draft'
    check (status in ('draft','scheduled','live','closed','results_published','cancelled')),
  starts_at timestamptz,
  ends_at timestamptz,
  results_publish_at timestamptz,
  negative_marking boolean not null default true,
  total_questions integer not null default 0 check (total_questions >= 0),
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at is null or starts_at is null or ends_at > starts_at)
);

create table if not exists public.exam_subjects (
  id uuid primary key default gen_random_uuid(),
  exam_id uuid not null references public.exams(id) on delete cascade,
  title text not null,
  question_count integer not null default 0 check (question_count >= 0),
  coefficient numeric(8,3) not null default 1 check (coefficient > 0),
  sort_order integer not null default 0,
  unique (exam_id, title)
);

create table if not exists public.questions (
  id uuid primary key default gen_random_uuid(),
  exam_id uuid not null references public.exams(id) on delete cascade,
  subject_id uuid references public.exam_subjects(id) on delete set null,
  question_number integer not null,
  body text not null,
  options jsonb not null,
  image_url text,
  created_at timestamptz not null default now(),
  unique (exam_id, question_number),
  check (jsonb_typeof(options) = 'array' and jsonb_array_length(options) = 4)
);

-- Answer keys are kept outside the exposed public schema.
create table if not exists private.answer_keys (
  question_id uuid primary key references public.questions(id) on delete cascade,
  correct_option smallint not null check (correct_option between 1 and 4),
  explanation text
);

create table if not exists public.exam_attempts (
  id uuid primary key default gen_random_uuid(),
  exam_id uuid not null references public.exams(id) on delete cascade,
  student_id uuid not null references public.profiles(id) on delete cascade,
  started_at timestamptz not null default now(),
  submitted_at timestamptz,
  status text not null default 'in_progress'
    check (status in ('in_progress','submitted','graded','invalidated')),
  correct_count integer,
  wrong_count integer,
  unanswered_count integer,
  raw_score numeric(8,3),
  total_percent numeric(8,3),
  rank integer,
  score_scaled numeric(10,3),
  unique (exam_id, student_id)
);

create table if not exists public.answers (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.exam_attempts(id) on delete cascade,
  question_id uuid not null references public.questions(id) on delete cascade,
  selected_option smallint check (selected_option between 1 and 4),
  answered_at timestamptz not null default now(),
  is_correct boolean,
  unique (attempt_id, question_id)
);

create index if not exists idx_exams_status_start on public.exams(status, starts_at);
create index if not exists idx_attempts_exam_rank on public.exam_attempts(exam_id, rank);
create index if not exists idx_attempts_student on public.exam_attempts(student_id);
create index if not exists idx_answers_attempt on public.answers(attempt_id);

alter table public.profiles enable row level security;
alter table public.exams enable row level security;
alter table public.exam_subjects enable row level security;
alter table public.questions enable row level security;
alter table public.exam_attempts enable row level security;
alter table public.answers enable row level security;
alter table private.answer_keys enable row level security;

-- No client-facing policies are created in this bootstrap migration.
-- Edge Functions must validate Telegram WebApp initData, check role and exam
-- timing, and then read/write data using server-side credentials.
-- Never grant students direct access to private.answer_keys.

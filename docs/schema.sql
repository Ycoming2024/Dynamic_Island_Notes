-- PostgreSQL schema for Notes Bridge MVP

create table users (
  id uuid primary key,
  email varchar(255) unique not null,
  password_hash text,
  display_name varchar(100),
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table devices (
  id uuid primary key,
  user_id uuid not null references users(id) on delete cascade,
  platform varchar(20) not null,
  device_name varchar(100),
  push_token text,
  last_seen_at timestamptz,
  created_at timestamptz not null default now()
);

create table notes (
  id uuid primary key,
  user_id uuid not null references users(id) on delete cascade,
  title varchar(200) not null default '',
  content text not null default '',
  color varchar(20),
  is_pinned boolean not null default false,
  is_archived boolean not null default false,
  is_deleted boolean not null default false,
  version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table reminders (
  id uuid primary key,
  user_id uuid not null references users(id) on delete cascade,
  note_id uuid references notes(id) on delete set null,
  title varchar(200) not null,
  body text,
  due_at timestamptz not null,
  timezone varchar(50) not null default 'Asia/Shanghai',
  repeat_rule varchar(50) not null default 'none',
  status varchar(20) not null default 'pending',
  snooze_until timestamptz,
  is_deleted boolean not null default false,
  version bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

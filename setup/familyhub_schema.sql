-- =====================================================================
--  Family Hub · Supabase 스키마 v1
--  Supabase 대시보드 → SQL Editor → 이 파일 전체를 붙여넣고 [Run] 한 번.
--  여러 번 실행해도 안전합니다 (테이블은 유지, 함수는 최신으로 교체).
--
--  보안 구조
--  · 모든 테이블은 RLS 켜짐 + 정책 없음 → 공개키(anon)로는 테이블을 직접 못 읽음
--  · 앱은 fh_* 함수(RPC)만 호출하고, 함수가 로그인 토큰을 확인한 뒤 필요한 것만 돌려줌
--  · 비밀 메시지 본문은 보낸 사람·받는 사람에게만 돌려줌 (admin 함수에도 없음)
--  · 비밀번호는 bcrypt 단방향 해시로 저장
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_net   with schema extensions;
create extension if not exists pg_cron;

-- ---------------------------------------------------------------- 테이블
create table if not exists public.members (
  id serial primary key,
  name text not null,
  nick text,
  birth date not null,
  role text not null default 'member' check (role in ('admin','member')),
  emoji text not null default '',
  color text not null default '#1e3a5f',
  sort int not null default 0,
  pass_hash text not null,
  must_change boolean not null default true,
  fail_count int not null default 0,
  locked_until timestamptz,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create table if not exists public.sessions (
  token uuid primary key default gen_random_uuid(),
  member_id int not null references public.members(id) on delete cascade,
  ua text,
  created_at timestamptz not null default now(),
  last_seen timestamptz not null default now()
);
create table if not exists public.events (
  id bigserial primary key,
  title text not null,
  day date not null,
  yearly boolean not null default false,
  category text not null default '일정',
  remind int not null default 1,
  memo text,
  created_by int references public.members(id) on delete set null,
  created_at timestamptz not null default now()
);
create table if not exists public.todos (
  id bigserial primary key,
  member_id int not null references public.members(id) on delete cascade,
  day date not null,
  text text not null,
  done boolean not null default false,
  done_at timestamptz,
  sort int not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists todos_md on public.todos(member_id, day);
create table if not exists public.day_logs (
  member_id int not null references public.members(id) on delete cascade,
  day date not null,
  score int check (score between 0 and 100),
  mood text,
  note text,
  updated_at timestamptz not null default now(),
  primary key (member_id, day)
);
create table if not exists public.locations (
  member_id int primary key references public.members(id) on delete cascade,
  lat double precision, lng double precision, acc real,
  updated_at timestamptz,
  status text, status_at timestamptz,
  sharing boolean not null default true
);
create table if not exists public.checkins (
  id bigserial primary key,
  member_id int not null references public.members(id) on delete cascade,
  label text not null,
  lat double precision, lng double precision,
  created_at timestamptz not null default now()
);
create table if not exists public.messages (
  id bigserial primary key,
  from_id int not null references public.members(id) on delete cascade,
  to_id int references public.members(id) on delete cascade,      -- 타임캡슐은 null = 가족 모두
  kind text not null default 'secret' check (kind in ('secret','capsule')),
  body text not null,
  open_on date,
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index if not exists messages_to on public.messages(to_id);
create table if not exists public.posts (
  id bigserial primary key,
  member_id int references public.members(id) on delete set null,
  body text not null default '',
  created_at timestamptz not null default now()
);
create table if not exists public.post_photos (
  id bigserial primary key,
  post_id bigint not null references public.posts(id) on delete cascade,
  data text not null,
  w int, h int, sort int not null default 0
);
create index if not exists post_photos_p on public.post_photos(post_id);
create table if not exists public.comments (
  id bigserial primary key,
  post_id bigint not null references public.posts(id) on delete cascade,
  member_id int references public.members(id) on delete set null,
  body text not null,
  created_at timestamptz not null default now()
);
create table if not exists public.likes (
  post_id bigint not null references public.posts(id) on delete cascade,
  member_id int not null references public.members(id) on delete cascade,
  primary key (post_id, member_id)
);
create table if not exists public.stickers (
  id bigserial primary key,
  from_id int references public.members(id) on delete set null,
  to_id int not null references public.members(id) on delete cascade,
  emoji text not null default '⭐',
  reason text,
  created_at timestamptz not null default now()
);
create table if not exists public.rewards (
  id bigserial primary key,
  title text not null,
  emoji text not null default '',
  cost int not null check (cost > 0),
  active boolean not null default true,
  sort int not null default 0
);
create table if not exists public.redemptions (
  id bigserial primary key,
  member_id int not null references public.members(id) on delete cascade,
  reward_id bigint references public.rewards(id) on delete set null,
  title text not null,
  cost int not null,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  decided_at timestamptz
);
create table if not exists public.point_adjust (
  id bigserial primary key,
  member_id int not null references public.members(id) on delete cascade,
  amount int not null,
  reason text,
  created_at timestamptz not null default now()
);
create table if not exists public.growth (
  id bigserial primary key,
  member_id int not null references public.members(id) on delete cascade,
  day date not null,
  height numeric, weight numeric,
  note text,
  created_by int references public.members(id) on delete set null,
  created_at timestamptz not null default now()
);
create table if not exists public.shopping (
  id bigserial primary key,
  text text not null,
  qty text,
  done boolean not null default false,
  created_by int references public.members(id) on delete set null,
  done_by int references public.members(id) on delete set null,
  created_at timestamptz not null default now(),
  done_at timestamptz
);
create table if not exists public.missions (
  id bigserial primary key,
  title text not null,
  emoji text not null default '🚩',
  unit text not null default '회',
  target numeric not null check (target > 0),
  start_on date not null,
  end_on date not null,
  reward int not null default 0,           -- 달성하면 참여한 가족 모두에게 주는 포인트
  created_by int references public.members(id) on delete set null,
  created_at timestamptz not null default now()
);
create table if not exists public.mission_logs (
  id bigserial primary key,
  mission_id bigint not null references public.missions(id) on delete cascade,
  member_id int not null references public.members(id) on delete cascade,
  amount numeric not null,
  day date not null,
  created_at timestamptz not null default now()
);
create table if not exists public.push_subs (
  endpoint text primary key,
  member_id int not null references public.members(id) on delete cascade,
  p256dh text not null, auth text not null, ua text,
  created_at timestamptz not null default now()
);
create table if not exists public.app_secrets (key text primary key, value text);
create table if not exists public.settings (key text primary key, value jsonb);

alter table public.members add column if not exists photo text;
alter table public.members add column if not exists photo_at timestamptz;
-- 사진 인증 할 일 (아이들 Before·After → 부모가 점수)
alter table public.members add column if not exists is_parent boolean not null default false;
alter table public.todos add column if not exists proof boolean not null default false;
alter table public.todos add column if not exists status text;            -- null / todo / review / approved / rejected
alter table public.todos add column if not exists points int;              -- 부모가 준 점수
alter table public.todos add column if not exists max_points int;
alter table public.todos add column if not exists assigned_by int references public.members(id) on delete set null;
alter table public.todos add column if not exists submitted_at timestamptz;
alter table public.todos add column if not exists reviewed_by int references public.members(id) on delete set null;
alter table public.todos add column if not exists reviewed_at timestamptz;
alter table public.todos add column if not exists review_note text;
create table if not exists public.todo_photos (
  todo_id bigint not null references public.todos(id) on delete cascade,
  kind text not null check (kind in ('before','after')),
  data text not null,
  created_at timestamptz not null default now(),
  primary key (todo_id, kind)
);

insert into public.settings values
  ('points', '{"todo":10,"bonus":20,"bonus_min":3,"todo_cap":10,"sticker":5,"sticker_per_day":3}')
on conflict (key) do nothing;

-- 처음 가족 4명 (비밀번호 = 생일 YYMMDD, 첫 로그인 때 바꾸도록 안내)
insert into public.members (name, nick, birth, role, emoji, color, sort, pass_hash)
select v.name, v.nick, v.birth::date, v.role, v.emoji, v.color, v.sort,
       extensions.crypt(to_char(v.birth::date, 'YYMMDD'), extensions.gen_salt('bf'))
from (values
  ('송진환','songjinhwan','1980-08-26','admin', '','#1d1d1f',1),
  ('김근영','kimkunyoung','1983-06-13','member','','#0071e3',2),
  ('송민하','songminha','2016-05-25','member','','#86868b',3),
  ('송효양','songhyoyang','2021-01-13','member','','#424245',4)
) as v(name, nick, birth, role, emoji, color, sort)
where not exists (select 1 from public.members);

insert into public.rewards (title, emoji, cost, sort)
select * from (values ('주말 게임 30분','',100,1), ('원하는 간식 하나','',150,2), ('용돈 1,000원','',200,3), ('저녁 메뉴 고르기','',250,4)) v
where not exists (select 1 from public.rewards);

-- 가족 여행
create table if not exists public.trips (
  id bigserial primary key,
  title text not null,
  place text,
  country text,
  start_on date not null,
  end_on date not null,
  emoji text not null default '✈️',
  members int[] not null default '{}',
  stay text,
  emergency text,
  memo text,
  currency text not null default 'KRW',
  rate numeric not null default 1,           -- 현지 통화 1 = 원화 얼마
  created_by int references public.members(id) on delete set null,
  created_at timestamptz not null default now()
);
create table if not exists public.trip_items (      -- kind: plan(일정) / pack(준비물)
  id bigserial primary key,
  trip_id bigint not null references public.trips(id) on delete cascade,
  kind text not null check (kind in ('plan','pack')),
  day date, time text,
  title text not null,
  place text, memo text,
  assignee int references public.members(id) on delete set null,
  done boolean not null default false,
  done_by int references public.members(id) on delete set null,
  sort int not null default 0,
  created_by int references public.members(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists trip_items_t on public.trip_items(trip_id, kind);
create table if not exists public.trip_files (      -- 여권·사진·항공권·숙소 등 (여행 멤버만 열람)
  id bigserial primary key,
  trip_id bigint not null references public.trips(id) on delete cascade,
  member_id int references public.members(id) on delete set null,
  kind text not null default 'etc',
  title text,
  data text not null,
  expires_on date,
  created_by int references public.members(id) on delete set null,
  created_at timestamptz not null default now()
);
create table if not exists public.trip_expenses (
  id bigserial primary key,
  trip_id bigint not null references public.trips(id) on delete cascade,
  day date, title text not null, category text not null default '기타',
  amount numeric not null, currency text not null default 'KRW',
  paid_by int references public.members(id) on delete set null,
  created_at timestamptz not null default now()
);
create table if not exists public.trip_msgs (
  id bigserial primary key,
  trip_id bigint not null references public.trips(id) on delete cascade,
  from_id int references public.members(id) on delete set null,
  to_ids int[] not null,
  body text not null,
  created_at timestamptz not null default now()
);

do $$ begin
  if not exists (select 1 from public.settings where key = 'parent_seeded') then
    update public.members set is_parent = true where role = 'admin' or name in ('송진환', '김근영');
    insert into public.settings values ('parent_seeded', 'true');
  end if;
end $$;

-- RLS: 켜두고 정책은 만들지 않음 → 테이블 직접 접근 차단
do $$ declare t text; begin
  foreach t in array array['members','sessions','events','todos','day_logs','locations','checkins','messages','posts','post_photos','comments','likes','stickers','rewards','redemptions','point_adjust','growth','shopping','missions','mission_logs','push_subs','app_secrets','settings','trips','trip_items','trip_files','trip_expenses','trip_msgs','todo_photos'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;

-- ---------------------------------------------------------------- 내부 도우미
create or replace function public.fh_today() returns date language sql stable as
$$ select (now() at time zone 'Asia/Seoul')::date $$;

create or replace function public.fh_auth(p_token uuid) returns public.members
language plpgsql security definer set search_path = public, extensions as $$
declare m public.members;
begin
  select mm.* into m from public.sessions s join public.members mm on mm.id = s.member_id
   where s.token = p_token and mm.active and s.last_seen > now() - interval '180 days';
  if not found then raise exception 'AUTH' using errcode = '28000'; end if;
  update public.sessions set last_seen = now() where token = p_token and last_seen < now() - interval '10 minutes';
  return m;
end $$;

create or replace function public.fh_admin(p_token uuid) returns public.members
language plpgsql security definer set search_path = public, extensions as $$
declare m public.members;
begin
  m := public.fh_auth(p_token);
  if m.role <> 'admin' then raise exception 'NOT_ADMIN' using errcode = '42501'; end if;
  return m;
end $$;

create or replace function public.fh_mj(m public.members) returns jsonb language sql stable as $$
  select jsonb_build_object('id', m.id, 'name', m.name, 'nick', coalesce(m.nick, m.name), 'birth', m.birth,
    'role', m.role, 'emoji', m.emoji, 'color', m.color, 'sort', m.sort, 'must_change', m.must_change, 'parent', m.is_parent or m.role = 'admin',
    'photo_v', case when m.photo is not null then floor(extract(epoch from m.photo_at))::bigint end)
$$;

create or replace function public.fh_rules() returns jsonb language sql stable security definer set search_path = public as $$
  select '{"todo":10,"bonus":20,"bonus_min":3,"todo_cap":10,"sticker":5,"sticker_per_day":3}'::jsonb
         || coalesce((select value from public.settings where key = 'points'), '{}'::jsonb)
$$;

-- 포인트: 할 일 완료 + 모두 완료 보너스 + 칭찬 스티커 + 미션 달성 + 관리자 조정 − 상점 사용
create or replace function public.fh_points(p_member int, p_from date default null, p_to date default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare r jsonb := public.fh_rules(); t int; b int; s int; mi int; a int; spent int;
begin
  select coalesce(sum(least(dn, (r->>'todo_cap')::int) * (r->>'todo')::int
           + case when n >= (r->>'bonus_min')::int and d = n then (r->>'bonus')::int else 0 end), 0)
    into t
    from (select day, count(*) n, count(*) filter (where done) d, count(*) filter (where done and not proof) dn from public.todos
           where member_id = p_member and day <= public.fh_today()
             and (p_from is null or day >= p_from) and (p_to is null or day <= p_to)
           group by day) x;
  -- 사진 인증 할 일: 부모가 준 점수
  select t + coalesce(sum(points), 0) into t from public.todos
   where member_id = p_member and proof and status = 'approved'
     and (p_from is null or day >= p_from) and (p_to is null or day <= p_to);
  select count(*) * (r->>'sticker')::int into s from public.stickers
   where to_id = p_member and (p_from is null or (created_at at time zone 'Asia/Seoul')::date >= p_from)
     and (p_to is null or (created_at at time zone 'Asia/Seoul')::date <= p_to);
  select coalesce(sum(m.reward), 0) into mi from public.missions m
   where m.reward > 0 and (p_from is null or m.end_on >= p_from) and (p_to is null or m.end_on <= p_to)
     and exists (select 1 from public.mission_logs l where l.mission_id = m.id and l.member_id = p_member)
     and (select coalesce(sum(amount), 0) from public.mission_logs l where l.mission_id = m.id) >= m.target;
  select coalesce(sum(amount), 0) into a from public.point_adjust where member_id = p_member
     and (p_from is null or (created_at at time zone 'Asia/Seoul')::date >= p_from)
     and (p_to is null or (created_at at time zone 'Asia/Seoul')::date <= p_to);
  select coalesce(sum(cost), 0) into spent from public.redemptions where member_id = p_member and status <> 'rejected'
     and (p_from is null or (created_at at time zone 'Asia/Seoul')::date >= p_from)
     and (p_to is null or (created_at at time zone 'Asia/Seoul')::date <= p_to);
  return jsonb_build_object('todo', t, 'sticker', s, 'mission', mi, 'adjust', a,
     'earned', t + s + mi + a, 'spent', spent, 'balance', t + s + mi + a - spent);
end $$;

-- 웹 푸시 보내기 (Edge Function 'fh-push' 호출). 알림 서버를 아직 연결하지 않았으면 조용히 넘어감
create or replace function public.fh_notify(p_ids int[], p_title text, p_body text, p_url text default './')
returns void language plpgsql security definer set search_path = public, extensions as $$
declare u text; sec text; subs jsonb;
begin
  select value into u from public.app_secrets where key = 'push_url';
  select value into sec from public.app_secrets where key = 'push_secret';
  if u is null or sec is null or p_ids is null then return; end if;
  select jsonb_agg(jsonb_build_object('endpoint', endpoint, 'p256dh', p256dh, 'auth', auth)) into subs
    from public.push_subs where member_id = any(p_ids);
  if subs is null then return; end if;
  perform net.http_post(url := u,
    body := jsonb_build_object('title', p_title, 'body', p_body, 'url', p_url, 'subs', subs),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', sec));
exception when others then null;   -- 알림 실패가 글쓰기 등을 막지 않도록
end $$;

create or replace function public.fh_others(p_me int) returns int[] language sql stable security definer set search_path = public as
$$ select coalesce(array_agg(id), '{}') from public.members where active and id <> coalesce(p_me, -1) $$;

create or replace function public.fh_nick(p_id int) returns text language sql stable security definer set search_path = public as
$$ select coalesce(nick, name) from public.members where id = p_id $$;

-- ---------------------------------------------------------------- 로그인
create or replace function public.fh_public_members() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'nick', coalesce(nick, name), 'emoji', emoji, 'color', color) order by sort, id), '[]')
    from public.members where active
$$;

create or replace function public.fh_login(p_member int, p_pin text, p_ua text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare m public.members; t uuid;
begin
  select * into m from public.members where id = p_member and active;
  if not found then return jsonb_build_object('error', 'NOUSER'); end if;
  if m.locked_until is not null and m.locked_until > now() then
    return jsonb_build_object('error', 'LOCKED', 'minutes', ceil(extract(epoch from m.locked_until - now()) / 60));
  end if;
  if m.pass_hash <> extensions.crypt(coalesce(p_pin, ''), m.pass_hash) then
    update public.members set fail_count = case when fail_count + 1 >= 5 then 0 else fail_count + 1 end,
      locked_until = case when fail_count + 1 >= 5 then now() + interval '5 minutes' else locked_until end
     where id = m.id;
    return jsonb_build_object('error', 'BADPIN', 'left', greatest(0, 4 - m.fail_count));
  end if;
  update public.members set fail_count = 0, locked_until = null where id = m.id;
  insert into public.sessions(member_id, ua) values (m.id, left(p_ua, 200)) returning token into t;
  return jsonb_build_object('token', t, 'me', public.fh_mj(m));
end $$;

create or replace function public.fh_logout(p_token uuid) returns jsonb
language sql security definer set search_path = public as
$$ delete from public.sessions where token = p_token; select '{}'::jsonb $$;

create or replace function public.fh_change_pin(p_token uuid, p_old text, p_new text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare m public.members := public.fh_auth(p_token);
begin
  if m.pass_hash <> extensions.crypt(coalesce(p_old, ''), m.pass_hash) then return jsonb_build_object('error', 'BADPIN'); end if;
  if p_new is null or length(p_new) < 4 or length(p_new) > 20 then return jsonb_build_object('error', 'SHORT'); end if;
  if p_new = to_char(m.birth, 'YYMMDD') then return jsonb_build_object('error', 'SAME_BIRTH'); end if;
  update public.members set pass_hash = extensions.crypt(p_new, extensions.gen_salt('bf')), must_change = false where id = m.id;
  return '{"ok":true}';
end $$;

create or replace function public.fh_profile_save(p_token uuid, p_emoji text, p_color text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token);
begin
  update public.members set emoji = coalesce(nullif(left(p_emoji, 8), ''), emoji), color = coalesce(nullif(p_color, ''), color)
   where id = m.id returning * into m;
  return public.fh_mj(m);
end $$;

-- ---------------------------------------------------------------- 홈 (한 번에)
create or replace function public.fh_home(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token); td date := public.fh_today(); o jsonb;
begin
  select jsonb_build_object(
    'today', td,
    'me', public.fh_mj(m),
    'rules', public.fh_rules(),
    'members', (select coalesce(jsonb_agg(public.fh_mj(x) || jsonb_build_object('points', public.fh_points(x.id)) order by x.sort, x.id), '[]') from public.members x where x.active),
    'progress', (select coalesce(jsonb_object_agg(member_id, jsonb_build_object('n', n, 'd', d)), '{}') from
                  (select member_id, count(*) n, count(*) filter (where done) d from public.todos where day = td group by member_id) p),
    'logs', (select coalesce(jsonb_object_agg(member_id, jsonb_build_object('score', score, 'mood', mood, 'note', note)), '{}') from public.day_logs where day = td),
    'locations', (select coalesce(jsonb_agg(jsonb_build_object('id', l.member_id, 'lat', case when l.sharing then l.lat end, 'lng', case when l.sharing then l.lng end,
                    'acc', l.acc, 'at', l.updated_at, 'status', l.status, 'status_at', l.status_at, 'sharing', l.sharing)), '[]') from public.locations l),
    'events', (select coalesce(jsonb_agg(to_jsonb(e) || jsonb_build_object('by', public.fh_nick(e.created_by)) order by e.day), '[]') from public.events e),
    'unread', (select count(*) from public.messages where kind = 'secret' and to_id = m.id and read_at is null),
    'capsules_open', (select count(*) from public.messages where kind = 'capsule' and (to_id = m.id or (to_id is null and from_id <> m.id))
                        and open_on <= td and open_on > td - 7),
    'shopping', (select count(*) from public.shopping where not done),
    'stickers_today', (select coalesce(jsonb_agg(jsonb_build_object('emoji', emoji, 'from', public.fh_nick(from_id), 'reason', reason)), '[]')
                         from public.stickers where to_id = m.id and (created_at at time zone 'Asia/Seoul')::date = td),
    'missions', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'title', x.title, 'emoji', x.emoji, 'unit', x.unit, 'target', x.target, 'end_on', x.end_on,
                    'sum', (select coalesce(sum(amount), 0) from public.mission_logs l where l.mission_id = x.id)) order by x.end_on), '[]')
                   from public.missions x where td between x.start_on and x.end_on),
    'onthisday', (select coalesce(jsonb_agg(jsonb_build_object('photo', ph.id, 'post', p.id, 'year', extract(year from p.created_at at time zone 'Asia/Seoul'))), '[]') from
                   (select id, created_at from public.posts where to_char(created_at at time zone 'Asia/Seoul', 'MM-DD') = to_char(td, 'MM-DD')
                      and (created_at at time zone 'Asia/Seoul')::date < td order by created_at desc limit 6) p
                   join lateral (select id from public.post_photos where post_id = p.id order by sort limit 1) ph on true),
    'trips', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'title', t.title, 'emoji', t.emoji, 'place', t.place, 'start_on', t.start_on, 'end_on', t.end_on,
                 'pack_left', (select count(*) from public.trip_items i where i.trip_id = t.id and i.kind = 'pack' and not i.done)) order by t.start_on), '[]')
               from public.trips t where t.end_on >= td and t.start_on <= td + 60 and (m.id = any(t.members) or t.created_by = m.id)),
    'pending', case when m.role = 'admin' then (select count(*) from public.redemptions where status = 'pending') else 0 end,
    'new_posts', (select count(*) from public.posts where created_at > now() - interval '1 day' and member_id <> m.id),
    'reviews', case when m.is_parent or m.role = 'admin' then (select count(*) from public.todos where status = 'review' and member_id <> m.id) else 0 end,
    'my_proof', (select jsonb_build_object('todo', count(*) filter (where status in ('todo', 'rejected')), 'review', count(*) filter (where status = 'review'))
                   from public.todos where member_id = m.id and proof and day >= td - 1)
  ) into o;
  return o;
end $$;

-- ---------------------------------------------------------------- 할 일
create or replace function public.fh_todos(p_token uuid, p_day date, p_member int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token); who int := coalesce(p_member, m.id);
begin
  return jsonb_build_object(
    'items', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'text', t.text, 'done', t.done, 'proof', t.proof, 'status', t.status, 'points', t.points, 'max', t.max_points,
               'by', t.assigned_by, 'note', t.review_note, 'rby', t.reviewed_by,
               'before', exists (select 1 from public.todo_photos ph where ph.todo_id = t.id and ph.kind = 'before'),
               'after', exists (select 1 from public.todo_photos ph where ph.todo_id = t.id and ph.kind = 'after')) order by t.sort, t.id), '[]') from public.todos t where t.member_id = who and t.day = p_day),
    'days', (select coalesce(jsonb_object_agg(day, jsonb_build_object('n', n, 'd', d)), '{}') from
              (select day, count(*) n, count(*) filter (where done) d from public.todos
                where member_id = who and day between p_day - 14 and p_day + 7 group by day) x),
    'carry', case when who = m.id and p_day = public.fh_today() then
       (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'text', text, 'day', day)), '[]') from public.todos
         where member_id = m.id and not done and day = (select max(day) from public.todos where member_id = m.id and day < p_day and day >= p_day - 7)) else '[]' end,
    'points', public.fh_points(who));
end $$;

drop function if exists public.fh_todo_add(uuid, date, text);
create or replace function public.fh_todo_add(p_token uuid, p_day date, p_text text, p_proof boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token);
begin
  if coalesce(trim(p_text), '') = '' then return '{"error":"EMPTY"}'; end if;
  if p_day < public.fh_today() then return '{"error":"PAST"}'; end if;
  insert into public.todos(member_id, day, text, sort, proof, status, max_points)
  values (m.id, p_day, left(trim(p_text), 100), (select coalesce(max(sort), 0) + 1 from public.todos where member_id = m.id and day = p_day),
          coalesce(p_proof, false), case when p_proof then 'todo' end, case when p_proof then 20 end);
  return '{"ok":true}';
end $$;

create or replace function public.fh_todo_toggle(p_token uuid, p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token); t public.todos; n int; d int;
begin
  select * into t from public.todos where id = p_id and member_id = m.id;
  if not found then return '{"error":"NOTFOUND"}'; end if;
  if t.day < public.fh_today() - 1 then return '{"error":"PAST"}'; end if;   -- 어제 것까지만 체크 가능
  if t.proof then return '{"error":"PROOF"}'; end if;                         -- 사진 인증 할 일은 부모 확인으로만 완료
  update public.todos set done = not done, done_at = case when not done then now() end where id = p_id;
  select count(*), count(*) filter (where done) into n, d from public.todos where member_id = m.id and day = t.day;
  return jsonb_build_object('ok', true, 'all', n > 0 and n = d, 'n', n, 'd', d);
end $$;

create or replace function public.fh_todo_del(p_token uuid, p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token);
begin
  delete from public.todos where id = p_id and coalesce(status, '') <> 'approved'
     and (member_id = m.id and (not done or day >= public.fh_today()) or (assigned_by = m.id));
  return '{"ok":true}';
end $$;

create or replace function public.fh_todo_carry(p_token uuid, p_ids bigint[]) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token); td date := public.fh_today();
begin
  insert into public.todos(member_id, day, text, sort, proof, status, max_points, assigned_by)
  select m.id, td, text, row_number() over (order by sort, id) + (select coalesce(max(sort), 0) from public.todos where member_id = m.id and day = td),
         proof, case when proof then 'todo' end, max_points, assigned_by
    from public.todos where id = any(p_ids) and member_id = m.id and not done and coalesce(status, '') <> 'review';
  delete from public.todos where id = any(p_ids) and member_id = m.id and not done and coalesce(status, '') <> 'review' and day < td;
  return '{"ok":true}';
end $$;

-- ---------------------------------------------------------------- 하루 점수·기분
create or replace function public.fh_daylog_save(p_token uuid, p_day date, p_score int, p_mood text, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token);
begin
  if p_day > public.fh_today() or p_day < public.fh_today() - 3 then return '{"error":"DAY"}'; end if;
  insert into public.day_logs(member_id, day, score, mood, note) values (m.id, p_day, p_score, left(p_mood, 8), left(p_note, 300))
  on conflict (member_id, day) do update set score = coalesce(excluded.score, day_logs.score), mood = coalesce(excluded.mood, day_logs.mood),
     note = coalesce(excluded.note, day_logs.note), updated_at = now();
  return '{"ok":true}';
end $$;

create or replace function public.fh_daylogs(p_token uuid, p_from date, p_to date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token);
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('member', member_id, 'day', day, 'score', score, 'mood', mood, 'note', note) order by day), '[]')
            from public.day_logs where day between p_from and p_to);
end $$;

-- ---------------------------------------------------------------- 일정·기념일
create or replace function public.fh_event_save(p_token uuid, p_id bigint, p_title text, p_day date, p_yearly boolean, p_category text, p_remind int, p_memo text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token); nid bigint;
begin
  if coalesce(trim(p_title), '') = '' or p_day is null then return '{"error":"EMPTY"}'; end if;
  if p_id is null then
    insert into public.events(title, day, yearly, category, remind, memo, created_by)
    values (left(trim(p_title), 60), p_day, coalesce(p_yearly, false), coalesce(p_category, '일정'), greatest(0, least(coalesce(p_remind, 1), 30)), left(p_memo, 300), m.id)
    returning id into nid;
    perform public.fh_notify(public.fh_others(m.id), '📅 새 일정 · ' || coalesce(m.nick, m.name), to_char(p_day, 'MM/DD') || ' ' || left(trim(p_title), 60), './#/cal');
  else
    update public.events set title = left(trim(p_title), 60), day = p_day, yearly = coalesce(p_yearly, false), category = coalesce(p_category, '일정'),
      remind = greatest(0, least(coalesce(p_remind, 1), 30)), memo = left(p_memo, 300) where id = p_id;
  end if;
  return '{"ok":true}';
end $$;

create or replace function public.fh_event_del(p_token uuid, p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token);
begin
  delete from public.events where id = p_id and (created_by = m.id or created_by is null or m.role = 'admin');
  return '{"ok":true}';
end $$;

-- ---------------------------------------------------------------- 위치·도착 알림
create or replace function public.fh_loc_update(p_token uuid, p_lat double precision, p_lng double precision, p_acc real) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token);
begin
  insert into public.locations(member_id, lat, lng, acc, updated_at) values (m.id, p_lat, p_lng, p_acc, now())
  on conflict (member_id) do update set lat = excluded.lat, lng = excluded.lng, acc = excluded.acc, updated_at = now()
   where public.locations.sharing;
  return '{"ok":true}';
end $$;

create or replace function public.fh_loc_sharing(p_token uuid, p_on boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token);
begin
  insert into public.locations(member_id, sharing) values (m.id, p_on)
  on conflict (member_id) do update set sharing = p_on,
    lat = case when p_on then public.locations.lat end, lng = case when p_on then public.locations.lng end;
  return '{"ok":true}';
end $$;

create or replace function public.fh_checkin(p_token uuid, p_label text, p_lat double precision, p_lng double precision) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token); lb text := left(trim(coalesce(p_label, '')), 30);
begin
  if lb = '' then return '{"error":"EMPTY"}'; end if;
  insert into public.checkins(member_id, label, lat, lng) values (m.id, lb, p_lat, p_lng);
  insert into public.locations(member_id, status, status_at, lat, lng, updated_at) values (m.id, lb, now(), p_lat, p_lng, case when p_lat is not null then now() end)
  on conflict (member_id) do update set status = lb, status_at = now(),
    lat = case when public.locations.sharing and p_lat is not null then p_lat else public.locations.lat end,
    lng = case when public.locations.sharing and p_lng is not null then p_lng else public.locations.lng end,
    updated_at = case when public.locations.sharing and p_lat is not null then now() else public.locations.updated_at end;
  perform public.fh_notify(public.fh_others(m.id), '📍 ' || coalesce(m.nick, m.name) || ' · ' || lb, to_char(now() at time zone 'Asia/Seoul', 'HH24:MI') || ' 에 알렸어요', './#/family');
  return '{"ok":true}';
end $$;

create or replace function public.fh_checkins(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token);
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('member', member_id, 'label', label, 'at', created_at) order by created_at desc), '[]')
            from (select * from public.checkins order by created_at desc limit 40) c);
end $$;

-- ---------------------------------------------------------------- 비밀 메시지·타임캡슐
create or replace function public.fh_msg_send(p_token uuid, p_to int, p_body text, p_kind text default 'secret', p_open_on date default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token); k text := coalesce(p_kind, 'secret');
begin
  if coalesce(trim(p_body), '') = '' then return '{"error":"EMPTY"}'; end if;
  if k = 'secret' then
    if p_to is null or p_to = m.id or not exists (select 1 from public.members where id = p_to and active) then return '{"error":"TO"}'; end if;
    insert into public.messages(from_id, to_id, kind, body) values (m.id, p_to, 'secret', left(p_body, 2000));
    perform public.fh_notify(array[p_to], '🔒 비밀 메시지가 왔어요', coalesce(m.nick, m.name) || '님이 보냈어요 · 열어서 확인하세요', './#/msg');
  else
    if p_open_on is null or p_open_on <= public.fh_today() then return '{"error":"DATE"}'; end if;
    if p_to = m.id then return '{"error":"TO"}'; end if;
    insert into public.messages(from_id, to_id, kind, body, open_on) values (m.id, p_to, 'capsule', left(p_body, 4000), p_open_on);
    perform public.fh_notify(case when p_to is null then public.fh_others(m.id) else array[p_to] end,
      '⏳ 타임캡슐이 묻혔어요', coalesce(m.nick, m.name) || '님의 편지 · ' || to_char(p_open_on, 'YYYY.MM.DD') || ' 에 열려요', './#/capsule');
  end if;
  return '{"ok":true}';
end $$;

create or replace function public.fh_msg_list(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token); td date := public.fh_today();
begin
  return jsonb_build_object(
    'secret', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'from', from_id, 'to', to_id, 'body', body, 'at', created_at, 'read', read_at is not null, 'mine', from_id = m.id) order by created_at desc), '[]')
                 from public.messages where kind = 'secret' and (from_id = m.id or to_id = m.id)),
    'capsule', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'from', from_id, 'to', to_id, 'open_on', open_on, 'at', created_at, 'mine', from_id = m.id,
                   'opened', open_on <= td,
                   'body', case when from_id = m.id or open_on <= td then body end) order by open_on), '[]')
                 from public.messages where kind = 'capsule' and (from_id = m.id or to_id = m.id or to_id is null)));
end $$;

create or replace function public.fh_msg_read(p_token uuid, p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token);
begin
  update public.messages set read_at = now() where id = p_id and to_id = m.id and read_at is null;
  return '{"ok":true}';
end $$;

create or replace function public.fh_msg_del(p_token uuid, p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token);
begin
  delete from public.messages where id = p_id and (to_id = m.id and kind = 'secret' or from_id = m.id);
  return '{"ok":true}';
end $$;

-- ---------------------------------------------------------------- 게시판·앨범
create or replace function public.fh_posts(p_token uuid, p_before bigint default null, p_limit int default 15) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token);
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'member', p.member_id, 'body', p.body, 'at', p.created_at,
      'photos', (select coalesce(jsonb_agg(jsonb_build_object('id', ph.id, 'w', ph.w, 'h', ph.h) order by ph.sort), '[]') from public.post_photos ph where ph.post_id = p.id),
      'likes', (select coalesce(jsonb_agg(member_id), '[]') from public.likes where post_id = p.id),
      'comments', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'member', c.member_id, 'body', c.body, 'at', c.created_at) order by c.id), '[]') from public.comments c where c.post_id = p.id)
    ) order by p.id desc), '[]')
    from (select * from public.posts where p_before is null or id < p_before order by id desc limit least(coalesce(p_limit, 15), 30)) p);
end $$;

create or replace function public.fh_post_add(p_token uuid, p_body text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token); nid bigint;
begin
  insert into public.posts(member_id, body) values (m.id, left(coalesce(p_body, ''), 3000)) returning id into nid;
  return jsonb_build_object('id', nid);
end $$;

-- 사진은 글을 만든 뒤 한 장씩 올림 (휴대폰에서 줄인 JPEG)
create or replace function public.fh_photo_add(p_token uuid, p_post bigint, p_data text, p_w int, p_h int, p_sort int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token);
begin
  if not exists (select 1 from public.posts where id = p_post and member_id = m.id) then return '{"error":"NOTFOUND"}'; end if;
  if length(p_data) > 1500000 or left(p_data, 11) <> 'data:image/' then return '{"error":"SIZE"}'; end if;
  if (select count(*) from public.post_photos where post_id = p_post) >= 10 then return '{"error":"MAX"}'; end if;
  insert into public.post_photos(post_id, data, w, h, sort) values (p_post, p_data, p_w, p_h, coalesce(p_sort, 0));
  return '{"ok":true}';
end $$;

-- 사진까지 다 올라간 뒤 알림
create or replace function public.fh_post_done(p_token uuid, p_post bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token); b text; n int;
begin
  select body into b from public.posts where id = p_post and member_id = m.id;
  if not found then return '{"error":"NOTFOUND"}'; end if;
  select count(*) into n from public.post_photos where post_id = p_post;
  perform public.fh_notify(public.fh_others(m.id), '📝 ' || coalesce(m.nick, m.name) || '님의 새 글',
     coalesce(nullif(left(b, 60), ''), '') || case when n > 0 then ' 📷' || n else '' end, './#/board');
  return '{"ok":true}';
end $$;

create or replace function public.fh_photo(p_token uuid, p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token);
begin
  return (select jsonb_build_object('id', id, 'data', data, 'post', post_id) from public.post_photos where id = p_id);
end $$;

create or replace function public.fh_post_del(p_token uuid, p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token);
begin
  delete from public.posts where id = p_id and (member_id = m.id or m.role = 'admin');
  return '{"ok":true}';
end $$;

create or replace function public.fh_comment_add(p_token uuid, p_post bigint, p_body text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token); ids int[];
begin
  if coalesce(trim(p_body), '') = '' then return '{"error":"EMPTY"}'; end if;
  insert into public.comments(post_id, member_id, body) values (p_post, m.id, left(trim(p_body), 500));
  select array_agg(distinct x) into ids from (
     select member_id x from public.posts where id = p_post
     union select member_id from public.comments where post_id = p_post) s where x is not null and x <> m.id;
  perform public.fh_notify(ids, '💬 ' || coalesce(m.nick, m.name) || '님의 댓글', left(trim(p_body), 80), './#/board');
  return '{"ok":true}';
end $$;

create or replace function public.fh_comment_del(p_token uuid, p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token);
begin
  delete from public.comments where id = p_id and (member_id = m.id or m.role = 'admin');
  return '{"ok":true}';
end $$;

create or replace function public.fh_like(p_token uuid, p_post bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token);
begin
  if exists (select 1 from public.likes where post_id = p_post and member_id = m.id) then
    delete from public.likes where post_id = p_post and member_id = m.id;
  else
    insert into public.likes values (p_post, m.id) on conflict do nothing;
  end if;
  return '{"ok":true}';
end $$;

create or replace function public.fh_album(p_token uuid, p_before bigint default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token);
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('id', ph.id, 'post', ph.post_id, 'w', ph.w, 'h', ph.h, 'at', p.created_at, 'member', p.member_id) order by ph.id desc), '[]')
            from (select * from public.post_photos where p_before is null or id < p_before order by id desc limit 36) ph
            join public.posts p on p.id = ph.post_id);
end $$;

-- ---------------------------------------------------------------- 칭찬 스티커·포인트 상점
create or replace function public.fh_sticker_give(p_token uuid, p_to int, p_emoji text, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token); r jsonb := public.fh_rules(); n int;
begin
  if p_to = m.id or not exists (select 1 from public.members where id = p_to and active) then return '{"error":"TO"}'; end if;
  select count(*) into n from public.stickers where from_id = m.id and (created_at at time zone 'Asia/Seoul')::date = public.fh_today();
  if n >= (r->>'sticker_per_day')::int then return jsonb_build_object('error', 'LIMIT', 'limit', (r->>'sticker_per_day')::int); end if;
  insert into public.stickers(from_id, to_id, emoji, reason) values (m.id, p_to, coalesce(nullif(left(p_emoji, 8), ''), '⭐'), left(p_reason, 80));
  perform public.fh_notify(array[p_to], coalesce(nullif(left(p_emoji, 8), ''), '⭐') || ' 칭찬 스티커를 받았어요!',
     coalesce(m.nick, m.name) || ': ' || coalesce(nullif(left(p_reason, 80), ''), '최고야!') || ' (+' || (r->>'sticker') || '점)', './#/points');
  return jsonb_build_object('ok', true, 'left', (r->>'sticker_per_day')::int - n - 1);
end $$;

create or replace function public.fh_shop(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token);
begin
  return jsonb_build_object(
    'points', public.fh_points(m.id),
    'rules', public.fh_rules(),
    'rewards', (select coalesce(jsonb_agg(to_jsonb(r) order by sort, cost), '[]') from public.rewards r where active),
    'mine', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'title', title, 'cost', cost, 'status', status, 'at', created_at) order by id desc), '[]')
               from (select * from public.redemptions where member_id = m.id order by id desc limit 20) x),
    'stickers', (select coalesce(jsonb_agg(jsonb_build_object('from', from_id, 'to', to_id, 'emoji', emoji, 'reason', reason, 'at', created_at) order by id desc), '[]')
               from (select * from public.stickers order by id desc limit 40) s),
    'given_today', (select count(*) from public.stickers where from_id = m.id and (created_at at time zone 'Asia/Seoul')::date = public.fh_today()),
    'board', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'points', public.fh_points(x.id), 'week', public.fh_points(x.id, public.fh_today() - extract(isodow from public.fh_today())::int + 1, public.fh_today())) order by x.sort), '[]') from public.members x where x.active));
end $$;

create or replace function public.fh_redeem(p_token uuid, p_reward bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token); r public.rewards; bal int;
begin
  select * into r from public.rewards where id = p_reward and active;
  if not found then return '{"error":"NOTFOUND"}'; end if;
  bal := (public.fh_points(m.id)->>'balance')::int;
  if bal < r.cost then return jsonb_build_object('error', 'POINTS', 'balance', bal); end if;
  insert into public.redemptions(member_id, reward_id, title, cost) values (m.id, r.id, trim(r.emoji || ' ' || r.title), r.cost);
  perform public.fh_notify((select array_agg(id) from public.members where role = 'admin' and active and id <> m.id),
     coalesce(m.nick, m.name) || '님의 보상 신청', trim(r.emoji || ' ' || r.title) || ' (' || r.cost || '점) · admin에서 승인해 주세요', './admin/');
  return '{"ok":true}';
end $$;

-- ---------------------------------------------------------------- 성장 기록
create or replace function public.fh_growth(p_token uuid, p_member int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token);
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'day', day, 'height', height, 'weight', weight, 'note', note, 'by', created_by) order by day, id), '[]')
            from public.growth where member_id = p_member);
end $$;

create or replace function public.fh_growth_add(p_token uuid, p_member int, p_day date, p_height numeric, p_weight numeric, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token);
begin
  if p_height is null and p_weight is null and coalesce(trim(p_note), '') = '' then return '{"error":"EMPTY"}'; end if;
  insert into public.growth(member_id, day, height, weight, note, created_by) values (p_member, coalesce(p_day, public.fh_today()), p_height, p_weight, left(p_note, 500), m.id);
  return '{"ok":true}';
end $$;

create or replace function public.fh_growth_del(p_token uuid, p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token);
begin
  delete from public.growth where id = p_id and (created_by = m.id or member_id = m.id or m.role = 'admin');
  return '{"ok":true}';
end $$;

-- ---------------------------------------------------------------- 장보기
create or replace function public.fh_shop_list(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token);
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'text', text, 'qty', qty, 'done', done, 'by', created_by, 'done_by', done_by, 'at', created_at, 'done_at', done_at)
              order by done, case when done then extract(epoch from done_at) * -1 else id end), '[]')
            from public.shopping where not done or done_at > now() - interval '3 days');
end $$;

create or replace function public.fh_shop_add(p_token uuid, p_text text, p_qty text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token);
begin
  if coalesce(trim(p_text), '') = '' then return '{"error":"EMPTY"}'; end if;
  insert into public.shopping(text, qty, created_by) values (left(trim(p_text), 60), nullif(left(trim(coalesce(p_qty, '')), 20), ''), m.id);
  return '{"ok":true}';
end $$;

create or replace function public.fh_shop_toggle(p_token uuid, p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token);
begin
  update public.shopping set done = not done, done_by = case when not done then m.id end, done_at = case when not done then now() end where id = p_id;
  return '{"ok":true}';
end $$;

create or replace function public.fh_shop_del(p_token uuid, p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token);
begin
  if p_id is null then delete from public.shopping where done; else delete from public.shopping where id = p_id; end if;
  return '{"ok":true}';
end $$;

-- ---------------------------------------------------------------- 가족 미션
create or replace function public.fh_missions(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token);
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'title', x.title, 'emoji', x.emoji, 'unit', x.unit, 'target', x.target, 'reward', x.reward,
      'start_on', x.start_on, 'end_on', x.end_on, 'by', x.created_by,
      'sum', (select coalesce(sum(amount), 0) from public.mission_logs l where l.mission_id = x.id),
      'per', (select coalesce(jsonb_object_agg(member_id, s), '{}') from (select member_id, sum(amount) s from public.mission_logs l where l.mission_id = x.id group by member_id) q),
      'logs', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'member', member_id, 'amount', amount, 'day', day) order by id desc), '[]')
                 from (select * from public.mission_logs l where l.mission_id = x.id order by id desc limit 15) q)
    ) order by (x.end_on < public.fh_today()), x.end_on), '[]')
    from public.missions x where x.end_on >= public.fh_today() - 30);
end $$;

create or replace function public.fh_mission_save(p_token uuid, p_title text, p_emoji text, p_unit text, p_target numeric, p_start date, p_end date, p_reward int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token);
begin
  if coalesce(trim(p_title), '') = '' or p_target is null or p_target <= 0 or p_end < p_start then return '{"error":"INPUT"}'; end if;
  insert into public.missions(title, emoji, unit, target, start_on, end_on, reward, created_by)
  values (left(trim(p_title), 60), coalesce(nullif(p_emoji, ''), '🚩'), coalesce(nullif(trim(p_unit), ''), '회'), p_target, p_start, p_end,
          case when m.role = 'admin' then greatest(0, coalesce(p_reward, 0)) else 0 end, m.id);
  perform public.fh_notify(public.fh_others(m.id), '🚩 새 가족 미션!', left(trim(p_title), 60) || ' · 목표 ' || p_target || coalesce(nullif(trim(p_unit), ''), '회'), './#/mission');
  return '{"ok":true}';
end $$;

create or replace function public.fh_mission_del(p_token uuid, p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token);
begin
  delete from public.missions where id = p_id and (created_by = m.id or m.role = 'admin');
  return '{"ok":true}';
end $$;

create or replace function public.fh_mission_log(p_token uuid, p_mission bigint, p_amount numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token); x public.missions; before numeric; after numeric;
begin
  select * into x from public.missions where id = p_mission;
  if not found or public.fh_today() not between x.start_on and x.end_on then return '{"error":"CLOSED"}'; end if;
  if p_amount is null or p_amount = 0 then return '{"error":"INPUT"}'; end if;
  select coalesce(sum(amount), 0) into before from public.mission_logs where mission_id = p_mission;
  insert into public.mission_logs(mission_id, member_id, amount, day) values (p_mission, m.id, p_amount, public.fh_today());
  after := before + p_amount;
  if before < x.target and after >= x.target then
    perform public.fh_notify((select array_agg(id) from public.members where active), '🎉 가족 미션 달성!', x.emoji || ' ' || x.title || ' 목표를 채웠어요' ||
       case when x.reward > 0 then ' (+' || x.reward || '점)' else '' end, './#/mission');
  end if;
  return jsonb_build_object('ok', true, 'sum', after, 'done', after >= x.target);
end $$;

create or replace function public.fh_mission_log_del(p_token uuid, p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token);
begin
  delete from public.mission_logs where id = p_id and (member_id = m.id or m.role = 'admin');
  return '{"ok":true}';
end $$;

-- ---------------------------------------------------------------- 주간 가족 리포트
create or replace function public.fh_week(p_token uuid, p_start date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token); e date := p_start + 6;
begin
  return jsonb_build_object('start', p_start, 'end', e,
    'members', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id,
        'todo_n', (select count(*) from public.todos where member_id = x.id and day between p_start and e),
        'todo_d', (select count(*) from public.todos where member_id = x.id and day between p_start and e and done),
        'perfect', (select count(*) from (select day from public.todos where member_id = x.id and day between p_start and e group by day having bool_and(done)) q),
        'points', (public.fh_points(x.id, p_start, e)->>'earned')::int,
        'score', (select round(avg(score)) from public.day_logs where member_id = x.id and day between p_start and e and score is not null),
        'moods', (select coalesce(jsonb_agg(jsonb_build_object('day', day, 'mood', mood) order by day), '[]') from public.day_logs where member_id = x.id and day between p_start and e and mood is not null),
        'stickers', (select count(*) from public.stickers where to_id = x.id and (created_at at time zone 'Asia/Seoul')::date between p_start and e),
        'posts', (select count(*) from public.posts where member_id = x.id and (created_at at time zone 'Asia/Seoul')::date between p_start and e),
        'mission', (select coalesce(sum(amount), 0) from public.mission_logs where member_id = x.id and day between p_start and e)
      ) order by x.sort), '[]') from public.members x where x.active),
    'photos', (select coalesce(jsonb_agg(ph.id order by ph.id desc), '[]') from (select ph.id from public.post_photos ph join public.posts p on p.id = ph.post_id
                 where (p.created_at at time zone 'Asia/Seoul')::date between p_start and e order by ph.id desc limit 9) ph),
    'shopping', (select count(*) from public.shopping where done and (done_at at time zone 'Asia/Seoul')::date between p_start and e),
    'checkins', (select count(*) from public.checkins where (created_at at time zone 'Asia/Seoul')::date between p_start and e));
end $$;

-- ---------------------------------------------------------------- 알림 구독
create or replace function public.fh_push_save(p_token uuid, p_endpoint text, p_p256dh text, p_auth text, p_ua text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token);
begin
  insert into public.push_subs(endpoint, member_id, p256dh, auth, ua) values (p_endpoint, m.id, p_p256dh, p_auth, left(p_ua, 200))
  on conflict (endpoint) do update set member_id = m.id, p256dh = excluded.p256dh, auth = excluded.auth, ua = excluded.ua;
  return '{"ok":true}';
end $$;

create or replace function public.fh_push_del(p_token uuid, p_endpoint text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token);
begin
  delete from public.push_subs where endpoint = p_endpoint;
  return '{"ok":true}';
end $$;

create or replace function public.fh_push_test(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token); n int;
begin
  select count(*) into n from public.push_subs where member_id = m.id;
  perform public.fh_notify(array[m.id], '🔔 Family Hub 알림 테스트', '이 알림이 보이면 연결 완료!', './');
  return jsonb_build_object('subs', n, 'server', exists (select 1 from public.app_secrets where key = 'push_url'));
end $$;

create or replace function public.fh_next(p_day date, p_yearly boolean, p_from date) returns date
language plpgsql immutable as $$
declare y int := extract(year from p_from)::int; d date;
begin
  if not p_yearly then return p_day; end if;
  for i in 0..1 loop
    begin d := make_date(y + i, extract(month from p_day)::int, extract(day from p_day)::int);
    exception when others then d := make_date(y + i, 3, 1); end;
    if d >= p_from then return d; end if;
  end loop;
  return d;
end $$;

-- ---------------------------------------------------------------- 매일 자동 알림 (pg_cron)
--  아침 8시: 오늘·다가오는 일정, 생일, 살아온 날 기념(1,000일 단위), 열리는 타임캡슐
--  저녁 9시: 오늘 할 일·하루 점수 남기기
create or replace function public.fh_daily_push(p_kind text) returns void
language plpgsql security definer set search_path = public as $$
declare td date := public.fh_today(); r record; all_ids int[]; dd int; nb date;
begin
  select array_agg(id) into all_ids from public.members where active;
  if p_kind = 'morning' then
    for r in select e.* from public.events e loop
      nb := public.fh_next(r.day, r.yearly, td);
      dd := nb - td;
      if dd = 0 then perform public.fh_notify(all_ids, '📅 오늘은 ' || r.title, coalesce(r.memo, r.category), './#/cal');
      elsif dd > 0 and dd = r.remind then perform public.fh_notify(all_ids, '⏰ D-' || dd || ' ' || r.title, to_char(nb, 'MM/DD') || ' · ' || r.category, './#/cal');
      end if;
    end loop;
    for r in select * from public.members where active loop
      if to_char(r.birth, 'MM-DD') = to_char(td, 'MM-DD') then
        perform public.fh_notify(all_ids, '🎂 오늘은 ' || coalesce(r.nick, r.name) || '의 생일!', '축하 메시지를 남겨 주세요 🎉', './#/board');
      elsif to_char(r.birth, 'MM-DD') = to_char(td + 3, 'MM-DD') then
        perform public.fh_notify(public.fh_others(r.id), '🎁 D-3 ' || coalesce(r.nick, r.name) || ' 생일', '선물·이벤트 준비해요 (본인에게는 비밀!)', './#/cal');
      end if;
      if (td - r.birth + 1) % 1000 = 0 then
        perform public.fh_notify(all_ids, '✨ ' || coalesce(r.nick, r.name) || ' 살아온 지 ' || to_char(td - r.birth + 1, 'FM999,999') || '일!', '오늘은 특별한 날이에요', './');
      end if;
    end loop;
    for r in select t.*, (select count(*) from public.trip_items i where i.trip_id = t.id and i.kind = 'pack' and not i.done) left_n,
                    (select count(*) from public.trip_files f where f.trip_id = t.id and f.kind = 'passport' and f.expires_on is not null and f.expires_on < t.end_on + interval '6 months') pp
               from public.trips t where t.start_on - td in (0, 1, 7, 30) loop
      dd := r.start_on - td;
      perform public.fh_notify(r.members, case when dd = 0 then r.emoji || ' 오늘 출발! ' || r.title else r.emoji || ' 여행 D-' || dd || ' · ' || r.title end,
        case when dd = 0 then '즐거운 여행 되세요 🧳' when r.left_n > 0 then '아직 못 챙긴 준비물 ' || r.left_n || '개' else '준비물 모두 챙겼어요 👍' end
        || case when r.pp > 0 and dd >= 7 then ' · ⚠️ 여권 유효기간을 확인하세요' else '' end, './#/trip?id=' || r.id);
    end loop;
    for r in select * from public.messages where kind = 'capsule' and open_on = td loop
      perform public.fh_notify(case when r.to_id is null then all_ids else array[r.to_id] end, '⏳ 타임캡슐이 열렸어요!',
         public.fh_nick(r.from_id) || '님이 ' || to_char(r.created_at at time zone 'Asia/Seoul', 'YYYY.MM.DD') || '에 묻어둔 편지', './#/capsule');
    end loop;
  else
    for r in select x.id, (select count(*) from public.todos t where t.member_id = x.id and t.day = td and not t.done) left_n,
                    exists (select 1 from public.day_logs l where l.member_id = x.id and l.day = td and l.score is not null) logged
               from public.members x where x.active loop
      if r.left_n > 0 or not r.logged then
        perform public.fh_notify(array[r.id], '🌙 오늘 하루 어땠어요?',
          case when r.left_n > 0 then '남은 할 일 ' || r.left_n || '개 · ' else '' end || case when not r.logged then '오늘의 점수를 남겨 주세요' else '마무리해요!' end, './#/todo');
      end if;
    end loop;
  end if;
end $$;

do $$ begin
  perform cron.unschedule(jobid) from cron.job where jobname in ('fh-morning', 'fh-evening');
  perform cron.schedule('fh-morning', '0 23 * * *', $c$select public.fh_daily_push('morning')$c$);   -- 한국 08:00
  perform cron.schedule('fh-evening', '0 12 * * *', $c$select public.fh_daily_push('evening')$c$);   -- 한국 21:00
exception when others then raise notice 'pg_cron 예약 실패: %', sqlerrm;
end $$;

-- ---------------------------------------------------------------- 관리자 (진환)
create or replace function public.fh_admin_members(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.members := public.fh_admin(p_token);
begin
  return (select coalesce(jsonb_agg(public.fh_mj(x) || jsonb_build_object('active', x.active, 'created_at', x.created_at,
      'last_seen', (select max(last_seen) from public.sessions s where s.member_id = x.id),
      'sessions', (select count(*) from public.sessions s where s.member_id = x.id),
      'push', (select count(*) from public.push_subs p where p.member_id = x.id),
      'locked', x.locked_until > now(),
      'points', public.fh_points(x.id)) order by x.sort, x.id), '[]') from public.members x);
end $$;

create or replace function public.fh_admin_member_save(p_token uuid, p_id int, p_name text, p_nick text, p_birth date, p_role text, p_emoji text, p_color text, p_sort int, p_active boolean) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare a public.members := public.fh_admin(p_token);
begin
  if coalesce(trim(p_name), '') = '' or p_birth is null then return '{"error":"INPUT"}'; end if;
  if p_id is null then
    insert into public.members(name, nick, birth, role, emoji, color, sort, pass_hash)
    values (trim(p_name), nullif(trim(p_nick), ''), p_birth, coalesce(p_role, 'member'), coalesce(nullif(p_emoji, ''), '🙂'), coalesce(nullif(p_color, ''), '#4dabf7'),
            coalesce(p_sort, (select coalesce(max(sort), 0) + 1 from public.members)), extensions.crypt(to_char(p_birth, 'YYMMDD'), extensions.gen_salt('bf')));
  else
    if p_id = a.id and (coalesce(p_role, 'admin') <> 'admin' or p_active = false) then return '{"error":"SELF"}'; end if;
    update public.members set name = trim(p_name), nick = nullif(trim(p_nick), ''), birth = p_birth, role = coalesce(p_role, role),
      emoji = coalesce(nullif(p_emoji, ''), emoji), color = coalesce(nullif(p_color, ''), color), sort = coalesce(p_sort, sort), active = coalesce(p_active, active)
     where id = p_id;
    if p_active = false then delete from public.sessions where member_id = p_id; end if;
  end if;
  return '{"ok":true}';
end $$;

create or replace function public.fh_admin_member_delete(p_token uuid, p_id int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.members := public.fh_admin(p_token);
begin
  if p_id = a.id then return '{"error":"SELF"}'; end if;
  delete from public.members where id = p_id;
  return '{"ok":true}';
end $$;

create or replace function public.fh_admin_reset_pin(p_token uuid, p_id int) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare a public.members := public.fh_admin(p_token); b date;
begin
  select birth into b from public.members where id = p_id;
  update public.members set pass_hash = extensions.crypt(to_char(b, 'YYMMDD'), extensions.gen_salt('bf')), must_change = true, fail_count = 0, locked_until = null where id = p_id;
  delete from public.sessions where member_id = p_id and token <> p_token;
  return jsonb_build_object('ok', true, 'pin', to_char(b, 'YYMMDD'));
end $$;

create or replace function public.fh_admin_rewards(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.members := public.fh_admin(p_token);
begin
  return jsonb_build_object(
    'rewards', (select coalesce(jsonb_agg(to_jsonb(r) order by sort, id), '[]') from public.rewards r),
    'redemptions', (select coalesce(jsonb_agg(to_jsonb(x) order by (x.status <> 'pending'), x.id desc), '[]') from (select * from public.redemptions order by id desc limit 60) x),
    'adjust', (select coalesce(jsonb_agg(to_jsonb(x) order by x.id desc), '[]') from (select * from public.point_adjust order by id desc limit 30) x),
    'rules', public.fh_rules());
end $$;

create or replace function public.fh_admin_reward_save(p_token uuid, p_id bigint, p_title text, p_emoji text, p_cost int, p_active boolean, p_sort int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.members := public.fh_admin(p_token);
begin
  if coalesce(trim(p_title), '') = '' or coalesce(p_cost, 0) <= 0 then return '{"error":"INPUT"}'; end if;
  if p_id is null then insert into public.rewards(title, emoji, cost, active, sort) values (trim(p_title), coalesce(p_emoji, ''), p_cost, coalesce(p_active, true), coalesce(p_sort, 0));
  else update public.rewards set title = trim(p_title), emoji = coalesce(nullif(p_emoji, ''), emoji), cost = p_cost, active = coalesce(p_active, active), sort = coalesce(p_sort, sort) where id = p_id; end if;
  return '{"ok":true}';
end $$;

create or replace function public.fh_admin_reward_del(p_token uuid, p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.members := public.fh_admin(p_token);
begin delete from public.rewards where id = p_id; return '{"ok":true}'; end $$;

create or replace function public.fh_admin_redeem_decide(p_token uuid, p_id bigint, p_ok boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.members := public.fh_admin(p_token); x public.redemptions;
begin
  update public.redemptions set status = case when p_ok then 'approved' else 'rejected' end, decided_at = now() where id = p_id and status = 'pending' returning * into x;
  if found then
    perform public.fh_notify(array[x.member_id], case when p_ok then '✅ 보상이 승인됐어요!' else '↩️ 보상 신청이 반려됐어요' end,
       x.title || case when p_ok then ' · 즐겁게 누리세요 🎉' else ' · 포인트는 돌려드렸어요' end, './#/points');
  end if;
  return '{"ok":true}';
end $$;

create or replace function public.fh_admin_points_adjust(p_token uuid, p_member int, p_amount int, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.members := public.fh_admin(p_token);
begin
  if coalesce(p_amount, 0) = 0 then return '{"error":"INPUT"}'; end if;
  insert into public.point_adjust(member_id, amount, reason) values (p_member, p_amount, left(p_reason, 80));
  perform public.fh_notify(array[p_member], case when p_amount > 0 then '🎉 보너스 +' || p_amount || '점!' else '포인트 ' || p_amount || '점' end, coalesce(p_reason, ''), './#/points');
  return '{"ok":true}';
end $$;

create or replace function public.fh_admin_rules_save(p_token uuid, p_rules jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.members := public.fh_admin(p_token);
begin
  insert into public.settings values ('points', p_rules) on conflict (key) do update set value = excluded.value;
  return public.fh_rules();
end $$;

create or replace function public.fh_admin_stats(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.members := public.fh_admin(p_token);
begin
  return jsonb_build_object(
    'db_bytes', pg_database_size(current_database()),
    'photo_bytes', pg_total_relation_size('public.post_photos'),
    'posts', (select count(*) from public.posts), 'photos', (select count(*) from public.post_photos),
    'comments', (select count(*) from public.comments), 'todos', (select count(*) from public.todos),
    'events', (select count(*) from public.events), 'messages', (select count(*) from public.messages),
    'push_server', exists (select 1 from public.app_secrets where key = 'push_url'),
    'cron', (select coalesce(jsonb_agg(jsonb_build_object('name', jobname, 'schedule', schedule)), '[]') from cron.job where jobname like 'fh-%'));
exception when others then
  return jsonb_build_object('db_bytes', pg_database_size(current_database()), 'photo_bytes', pg_total_relation_size('public.post_photos'),
    'posts', (select count(*) from public.posts), 'photos', (select count(*) from public.post_photos), 'push_server', exists (select 1 from public.app_secrets where key = 'push_url'), 'cron', '[]'::jsonb);
end $$;

create or replace function public.fh_admin_broadcast(p_token uuid, p_title text, p_body text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.members := public.fh_admin(p_token);
begin
  perform public.fh_notify((select array_agg(id) from public.members where active), coalesce(nullif(p_title, ''), '📢 Family Hub'), coalesce(p_body, ''), './');
  return '{"ok":true}';
end $$;

create or replace function public.fh_admin_logout_member(p_token uuid, p_id int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.members := public.fh_admin(p_token);
begin delete from public.sessions where member_id = p_id and token <> p_token; return '{"ok":true}'; end $$;

-- ---------------------------------------------------------------- 가족 여행
create or replace function public.fh_trip_get(p_m public.members, p_id bigint) returns public.trips
language plpgsql stable security definer set search_path = public as $$
declare t public.trips;
begin
  select * into t from public.trips where id = p_id;
  if not found then raise exception 'NOTFOUND'; end if;
  if not (p_m.id = any(t.members) or t.created_by = p_m.id) then raise exception 'NOT_MEMBER'; end if;
  return t;
end $$;

create or replace function public.fh_trips(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token);
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'title', t.title, 'place', t.place, 'country', t.country, 'emoji', t.emoji,
      'start_on', t.start_on, 'end_on', t.end_on, 'members', t.members, 'mine', m.id = any(t.members) or t.created_by = m.id,
      'plans', (select count(*) from public.trip_items i where i.trip_id = t.id and i.kind = 'plan'),
      'pack_n', (select count(*) from public.trip_items i where i.trip_id = t.id and i.kind = 'pack'),
      'pack_d', (select count(*) from public.trip_items i where i.trip_id = t.id and i.kind = 'pack' and i.done)
    ) order by (t.end_on < public.fh_today()), case when t.end_on < public.fh_today() then -extract(epoch from t.start_on) else extract(epoch from t.start_on) end), '[]')
    from public.trips t);
end $$;

create or replace function public.fh_trip(p_token uuid, p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token); t public.trips := public.fh_trip_get(m, p_id);
begin
  return jsonb_build_object('trip', to_jsonb(t),
    'items', (select coalesce(jsonb_agg(to_jsonb(i) order by i.day nulls last, i.time nulls first, i.sort, i.id), '[]') from public.trip_items i where i.trip_id = t.id),
    'files', (select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'member', f.member_id, 'kind', f.kind, 'title', f.title, 'expires_on', f.expires_on, 'by', f.created_by, 'at', f.created_at) order by f.kind, f.member_id, f.id), '[]') from public.trip_files f where f.trip_id = t.id),
    'expenses', (select coalesce(jsonb_agg(to_jsonb(e) order by e.day desc nulls last, e.id desc), '[]') from public.trip_expenses e where e.trip_id = t.id),
    'msgs', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'from', x.from_id, 'to', x.to_ids, 'body', x.body, 'at', x.created_at) order by x.id desc), '[]')
               from public.trip_msgs x where x.trip_id = t.id and (x.from_id = m.id or m.id = any(x.to_ids))));
end $$;

create or replace function public.fh_trip_save(p_token uuid, p_id bigint, p_title text, p_place text, p_country text, p_start date, p_end date, p_emoji text,
  p_members int[], p_stay text, p_emergency text, p_memo text, p_currency text, p_rate numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token); nid bigint; old public.trips; newbies int[];
begin
  if coalesce(trim(p_title), '') = '' or p_start is null or p_end is null or p_end < p_start then return '{"error":"INPUT"}'; end if;
  if p_end - p_start > 60 then return '{"error":"LONG"}'; end if;
  if p_members is null or array_length(p_members, 1) is null then p_members := array[m.id]; end if;
  if p_id is null then
    insert into public.trips(title, place, country, start_on, end_on, emoji, members, stay, emergency, memo, currency, rate, created_by)
    values (left(trim(p_title), 60), left(p_place, 80), left(p_country, 40), p_start, p_end, coalesce(nullif(left(p_emoji, 8), ''), '✈️'), p_members,
            left(p_stay, 500), left(p_emergency, 500), left(p_memo, 1000), coalesce(nullif(upper(trim(p_currency)), ''), 'KRW'), coalesce(nullif(p_rate, 0), 1), m.id)
    returning id into nid;
    newbies := array(select unnest(p_members) except select m.id);
  else
    old := public.fh_trip_get(m, p_id);
    update public.trips set title = left(trim(p_title), 60), place = left(p_place, 80), country = left(p_country, 40), start_on = p_start, end_on = p_end,
      emoji = coalesce(nullif(left(p_emoji, 8), ''), emoji), members = p_members, stay = left(p_stay, 500), emergency = left(p_emergency, 500), memo = left(p_memo, 1000),
      currency = coalesce(nullif(upper(trim(p_currency)), ''), 'KRW'), rate = coalesce(nullif(p_rate, 0), 1) where id = p_id;
    nid := p_id;
    newbies := array(select unnest(p_members) except select unnest(old.members || array[m.id]));
  end if;
  perform public.fh_notify(newbies, coalesce(nullif(left(p_emoji, 8), ''), '✈️') || ' 가족 여행에 초대됐어요!',
    left(trim(p_title), 60) || ' · ' || to_char(p_start, 'MM/DD') || '~' || to_char(p_end, 'MM/DD') || coalesce(' · ' || nullif(p_place, ''), ''), './#/trip?id=' || nid);
  return jsonb_build_object('id', nid);
end $$;

create or replace function public.fh_trip_del(p_token uuid, p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token);
begin
  delete from public.trips where id = p_id and (created_by = m.id or m.role = 'admin');
  return '{"ok":true}';
end $$;

create or replace function public.fh_trip_item_save(p_token uuid, p_trip bigint, p_id bigint, p_kind text, p_day date, p_time text, p_title text, p_place text, p_memo text, p_assignee int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token); t public.trips := public.fh_trip_get(m, p_trip);
begin
  if coalesce(trim(p_title), '') = '' or p_kind not in ('plan','pack') then return '{"error":"EMPTY"}'; end if;
  if p_id is null then
    insert into public.trip_items(trip_id, kind, day, time, title, place, memo, assignee, sort, created_by)
    values (t.id, p_kind, p_day, nullif(left(p_time, 5), ''), left(trim(p_title), 80), nullif(left(p_place, 120), ''), nullif(left(p_memo, 500), ''), p_assignee,
            (select coalesce(max(sort), 0) + 1 from public.trip_items where trip_id = t.id and kind = p_kind), m.id);
  else
    update public.trip_items set day = p_day, time = nullif(left(p_time, 5), ''), title = left(trim(p_title), 80), place = nullif(left(p_place, 120), ''),
      memo = nullif(left(p_memo, 500), ''), assignee = p_assignee where id = p_id and trip_id = t.id;
  end if;
  return '{"ok":true}';
end $$;

create or replace function public.fh_trip_pack_bulk(p_token uuid, p_trip bigint, p_titles text[], p_assignee int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token); t public.trips := public.fh_trip_get(m, p_trip); n int;
begin
  insert into public.trip_items(trip_id, kind, title, assignee, sort, created_by)
  select t.id, 'pack', left(trim(x), 80), p_assignee, (select coalesce(max(sort), 0) from public.trip_items where trip_id = t.id and kind = 'pack') + row_number() over (), m.id
    from (select distinct on (trim(x)) trim(x) x, ord from unnest(p_titles) with ordinality u(x, ord) order by trim(x), ord) q
   where x <> '' and not exists (select 1 from public.trip_items i where i.trip_id = t.id and i.kind = 'pack' and i.title = trim(x) and i.assignee is not distinct from p_assignee);
  get diagnostics n = row_count;
  return jsonb_build_object('ok', true, 'added', n);
end $$;

create or replace function public.fh_trip_item_toggle(p_token uuid, p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token); tid bigint;
begin
  select trip_id into tid from public.trip_items where id = p_id; perform public.fh_trip_get(m, tid);
  update public.trip_items set done = not done, done_by = case when not done then m.id end where id = p_id;
  return '{"ok":true}';
end $$;

create or replace function public.fh_trip_item_del(p_token uuid, p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token); tid bigint;
begin
  select trip_id into tid from public.trip_items where id = p_id; perform public.fh_trip_get(m, tid);
  delete from public.trip_items where id = p_id;
  return '{"ok":true}';
end $$;

create or replace function public.fh_trip_file_add(p_token uuid, p_trip bigint, p_member int, p_kind text, p_title text, p_data text, p_expires date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token); t public.trips := public.fh_trip_get(m, p_trip);
begin
  if p_data is null or length(p_data) > 2500000 or left(p_data, 11) <> 'data:image/' then return '{"error":"SIZE"}'; end if;
  if (select count(*) from public.trip_files where trip_id = t.id) >= 60 then return '{"error":"MAX"}'; end if;
  insert into public.trip_files(trip_id, member_id, kind, title, data, expires_on, created_by)
  values (t.id, p_member, coalesce(nullif(p_kind, ''), 'etc'), left(p_title, 60), p_data, p_expires, m.id);
  return '{"ok":true}';
end $$;

create or replace function public.fh_trip_file(p_token uuid, p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token); f public.trip_files;
begin
  select * into f from public.trip_files where id = p_id; if not found then return '{"error":"NOTFOUND"}'; end if;
  perform public.fh_trip_get(m, f.trip_id);
  return jsonb_build_object('id', f.id, 'data', f.data);
end $$;

create or replace function public.fh_trip_file_del(p_token uuid, p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token); tid bigint;
begin
  select trip_id into tid from public.trip_files where id = p_id; perform public.fh_trip_get(m, tid);
  delete from public.trip_files where id = p_id;
  return '{"ok":true}';
end $$;

create or replace function public.fh_trip_exp_save(p_token uuid, p_trip bigint, p_id bigint, p_day date, p_title text, p_category text, p_amount numeric, p_currency text, p_paid_by int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token); t public.trips := public.fh_trip_get(m, p_trip);
begin
  if coalesce(trim(p_title), '') = '' or p_amount is null then return '{"error":"INPUT"}'; end if;
  if p_id is null then
    insert into public.trip_expenses(trip_id, day, title, category, amount, currency, paid_by)
    values (t.id, p_day, left(trim(p_title), 60), coalesce(nullif(p_category, ''), '기타'), p_amount, coalesce(nullif(upper(p_currency), ''), 'KRW'), coalesce(p_paid_by, m.id));
  else
    update public.trip_expenses set day = p_day, title = left(trim(p_title), 60), category = coalesce(nullif(p_category, ''), '기타'), amount = p_amount,
      currency = coalesce(nullif(upper(p_currency), ''), 'KRW'), paid_by = coalesce(p_paid_by, m.id) where id = p_id and trip_id = t.id;
  end if;
  return '{"ok":true}';
end $$;

create or replace function public.fh_trip_exp_del(p_token uuid, p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token); tid bigint;
begin
  select trip_id into tid from public.trip_expenses where id = p_id; perform public.fh_trip_get(m, tid);
  delete from public.trip_expenses where id = p_id;
  return '{"ok":true}';
end $$;

-- 여행 멤버를 골라 메시지 보내기 (앱 안 기록 + 휴대폰 알림)
create or replace function public.fh_trip_share(p_token uuid, p_trip bigint, p_to int[], p_body text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token); t public.trips := public.fh_trip_get(m, p_trip); ids int[];
begin
  if coalesce(trim(p_body), '') = '' then return '{"error":"EMPTY"}'; end if;
  ids := array(select x from unnest(p_to) x where x <> m.id and exists (select 1 from public.members where id = x and active));
  if array_length(ids, 1) is null then return '{"error":"TO"}'; end if;
  insert into public.trip_msgs(trip_id, from_id, to_ids, body) values (t.id, m.id, ids, left(p_body, 4000));
  perform public.fh_notify(ids, t.emoji || ' ' || t.title || ' · ' || coalesce(m.nick, m.name), left(regexp_replace(p_body, '\s+', ' ', 'g'), 100), './#/trip?id=' || t.id || '&tab=share');
  return jsonb_build_object('ok', true, 'sent', array_length(ids, 1));
end $$;

-- ---------------------------------------------------------------- 프로필 사진
create or replace function public.fh_photo_me(p_token uuid, p_data text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token);
begin
  if p_data is not null and (length(p_data) > 400000 or left(p_data, 11) <> 'data:image/') then return '{"error":"SIZE"}'; end if;
  update public.members set photo = p_data, photo_at = case when p_data is null then null else now() end where id = m.id returning * into m;
  return public.fh_mj(m);
end $$;

create or replace function public.fh_admin_member_photo(p_token uuid, p_id int, p_data text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.members := public.fh_admin(p_token);
begin
  if p_data is not null and (length(p_data) > 400000 or left(p_data, 11) <> 'data:image/') then return '{"error":"SIZE"}'; end if;
  update public.members set photo = p_data, photo_at = case when p_data is null then null else now() end where id = p_id;
  return '{"ok":true}';
end $$;

create or replace function public.fh_member_photos(p_token uuid, p_ids int[]) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token);
begin
  return (select coalesce(jsonb_object_agg(id, photo), '{}') from public.members where id = any(p_ids) and photo is not null);
end $$;

-- ---------------------------------------------------------------- 사진 인증 할 일
create or replace function public.fh_parent(p_token uuid) returns public.members
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token);
begin
  if not (m.is_parent or m.role = 'admin') then raise exception 'NOT_PARENT' using errcode = '42501'; end if;
  return m;
end $$;

-- 부모가 아이에게 할 일 주기 (사진 인증 + 최대 점수)
create or replace function public.fh_todo_assign(p_token uuid, p_member int, p_day date, p_text text, p_max int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_parent(p_token);
begin
  if coalesce(trim(p_text), '') = '' then return '{"error":"EMPTY"}'; end if;
  if p_day < public.fh_today() then return '{"error":"PAST"}'; end if;
  insert into public.todos(member_id, day, text, sort, proof, status, max_points, assigned_by)
  values (p_member, p_day, left(trim(p_text), 100), (select coalesce(max(sort), 0) + 1 from public.todos where member_id = p_member and day = p_day),
          true, 'todo', greatest(1, least(coalesce(p_max, 20), 100)), m.id);
  perform public.fh_notify(array[p_member], '📋 새 할 일이 생겼어요', coalesce(m.nick, m.name) || ': ' || left(trim(p_text), 60) || ' (최대 ' || coalesce(p_max, 20) || '점 · 사진 인증)', './#/todo');
  return '{"ok":true}';
end $$;

-- 아이가 Before / After 사진 올리기
create or replace function public.fh_todo_photo(p_token uuid, p_id bigint, p_kind text, p_data text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token); t public.todos;
begin
  select * into t from public.todos where id = p_id and member_id = m.id and proof;
  if not found then return '{"error":"NOTFOUND"}'; end if;
  if t.status in ('review', 'approved') then return '{"error":"LOCKED_TODO"}'; end if;
  if p_kind not in ('before', 'after') then return '{"error":"INPUT"}'; end if;
  if p_data is null then delete from public.todo_photos where todo_id = p_id and kind = p_kind; return '{"ok":true}'; end if;
  if length(p_data) > 1500000 or left(p_data, 11) <> 'data:image/' then return '{"error":"SIZE"}'; end if;
  insert into public.todo_photos(todo_id, kind, data) values (p_id, p_kind, p_data)
  on conflict (todo_id, kind) do update set data = excluded.data, created_at = now();
  return '{"ok":true}';
end $$;

-- 확인 요청 보내기 (After 사진 필수)
create or replace function public.fh_todo_submit(p_token uuid, p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token); t public.todos; ids int[];
begin
  select * into t from public.todos where id = p_id and member_id = m.id and proof;
  if not found then return '{"error":"NOTFOUND"}'; end if;
  if not exists (select 1 from public.todo_photos where todo_id = p_id and kind = 'after') then return '{"error":"NO_AFTER"}'; end if;
  update public.todos set status = 'review', submitted_at = now(), review_note = null where id = p_id;
  select array_agg(id) into ids from public.members where active and (is_parent or role = 'admin') and id <> m.id;
  perform public.fh_notify(ids, '📸 ' || coalesce(m.nick, m.name) || '의 인증 사진', left(t.text, 60) || ' · Before/After를 확인하고 점수를 주세요', './#/review');
  return '{"ok":true}';
end $$;

create or replace function public.fh_todo_photos(p_token uuid, p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_auth(p_token);
begin
  return (select coalesce(jsonb_object_agg(kind, data), '{}') from public.todo_photos where todo_id = p_id);
end $$;

-- 부모 확인 목록
create or replace function public.fh_review_list(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_parent(p_token);
begin
  return jsonb_build_object(
    'pending', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'member', t.member_id, 'text', t.text, 'day', t.day, 'max', coalesce(t.max_points, 20), 'by', t.assigned_by, 'at', t.submitted_at,
                  'before', exists (select 1 from public.todo_photos ph where ph.todo_id = t.id and ph.kind = 'before')) order by t.submitted_at), '[]')
                from public.todos t where t.status = 'review' and t.member_id <> m.id),
    'done', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'member', t.member_id, 'text', t.text, 'day', t.day, 'status', t.status, 'points', t.points, 'note', t.review_note, 'rby', t.reviewed_by, 'at', t.reviewed_at) order by t.reviewed_at desc), '[]')
                from (select * from public.todos where proof and status in ('approved', 'rejected') and reviewed_at > now() - interval '14 days' order by reviewed_at desc limit 30) t));
end $$;

-- 부모가 점수 주기 / 다시 하기
create or replace function public.fh_todo_review(p_token uuid, p_id bigint, p_ok boolean, p_points int, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.members := public.fh_parent(p_token); t public.todos; pts int;
begin
  select * into t from public.todos where id = p_id and status = 'review';
  if not found then return '{"error":"NOTFOUND"}'; end if;
  if t.member_id = m.id then return '{"error":"SELF_REVIEW"}'; end if;
  if p_ok then
    pts := greatest(0, least(coalesce(p_points, t.max_points, 20), 100));
    update public.todos set status = 'approved', done = true, done_at = now(), points = pts, reviewed_by = m.id, reviewed_at = now(), review_note = nullif(left(trim(coalesce(p_note, '')), 200), '') where id = p_id;
    perform public.fh_notify(array[t.member_id], '✅ 인증 완료! +' || pts || '점', left(t.text, 50) || coalesce(' · ' || nullif(trim(coalesce(p_note, '')), ''), ' · 정말 잘했어요!'), './#/todo');
  else
    update public.todos set status = 'rejected', reviewed_by = m.id, reviewed_at = now(), review_note = nullif(left(trim(coalesce(p_note, '')), 200), '') where id = p_id;
    perform public.fh_notify(array[t.member_id], '🔁 한 번 더 해 볼까요?', left(t.text, 50) || coalesce(' · ' || nullif(trim(coalesce(p_note, '')), ''), ''), './#/todo');
  end if;
  return jsonb_build_object('ok', true, 'points', pts);
end $$;

create or replace function public.fh_admin_member_parent(p_token uuid, p_id int, p_on boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.members := public.fh_admin(p_token);
begin update public.members set is_parent = coalesce(p_on, false) where id = p_id; return '{"ok":true}'; end $$;

-- ---------------------------------------------------------------- 실행 권한 정리
do $$ declare f record; begin
  for f in select p.oid::regprocedure sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname like 'fh\_%' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname not in ('fh_auth','fh_admin','fh_mj','fh_rules','fh_points','fh_notify','fh_others','fh_nick','fh_daily_push','fh_next','fh_trip_get','fh_parent') then
      execute format('grant execute on function %s to anon, authenticated', f.sig);
    end if;
  end loop;
end $$;

notify pgrst, 'reload schema';
-- 끝. 결과 창에 Success 가 보이면 완료입니다.

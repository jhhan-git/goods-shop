-- 굿즈 쇼핑몰 초기 스키마
-- 상품 / 주문 / 주문상품 / 관리자 테이블과 보안 규칙(RLS), 주문 생성 함수

-- ───────── 테이블 ─────────
create table public.products (
  id          bigint generated always as identity primary key,
  name        text    not null,
  description text    not null default '',
  price       integer not null check (price > 0),
  emoji       text    not null default '🎁',
  image_url   text,
  created_at  timestamptz not null default now()
);

create table public.admins (
  user_id uuid primary key references auth.users (id) on delete cascade
);

create table public.orders (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users (id) on delete cascade,
  user_email     text not null default '',
  order_name     text not null default '',
  total_amount   integer not null default 0 check (total_amount >= 0),
  status         text not null default 'pending' check (status in ('pending', 'paid', 'failed')),
  payment_key    text,
  payment_method text,
  approved_at    timestamptz,
  created_at     timestamptz not null default now()
);
create index orders_user_id_idx on public.orders (user_id);
create index orders_created_at_idx on public.orders (created_at desc);

create table public.order_items (
  id           bigint generated always as identity primary key,
  order_id     uuid    not null references public.orders (id) on delete cascade,
  product_id   bigint  not null references public.products (id),
  product_name text    not null,
  unit_price   integer not null check (unit_price > 0),
  quantity     integer not null check (quantity between 1 and 99)
);
create index order_items_order_id_idx on public.order_items (order_id);
create index order_items_product_id_idx on public.order_items (product_id);

-- ───────── 권한: 화면(브라우저)에서는 읽기만 가능 ─────────
revoke insert, update, delete, truncate on public.products, public.admins, public.orders, public.order_items from anon, authenticated;

alter table public.products    enable row level security;
alter table public.admins      enable row level security;
alter table public.orders      enable row level security;
alter table public.order_items enable row level security;

-- 관리자인지 확인하는 함수
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.admins where user_id = (select auth.uid()));
$$;
revoke execute on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;

-- ───────── 보안 규칙(RLS) ─────────
create policy "상품은 누구나 조회" on public.products
  for select to anon, authenticated using (true);

create policy "본인 관리자 여부만 조회" on public.admins
  for select to authenticated using (user_id = (select auth.uid()));

create policy "본인 주문 또는 관리자 조회" on public.orders
  for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));

create policy "본인 주문상품 또는 관리자 조회" on public.order_items
  for select to authenticated
  using (exists (
    select 1 from public.orders o
    where o.id = order_id
      and (o.user_id = (select auth.uid()) or (select public.is_admin()))
  ));

-- ───────── 주문 생성 함수 ─────────
-- items: [{"product_id": 1, "quantity": 2}, ...]
-- 가격은 브라우저가 보낸 값이 아니라 DB의 상품 가격으로 계산한다.
create or replace function public.create_order(items jsonb)
returns table (order_id uuid, amount integer, order_name text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := auth.uid();
  v_order    uuid := gen_random_uuid();
  v_expected integer;
  v_count    integer;
  v_total    integer;
  v_first    text;
  v_name     text;
begin
  if v_uid is null then
    raise exception '로그인이 필요해요';
  end if;
  if jsonb_typeof(items) <> 'array' or jsonb_array_length(items) = 0 or jsonb_array_length(items) > 50 then
    raise exception '장바구니가 올바르지 않아요';
  end if;

  select count(distinct (e ->> 'product_id')) into v_expected from jsonb_array_elements(items) e;

  insert into public.orders (id, user_id, user_email)
  values (v_order, v_uid, coalesce(auth.jwt() ->> 'email', ''));

  insert into public.order_items (order_id, product_id, product_name, unit_price, quantity)
  select v_order, p.id, p.name, p.price, r.qty
  from (
    select (e ->> 'product_id')::bigint as pid, sum((e ->> 'quantity')::integer)::integer as qty
    from jsonb_array_elements(items) e
    group by 1
  ) r
  join public.products p on p.id = r.pid;
  get diagnostics v_count = row_count;

  if v_count <> v_expected then
    raise exception '없는 상품이 장바구니에 있어요';
  end if;

  select sum(oi.unit_price * oi.quantity)::integer, (array_agg(oi.product_name order by oi.id))[1]
    into v_total, v_first
  from public.order_items oi
  where oi.order_id = v_order;

  v_name := case when v_count > 1 then v_first || ' 외 ' || (v_count - 1) || '건' else v_first end;

  update public.orders set total_amount = v_total, order_name = v_name where id = v_order;

  return query select v_order, v_total, v_name;
end;
$$;
revoke execute on function public.create_order(jsonb) from public, anon;
grant execute on function public.create_order(jsonb) to authenticated;

-- ───────── 예시 상품 ─────────
insert into public.products (name, description, price, emoji) values
  ('로고 머그컵',     '매일 쓰기 좋은 350ml 세라믹 머그컵',   12000, '☕'),
  ('스티커 팩',       '노트북에 붙이기 좋은 방수 스티커 10장', 4500,  '🌈'),
  ('캔버스 에코백',   '튼튼한 코튼 캔버스 소재 에코백',        18000, '👜'),
  ('아크릴 키링',     '양면 인쇄 아크릴 키링',                 7000,  '🔑'),
  ('오버핏 후드티',   '도톰한 기모 안감의 오버핏 후드티',      45000, '🧥'),
  ('자수 볼캡',       '로고 자수가 들어간 면 볼캡',            22000, '🧢');

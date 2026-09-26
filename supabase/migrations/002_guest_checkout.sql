-- 비회원 구매
-- 비회원은 Supabase 익명 로그인(is_anonymous)으로 임시 계정을 받고, 주문할 때 연락용 이메일을 입력한다.

alter table public.orders add column is_guest boolean not null default false;

-- create_order에 비회원 이메일 인자 추가 (기존 함수 교체)
drop function public.create_order(jsonb);

create function public.create_order(items jsonb, guest_email text default null)
returns table (order_id uuid, amount integer, order_name text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := auth.uid();
  v_guest    boolean := coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false);
  v_email    text;
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

  if v_guest then
    v_email := lower(trim(coalesce(guest_email, '')));
    if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
      raise exception '주문 확인에 쓸 이메일을 정확히 입력해 주세요';
    end if;
  else
    v_email := coalesce(auth.jwt() ->> 'email', '');
  end if;

  select count(distinct (e ->> 'product_id')) into v_expected from jsonb_array_elements(items) e;

  insert into public.orders (id, user_id, user_email, is_guest)
  values (v_order, v_uid, v_email, v_guest);

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
revoke execute on function public.create_order(jsonb, text) from public, anon;
grant execute on function public.create_order(jsonb, text) to authenticated;

-- 비회원 주문 조회: 주문번호 + 이메일이 모두 맞으면 주문 1건을 돌려준다 (다른 기기에서도 조회 가능)
create function public.find_guest_order(p_order_id uuid, p_email text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select (to_jsonb(o) - 'user_id' - 'payment_key')
         || jsonb_build_object('order_items', coalesce(
              (select jsonb_agg(to_jsonb(i) order by i.id) from public.order_items i where i.order_id = o.id),
              '[]'::jsonb))
  from public.orders o
  where o.id = p_order_id
    and o.is_guest
    and o.status <> 'pending'
    and o.user_email = lower(trim(p_email));
$$;
revoke execute on function public.find_guest_order(uuid, text) from public;
grant execute on function public.find_guest_order(uuid, text) to anon, authenticated;

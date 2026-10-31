create extension if not exists pgcrypto;
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to anon, authenticated;

create table if not exists private.owner_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
revoke all on private.owner_users from public, anon, authenticated;

-- Owner bootstrap: create this Auth user FIRST, then run this SQL.
insert into private.owner_users(user_id)
select id from auth.users where lower(email)=lower('satanteam034@gmail.com')
on conflict (user_id) do nothing;

create or replace function private.is_owner()
returns boolean language sql stable security definer set search_path=''
as $$
 select exists(select 1 from private.owner_users where user_id=(select auth.uid()));
$$;
revoke all on function private.is_owner() from public;
grant execute on function private.is_owner() to anon, authenticated;

create or replace function public.is_owner()
returns boolean language sql stable security definer set search_path=''
as $$ select private.is_owner(); $$;
revoke all on function public.is_owner() from public;
grant execute on function public.is_owner() to authenticated;

create table if not exists public.products (
 id uuid primary key default gen_random_uuid(),
 name text not null,
 description text not null default '',
 additional_info text not null default '',
 variations text not null default '',
 category text not null default 'Umum',
 price bigint not null check(price>=0),
 discount_price bigint check(discount_price is null or discount_price>=0),
 stock integer not null default 0 check(stock>=0),
 image_url text not null default '',
 sales_count integer not null default 0,
 rating numeric(3,2) not null default 5,
 is_active boolean not null default true,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table if not exists public.orders (
 id text primary key,
 customer_name text not null,
 customer_phone text not null,
 address text not null,
 notes text not null default '',
 payment_method text not null default '',
 items jsonb not null check(jsonb_typeof(items)='array'),
 total bigint not null check(total>=0),
 status text not null default 'Pesanan Baru',
 created_at timestamptz not null default now()
);

alter table public.products enable row level security;
alter table public.orders enable row level security;

drop policy if exists "Public read active products" on public.products;
create policy "Public read active products" on public.products
for select to anon, authenticated using (is_active=true or private.is_owner());

drop policy if exists "Owner manage products" on public.products;
create policy "Owner manage products" on public.products
for all to authenticated using (private.is_owner()) with check (private.is_owner());

drop policy if exists "Owner read orders" on public.orders;
create policy "Owner read orders" on public.orders
for select to authenticated using (private.is_owner());

drop policy if exists "Owner update orders" on public.orders;
create policy "Owner update orders" on public.orders
for update to authenticated using (private.is_owner()) with check (private.is_owner());

drop policy if exists "Owner delete orders" on public.orders;
create policy "Owner delete orders" on public.orders
for delete to authenticated using (private.is_owner());

grant select on public.products to anon, authenticated;
grant insert, update, delete on public.products to authenticated;
grant select, update, delete on public.orders to authenticated;
revoke insert on public.orders from anon, authenticated;

-- Secure checkout: validates product IDs, price and stock in PostgreSQL.
create or replace function public.create_order(
 p_customer_name text,
 p_customer_phone text,
 p_address text,
 p_notes text,
 p_payment_method text,
 p_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
 item jsonb;
 product_row public.products%rowtype;
 qty integer;
 unit_price bigint;
 total_amount bigint := 0;
 saved_items jsonb := '[]'::jsonb;
 new_id text := 'ORD-' || to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS') || '-' || upper(substr(encode(gen_random_bytes(3),'hex'),1,6));
begin
 if length(trim(coalesce(p_customer_name,''))) < 2 or length(p_customer_name)>120 then
   raise exception 'Nama pelanggan tidak valid';
 end if;
 if length(trim(coalesce(p_customer_phone,''))) < 6 or length(p_customer_phone)>30 then
   raise exception 'Nomor telepon tidak valid';
 end if;
 if length(trim(coalesce(p_address,''))) < 5 or length(p_address)>1000 then
   raise exception 'Alamat tidak valid';
 end if;
 if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items)<1 or jsonb_array_length(p_items)>50 then
   raise exception 'Daftar produk tidak valid';
 end if;

 for item in select value from jsonb_array_elements(p_items)
 loop
   qty := (item->>'quantity')::integer;
   if qty < 1 or qty > 20 then raise exception 'Jumlah produk tidak valid'; end if;
   select * into product_row from public.products
    where id=(item->>'product_id')::uuid and is_active=true
    for update;
   if not found then raise exception 'Produk tidak tersedia'; end if;
   if product_row.stock < qty then raise exception 'Stok produk % tidak cukup', product_row.name; end if;
   unit_price := coalesce(product_row.discount_price,product_row.price);
   total_amount := total_amount + unit_price*qty;
   saved_items := saved_items || jsonb_build_array(jsonb_build_object(
     'product_id',product_row.id,'name',product_row.name,
     'variation',coalesce(item->>'variation',''),
     'quantity',qty,'unit_price',unit_price
   ));
   update public.products set stock=stock-qty, sales_count=sales_count+qty, updated_at=now()
    where id=product_row.id;
 end loop;

 insert into public.orders(id,customer_name,customer_phone,address,notes,payment_method,items,total,status)
 values(new_id,trim(p_customer_name),trim(p_customer_phone),trim(p_address),
        coalesce(p_notes,''),coalesce(p_payment_method,''),saved_items,total_amount,'Pesanan Baru');
 return jsonb_build_object('id',new_id,'total',total_amount);
end;
$$;
revoke all on function public.create_order(text,text,text,text,text,jsonb) from public;
grant execute on function public.create_order(text,text,text,text,text,jsonb) to anon, authenticated;

-- Seed starter products if the catalog is empty.
insert into public.products(name,description,additional_info,variations,category,price,discount_price,stock,image_url,sales_count,rating)
select 'Gamis Modern Premium Edition SAWWAL',
 'Gamis dengan bahan katun toyobo super halus, adem, tidak menerawang, dan nyaman untuk acara formal maupun harian.',
 'Garansi retur 7 hari jika terdapat cacat pabrik atau salah ukuran.',
 'Warna: Hitam, Navy, Olive | Ukuran: M, L, XL','Busana Muslim',350000,289000,25,
 'https://images.unsplash.com/photo-1583391733956-3750e0ff4e8b?auto=format&fit=crop&q=80&w=600',142,4.9
where not exists(select 1 from public.products);
insert into public.products(name,description,additional_info,variations,category,price,discount_price,stock,image_url,sales_count,rating)
select 'Kemeja Koko Modern Slimfit SAWWAL',
 'Kemeja koko berbahan katun linen premium dengan jahitan presisi.',
 'Bahan adem, tidak mudah kusut.','Warna: Putih, Abu, Mocca | Ukuran: L, XL, XXL',
 'Busana Muslim',220000,175000,40,
 'https://images.unsplash.com/photo-1602810318383-e386cc2a3ccf?auto=format&fit=crop&q=80&w=600',98,4.8
where not exists(select 1 from public.products where name='Kemeja Koko Modern Slimfit SAWWAL');
insert into public.products(name,description,additional_info,variations,category,price,discount_price,stock,image_url,sales_count,rating)
select 'Hijab Pashmina Silk Luxury Edition',
 'Pashmina silk berkualitas tinggi yang lembut, mudah dibentuk.',
 '100% Original SAWWAL Hijab Collection.',
 'Warna: Rose Gold, Mocca, Emerald, Jet Black','Hijab & Aksesoris',95000,65000,60,
 'https://images.unsplash.com/photo-1584917865442-de89df76afd3?auto=format&fit=crop&q=80&w=600',230,5.0
where not exists(select 1 from public.products where name='Hijab Pashmina Silk Luxury Edition');

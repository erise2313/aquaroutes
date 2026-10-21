-- =====================================================================
-- Sample products and prices for the seeded stations (demo/testing only).
--
-- Customers order products, not a station's single price. The schema step
-- turns each existing station's price into products, but on a new project
-- it runs before any station exists, so without this the seeded stations
-- would have nothing to order.
--
--   Buenavista (owner1)      purified and alkaline, slim and round 5-gal,
--                            1-gallon, 350 mL bottle, a new slim jug
--   Navarro Springs (owner2) purified and mineral, slim and round 5-gal,
--                            500 mL bottle
--   Tejero (owner3)          purified, slim and round 5-gal
--
-- Prices are typical General Trias refill prices, for demonstration.
-- Additive and idempotent: a product a station already lists is left as
-- it is. Run after seed_role_accounts.sql. Safe to re-run.
-- DO NOT run this against a production project with real users.
-- =====================================================================

do $$
declare
  r record;
begin
  for r in
    select ws.id as station_id, p.water_type, p.container_code, p.kind, p.price
      from (values
        ('owner1@gentriwasa.test', 'purified', 'slim_5gal',    'refill',         25.00),
        ('owner1@gentriwasa.test', 'purified', 'round_5gal',   'refill',         25.00),
        ('owner1@gentriwasa.test', 'alkaline', 'slim_5gal',    'refill',         35.00),
        ('owner1@gentriwasa.test', 'alkaline', 'round_5gal',   'refill',         35.00),
        ('owner1@gentriwasa.test', 'purified', 'gallon_1',     'refill',         10.00),
        ('owner1@gentriwasa.test', 'purified', 'bottle_350ml', 'refill',          8.00),
        ('owner1@gentriwasa.test', 'purified', 'slim_5gal',    'new_container', 220.00),
        ('owner2@gentriwasa.test', 'purified', 'slim_5gal',    'refill',         22.00),
        ('owner2@gentriwasa.test', 'purified', 'round_5gal',   'refill',         22.00),
        ('owner2@gentriwasa.test', 'mineral',  'slim_5gal',    'refill',         30.00),
        ('owner2@gentriwasa.test', 'mineral',  'round_5gal',   'refill',         30.00),
        ('owner2@gentriwasa.test', 'purified', 'bottle_500ml', 'refill',         10.00),
        ('owner3@gentriwasa.test', 'purified', 'slim_5gal',    'refill',         25.00),
        ('owner3@gentriwasa.test', 'purified', 'round_5gal',   'refill',         25.00)
      ) as p(owner_email, water_type, container_code, kind, price)
      join auth.users u on u.email = p.owner_email
      join water_stations ws on ws.owner_profile_id = u.id
  loop
    insert into station_products (station_id, water_type, container_code, kind, price)
    values (r.station_id, r.water_type, r.container_code, r.kind, r.price)
    on conflict (station_id, water_type, container_code, kind) do nothing;
  end loop;

  -- Water types, containers and the "from" price shown on the map follow
  -- the products.
  for r in select distinct station_id from station_products loop
    perform sync_station_from_products(r.station_id);
  end loop;
end $$;

-- VERIFY -- products per station.
select ws.station_name, count(*) as products, min(sp.price) as from_price
  from station_products sp join water_stations ws on ws.id = sp.station_id
 group by ws.station_name
 order by ws.station_name;

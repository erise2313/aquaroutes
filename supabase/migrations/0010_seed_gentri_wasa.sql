-- Seed data: the GENTRI WASA association plus its 33 constituent barangays.
-- Barangay list verified against General Trias City's official roster
-- (PhilAtlas / Barangay Directory), not reverse-engineered from app data.

insert into associations (id, name, province, municipality)
values ('00000000-0000-0000-0000-000000000001', 'GENTRI WASA', 'Cavite', 'General Trias')
on conflict (id) do nothing;

insert into barangays (association_id, name)
select '00000000-0000-0000-0000-000000000001', name
from (values
  ('Alingaro'),
  ('Arnaldo (Poblacion 7)'),
  ('Bacao I'),
  ('Bacao II'),
  ('Bagumbayan (Poblacion 5)'),
  ('Biclatan'),
  ('Buenavista I'),
  ('Buenavista II'),
  ('Buenavista III'),
  ('Corregidor (Poblacion 10)'),
  ('Dulong Bayan (Poblacion 3)'),
  ('Gov. Ferrer (Poblacion 1)'),
  ('Javalera'),
  ('Manggahan'),
  ('Navarro'),
  ('Ninety Sixth (Poblacion 8)'),
  ('Panungyanan'),
  ('Pasong Camachile I'),
  ('Pasong Camachile II'),
  ('Pasong Kawayan I'),
  ('Pasong Kawayan II'),
  ('Pinagtipunan'),
  ('Prinza (Poblacion 9)'),
  ('Sampalucan (Poblacion 2)'),
  ('San Francisco'),
  ('San Gabriel (Poblacion 4)'),
  ('San Juan I'),
  ('San Juan II'),
  ('Santa Clara'),
  ('Santiago'),
  ('Tapia'),
  ('Tejero'),
  ('Vibora (Poblacion 6)')
) as b(name)
on conflict (association_id, name) do nothing;

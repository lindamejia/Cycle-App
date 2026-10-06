-- Creates 20 random invite codes (one per tester, a few spare).
-- Run in the SQL editor, then copy the list into your own offline sheet of who got which code.
insert into public.invite_codes (code)
select upper(substr(encode(gen_random_bytes(6), 'hex'), 1, 4) || '-' || substr(encode(gen_random_bytes(6), 'hex'), 1, 4))
  from generate_series(1, 20)
returning code;

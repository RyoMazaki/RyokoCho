-- Run after migrations ONLY on a disposable database, as postgres.
-- Fixtures, including the test-only membership writes, are always rolled back.
BEGIN;
CREATE FUNCTION pg_temp.assert_trip_read(p_ok boolean, p_message text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF p_ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'ASSERT: %', p_message; END IF;
END;
$$;

INSERT INTO auth.users(id) VALUES
 ('20000000-0000-0000-0000-000000000001'), -- creator
 ('20000000-0000-0000-0000-000000000002'), -- regular member
 ('20000000-0000-0000-0000-000000000003'), -- outsider
 ('20000000-0000-0000-0000-000000000004'), -- member who leaves
 ('20000000-0000-0000-0000-000000000005'); -- other creator

INSERT INTO public.trips(id,name,start_date,end_date,visibility,created_by) VALUES
 ('30000000-0000-0000-0000-000000000001','Private trip','2026-10-01','2026-10-02','private','20000000-0000-0000-0000-000000000001'),
 ('30000000-0000-0000-0000-000000000002','Unlisted trip','2026-10-03','2026-10-03','unlisted','20000000-0000-0000-0000-000000000001'),
 ('30000000-0000-0000-0000-000000000003','Other trip','2026-10-04','2026-10-05','private','20000000-0000-0000-0000-000000000005');
INSERT INTO public.trip_members(trip_id,user_id)
SELECT t.id,u.id FROM public.trips t CROSS JOIN auth.users u
WHERE t.id IN ('30000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000002')
  AND u.id IN ('20000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000004');

INSERT INTO public.profiles(id,display_name,avatar_path) VALUES
 ('20000000-0000-0000-0000-000000000001','Same',NULL),
 ('20000000-0000-0000-0000-000000000002','Same','member/avatar.jpg'),
 ('20000000-0000-0000-0000-000000000003','Outsider',NULL),
 ('20000000-0000-0000-0000-000000000005','Other creator',NULL);
-- The fourth member deliberately has no profile; existing RPC uses INNER JOIN.
CREATE FUNCTION pg_temp.assert_members_denied(p_trip_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    PERFORM * FROM public.get_trip_members(p_trip_id);
    RAISE EXCEPTION 'member RPC unexpectedly allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END;
$$;
-- Queries under API roles, not the bypassing fixture owner.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','20000000-0000-0000-0000-000000000001',true);
SELECT pg_temp.assert_trip_read((SELECT count(*)=2 FROM public.trips),'creator reads only own memberships');
SELECT pg_temp.assert_trip_read((SELECT count(*)=2 FROM public.get_trip_members('30000000-0000-0000-0000-000000000001')),'creator member profiles');
SELECT pg_temp.assert_trip_read(
 (SELECT count(*)=0 FROM public.trips WHERE id='30000000-0000-0000-0000-000000000003'),
 'creator cannot read another trip');

SELECT set_config('request.jwt.claim.sub','20000000-0000-0000-0000-000000000002',true);
SELECT pg_temp.assert_trip_read((SELECT count(*)=2 FROM public.trips),'member reads private and unlisted trips');
SELECT pg_temp.assert_trip_read(
 (SELECT name='Private trip' AND start_date='2026-10-01' AND end_date='2026-10-02'
   AND thumbnail_path IS NULL AND visibility='private'
  FROM public.trips WHERE id='30000000-0000-0000-0000-000000000001'),
 'detail fields returned for member');
SELECT pg_temp.assert_trip_read(
 (SELECT id='30000000-0000-0000-0000-000000000002'
  FROM public.trips WHERE id > '30000000-0000-0000-0000-000000000001' ORDER BY id LIMIT 1),
 'cursor page stays inside membership');
SELECT pg_temp.assert_trip_read(
 (SELECT count(*)=0 FROM public.trips WHERE id='30000000-0000-0000-0000-000000000099'),
 'missing trip is empty');

SELECT pg_temp.assert_trip_read(
 (SELECT count(*)=2 AND count(*) FILTER (WHERE avatar_path IS NULL)=1
 AND bool_and(display_name='Same')
 FROM public.get_trip_members('30000000-0000-0000-0000-000000000001')),
 'member reads others, duplicate names and null avatars without collapsing rows');
SELECT pg_temp.assert_trip_read(
 (SELECT count(*)=2 FROM public.get_trip_members('30000000-0000-0000-0000-000000000002')),
 'member profiles for unlisted trip');
SELECT pg_temp.assert_members_denied('30000000-0000-0000-0000-000000000003');
SELECT pg_temp.assert_members_denied('30000000-0000-0000-0000-000000000099');
SELECT set_config('request.jwt.claim.sub','20000000-0000-0000-0000-000000000003',true);
SELECT pg_temp.assert_members_denied('30000000-0000-0000-0000-000000000001');
SELECT pg_temp.assert_members_denied('30000000-0000-0000-0000-000000000002');
SELECT pg_temp.assert_trip_read((SELECT count(*)=0 FROM public.trips),'outsider list empty');
SELECT pg_temp.assert_trip_read(
 (SELECT count(*)=0 FROM public.trips WHERE id='30000000-0000-0000-0000-000000000001'),
 'outsider private detail denied');
SELECT pg_temp.assert_trip_read(
 (SELECT count(*)=0 FROM public.trips WHERE id='30000000-0000-0000-0000-000000000002'),
 'unlisted visibility alone never grants member detail access');

SELECT set_config('request.jwt.claim.sub','20000000-0000-0000-0000-000000000004',true);
SELECT pg_temp.assert_trip_read((SELECT count(*)=2 FROM public.trips),'leaver initially sees trips');
DELETE FROM public.trip_members WHERE user_id=auth.uid();
SELECT pg_temp.assert_trip_read((SELECT count(*)=0 FROM public.trips),'leaver list immediately empty');
SELECT pg_temp.assert_members_denied('30000000-0000-0000-0000-000000000001');
SELECT pg_temp.assert_trip_read(
 (SELECT count(*)=0 FROM public.trips WHERE id IN
 ('30000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000002')),
 'leaver details immediately denied with unchanged auth identity');

-- An authenticated role without an identity also has no visible rows.
SELECT set_config('request.jwt.claim.sub','',true);
SELECT pg_temp.assert_trip_read((SELECT count(*)=0 FROM public.trips),'missing claim denied');
SELECT pg_temp.assert_members_denied('30000000-0000-0000-0000-000000000001');

SET LOCAL ROLE anon;
SELECT pg_temp.assert_members_denied('30000000-0000-0000-0000-000000000001');
DO $$
BEGIN
  BEGIN
    PERFORM id,name,start_date,end_date,thumbnail_path FROM public.trips;
    RAISE EXCEPTION 'anonymous list unexpectedly readable';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM id,name,start_date,end_date,thumbnail_path,visibility FROM public.trips
      WHERE id='30000000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'anonymous detail unexpectedly readable';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END;
$$;
RESET ROLE;
SELECT 'trip_read_checks_passed' AS result;
ROLLBACK;

-- Run AFTER migrations against a disposable Supabase database, as postgres.
-- All fixtures and test helpers are rolled back, including on psql connection exit.
BEGIN;
CREATE FUNCTION pg_temp.assert_true(p_ok boolean, p_message text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF p_ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'ASSERT: %', p_message; END IF;
END;
$$;
CREATE FUNCTION pg_temp.expect_error(p_sql text, p_code text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_code text;
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_code = RETURNED_SQLSTATE;
  END;
  IF v_code IS DISTINCT FROM p_code THEN
    RAISE EXCEPTION 'Expected SQLSTATE %, got % for %', p_code, coalesce(v_code,'success'), p_sql;
  END IF;
END;
$$;

SELECT pg_temp.assert_true(
  (SELECT count(*) = 5 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relname IN
   ('profiles','trips','trip_members','itinerary_items','itinerary_photos') AND c.relrowsecurity),
  'RLS on every app table');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 5 FROM pg_indexes WHERE schemaname='public' AND indexname IN
   ('trips_created_by_idx','trip_members_user_trip_idx','itinerary_items_trip_date_order_idx',
    'itinerary_photos_item_idx','itinerary_photos_uploaded_by_idx')), 'five supporting indexes');
SELECT pg_temp.assert_true(
  NOT pg_has_role('authenticated','ryoko_reader','MEMBER')
  AND NOT pg_has_role('anon','ryoko_reader','MEMBER'), 'internal role inaccessible');
SELECT pg_temp.assert_true(
  (SELECT count(*)=3 FROM storage.buckets
   WHERE id IN ('avatars','trip-thumbnails','itinerary-photos') AND NOT public), 'three private buckets');


SELECT pg_temp.assert_true((
 SELECT count(*)=7
 FROM (VALUES
   ('profiles','id','auth.users','c'),
   ('trips','created_by','auth.users','a'),
   ('trip_members','trip_id','public.trips','c'),
   ('trip_members','user_id','auth.users','c'),
   ('itinerary_items','trip_id','public.trips','c'),
   ('itinerary_photos','itinerary_item_id','public.itinerary_items','c'),
   ('itinerary_photos','uploaded_by','auth.users','a')
 ) AS e(tbl,col,parent,action)
 JOIN pg_constraint c ON c.conrelid=to_regclass('public.'||e.tbl)
   AND c.contype='f' AND c.confrelid=to_regclass(e.parent) AND c.confdeltype::text=e.action
 JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attname=e.col AND c.conkey=ARRAY[a.attnum]
), 'all seven application FK targets and ON DELETE actions');
SELECT pg_temp.assert_true(
 NOT has_function_privilege('anon','public.create_trip(text,date,date)','EXECUTE')
 AND NOT has_function_privilege('authenticated','private.add_trip_creator()','EXECUTE')
 AND NOT has_function_privilege('anon','private.can_read_shared_trip(uuid,text)','EXECUTE'),
 'function execute privileges are explicit');

INSERT INTO auth.users(id) VALUES
 ('10000000-0000-0000-0000-000000000001'),
 ('10000000-0000-0000-0000-000000000002'),
 ('10000000-0000-0000-0000-000000000003'),
 ('10000000-0000-0000-0000-000000000004');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
INSERT INTO public.profiles(id,display_name) VALUES(auth.uid(),'Same Name');
SELECT pg_temp.expect_error(
  $$INSERT INTO public.profiles(id,display_name) VALUES('10000000-0000-0000-0000-000000000002','Fake')$$,'42501');
SELECT pg_temp.expect_error($$UPDATE public.profiles SET created_at=now()$$,'42501');
SELECT pg_temp.expect_error($$UPDATE public.profiles SET avatar_path='other/path.jpg'$$,'42501');
SELECT pg_temp.expect_error(
  $$INSERT INTO public.trips(name,start_date,end_date,created_by) VALUES('Bypass','2026-10-10','2026-10-11',auth.uid())$$,'42501');
-- Store identifiers in transaction-local GUCs for both PostgreSQL and PGlite.
SELECT set_config('test.trip',public.create_trip('Kyoto','2026-10-10','2026-10-12')::text,true);
SELECT pg_temp.assert_true(
  (SELECT count(*)=1 FROM public.trip_members WHERE trip_id=current_setting('test.trip')::uuid),
  'creator membership is atomic and immediately selectable');
SELECT pg_temp.assert_true(
  (SELECT visibility='private' FROM public.trips WHERE id=current_setting('test.trip')::uuid), 'private default');
SELECT pg_temp.expect_error(
  $$SELECT public.create_trip('Invalid','2026-10-12','2026-10-10')$$,'23514');
SELECT public.set_trip_visibility(current_setting('test.trip')::uuid,'unlisted');
SELECT pg_temp.expect_error(
  $$SELECT public.set_trip_visibility(current_setting('test.trip')::uuid,'public')$$,'23514');
SELECT pg_temp.expect_error($$DELETE FROM public.trips$$,'42501');
WITH d AS (DELETE FROM public.trip_members WHERE user_id=auth.uid() RETURNING id) SELECT pg_temp.assert_true(count(*)=0, 'creator cannot leave') FROM d;
SELECT set_config('test.invite',token,true) FROM public.create_trip_invitation(current_setting('test.trip')::uuid);
SELECT pg_temp.expect_error($$SELECT * FROM private.trip_invitations$$,'42501');

SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
INSERT INTO public.profiles(id,display_name) VALUES(auth.uid(),'Same Name');
SELECT pg_temp.assert_true((SELECT count(*)=1 FROM public.profiles),'profiles are self-only, names may duplicate');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM public.trips),'nonmember cannot read base trip');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM public.trip_members),'nonmember cannot list membership');
SELECT pg_temp.expect_error(
  $$SELECT public.get_trip_members(current_setting('test.trip')::uuid)$$,'42501');
SELECT pg_temp.expect_error(
  $$SELECT public.set_trip_visibility(current_setting('test.trip')::uuid,'private')$$,'42501');
SELECT pg_temp.expect_error(
  $$SELECT public.create_trip_invitation(current_setting('test.trip')::uuid)$$,'42501');
SELECT pg_temp.expect_error($$UPDATE public.trips SET name='tamper'$$,'42501');
SELECT pg_temp.expect_error($$DELETE FROM public.trips$$,'42501');
SELECT pg_temp.expect_error(
  $$INSERT INTO public.trip_members(trip_id,user_id) VALUES(current_setting('test.trip')::uuid,auth.uid())$$,'42501');
SELECT public.accept_trip_invitation(current_setting('test.invite'));
SELECT public.accept_trip_invitation(current_setting('test.invite'));
SELECT pg_temp.assert_true(
  (SELECT count(*)=2 FROM public.trip_members WHERE trip_id=current_setting('test.trip')::uuid),
  'invite is idempotent');
SELECT pg_temp.assert_true(
  (SELECT count(*)=2 FROM public.get_trip_members(current_setting('test.trip')::uuid)), 'member profiles through scoped RPC');
SELECT pg_temp.expect_error(
  $$SELECT public.set_trip_visibility(current_setting('test.trip')::uuid,'private')$$,'42501');
SELECT pg_temp.expect_error(
  $$SELECT public.create_trip_invitation(current_setting('test.trip')::uuid)$$,'42501');

SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true);
SELECT pg_temp.expect_error($$SELECT public.accept_trip_invitation(current_setting('test.invite'))$$,'42501');
INSERT INTO public.profiles(id,display_name) VALUES(auth.uid(),'Third');
SELECT public.accept_trip_invitation(current_setting('test.invite'));
SELECT pg_temp.assert_true(
  (SELECT count(*)=3 FROM public.trip_members WHERE trip_id=current_setting('test.trip')::uuid),
  'same invitation admits multiple people');

RESET ROLE;
SELECT pg_temp.expect_error(
  $$INSERT INTO public.trip_members(trip_id,user_id) VALUES(current_setting('test.trip')::uuid,'10000000-0000-0000-0000-000000000002')$$,'23505');
SELECT pg_temp.expect_error(
  $$INSERT INTO public.profiles(id,display_name) VALUES('ffffffff-ffff-ffff-ffff-ffffffffffff','Orphan')$$,'23503');
SELECT pg_temp.expect_error($$INSERT INTO public.profiles(id) VALUES('10000000-0000-0000-0000-000000000004')$$,'23502');

INSERT INTO public.itinerary_items(id,trip_id,date,category,title,sort_order)
VALUES ('20000000-0000-0000-0000-000000000001',current_setting('test.trip')::uuid,'2026-10-10','place','Lunch',0);
SELECT pg_temp.assert_true(
  (SELECT time_type='none' AND exact_time IS NULL AND time_period IS NULL FROM public.itinerary_items
   WHERE id='20000000-0000-0000-0000-000000000001'), 'name-only item has no time');
SELECT pg_temp.expect_error($$UPDATE public.itinerary_items SET title=''$$,'23514');
SELECT pg_temp.expect_error($$UPDATE public.itinerary_items SET sort_order=-1$$,'23514');
SELECT pg_temp.expect_error($$UPDATE public.itinerary_items SET duration_minutes=0$$,'23514');
SELECT pg_temp.expect_error($$UPDATE public.itinerary_items SET category='action'$$,'23514');
SELECT pg_temp.expect_error($$UPDATE public.itinerary_items SET time_type='exact'$$,'23514');
SELECT pg_temp.expect_error($$UPDATE public.itinerary_items SET time_type='period'$$,'23514');
SELECT pg_temp.expect_error($$UPDATE public.itinerary_items SET time_type='period',time_period='midnight'$$,'23514');
UPDATE public.itinerary_items SET time_type='exact',exact_time='12:00';
SELECT pg_temp.expect_error($$UPDATE public.itinerary_items SET time_period='昼'$$,'23514');
UPDATE public.itinerary_items SET time_type='period',exact_time=NULL,time_period='おやつ';
UPDATE public.itinerary_items SET time_type='none',time_period=NULL,description='MEMBER-ONLY';
SELECT pg_temp.expect_error($$UPDATE public.itinerary_items SET time_period='朝'$$,'23514');
SELECT pg_temp.expect_error($$UPDATE public.itinerary_items SET time_type='invalid'$$,'23514');
SELECT pg_temp.expect_error($$UPDATE public.itinerary_items SET trip_id=gen_random_uuid()$$,'23514');
SELECT pg_temp.expect_error(
  $$INSERT INTO public.itinerary_items(trip_id,date,category,title,sort_order) VALUES(gen_random_uuid(),'2026-10-10','place','Orphan',0)$$,'23503');

INSERT INTO public.itinerary_photos(id,itinerary_item_id,storage_path,uploaded_by)
SELECT ('30000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
 '20000000-0000-0000-0000-000000000001',
 current_setting('test.trip')||'/20000000-0000-0000-0000-000000000001/'||n||'.jpg',
 '10000000-0000-0000-0000-000000000002' FROM generate_series(1,5) AS n;
SELECT pg_temp.expect_error(
  $$INSERT INTO public.itinerary_photos(itinerary_item_id,storage_path,uploaded_by)
    VALUES('20000000-0000-0000-0000-000000000001','sixth.jpg','10000000-0000-0000-0000-000000000002')$$,'23514');
SELECT pg_temp.expect_error(
  $$UPDATE public.itinerary_photos SET is_public=true WHERE id='30000000-0000-0000-0000-000000000001'$$,'42501');
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
UPDATE public.itinerary_photos SET is_public=true WHERE id='30000000-0000-0000-0000-000000000001';
UPDATE public.itinerary_photos SET storage_path=current_setting('test.trip')||'/20000000-0000-0000-0000-000000000001/replaced.jpg'
 WHERE id='30000000-0000-0000-0000-000000000001';
SELECT pg_temp.assert_true(
 (SELECT NOT is_public FROM public.itinerary_photos WHERE id='30000000-0000-0000-0000-000000000001'),
 'replacement resets even creator photo');
SELECT pg_temp.expect_error(
 $$UPDATE public.itinerary_photos SET uploaded_by='10000000-0000-0000-0000-000000000001'$$,'23514');
SELECT pg_temp.expect_error(
 $$DELETE FROM auth.users WHERE id='10000000-0000-0000-0000-000000000001'$$,'23503');
SELECT pg_temp.expect_error(
 $$DELETE FROM auth.users WHERE id='10000000-0000-0000-0000-000000000002'$$,'23503');


-- Provision test-only read credentials as postgres. No application issuer exists.
UPDATE public.itinerary_photos SET is_public=true WHERE id='30000000-0000-0000-0000-000000000001';
INSERT INTO private.trip_share_links(trip_id,token_hash)
 VALUES(current_setting('test.trip')::uuid,sha256(convert_to('fixture-read-token','UTF8')));
SELECT pg_temp.assert_true(
 NOT has_table_privilege('authenticated','private.trip_share_links','INSERT')
 AND NOT has_table_privilege('anon','private.trip_share_links','SELECT'), 'read credential administration closed');
SELECT pg_temp.expect_error(
 $$SELECT public.get_shared_trip(current_setting('test.trip')::uuid,current_setting('test.invite'))$$,'42501');
SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claim.sub','',true);
SELECT pg_temp.assert_true(
 public.get_shared_trip(current_setting('test.trip')::uuid,'fixture-read-token')->>'name'='Kyoto',
 'anon authorized shared trip');
SELECT pg_temp.assert_true(
 (public.get_shared_trip(current_setting('test.trip')::uuid,'fixture-read-token')->>'member_count')::integer=3,
 'shared response contains only member count');
SELECT pg_temp.assert_true(
 jsonb_array_length(public.get_shared_trip(current_setting('test.trip')::uuid,'fixture-read-token')->'items'->0->'photos')=1,
 'private photos omitted');
SELECT pg_temp.assert_true(
 NOT (public.get_shared_trip(current_setting('test.trip')::uuid,'fixture-read-token')::text ~
   'description|MEMBER-ONLY|display_name|avatar_path|uploaded_by|created_by|created_at|updated_at|joined_at|token_hash'),
 'shared response excludes memo, identities and control fields');
SELECT pg_temp.assert_true(
 public.get_shared_photo_path(current_setting('test.trip')::uuid,'30000000-0000-0000-0000-000000000001','fixture-read-token')
 LIKE '%/replaced.jpg', 'authorized photo delivery path');
SELECT pg_temp.expect_error(
 $$SELECT public.get_shared_photo_path(current_setting('test.trip')::uuid,'30000000-0000-0000-0000-000000000002','fixture-read-token')$$,'42501');
SELECT pg_temp.expect_error(
 $$SELECT public.get_shared_trip(current_setting('test.trip')::uuid,NULL)$$,'42501');
SELECT pg_temp.expect_error(
 $$SELECT public.get_shared_trip(current_setting('test.trip')::uuid,'wrong-token')$$,'42501');
SELECT pg_temp.expect_error(
 $$SELECT public.get_shared_trip('ffffffff-ffff-ffff-ffff-ffffffffffff','fixture-read-token')$$,'42501');
SELECT pg_temp.expect_error($$SELECT * FROM private.trip_share_links$$,'42501');
RESET ROLE;
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
SELECT public.set_trip_visibility(current_setting('test.trip')::uuid,'private');
SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claim.sub','',true);
SELECT pg_temp.expect_error(
 $$SELECT public.get_shared_trip(current_setting('test.trip')::uuid,'fixture-read-token')$$,'42501');
SELECT pg_temp.expect_error(
 $$SELECT public.get_shared_photo_path(current_setting('test.trip')::uuid,'30000000-0000-0000-0000-000000000001','fixture-read-token')$$,'42501');
RESET ROLE;
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
SELECT public.set_trip_visibility(current_setting('test.trip')::uuid,'unlisted');

-- An unrelated permissive Storage policy must not bypass our bucket guards.
CREATE POLICY test_permissive_storage ON storage.objects FOR ALL TO anon, authenticated USING(true) WITH CHECK(true);

-- Positive Storage read fixtures are metadata only; no actual files uploaded.
INSERT INTO storage.objects(bucket_id,name,owner_id)
SELECT 'itinerary-photos',storage_path,uploaded_by::text FROM public.itinerary_photos;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
SELECT pg_temp.assert_true((SELECT count(*)=1 FROM public.itinerary_items),'member reads memo/item');
SELECT pg_temp.assert_true((SELECT count(*)=5 FROM public.itinerary_photos),'member reads all photos');
SELECT pg_temp.assert_true((SELECT count(*)=5 FROM storage.objects WHERE bucket_id='itinerary-photos'),
 'member reads images posted by a member');
SELECT pg_temp.expect_error($$UPDATE public.itinerary_items SET description='bypass'$$,'42501');
SELECT pg_temp.expect_error($$DELETE FROM public.itinerary_items$$,'42501');
SELECT pg_temp.expect_error($$UPDATE public.itinerary_photos SET is_public=true$$,'42501');
SELECT pg_temp.expect_error($$DELETE FROM public.itinerary_photos$$,'42501');

INSERT INTO storage.objects(bucket_id,name,owner_id)
 VALUES('avatars',auth.uid()::text||'/avatar.jpg',auth.uid()::text);
SELECT public.set_my_avatar(auth.uid()::text||'/avatar.jpg');
SELECT pg_temp.expect_error(
 $$SELECT public.set_my_avatar('10000000-0000-0000-0000-000000000001/other.jpg')$$,'42501');
SELECT pg_temp.expect_error(
 $$INSERT INTO storage.objects(bucket_id,name,owner_id) VALUES('avatars','invalid/avatar.jpg',auth.uid()::text)$$,'42501');
SELECT pg_temp.expect_error(
 $$INSERT INTO storage.objects(bucket_id,name,owner_id) VALUES('itinerary-photos',current_setting('test.trip')||'/20000000-0000-0000-0000-000000000001/new.jpg',auth.uid()::text)$$,'42501');
WITH d AS (DELETE FROM storage.objects RETURNING id) SELECT pg_temp.assert_true(count(*)=0, 'direct object deletion blocked') FROM d;
WITH u AS (UPDATE storage.objects SET name='overwritten' RETURNING id) SELECT pg_temp.assert_true(count(*)=0, 'object overwrite blocked') FROM u;

SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000004',true);
INSERT INTO public.profiles(id,display_name) VALUES(auth.uid(),'Outsider');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM public.itinerary_items),'outsider cannot read memo');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM public.itinerary_photos),'outsider cannot read base photos');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM storage.objects),'outsider cannot read objects');
SELECT pg_temp.expect_error(
 $$INSERT INTO storage.objects(bucket_id,name) VALUES('trip-thumbnails',current_setting('test.trip')||'/photo.jpg')$$,'42501');
SELECT pg_temp.expect_error($$SELECT public.accept_trip_invitation('wrong-token')$$,'42501');
SELECT pg_temp.assert_true(public.get_shared_trip(current_setting('test.trip')::uuid,'fixture-read-token')->>'name'='Kyoto', 'authenticated nonmember shared read');

RESET ROLE;
UPDATE private.trip_invitations SET created_at=now()-interval '25 hours',expires_at=now()-interval '1 hour';
SET LOCAL ROLE authenticated;
SELECT pg_temp.expect_error($$SELECT public.accept_trip_invitation(current_setting('test.invite'))$$,'42501');

SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
DELETE FROM public.trip_members WHERE user_id=auth.uid();
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM public.trips),'ex-member no longer reads trip');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM storage.objects WHERE bucket_id='itinerary-photos'),'ex-member image denial');

SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claim.sub','',true);
SELECT pg_temp.expect_error($$SELECT * FROM public.trips$$,'42501');
SELECT pg_temp.expect_error($$SELECT * FROM public.itinerary_photos$$,'42501');
SELECT pg_temp.expect_error($$SELECT public.create_trip('Bad','2026-10-10','2026-10-10')$$,'42501');
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM storage.objects),'anon direct Storage denial');
RESET ROLE;

-- Direct DELETE is not a production interface. Temporarily grant inside this
-- rolled-back test to independently exercise the creator-only RLS policy.
GRANT DELETE ON public.trips TO authenticated;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true);
WITH d AS (DELETE FROM public.trips WHERE id=current_setting('test.trip')::uuid RETURNING id) SELECT pg_temp.assert_true(count(*)=0, 'noncreator DELETE policy denial') FROM d;
SELECT set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
DELETE FROM public.trips WHERE id=current_setting('test.trip')::uuid;
RESET ROLE;
SELECT pg_temp.assert_true(
 NOT EXISTS(SELECT 1 FROM public.trips) AND NOT EXISTS(SELECT 1 FROM public.itinerary_items)
 AND NOT EXISTS(SELECT 1 FROM public.itinerary_photos) AND NOT EXISTS(SELECT 1 FROM public.trip_members)
 AND NOT EXISTS(SELECT 1 FROM private.trip_invitations) AND NOT EXISTS(SELECT 1 FROM private.trip_share_links), 'creator deletion and FK cascade');
SELECT pg_temp.assert_true((SELECT count(*)=5 FROM storage.objects WHERE bucket_id='itinerary-photos'),
 'SQL cascade does not delete Storage objects');
DELETE FROM auth.users WHERE id='10000000-0000-0000-0000-000000000001';
SELECT pg_temp.assert_true(NOT EXISTS(SELECT 1 FROM public.profiles WHERE id='10000000-0000-0000-0000-000000000001'),
 'profile cascade on Auth deletion');

SELECT 'initial_database_checks_passed' AS result;
ROLLBACK;

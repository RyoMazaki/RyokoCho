-- Disposable database only. Privileged fixture writes are rolled back.
BEGIN;
CREATE FUNCTION pg_temp.assert_itinerary(p_ok boolean, p_message text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF p_ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'ASSERT: %', p_message; END IF;
END;
$$;
INSERT INTO auth.users(id) VALUES
 ('21000000-0000-0000-0000-000000000001'),
 ('21000000-0000-0000-0000-000000000002'),
 ('21000000-0000-0000-0000-000000000003');
INSERT INTO public.trips(id,name,start_date,end_date,visibility,created_by) VALUES
 ('31000000-0000-0000-0000-000000000001','Private','2026-10-01','2026-10-03','private','21000000-0000-0000-0000-000000000001'),
 ('31000000-0000-0000-0000-000000000002','Unlisted','2026-10-01','2026-10-03','unlisted','21000000-0000-0000-0000-000000000001'),
 ('31000000-0000-0000-0000-000000000003','Other','2026-10-01','2026-10-03','private','21000000-0000-0000-0000-000000000003');
INSERT INTO public.trip_members(trip_id,user_id) VALUES
 ('31000000-0000-0000-0000-000000000001','21000000-0000-0000-0000-000000000002'),
 ('31000000-0000-0000-0000-000000000002','21000000-0000-0000-0000-000000000002');
INSERT INTO public.itinerary_items(id,trip_id,date,category,title,sort_order,time_type,exact_time,time_period) VALUES
 ('41000000-0000-0000-0000-000000000001','31000000-0000-0000-0000-000000000001','2026-10-01','place','First',0,'exact','18:00',NULL),
 ('41000000-0000-0000-0000-000000000002','31000000-0000-0000-0000-000000000001','2026-10-01','transportation','Second',1,'exact','09:00',NULL),
 ('41000000-0000-0000-0000-000000000003','31000000-0000-0000-0000-000000000001','2026-10-01','place','Third',1,'none',NULL,NULL),
 ('41000000-0000-0000-0000-000000000004','31000000-0000-0000-0000-000000000001','2026-10-02','place','Next day',0,'period',NULL,'朝'),
 ('41000000-0000-0000-0000-000000000005','31000000-0000-0000-0000-000000000002','2026-10-01','place','Unlisted item',0,'none',NULL,NULL),
 ('41000000-0000-0000-0000-000000000006','31000000-0000-0000-0000-000000000003','2026-10-01','place','Other item',0,'none',NULL,NULL);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','21000000-0000-0000-0000-000000000001',true);
SELECT pg_temp.assert_itinerary((SELECT count(*)=5 FROM public.itinerary_items),'creator sees only member trips');

SELECT set_config('request.jwt.claim.sub','21000000-0000-0000-0000-000000000002',true);
SELECT pg_temp.assert_itinerary((SELECT count(*)=5 FROM public.itinerary_items),'regular member reads private and unlisted');
SELECT pg_temp.assert_itinerary(
 (SELECT array_agg(title ORDER BY sort_order,id)=ARRAY['First','Second','Third']
  FROM public.itinerary_items WHERE trip_id='31000000-0000-0000-0000-000000000001' AND date='2026-10-01'),
 'day filter preserves user order, tied order, mixed categories and unspecified time');
SELECT pg_temp.assert_itinerary(
 (SELECT array_agg(title ORDER BY sort_order,id)=ARRAY['Third']
  FROM public.itinerary_items WHERE trip_id='31000000-0000-0000-0000-000000000001' AND date='2026-10-01'
  AND (sort_order>1 OR (sort_order=1 AND id>'41000000-0000-0000-0000-000000000002'))),
 'compound cursor does not skip tied sort_order');
SELECT pg_temp.assert_itinerary(
 (SELECT count(*)=0 FROM public.itinerary_items WHERE trip_id='31000000-0000-0000-0000-000000000001' AND date='2026-10-03'),
 'empty day');
SELECT pg_temp.assert_itinerary(
 (SELECT category='transportation' AND exact_time='09:00' AND time_period IS NULL AND duration_minutes IS NULL
  FROM public.itinerary_items WHERE trip_id='31000000-0000-0000-0000-000000000001' AND id='41000000-0000-0000-0000-000000000002'),
 'member detail');
SELECT pg_temp.assert_itinerary(
 (SELECT count(*)=0 FROM public.itinerary_items WHERE trip_id='31000000-0000-0000-0000-000000000002' AND id='41000000-0000-0000-0000-000000000001'),
 'detail rejects wrong trip even when member of both');
SELECT pg_temp.assert_itinerary(
 (SELECT count(*)=0 FROM public.itinerary_items WHERE id='41000000-0000-0000-0000-000000000099'),
 'missing detail');
SELECT pg_temp.assert_itinerary(
 (SELECT count(*)=0 FROM public.itinerary_items WHERE trip_id='31000000-0000-0000-0000-000000000003'),
 'other trip denied');

DELETE FROM public.trip_members WHERE user_id=auth.uid();
SELECT pg_temp.assert_itinerary((SELECT count(*)=0 FROM public.itinerary_items),'after leaving all reads denied');

SELECT set_config('request.jwt.claim.sub','21000000-0000-0000-0000-000000000003',true);
SELECT pg_temp.assert_itinerary(
 (SELECT count(*)=0 FROM public.itinerary_items WHERE trip_id IN
 ('31000000-0000-0000-0000-000000000001','31000000-0000-0000-0000-000000000002')),
 'outsider denied for private and unlisted');
SELECT set_config('request.jwt.claim.sub','',true);
SELECT pg_temp.assert_itinerary((SELECT count(*)=0 FROM public.itinerary_items),'missing identity denied');
SET LOCAL ROLE anon;
DO $$
BEGIN
  BEGIN
    PERFORM id FROM public.itinerary_items;
    RAISE EXCEPTION 'anonymous read unexpectedly allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END;
$$;
RESET ROLE;
SELECT 'itinerary_read_checks_passed' AS result;
ROLLBACK;

-- Read-only sharing data and projections from design sections 6.7 / 6.8.
-- No client issuance API: issuer permissions and link lifetime are unresolved.
BEGIN;
CREATE TABLE private.trip_share_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id uuid NOT NULL REFERENCES public.trips(id) ON DELETE CASCADE,
  token_hash bytea NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT trip_share_links_hash_length CHECK (octet_length(token_hash) = 32)
);
CREATE INDEX trip_share_links_trip_idx ON private.trip_share_links(trip_id);
ALTER TABLE private.trip_share_links ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.trip_share_links FROM PUBLIC, anon, authenticated;
GRANT SELECT ON private.trip_share_links TO ryoko_reader;
CREATE POLICY trip_share_links_internal_read ON private.trip_share_links
  FOR SELECT TO ryoko_reader USING (true);

CREATE FUNCTION private.can_read_shared_trip(p_trip_id uuid, p_token text)
RETURNS boolean LANGUAGE sql STABLE SET search_path = ''
AS $$
  SELECT p_token IS NOT NULL AND p_token <> '' AND EXISTS (
    SELECT 1 FROM private.trip_share_links l
    JOIN public.trips t ON t.id = l.trip_id
    WHERE l.trip_id = p_trip_id AND t.visibility = 'unlisted'
      AND l.token_hash = sha256(convert_to(p_token, 'UTF8'))
  );
$$;

CREATE FUNCTION public.get_shared_trip(p_trip_id uuid, p_token text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
DECLARE v_result jsonb;
BEGIN
  IF NOT private.can_read_shared_trip(p_trip_id, p_token) THEN
    RAISE EXCEPTION 'Shared trip unavailable' USING ERRCODE = '42501';
  END IF;
  SELECT jsonb_build_object(
    'id', t.id, 'name', t.name, 'start_date', t.start_date, 'end_date', t.end_date,
    'thumbnail_path', t.thumbnail_path,
    'member_count', (SELECT count(*) FROM public.trip_members m WHERE m.trip_id=t.id),
    'items', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'id', i.id, 'date', i.date, 'category', i.category, 'title', i.title,
        'sort_order', i.sort_order, 'time_type', i.time_type,
        'exact_time', i.exact_time, 'time_period', i.time_period,
        'duration_minutes', i.duration_minutes,
        'photos', coalesce((
          SELECT jsonb_agg(jsonb_build_object('id', p.id))
          FROM public.itinerary_photos p WHERE p.itinerary_item_id=i.id AND p.is_public
        ), '[]'::jsonb)
      ) ORDER BY i.date, i.sort_order)
      FROM public.itinerary_items i WHERE i.trip_id=t.id
    ), '[]'::jsonb)
  ) INTO v_result FROM public.trips t WHERE t.id=p_trip_id;
  RETURN v_result;
END;
$$;

-- A server may sign/download this verified path with the Storage API.
-- This function is NOT a signed URL, a direct blob grant, or a proxy endpoint.
CREATE FUNCTION public.get_shared_photo_path(p_trip_id uuid, p_photo_id uuid, p_token text)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
DECLARE v_path text;
BEGIN
  IF NOT private.can_read_shared_trip(p_trip_id, p_token) THEN
    RAISE EXCEPTION 'Shared photo unavailable' USING ERRCODE = '42501';
  END IF;
  SELECT p.storage_path INTO v_path FROM public.itinerary_photos p
    JOIN public.itinerary_items i ON i.id=p.itinerary_item_id
    WHERE p.id=p_photo_id AND p.is_public AND i.trip_id=p_trip_id
      AND private.path_uuid(p.storage_path,1)=p_trip_id
      AND private.path_uuid(p.storage_path,2)=i.id;
  IF v_path IS NULL THEN
    RAISE EXCEPTION 'Shared photo unavailable' USING ERRCODE = '42501';
  END IF;
  -- Multiple references/public flags on one object are explicitly unresolved.
  -- Refuse ambiguous delivery until that design decision is made.
  IF EXISTS (SELECT 1 FROM public.itinerary_photos p
    WHERE p.storage_path=v_path AND p.id<>p_photo_id) THEN
    RAISE EXCEPTION 'Shared object references require a delivery rule' USING ERRCODE = '55000';
  END IF;
  RETURN v_path;
END;
$$;
GRANT CREATE ON SCHEMA public TO ryoko_reader;
ALTER FUNCTION public.get_shared_trip(uuid,text) OWNER TO ryoko_reader;
ALTER FUNCTION public.get_shared_photo_path(uuid,uuid,text) OWNER TO ryoko_reader;
REVOKE CREATE ON SCHEMA public FROM ryoko_reader;
REVOKE ALL ON FUNCTION private.can_read_shared_trip(uuid,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.can_read_shared_trip(uuid,text) TO ryoko_reader;
REVOKE ALL ON FUNCTION public.get_shared_trip(uuid,text),
  public.get_shared_photo_path(uuid,uuid,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_shared_trip(uuid,text),
  public.get_shared_photo_path(uuid,uuid,text) TO anon, authenticated;
COMMIT;

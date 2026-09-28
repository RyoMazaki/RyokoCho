
-- Private buckets. Blob upload/download/deletion still uses the Storage API.
BEGIN;
INSERT INTO storage.buckets (id, name, public) VALUES
  ('avatars', 'avatars', false),
  ('trip-thumbnails', 'trip-thumbnails', false),
  ('itinerary-photos', 'itinerary-photos', false);

CREATE FUNCTION private.path_uuid(p_path text, p_part integer)
RETURNS uuid LANGUAGE plpgsql IMMUTABLE SET search_path = ''
AS $$
BEGIN
  RETURN split_part(p_path, '/', p_part)::uuid;
EXCEPTION WHEN invalid_text_representation THEN RETURN NULL;
END;
$$;

CREATE FUNCTION private.can_read_storage_object(p_bucket text, p_name text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT auth.uid() IS NOT NULL AND CASE p_bucket
    WHEN 'avatars' THEN private.path_uuid(p_name, 1) = auth.uid()
    WHEN 'trip-thumbnails' THEN EXISTS (
      SELECT 1 FROM public.trips t
      JOIN public.trip_members m ON m.trip_id = t.id AND m.user_id = auth.uid()
      WHERE t.thumbnail_path = p_name AND t.id = private.path_uuid(p_name, 1)
    )
    WHEN 'itinerary-photos' THEN EXISTS (
      SELECT 1 FROM public.itinerary_photos p
      JOIN public.itinerary_items i ON i.id = p.itinerary_item_id
      JOIN public.trip_members m ON m.trip_id = i.trip_id AND m.user_id = auth.uid()
      WHERE p.storage_path = p_name
        AND i.trip_id = private.path_uuid(p_name, 1)
        AND i.id = private.path_uuid(p_name, 2)
    )
    ELSE false END;
$$;
CREATE FUNCTION private.can_insert_storage_object(p_bucket text, p_name text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT auth.uid() IS NOT NULL AND CASE p_bucket
    WHEN 'avatars' THEN private.path_uuid(p_name, 1) = auth.uid()
    WHEN 'trip-thumbnails' THEN private.is_trip_member(private.path_uuid(p_name, 1))
    -- Requires an upload lease protecting the parent against deletion.
    WHEN 'itinerary-photos' THEN false
    ELSE false END;
$$;
GRANT CREATE ON SCHEMA private TO ryoko_reader;
ALTER FUNCTION private.can_read_storage_object(text,text) OWNER TO ryoko_reader;
ALTER FUNCTION private.can_insert_storage_object(text,text) OWNER TO ryoko_reader;
REVOKE CREATE ON SCHEMA private FROM ryoko_reader;
REVOKE ALL ON FUNCTION private.path_uuid(text,integer),
  private.can_read_storage_object(text,text),
  private.can_insert_storage_object(text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.path_uuid(text,integer) TO ryoko_reader;
GRANT USAGE ON SCHEMA private TO anon;
GRANT EXECUTE ON FUNCTION private.can_read_storage_object(text,text),
  private.can_insert_storage_object(text,text) TO anon, authenticated;

CREATE POLICY ryoko_objects_select ON storage.objects
  FOR SELECT TO authenticated
  USING (private.can_read_storage_object(bucket_id, name));
CREATE POLICY ryoko_objects_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (private.can_insert_storage_object(bucket_id, name));

-- Existing permissive policies in a target project must not override our rules.
-- Other applications' buckets are unaffected by these restrictive policies.
CREATE POLICY ryoko_objects_select_guard ON storage.objects AS RESTRICTIVE
  FOR SELECT TO anon, authenticated
  USING (bucket_id NOT IN ('avatars','trip-thumbnails','itinerary-photos')
    OR private.can_read_storage_object(bucket_id, name));
CREATE POLICY ryoko_objects_insert_guard ON storage.objects AS RESTRICTIVE
  FOR INSERT TO anon, authenticated
  WITH CHECK (bucket_id NOT IN ('avatars','trip-thumbnails','itinerary-photos')
    OR private.can_insert_storage_object(bucket_id, name));
CREATE POLICY ryoko_objects_update_guard ON storage.objects AS RESTRICTIVE
  FOR UPDATE TO anon, authenticated
  USING (bucket_id NOT IN ('avatars','trip-thumbnails','itinerary-photos'))
  WITH CHECK (bucket_id NOT IN ('avatars','trip-thumbnails','itinerary-photos'));
CREATE POLICY ryoko_objects_delete_guard ON storage.objects AS RESTRICTIVE
  FOR DELETE TO anon, authenticated
  USING (bucket_id NOT IN ('avatars','trip-thumbnails','itinerary-photos'));

-- Do not add FK to storage.objects or delete its rows with SQL.
-- Avatar paths need verified attachment rather than arbitrary profile UPDATE.
CREATE FUNCTION public.set_my_avatar(p_path text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_path IS NULL OR private.path_uuid(p_path, 1) IS DISTINCT FROM auth.uid()
    OR NOT EXISTS (SELECT 1 FROM storage.objects o
      WHERE o.bucket_id = 'avatars' AND o.name = p_path AND o.owner_id = auth.uid()::text) THEN
    RAISE EXCEPTION 'An uploaded avatar owned by the current user is required' USING ERRCODE = '42501';
  END IF;
  -- Replacement/deletion requires the unresolved durable cleanup workflow.
  UPDATE public.profiles SET avatar_path = p_path
    WHERE id = auth.uid() AND (avatar_path IS NULL OR avatar_path = p_path);
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Profile missing or avatar replacement requires cleanup workflow'
      USING ERRCODE = '55000';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.set_my_avatar(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_my_avatar(text) TO authenticated;
COMMIT;


-- Initial application schema. Run through Supabase migrations as postgres.
-- Unfinished application write workflows are deliberately not granted direct DML.
BEGIN;

CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA private TO authenticated;

-- A non-login, read-only function owner avoids both recursive RLS and a
-- superuser-owned public read API. Never grant this role to API roles.
CREATE ROLE ryoko_reader NOLOGIN NOINHERIT NOBYPASSRLS;
GRANT ryoko_reader TO postgres;
GRANT USAGE ON SCHEMA public, private, auth TO ryoko_reader;
GRANT EXECUTE ON FUNCTION auth.uid() TO ryoko_reader;

CREATE TABLE public.profiles (
  id uuid PRIMARY KEY
    REFERENCES auth.users (id) ON DELETE CASCADE,
  display_name text NOT NULL,
  avatar_path text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.trips (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  start_date date NOT NULL,
  end_date date NOT NULL,
  thumbnail_path text,
  visibility text NOT NULL DEFAULT 'private',
  created_by uuid NOT NULL
    REFERENCES auth.users (id) ON DELETE NO ACTION,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT trips_visibility_check CHECK (visibility IN ('private', 'unlisted')),
  CONSTRAINT trips_date_range_check CHECK (end_date >= start_date)
);

CREATE TABLE public.trip_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id uuid NOT NULL
    REFERENCES public.trips (id) ON DELETE CASCADE,
  user_id uuid NOT NULL
    REFERENCES auth.users (id) ON DELETE CASCADE,
  joined_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT trip_members_trip_user_key UNIQUE (trip_id, user_id)
);

CREATE TABLE public.itinerary_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id uuid NOT NULL
    REFERENCES public.trips (id) ON DELETE CASCADE,
  date date NOT NULL,
  category text NOT NULL,
  title text NOT NULL,
  description text,
  sort_order integer NOT NULL,
  time_type text NOT NULL DEFAULT 'none',
  exact_time time without time zone,
  time_period text,
  duration_minutes integer,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT itinerary_items_title_check CHECK (title <> ''),
  CONSTRAINT itinerary_items_time_period_check
    CHECK (time_period IS NULL OR time_period IN ('朝', '昼', 'おやつ', '夕方', '夜')),
  CONSTRAINT itinerary_items_category_check
    CHECK (category IN ('place', 'transportation')),
  CONSTRAINT itinerary_items_time_type_check
    CHECK (time_type IN ('none', 'exact', 'period')),
  CONSTRAINT itinerary_items_time_consistency_check CHECK (
    (time_type = 'exact' AND exact_time IS NOT NULL AND time_period IS NULL)
    OR (time_type = 'period' AND exact_time IS NULL AND time_period IS NOT NULL)
    OR (time_type = 'none' AND exact_time IS NULL AND time_period IS NULL)
  ),
  CONSTRAINT itinerary_items_sort_order_check CHECK (sort_order >= 0),
  CONSTRAINT itinerary_items_duration_check
    CHECK (duration_minutes IS NULL OR duration_minutes > 0)
);

CREATE TABLE public.itinerary_photos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  itinerary_item_id uuid NOT NULL
    REFERENCES public.itinerary_items (id) ON DELETE CASCADE,
  storage_path text NOT NULL,
  is_public boolean NOT NULL DEFAULT false,
  uploaded_by uuid NOT NULL
    REFERENCES auth.users (id) ON DELETE NO ACTION,
  created_at timestamptz NOT NULL DEFAULT now()
);


CREATE INDEX trips_created_by_idx
  ON public.trips (created_by);

CREATE INDEX trip_members_user_trip_idx
  ON public.trip_members (user_id, trip_id);

CREATE INDEX itinerary_items_trip_date_order_idx
  ON public.itinerary_items (trip_id, date, sort_order);

CREATE INDEX itinerary_photos_item_idx
  ON public.itinerary_photos (itinerary_item_id);

CREATE INDEX itinerary_photos_uploaded_by_idx
  ON public.itinerary_photos (uploaded_by);


REVOKE ALL ON TABLE public.profiles, public.trips, public.trip_members,
  public.itinerary_items, public.itinerary_photos FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.profiles, public.trips, public.trip_members,
  public.itinerary_items, public.itinerary_photos TO authenticated, ryoko_reader;
GRANT INSERT (id, display_name) ON public.profiles TO authenticated;
GRANT UPDATE (display_name) ON public.profiles TO authenticated;
GRANT DELETE ON public.trip_members TO authenticated;

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trips ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trip_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.itinerary_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.itinerary_photos ENABLE ROW LEVEL SECURITY;

CREATE POLICY profiles_internal_read ON public.profiles FOR SELECT TO ryoko_reader USING (true);
CREATE POLICY trips_internal_read ON public.trips FOR SELECT TO ryoko_reader USING (true);
CREATE POLICY trip_members_internal_read ON public.trip_members FOR SELECT TO ryoko_reader USING (true);
CREATE POLICY itinerary_items_internal_read ON public.itinerary_items FOR SELECT TO ryoko_reader USING (true);
CREATE POLICY itinerary_photos_internal_read ON public.itinerary_photos FOR SELECT TO ryoko_reader USING (true);

CREATE FUNCTION private.is_trip_member(p_trip_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT auth.uid() IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.trip_members m
    WHERE m.trip_id = p_trip_id AND m.user_id = auth.uid()
  );
$$;
CREATE FUNCTION private.is_trip_creator(p_trip_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT auth.uid() IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.trips t
    WHERE t.id = p_trip_id AND t.created_by = auth.uid()
  );
$$;
CREATE FUNCTION private.is_item_member(p_item_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT auth.uid() IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.itinerary_items i
    JOIN public.trip_members m ON m.trip_id = i.trip_id
    WHERE i.id = p_item_id AND m.user_id = auth.uid()
  );
$$;

-- Temporarily allow ownership transfer; this is revoked in this transaction.
GRANT CREATE ON SCHEMA private TO ryoko_reader;
ALTER FUNCTION private.is_trip_member(uuid) OWNER TO ryoko_reader;
ALTER FUNCTION private.is_trip_creator(uuid) OWNER TO ryoko_reader;
ALTER FUNCTION private.is_item_member(uuid) OWNER TO ryoko_reader;
REVOKE CREATE ON SCHEMA private FROM ryoko_reader;
REVOKE ALL ON FUNCTION private.is_trip_member(uuid),
  private.is_trip_creator(uuid), private.is_item_member(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.is_trip_member(uuid),
  private.is_trip_creator(uuid), private.is_item_member(uuid) TO authenticated;

CREATE POLICY profiles_select_self ON public.profiles
  FOR SELECT TO authenticated USING (id = (SELECT auth.uid()));
CREATE POLICY profiles_insert_self ON public.profiles
  FOR INSERT TO authenticated WITH CHECK (id = (SELECT auth.uid()));
CREATE POLICY profiles_update_self ON public.profiles
  FOR UPDATE TO authenticated USING (id = (SELECT auth.uid()))
  WITH CHECK (id = (SELECT auth.uid()));

CREATE POLICY trips_select_member ON public.trips
  FOR SELECT TO authenticated USING (private.is_trip_member(id));
CREATE POLICY trips_insert_creator ON public.trips
  FOR INSERT TO authenticated
  WITH CHECK (created_by = (SELECT auth.uid()) AND visibility = 'private');
-- These policies are necessary row-level gates, NOT grants for direct writes.
-- Dates / images / deletion need the dedicated workflow described in the design.
CREATE POLICY trips_update_member ON public.trips
  FOR UPDATE TO authenticated USING (private.is_trip_member(id))
  WITH CHECK (private.is_trip_member(id));
CREATE POLICY trips_delete_creator ON public.trips
  FOR DELETE TO authenticated USING (private.is_trip_creator(id));

CREATE POLICY trip_members_select_member ON public.trip_members
  FOR SELECT TO authenticated USING (private.is_trip_member(trip_id));
CREATE POLICY trip_members_delete_self ON public.trip_members
  FOR DELETE TO authenticated
  USING (user_id = (SELECT auth.uid()) AND NOT private.is_trip_creator(trip_id));
CREATE POLICY itinerary_items_select_member ON public.itinerary_items
  FOR SELECT TO authenticated USING (private.is_trip_member(trip_id));
CREATE POLICY itinerary_photos_select_member ON public.itinerary_photos
  FOR SELECT TO authenticated USING (private.is_item_member(itinerary_item_id));

-- Audit fields are server generated, and identity/parent references are immutable.
CREATE FUNCTION private.stamp_application_row()
RETURNS trigger LANGUAGE plpgsql SET search_path = ''
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.created_at := now();
  ELSE
    IF NEW.id IS DISTINCT FROM OLD.id OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
      RAISE EXCEPTION 'Identity and creation time are immutable' USING ERRCODE = '23514';
    END IF;
    IF TG_TABLE_NAME = 'trips' AND
       (to_jsonb(NEW)->'created_by') IS DISTINCT FROM (to_jsonb(OLD)->'created_by') THEN
      RAISE EXCEPTION 'Trip creator is immutable' USING ERRCODE = '23514';
    END IF;
    IF TG_TABLE_NAME = 'itinerary_items' AND
       (to_jsonb(NEW)->'trip_id') IS DISTINCT FROM (to_jsonb(OLD)->'trip_id') THEN
      RAISE EXCEPTION 'Item trip is immutable' USING ERRCODE = '23514';
    END IF;
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;
CREATE TRIGGER profiles_stamp BEFORE INSERT OR UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION private.stamp_application_row();
CREATE TRIGGER trips_stamp BEFORE INSERT OR UPDATE ON public.trips
  FOR EACH ROW EXECUTE FUNCTION private.stamp_application_row();
CREATE TRIGGER itinerary_items_stamp BEFORE INSERT OR UPDATE ON public.itinerary_items
  FOR EACH ROW EXECUTE FUNCTION private.stamp_application_row();

CREATE FUNCTION private.add_trip_creator()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.trip_members (trip_id, user_id) VALUES (NEW.id, NEW.created_by);
  RETURN NEW;
END;
$$;
CREATE TRIGGER trips_add_creator AFTER INSERT ON public.trips
  FOR EACH ROW EXECUTE FUNCTION private.add_trip_creator();

CREATE FUNCTION private.stamp_membership()
RETURNS trigger LANGUAGE plpgsql SET search_path = ''
AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    RAISE EXCEPTION 'Memberships cannot be reassigned' USING ERRCODE = '23514';
  END IF;
  NEW.joined_at := now();
  RETURN NEW;
END;
$$;
CREATE TRIGGER trip_members_stamp BEFORE INSERT OR UPDATE ON public.trip_members
  FOR EACH ROW EXECUTE FUNCTION private.stamp_membership();

-- Backstop for privileged seed/import paths too. API writes remain revoked
-- until edit leases, Storage ownership checks and cleanup are implemented.
CREATE FUNCTION private.guard_photo()
RETURNS trigger LANGUAGE plpgsql SET search_path = ''
AS $$
DECLARE
  v_trip_id uuid;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.id IS DISTINCT FROM OLD.id
      OR NEW.itinerary_item_id IS DISTINCT FROM OLD.itinerary_item_id
      OR NEW.uploaded_by IS DISTINCT FROM OLD.uploaded_by
      OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
      RAISE EXCEPTION 'Photo identity and attribution are immutable' USING ERRCODE = '23514';
    END IF;
  END IF;
  SELECT i.trip_id INTO v_trip_id FROM public.itinerary_items i
    WHERE i.id = NEW.itinerary_item_id FOR UPDATE;
  IF TG_OP = 'INSERT' THEN
    IF (SELECT count(*) FROM public.itinerary_photos p
        WHERE p.itinerary_item_id = NEW.itinerary_item_id) >= 5 THEN
      RAISE EXCEPTION 'At most five photos per item' USING ERRCODE = '23514';
    END IF;
    -- Explicit true is also rejected; DEFAULT alone is insufficient.
    IF NEW.is_public IS DISTINCT FROM false THEN
      RAISE EXCEPTION 'New photos must be private' USING ERRCODE = '23514';
    END IF;
    NEW.created_at := now();
  ELSIF NEW.storage_path IS DISTINCT FROM OLD.storage_path THEN
    NEW.is_public := false;
  ELSIF NEW.is_public IS DISTINCT FROM OLD.is_public THEN
    IF NOT private.is_trip_creator(v_trip_id) THEN
      RAISE EXCEPTION 'Only the trip creator may change photo visibility' USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER itinerary_photos_guard BEFORE INSERT OR UPDATE ON public.itinerary_photos
  FOR EACH ROW EXECUTE FUNCTION private.guard_photo();

-- RPC creation avoids the INSERT RETURNING/RLS visibility issue before an
-- AFTER INSERT membership trigger has fired; creator comes only from auth.uid().
CREATE FUNCTION public.create_trip(p_name text, p_start_date date, p_end_date date)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE v_id uuid; v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.trips (name, start_date, end_date, created_by)
    VALUES (p_name, p_start_date, p_end_date, v_user_id) RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE FUNCTION public.set_trip_visibility(p_trip_id uuid, p_visibility text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  PERFORM 1 FROM public.trips t
    WHERE t.id = p_trip_id AND t.created_by = auth.uid() FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Only the trip creator may change visibility' USING ERRCODE = '42501';
  END IF;
  UPDATE public.trips SET visibility = p_visibility WHERE id = p_trip_id;
END;
$$;

CREATE FUNCTION public.get_trip_members(p_trip_id uuid)
RETURNS TABLE (display_name text, avatar_path text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  IF NOT private.is_trip_member(p_trip_id) THEN
    RAISE EXCEPTION 'Trip membership required' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY SELECT p.display_name, p.avatar_path FROM public.trip_members m
    JOIN public.profiles p ON p.id = m.user_id WHERE m.trip_id = p_trip_id;
END;
$$;
GRANT CREATE ON SCHEMA public TO ryoko_reader;
ALTER FUNCTION public.get_trip_members(uuid) OWNER TO ryoko_reader;
REVOKE CREATE ON SCHEMA public FROM ryoko_reader;

REVOKE ALL ON FUNCTION private.stamp_application_row(), private.add_trip_creator(),
  private.stamp_membership(), private.guard_photo() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_trip(text,date,date),
  public.set_trip_visibility(uuid,text), public.get_trip_members(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_trip(text,date,date),
  public.set_trip_visibility(uuid,text), public.get_trip_members(uuid) TO authenticated;

COMMIT;

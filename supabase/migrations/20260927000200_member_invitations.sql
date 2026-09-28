
-- Member invitations are separate from read-only sharing credentials.
BEGIN;
CREATE TABLE private.trip_invitations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id uuid NOT NULL REFERENCES public.trips(id) ON DELETE CASCADE,
  token_hash bytea NOT NULL UNIQUE,
  issued_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE NO ACTION,
  created_at timestamptz NOT NULL,
  expires_at timestamptz NOT NULL,
  CONSTRAINT trip_invitations_hash_length CHECK (octet_length(token_hash) = 32),
  CONSTRAINT trip_invitations_lifetime CHECK (expires_at = created_at + interval '24 hours')
);
CREATE INDEX trip_invitations_trip_idx ON private.trip_invitations(trip_id);
ALTER TABLE private.trip_invitations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.trip_invitations FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.create_trip_invitation(p_trip_id uuid)
RETURNS TABLE (token text, expires_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE v_token text; v_created timestamptz;
BEGIN
  PERFORM 1 FROM public.trips
    WHERE id = p_trip_id AND created_by = auth.uid() FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Only the trip creator may invite members' USING ERRCODE = '42501';
  END IF;
  -- Two random UUIDs provide 244 random bits; no token is persisted in plaintext.
  v_token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  v_created := clock_timestamp();
  INSERT INTO private.trip_invitations(trip_id, token_hash, issued_by, created_at, expires_at)
    VALUES (p_trip_id, sha256(convert_to(v_token, 'UTF8')), auth.uid(),
      v_created, v_created + interval '24 hours');
  RETURN QUERY SELECT v_token, v_created + interval '24 hours';
END;
$$;

CREATE FUNCTION public.accept_trip_invitation(p_token text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE v_trip_id uuid; v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_user_id) THEN
    RAISE EXCEPTION 'Authentication and initial profile are required' USING ERRCODE = '42501';
  END IF;
  SELECT i.trip_id INTO v_trip_id FROM private.trip_invitations i
    WHERE i.token_hash = sha256(convert_to(p_token, 'UTF8'))
      AND i.expires_at > clock_timestamp();
  IF v_trip_id IS NULL THEN
    RAISE EXCEPTION 'Invalid or expired invitation' USING ERRCODE = '42501';
  END IF;
  -- Lock trip first, then recheck invitation, including expiry after waiting.
  PERFORM 1 FROM public.trips WHERE id = v_trip_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid or expired invitation' USING ERRCODE = '42501';
  END IF;
  PERFORM 1 FROM private.trip_invitations i
    WHERE i.trip_id = v_trip_id AND i.token_hash = sha256(convert_to(p_token, 'UTF8'))
      AND i.expires_at > clock_timestamp() FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid or expired invitation' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.trip_members(trip_id, user_id) VALUES(v_trip_id, v_user_id)
    ON CONFLICT (trip_id, user_id) DO NOTHING;
  RETURN v_trip_id;
END;
$$;
REVOKE ALL ON FUNCTION public.create_trip_invitation(uuid),
  public.accept_trip_invitation(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_trip_invitation(uuid),
  public.accept_trip_invitation(text) TO authenticated;
COMMIT;

import "server-only";

import { isAuthSessionMissingError } from "@supabase/supabase-js";
import { getCurrentUser } from "@/lib/supabase/auth";
import { createClient } from "@/lib/supabase/server";
import type { Tables } from "@/types/database.types";

const summaryColumns = "id,name,start_date,end_date,thumbnail_path";
const detailColumns = "id,name,start_date,end_date,thumbnail_path,visibility";
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export type TripSummary = Pick<
  Tables<"trips">,
  "id" | "name" | "start_date" | "end_date" | "thumbnail_path"
>;
export type TripDetail = TripSummary & Pick<Tables<"trips">, "visibility">;

export type TripReadErrorCode =
  | "UNAUTHENTICATED"
  | "AUTH_UNAVAILABLE"
  | "INVALID_INPUT"
  | "NOT_FOUND"
  | "READ_FAILED";

export class TripReadError extends Error {
  constructor(public readonly code: TripReadErrorCode) {
    const messages: Record<TripReadErrorCode, string> = {
      UNAUTHENTICATED: "ログインが必要です。",
      AUTH_UNAVAILABLE: "認証状態を確認できませんでした。",
      INVALID_INPUT: "旅行の取得条件が正しくありません。",
      NOT_FOUND: "旅行が見つからないか、閲覧できません。",
      READ_FAILED: "旅行を取得できませんでした。",
    };
    super(messages[code]);
    this.name = "TripReadError";
  }
}

async function authenticatedClient() {
  // Do not cache auth or membership across requests. Leaving a trip must take
  // effect on the very next query, even while the Auth session is still valid.
  let result: Awaited<ReturnType<typeof getCurrentUser>>;
  try {
    result = await getCurrentUser();
  } catch {
    throw new TripReadError("AUTH_UNAVAILABLE");
  }
  if (result.error) {
    if (
      isAuthSessionMissingError(result.error) ||
      result.error.status === 401 ||
      result.error.status === 403
    ) {
      throw new TripReadError("UNAUTHENTICATED");
    }
    throw new TripReadError("AUTH_UNAVAILABLE");
  }
  if (!result.data.user) throw new TripReadError("UNAUTHENTICATED");
  // The existing client sends this request's user JWT; never a service-role key.
  return createClient();
}

/**
 * Member-only page. ID order is a technical cursor order, not the UI's
 * undecided trip display order. RLS determines membership in the same SELECT.
 */
export async function listMyTrips(
  { cursor, pageSize = 50 }: { cursor?: string; pageSize?: number } = {},
): Promise<{ trips: TripSummary[]; nextCursor: string | null }> {
  const supabase = await authenticatedClient();
  if (
    !Number.isInteger(pageSize) || pageSize < 1 || pageSize > 100 ||
    (cursor !== undefined && !uuidPattern.test(cursor))
  ) {
    throw new TripReadError("INVALID_INPUT");
  }

  try {
    let query = supabase.from("trips").select(summaryColumns, { count: "exact" })
      .order("id", { ascending: true }).limit(pageSize);
    if (cursor) query = query.gt("id", cursor);
    const { data, error, count } = await query;
    if (error || !data || count === null || (count > 0 && data.length === 0)) {
      throw new TripReadError("READ_FAILED");
    }

    const trips = data;
    return {
      trips,
      nextCursor: count > trips.length ? trips[trips.length - 1].id : null,
    };
  } catch {
    throw new TripReadError("READ_FAILED");
  }
}

/** Missing trips and RLS-filtered trips intentionally share the same result. */
export async function getMyTrip(tripId: string): Promise<TripDetail> {
  const supabase = await authenticatedClient();
  if (!uuidPattern.test(tripId)) throw new TripReadError("INVALID_INPUT");

  let result;
  try {
    result = await supabase.from("trips").select(detailColumns)
      .eq("id", tripId).maybeSingle();
  } catch {
    throw new TripReadError("READ_FAILED");
  }
  if (result.error) throw new TripReadError("READ_FAILED");
  if (!result.data) throw new TripReadError("NOT_FOUND");
  return result.data;
}
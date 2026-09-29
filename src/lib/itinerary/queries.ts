import "server-only";

import { isAuthSessionMissingError } from "@supabase/supabase-js";
import { getCurrentUser } from "@/lib/supabase/auth";
import { createClient } from "@/lib/supabase/server";
import type { Tables } from "@/types/database.types";

const itemColumns = "id,trip_id,date,category,title,sort_order,time_type,exact_time,time_period,duration_minutes";
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export type ItineraryItem = Pick<
  Tables<"itinerary_items">,
  "id" | "trip_id" | "date" | "category" | "title" | "sort_order" |
  "time_type" | "exact_time" | "time_period" | "duration_minutes"
>;

export type ItineraryCursor = { sortOrder: number; id: string };
export type ItineraryReadErrorCode =
  | "UNAUTHENTICATED"
  | "AUTH_UNAVAILABLE"
  | "INVALID_INPUT"
  | "NOT_FOUND"
  | "READ_FAILED";

export class ItineraryReadError extends Error {
  constructor(public readonly code: ItineraryReadErrorCode) {
    const messages: Record<ItineraryReadErrorCode, string> = {
      UNAUTHENTICATED: "ログインが必要です。",
      AUTH_UNAVAILABLE: "認証状態を確認できませんでした。",
      INVALID_INPUT: "旅程の取得条件が正しくありません。",
      NOT_FOUND: "旅程が見つからないか、閲覧できません。",
      READ_FAILED: "旅程を取得できませんでした。",
    };
    super(messages[code]);
    this.name = "ItineraryReadError";
  }
}

async function authenticatedClient() {
  let result: Awaited<ReturnType<typeof getCurrentUser>>;
  try {
    result = await getCurrentUser();
  } catch {
    throw new ItineraryReadError("AUTH_UNAVAILABLE");
  }
  if (result.error) {
    if (
      isAuthSessionMissingError(result.error) ||
      result.error.status === 401 || result.error.status === 403
    ) {
      throw new ItineraryReadError("UNAUTHENTICATED");
    }
    throw new ItineraryReadError("AUTH_UNAVAILABLE");
  }
  if (!result.data.user) throw new ItineraryReadError("UNAUTHENTICATED");
  // A fresh user-JWT client on each call; membership and results are not cached.
  try {
    return await createClient();
  } catch {
    throw new ItineraryReadError("READ_FAILED");
  }
}

function isCalendarDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value) || value.startsWith("0000")) return false;
  const date = new Date(`${value}T00:00:00.000Z`);
  return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value;
}

/** A member-only day page. Empty also covers trips hidden by RLS. */
export async function listMyItineraryItems(
  tripId: string,
  date: string,
  { cursor, pageSize = 50 }: { cursor?: ItineraryCursor; pageSize?: number } = {},
): Promise<{ items: ItineraryItem[]; nextCursor: ItineraryCursor | null }> {
  const supabase = await authenticatedClient();
  if (
    !uuidPattern.test(tripId) || !isCalendarDate(date) ||
    !Number.isInteger(pageSize) || pageSize < 1 || pageSize > 100 ||
    (cursor !== undefined && (
      !cursor || !Number.isInteger(cursor.sortOrder) ||
      cursor.sortOrder < 0 || cursor.sortOrder > 2147483647 || !uuidPattern.test(cursor.id)
    ))
  ) {
    throw new ItineraryReadError("INVALID_INPUT");
  }

  try {
    let query = supabase.from("itinerary_items").select(itemColumns, { count: "exact" })
      .eq("trip_id", tripId).eq("date", date)
      .order("sort_order", { ascending: true }).order("id", { ascending: true })
      .limit(pageSize);
    // sort_order is not unique. ID only breaks ties for stable pagination.
    // Both interpolated values are validated above before entering PostgREST syntax.
    if (cursor) {
      query = query.or(`sort_order.gt.${cursor.sortOrder},and(sort_order.eq.${cursor.sortOrder},id.gt.${cursor.id})`);
    }
    const { data, error, count } = await query;
    if (error || !data || count === null || (count > 0 && data.length === 0)) {
      throw new ItineraryReadError("READ_FAILED");
    }
    const last = data[data.length - 1];
    return {
      items: data,
      // Use count rather than pageSize: the API may enforce a smaller row cap.
      nextCursor: count > data.length ? { sortOrder: last.sort_order, id: last.id } : null,
    };
  } catch {
    throw new ItineraryReadError("READ_FAILED");
  }
}

/** Trip scope and membership are checked by the same RLS-protected SELECT. */
export async function getMyItineraryItem(tripId: string, itemId: string): Promise<ItineraryItem> {
  const supabase = await authenticatedClient();
  if (!uuidPattern.test(tripId) || !uuidPattern.test(itemId)) {
    throw new ItineraryReadError("INVALID_INPUT");
  }
  let result;
  try {
    result = await supabase.from("itinerary_items").select(itemColumns)
      .eq("trip_id", tripId).eq("id", itemId).maybeSingle();
  } catch {
    throw new ItineraryReadError("READ_FAILED");
  }
  if (result.error) throw new ItineraryReadError("READ_FAILED");
  if (!result.data) throw new ItineraryReadError("NOT_FOUND");
  return result.data;
}

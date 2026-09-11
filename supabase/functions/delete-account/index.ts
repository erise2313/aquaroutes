// Deletes a GenTri WASA account.
//
// Google Play requires an in-app way to delete an account for any app with
// sign-up. Deleting a login needs the service-role key, which must never be
// in the app, so the app calls this function instead.
//
// Two ways in:
//   * {}                 -- a customer deletes their own account.
//   * { profile_id }     -- WASA admin completes a station owner's, driver's
//                           or admin's pending deletion request.
// Station owners, drivers and admins can't self-delete: their accounts are
// tied to association records (stations, jug ledger, permits), so they send
// a request (account_deletion_requests) that an admin reviews.
//
// What deletion does (supabase/patch_account_lifecycle.sql):
//   1. refuses while account_deletion_blockers() lists anything (an order in
//      progress, an open station, the last admin);
//   2. anonymize_account(): past orders keep their items and amounts but
//      lose the name, phone and exact address; their posts read "Former
//      member";
//   3. removes the person's files from the public photo buckets -- through
//      the Storage API, since direct deletes from storage tables are blocked;
//   4. deletes the login, which cascades to the profile, memberships,
//      reviews, comments, reactions and the deletion request.

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Removes every file directly under `folder` in `bucket`. */
async function removeFolder(client: SupabaseClient, bucket: string, folder: string): Promise<void> {
  const { data, error } = await client.storage.from(bucket).list(folder, { limit: 1000 });
  if (error) throw new Error(`Could not list ${bucket}: ${error.message}`);
  const paths = (data ?? []).map((f) => `${folder}/${f.name}`);
  if (paths.length === 0) return;
  const { error: removeError } = await client.storage.from(bucket).remove(paths);
  if (removeError) throw new Error(`Could not remove files from ${bucket}: ${removeError.message}`);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  // verify_jwt has checked the signature; this resolves who is calling and
  // rejects the anon key, which has no user.
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: userData, error: userError } = await admin.auth.getUser(token);
  const caller = userData?.user;
  if (userError || !caller) return json({ error: "Sign in again, then try once more." }, 401);

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    body = {};
  }
  const requested = typeof body.profile_id === "string" ? body.profile_id : null;
  if (requested !== null && !UUID.test(requested)) return json({ error: "Invalid account id." }, 400);

  // Every membership, whatever its status: a suspended station owner is still
  // a station owner and must go through the admin-reviewed request.
  const { data: memberships, error: membershipError } = await admin
    .from("memberships")
    .select("role, status")
    .eq("profile_id", caller.id);
  if (membershipError) return json({ error: "Could not check your account." }, 500);
  const callerIsAdmin = (memberships ?? []).some((m) => m.role === "wasa_admin" && m.status === "active");

  let profileId: string;
  if (requested !== null && requested !== caller.id) {
    if (!callerIsAdmin) return json({ error: "Only WASA admin can delete another account." }, 403);
    const { data: pending, error: pendingError } = await admin
      .from("account_deletion_requests")
      .select("id")
      .eq("profile_id", requested)
      .eq("status", "pending")
      .maybeSingle();
    if (pendingError) return json({ error: "Could not check the deletion request." }, 500);
    if (!pending) return json({ error: "This account has no pending deletion request." }, 409);
    profileId = requested;
  } else {
    if ((memberships ?? []).some((m) => m.role !== "public_consumer")) {
      return json({
        error: "Station owner, driver and admin accounts are deleted by WASA admin. Send a deletion request instead.",
      }, 403);
    }
    profileId = caller.id;
  }

  const { data: blockers, error: blockerError } = await admin.rpc("account_deletion_blockers", { p_profile: profileId });
  if (blockerError) return json({ error: "Could not check the account." }, 500);
  if (Array.isArray(blockers) && blockers.length > 0) {
    return json({ error: blockers.join(" "), blockers }, 409);
  }

  // Anonymize before touching any files: if it fails, nothing has changed.
  // Every step after it can simply be retried by calling this again.
  const { error: anonymizeError } = await admin.rpc("anonymize_account", { p_profile: profileId });
  if (anonymizeError) {
    console.error("anonymize_account failed", anonymizeError.message);
    return json({ error: "Could not anonymize the account's records." }, 500);
  }

  try {
    await removeFolder(admin, "avatars", profileId);
    await removeFolder(admin, "bulletin-images", profileId);
  } catch (e) {
    return json({ error: (e as Error).message }, 500);
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(profileId);
  if (deleteError) return json({ error: `Could not delete the login: ${deleteError.message}` }, 500);

  return json({ deleted: true });
});

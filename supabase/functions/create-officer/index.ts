// Creates a WASA officer account (super admins only).
//
// New officers used to have to register as a customer in the app first and
// then be promoted. Now a super admin enters their name, email and officer
// role, and this creates the login directly with a temporary password that
// is returned once, for the super admin to hand over. The officer must
// replace it the first time they sign in (profiles.must_change_password).
//
// Creating a login needs the service-role key, which must never reach a
// browser, so the admin portal calls this function.
//
// Body: { email, full_name, officer_role }
//   officer_role: superadmin | officer | compliance | workforce | content | viewer
//   (what each may change: supabase/patch_officer_roles.sql)

import { createClient } from "npm:@supabase/supabase-js@2";

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

const ROLES = ["superadmin", "officer", "compliance", "workforce", "content", "viewer"];
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/** 12 characters with no look-alikes (0/O, 1/l/I), at least one digit. */
function temporaryPassword(): string {
  const letters = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz";
  const digits = "23456789";
  const all = letters + digits;
  const bytes = new Uint32Array(12);
  crypto.getRandomValues(bytes);
  const chars = Array.from(bytes, (b) => all[b % all.length]);
  chars[bytes[0] % 12] = digits[bytes[1] % digits.length];
  return chars.join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: userData, error: userError } = await admin.auth.getUser(token);
  const caller = userData?.user;
  if (userError || !caller) return json({ error: "Sign in again, then try once more." }, 401);

  const { data: callerRows, error: callerError } = await admin
    .from("memberships")
    .select("role, status")
    .eq("profile_id", caller.id);
  if (callerError) return json({ error: "Could not check your account." }, 500);
  const isSuperadmin = (callerRows ?? []).some((m) => m.role === "wasa_superadmin" && m.status === "active");
  if (!isSuperadmin) return json({ error: "Only a WASA super admin can create officer accounts." }, 403);

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    body = {};
  }
  const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
  const fullName = typeof body.full_name === "string" ? body.full_name.trim() : "";
  const officerRole = typeof body.officer_role === "string" ? body.officer_role : "";
  if (!EMAIL.test(email)) return json({ error: "Enter a valid email address." }, 400);
  if (fullName.length < 2) return json({ error: "Enter the officer's full name." }, 400);
  if (!ROLES.includes(officerRole)) return json({ error: "Choose an officer role." }, 400);

  const password = temporaryPassword();
  const { data: created, error: createError } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { full_name: fullName },
  });
  if (createError || !created?.user) {
    const exists = (createError?.message ?? "").toLowerCase().includes("already");
    return json({
      error: exists
        ? "This email already has an account. Use \"Promote an existing account\" instead."
        : `Could not create the login: ${createError?.message ?? "unknown error"}`,
    }, exists ? 409 : 500);
  }
  const profileId = created.user.id;

  // The new-user trigger has made the profile; fill it in and require a new
  // password at first sign-in.
  const { error: profileError } = await admin
    .from("profiles")
    .upsert({ id: profileId, full_name: fullName, must_change_password: true });

  const { data: association } = await admin.from("associations").select("id").limit(1).maybeSingle();
  const { error: membershipError } = await admin.from("memberships").insert({
    profile_id: profileId,
    association_id: association?.id,
    role: officerRole === "superadmin" ? "wasa_superadmin" : "wasa_admin",
    officer_role: officerRole === "superadmin" ? null : officerRole,
    status: "active",
  });

  if (profileError || membershipError) {
    // Don't leave a login with no officer access behind.
    await admin.auth.admin.deleteUser(profileId);
    return json({ error: `Could not set up the account: ${(profileError ?? membershipError)!.message}` }, 500);
  }

  await admin.from("audit_log").insert({
    actor_id: caller.id,
    action: "INSERT",
    table_name: "memberships",
    record_id: profileId,
    summary: `Created officer account ${email} (${officerRole})`,
  });

  return json({ profile_id: profileId, email, temporary_password: password });
});

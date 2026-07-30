// supabase/functions/send-fcm-notification/index.ts
// Supabase Edge Function: Automatically sends FCM Push Notifications via HTTP v1 API.
// Triggered via Database Webhook on INSERT into public.notifications.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

interface NotificationRecord {
  id: string;
  recipient_id: string;
  title: string;
  body: string;
  type?: string;
  reference_type?: string;
  reference_id?: string;
}

interface WebhookPayload {
  type: "INSERT" | "UPDATE" | "DELETE";
  table: string;
  schema: string;
  record: NotificationRecord;
  old_record: NotificationRecord | null;
}

// ── JWT & OAuth2 Google Auth Helper ──────────────────────────────────────────

async function getAccessToken(serviceAccount: ServiceAccount): Promise<string> {
  const iat = Math.floor(Date.now() / 1000);
  const exp = iat + 3600; // 1 hour token lifetime

  const header = { alg: "RS256", typ: "JWT" };
  const claimSet = {
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    exp,
    iat,
  };

  const base64UrlEncode = (str: string): string =>
    btoa(str)
      .replace(/=/g, "")
      .replace(/\+/g, "-")
      .replace(/\//g, "_");

  const unsignedJwt = `${base64UrlEncode(JSON.stringify(header))}.${base64UrlEncode(
    JSON.stringify(claimSet)
  )}`;

  // PEM to ArrayBuffer for RS256 signature
  const pemHeader = "-----BEGIN PRIVATE KEY-----";
  const pemFooter = "-----END PRIVATE KEY-----";
  const pemContents = serviceAccount.private_key
    .replace(/\\n/g, "\n")
    .replace(pemHeader, "")
    .replace(pemFooter, "")
    .replace(/\s/g, "");

  const binaryDer = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0));

  const key = await crypto.subtle.importKey(
    "pkcs8",
    binaryDer.buffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsignedJwt)
  );

  const signedJwt = `${unsignedJwt}.${base64UrlEncode(
    String.fromCharCode(...new Uint8Array(signature))
  )}`;

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: signedJwt,
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`OAuth2 token exchange failed: ${errorText}`);
  }

  const data = await response.json();
  return data.access_token;
}

// ── Edge Function Entry Point ────────────────────────────────────────────────

Deno.serve(async (req) => {
  // Allow OPTIONS for CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  try {
    const payload: WebhookPayload = await req.json();
    const record = payload.record || (payload as unknown as NotificationRecord);

    if (!record || !record.recipient_id || !record.title) {
      return new Response(
        JSON.stringify({ error: "Missing required notification fields" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const firebaseServiceAccountEnv = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");

    if (!firebaseServiceAccountEnv) {
      console.error("FIREBASE_SERVICE_ACCOUNT env variable is missing");
      return new Response(
        JSON.stringify({ error: "FIREBASE_SERVICE_ACCOUNT secret not configured" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    const serviceAccount: ServiceAccount = JSON.parse(firebaseServiceAccountEnv);
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // 1. Fetch recipient's FCM token from profiles table
    const { data: profile, error: profileErr } = await supabase
      .from("profiles")
      .select("fcm_token, full_name")
      .eq("id", record.recipient_id)
      .single();

    if (profileErr || !profile?.fcm_token) {
      console.log(
        `[FCM] No FCM token found for recipient_id: ${record.recipient_id}. Skipping.`
      );
      return new Response(
        JSON.stringify({ message: "No FCM token registered for recipient" }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    }

    const fcmToken = profile.fcm_token;

    // 2. Obtain Google OAuth2 access token for FCM HTTP v1 API
    const accessToken = await getAccessToken(serviceAccount);

    // Pick channel ID (HR & Attendance vs Tasks)
    const hrTypes = [
      "attendance_alert",
      "attendance_checkin",
      "attendance_checkout",
      "attendance_approved",
      "penalty_applied",
      "penalty_created",
      "expense_created",
      "expense_approved",
      "expense_rejected",
      "role_changed",
      "team_changed",
      "announcement_created",
    ];
    const channelId = hrTypes.includes(record.type || "") ? "cbtodo_hr" : "cbtodo_tasks";

    // 3. Construct FCM HTTP v1 Message Payload
    const fcmPayload = {
      message: {
        token: fcmToken,
        notification: {
          title: record.title,
          body: record.body || "",
        },
        data: {
          id: record.id || "",
          type: record.type || "system",
          reference_type: record.reference_type || "",
          reference_id: record.reference_id || "",
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        android: {
          priority: "HIGH",
          notification: {
            sound: "default",
            channel_id: channelId,
            click_action: "FLUTTER_NOTIFICATION_CLICK",
          },
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              "content-available": 1,
            },
          },
        },
      },
    };

    // 4. Send Message via FCM HTTP v1 API
    const fcmUrl = `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`;
    const fcmRes = await fetch(fcmUrl, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(fcmPayload),
    });

    const fcmResult = await fcmRes.json();

    if (!fcmRes.ok) {
      console.error("[FCM Error]", fcmResult);

      // Handle invalid / unregistered tokens and clear them from profiles
      const errorCode = fcmResult.error?.details?.[0]?.errorCode || fcmResult.error?.status;
      if (
        fcmRes.status === 404 ||
        errorCode === "UNREGISTERED" ||
        errorCode === "INVALID_ARGUMENT"
      ) {
        console.warn(
          `[FCM] Token invalid/unregistered for user ${record.recipient_id}. Clearing token.`
        );
        await supabase
          .from("profiles")
          .update({ fcm_token: null })
          .eq("id", record.recipient_id);
      }

      return new Response(
        JSON.stringify({ error: "Failed to send FCM push notification", details: fcmResult }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    console.log(
      `[FCM Success] Sent push to ${profile.full_name || record.recipient_id}. MessageId: ${fcmResult.name}`
    );

    return new Response(
      JSON.stringify({ success: true, messageId: fcmResult.name }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  } catch (err: any) {
    console.error("[Edge Function Exception]", err);
    return new Response(
      JSON.stringify({ error: err.message || "Internal Server Error" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});

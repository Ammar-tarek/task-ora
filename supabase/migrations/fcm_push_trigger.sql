-- ============================================================================
-- Supabase Database Trigger & Migration for FCM Push Notifications
-- Automatically invokes the 'send-fcm-notification' Edge Function whenever
-- a new row is inserted into public.notifications.
-- ============================================================================

-- 1. Ensure fcm_token column exists on public.profiles table
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS fcm_token TEXT;

-- 2. Enable pg_net extension (required for async HTTP requests from Postgres)
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- 3. Create the Database Trigger Function that calls the Edge Function
CREATE OR REPLACE FUNCTION public.tr_send_fcm_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  edge_function_url TEXT;
  service_role_key TEXT;
  payload JSONB;
  request_id BIGINT;
BEGIN
  -- Construct the Edge Function URL & Authorization headers
  -- Replace <YOUR_PROJECT_REF> with your actual Supabase project reference if not using standard env
  edge_function_url := current_setting('app.settings.supabase_url', true) || '/functions/v1/send-fcm-notification';
  
  -- Fallback to default Supabase URL if setting is null
  IF edge_function_url IS NULL OR edge_function_url = '/functions/v1/send-fcm-notification' THEN
    edge_function_url := 'https://' || current_setting('request.jwt.claim.sub', true) || '.supabase.co/functions/v1/send-fcm-notification';
  END IF;

  -- Service role key / anon key header for authentication
  service_role_key := current_setting('app.settings.service_role_key', true);

  -- Prepare standard Webhook JSON Payload
  payload := jsonb_build_object(
    'type', TG_OP,
    'table', TG_TABLE_NAME,
    'schema', TG_TABLE_SCHEMA,
    'record', row_to_json(NEW)::jsonb,
    'old_record', NULL
  );

  -- Dispatch HTTP POST request via pg_net (non-blocking / asynchronous)
  -- Note: Alternatively, configure via Supabase Dashboard -> Database -> Webhooks pointing to send-fcm-notification
  PERFORM net.http_post(
    url := 'https://YOUR_SUPABASE_PROJECT_REF.supabase.co/functions/v1/send-fcm-notification',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer YOUR_SUPABASE_ANON_OR_SERVICE_KEY'
    ),
    body := payload
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Catch & log warning so notification insertion is never blocked by HTTP failure
  RAISE WARNING 'FCM Push notification trigger error: %', SQLERRM;
  RETURN NEW;
END;
$$;

-- 4. Create AFTER INSERT trigger on public.notifications
DROP TRIGGER IF EXISTS on_notification_created_send_fcm ON public.notifications;

CREATE TRIGGER on_notification_created_send_fcm
  AFTER INSERT ON public.notifications
  FOR EACH ROW
  EXECUTE FUNCTION public.tr_send_fcm_notification();

-- ============================================================================
-- NOTE ON ALTERNATIVE SETUP (SUPABASE DASHBOARD WEBHOOK):
-- Instead of pg_net SQL function above, you can also configure this directly in:
-- Supabase Dashboard -> Database -> Webhooks -> Add Webhook:
--   - Name: send-fcm-push
--   - Table: public.notifications
--   - Events: INSERT
--   - Type: HTTP Request
--   - Method: POST
--   - URL: https://<YOUR_PROJECT_REF>.supabase.co/functions/v1/send-fcm-notification
--   - HTTP Headers: Authorization: Bearer <YOUR_SUPABASE_ANON_KEY>
-- ============================================================================

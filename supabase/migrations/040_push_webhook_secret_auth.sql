-- Use an app-scoped webhook secret for database-triggered push delivery.
-- The secret value is stored as a Supabase Edge Function secret and in a
-- private database table, never in migrations.

CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC;
REVOKE ALL ON SCHEMA private FROM anon;
REVOKE ALL ON SCHEMA private FROM authenticated;

CREATE TABLE IF NOT EXISTS private.app_secrets (
  name text PRIMARY KEY,
  value text NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

REVOKE ALL ON TABLE private.app_secrets FROM PUBLIC;
REVOKE ALL ON TABLE private.app_secrets FROM anon;
REVOKE ALL ON TABLE private.app_secrets FROM authenticated;

CREATE OR REPLACE FUNCTION public.notify_push_on_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'net'
AS $function$
DECLARE
  payload jsonb;
  func_url text;
  webhook_secret text;
BEGIN
  payload := jsonb_build_object(
    'type', TG_OP,
    'table', TG_TABLE_NAME,
    'record', CASE WHEN TG_OP = 'DELETE' THEN row_to_json(OLD)::jsonb ELSE row_to_json(NEW)::jsonb END,
    'old_record', CASE WHEN TG_OP = 'UPDATE' THEN row_to_json(OLD)::jsonb ELSE NULL END
  );

  func_url := 'https://nxielmwdoiwiwhzczrmt.supabase.co/functions/v1/send-push-notification';
  SELECT value
  INTO webhook_secret
  FROM private.app_secrets
  WHERE name = 'together_push_webhook_secret';

  IF webhook_secret IS NULL OR webhook_secret = '' THEN
    RAISE WARNING 'together_push_webhook_secret is not configured; push webhook skipped';
    RETURN COALESCE(NEW, OLD);
  END IF;

  PERFORM net.http_post(
    url := func_url,
    body := payload,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'X-Together-Webhook-Secret', webhook_secret
    )
  );

  RETURN COALESCE(NEW, OLD);
END;
$function$;

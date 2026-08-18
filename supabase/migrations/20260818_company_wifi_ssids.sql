-- Multi-network WiFi attendance migration.
--
-- Introduces the `company_wifi_ssids` key in the `app_settings` key/value
-- store, holding a JSON array of SSID strings, e.g. ["Cashback","Cashback_5G"].
--
-- Safe / non-destructive:
--   * Preserves the existing single SSID by merging it into the array.
--   * Preserves any SSIDs already present in `company_wifi_ssids`.
--   * Does NOT delete the legacy `company_wifi_ssid` key (old app versions and
--     backward-compat reads still rely on it).
--   * Idempotent — re-running only ever unions values, never drops them.

do $$
declare
  legacy   text;
  existing jsonb := '[]'::jsonb;
  merged   jsonb;
begin
  select nullif(trim(value), '') into legacy
    from app_settings where key = 'company_wifi_ssid';

  begin
    select coalesce(nullif(trim(value), '')::jsonb, '[]'::jsonb) into existing
      from app_settings where key = 'company_wifi_ssids';
  exception when others then
    existing := '[]'::jsonb;   -- legacy non-JSON value; start fresh from legacy
  end;

  if existing is null or jsonb_typeof(existing) <> 'array' then
    existing := '[]'::jsonb;
  end if;

  merged := existing;

  -- Union the legacy single SSID in if it isn't already listed.
  if legacy is not null and not (merged ? legacy) then
    merged := merged || to_jsonb(legacy);
  end if;

  insert into app_settings (key, value, updated_at)
  values ('company_wifi_ssids', merged::text, now())
  on conflict (key) do update
    set value = excluded.value,
        updated_at = now();
end $$;

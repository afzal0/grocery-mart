-- RLS only constrains NON-superuser roles. The bootstrap POSTGRES_USER (grocery) is a
-- superuser and bypasses RLS, so we introduce a least-privilege application role that
-- the API will connect as (wired in Epic 2 hardening) and that the isolation test uses
-- via SET ROLE to prove the policy actually enforces.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'grocery_app') THEN
        CREATE ROLE grocery_app NOLOGIN;
    END IF;
END
$$;

GRANT USAGE ON SCHEMA public TO grocery_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON tenant_demo TO grocery_app;

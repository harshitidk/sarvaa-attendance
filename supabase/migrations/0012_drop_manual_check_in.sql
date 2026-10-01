-- ===========================================================================
-- 0012_drop_manual_check_in.sql
--
-- Manual check-in without a location is removed. Check-in now always requires
-- a location scan that confirms the employee is inside a geofence, so nobody
-- can record a check-in from anywhere. Dropping the function closes the API
-- path as well as the app button.
-- ===========================================================================

drop function if exists public.employee_manual_check_in(timestamptz, text);

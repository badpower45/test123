-- =============================================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- =============================================================================
-- These policies ensure that:
-- 1. Users can only access their own data
-- 2. Admins can view all records
-- 3. Data integrity is maintained at the database level
-- =============================================================================

-- Enable RLS on all tables
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE shifts ENABLE ROW LEVEL SECURITY;
ALTER TABLE pulses ENABLE ROW LEVEL SECURITY;

-- =============================================================================
-- PROFILES TABLE POLICIES
-- =============================================================================

-- Users can view their own profile
CREATE POLICY "Users can view own profile"
    ON profiles
    FOR SELECT
    USING (auth.uid() = id);

-- Users can update their own profile (but cannot change role)
CREATE POLICY "Users can update own profile"
    ON profiles
    FOR UPDATE
    USING (auth.uid() = id)
    WITH CHECK (
        auth.uid() = id 
        AND role = (SELECT role FROM profiles WHERE id = auth.uid())
    );

-- Admins can view all profiles
CREATE POLICY "Admins can view all profiles"
    ON profiles
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE id = auth.uid()
            AND role = 'admin'
        )
    );

-- Admins can insert new profiles
CREATE POLICY "Admins can insert profiles"
    ON profiles
    FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE id = auth.uid()
            AND role = 'admin'
        )
    );

-- Admins can update any profile
CREATE POLICY "Admins can update all profiles"
    ON profiles
    FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE id = auth.uid()
            AND role = 'admin'
        )
    );

-- =============================================================================
-- SHIFTS TABLE POLICIES
-- =============================================================================

-- Users can view their own shifts
CREATE POLICY "Users can view own shifts"
    ON shifts
    FOR SELECT
    USING (auth.uid() = user_id);

-- Users can insert their own shifts
CREATE POLICY "Users can create own shifts"
    ON shifts
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Users can update their own shifts
CREATE POLICY "Users can update own shifts"
    ON shifts
    FOR UPDATE
    USING (auth.uid() = user_id);

-- Admins can view all shifts
CREATE POLICY "Admins can view all shifts"
    ON shifts
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE id = auth.uid()
            AND role = 'admin'
        )
    );

-- Admins can update any shift
CREATE POLICY "Admins can update all shifts"
    ON shifts
    FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE id = auth.uid()
            AND role = 'admin'
        )
    );

-- =============================================================================
-- PULSES TABLE POLICIES
-- =============================================================================

-- Users can view pulses from their own shifts
CREATE POLICY "Users can view own pulses"
    ON pulses
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM shifts
            WHERE shifts.id = pulses.shift_id
            AND shifts.user_id = auth.uid()
        )
    );

-- Users can insert pulses for their own shifts
CREATE POLICY "Users can create pulses for own shifts"
    ON pulses
    FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM shifts
            WHERE shifts.id = shift_id
            AND shifts.user_id = auth.uid()
        )
    );

-- Admins can view all pulses
CREATE POLICY "Admins can view all pulses"
    ON pulses
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE id = auth.uid()
            AND role = 'admin'
        )
    );

-- =============================================================================
-- SERVICE ROLE POLICIES (for edge functions and backend services)
-- =============================================================================
-- Service role bypasses RLS, but we add these for completeness

-- Allow service role full access to profiles
CREATE POLICY "Service role full access to profiles"
    ON profiles
    FOR ALL
    USING (auth.jwt() ->> 'role' = 'service_role');

-- Allow service role full access to shifts
CREATE POLICY "Service role full access to shifts"
    ON shifts
    FOR ALL
    USING (auth.jwt() ->> 'role' = 'service_role');

-- Allow service role full access to pulses
CREATE POLICY "Service role full access to pulses"
    ON pulses
    FOR ALL
    USING (auth.jwt() ->> 'role' = 'service_role');

-- =============================================================================
-- COMMENTS
-- =============================================================================
COMMENT ON POLICY "Users can view own profile" ON profiles IS 'Allows users to read their own profile data';
COMMENT ON POLICY "Admins can view all profiles" ON profiles IS 'Allows admin role to view all employee profiles';
COMMENT ON POLICY "Users can view own shifts" ON shifts IS 'Allows users to view their own shift records';
COMMENT ON POLICY "Admins can view all shifts" ON shifts IS 'Allows admin role to monitor all shifts';
COMMENT ON POLICY "Users can view own pulses" ON pulses IS 'Allows users to view pulses from their shifts';
COMMENT ON POLICY "Admins can view all pulses" ON pulses IS 'Allows admin role to monitor all location pulses';

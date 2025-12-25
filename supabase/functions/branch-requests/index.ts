import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.3'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      {
        global: {
          headers: { Authorization: req.headers.get('Authorization')! },
        },
      }
    )

    const { data: { user }, error: userError } = await supabaseClient.auth.getUser()
    
    if (userError || !user) {
      console.error('❌ Authentication failed:', userError)
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 401 }
      )
    }

    console.log('✅ Authenticated user:', user.id)

    // Get branch name from query parameters
    const url = new URL(req.url)
    const branchName = url.searchParams.get('branch')
    const managerId = url.searchParams.get('manager_id')

    if (!branchName) {
      console.error('❌ Branch name is required')
      return new Response(
        JSON.stringify({ error: 'Branch name is required' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      )
    }

    console.log('📍 Branch name from query:', branchName)
    if (managerId) {
      console.log('👤 Manager ID from query:', managerId)
    }

    // Get manager's branch info to verify
    let managerBranchId: string | null = null
    if (managerId) {
      const { data: managerData, error: managerError } = await supabaseClient
        .from('employees')
        .select('branch, branch_id')
        .eq('id', managerId)
        .maybeSingle()

      if (managerError) {
        console.error('❌ Error fetching manager data:', managerError)
      } else if (managerData) {
        // Verify manager's branch matches the requested branch
        if (managerData.branch !== branchName) {
          console.warn('⚠️ Manager branch mismatch:', managerData.branch, 'vs', branchName)
        }
        managerBranchId = managerData.branch_id
        console.log('📍 Manager branch_id:', managerBranchId)
      }
    }

    // Get all employees in this branch (by branch name and branch_id if available)
    // First try by branch name, then verify with branch_id if available
    let query = supabaseClient
      .from('employees')
      .select('id')
      .eq('branch', branchName)
      .eq('is_active', true)
    
    // If manager has branch_id, also filter by it for extra security
    if (managerBranchId) {
      query = query.eq('branch_id', managerBranchId)
    }
    
    const { data: branchEmployees, error: employeesError } = await query

    if (employeesError) {
      console.error('❌ Error fetching branch employees:', employeesError)
      return new Response(
        JSON.stringify({ error: 'Failed to fetch branch employees' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
      )
    }

    console.log('👥 Branch employees count:', branchEmployees?.length || 0)

    // Extract employee IDs (using 'id' field from employees table)
    const employeeIds = branchEmployees?.map(e => e.id).filter(Boolean) || []
    
    if (employeeIds.length === 0) {
      console.warn('⚠️ No employees found in branch')
      return new Response(
        JSON.stringify({ 
          leave_requests: [], 
          salary_advances: [], 
          attendance_requests: [],
          break_requests: []
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
      )
    }

    console.log('🔍 Fetching requests for employee IDs:', employeeIds)

    // Fetch leave requests - ALL statuses (or scoped by manager if provided)
    const { data: leaveRequests, error: leaveError } = await supabaseClient
      .from('leave_requests')
      .select(`
        *,
        employee:employees!leave_requests_employee_id_fkey (
          full_name,
          id
        )
      `)
      .in('employee_id', employeeIds)
      .order('created_at', { ascending: false });

    // Apply manager filter manually to avoid Deno type issues
    const filteredLeave = (leaveRequests || []).filter((r: any) => !managerId || r.assigned_manager_id === managerId);
    
    // Fetch salary advances - ALL statuses (or scoped by manager if provided)
    const { data: salaryAdvancesRaw, error: salaryError } = await supabaseClient
      .from('salary_advances')
      .select(`
        *,
        employee:employees!salary_advances_employee_id_fkey (
          full_name,
          id
        )
      `)
      .in('employee_id', employeeIds)
      .order('created_at', { ascending: false })
    const filteredAdvances = (salaryAdvancesRaw || []).filter((r: any) => !managerId || r.assigned_manager_id === managerId);

    if (salaryError) {
      console.error('❌ Error fetching salary advances:', salaryError)
    } else {
      console.log('💰 Salary advances found:', filteredAdvances?.length || 0)
    }

    if (leaveError) {
      console.error('❌ Error fetching leave requests:', leaveError)
    } else {
      console.log('📝 Leave requests found:', filteredLeave?.length || 0)
    }

    // Fetch attendance requests - ALL statuses (or scoped by manager if provided)
    const { data: attendanceRequestsRaw, error: attendanceError } = await supabaseClient
      .from('attendance_requests')
      .select(`
        *,
        employee:employees!attendance_requests_employee_id_fkey (
          full_name,
          id
        )
      `)
      .in('employee_id', employeeIds)
      .order('created_at', { ascending: false })
    const filteredAttendance = (attendanceRequestsRaw || []).filter((r: any) => !managerId || r.assigned_manager_id === managerId);

    if (attendanceError) {
      console.error('❌ Error fetching attendance requests:', attendanceError)
    } else {
      console.log('⏰ Attendance requests found:', filteredAttendance?.length || 0)
    }

    // Fetch break requests - ALL statuses (or scoped by manager if provided)
    const { data: breakRequestsRaw, error: breakError } = await supabaseClient
      .from('breaks')
      .select(`
        *,
        employee:employees!breaks_employee_id_fkey (
          full_name,
          id
        )
      `)
      .in('employee_id', employeeIds)
      .order('created_at', { ascending: false })
    
    // Filter by manager if provided
    const filteredBreaks = (breakRequestsRaw || []).filter((r: any) => !managerId || r.assigned_manager_id === managerId);
    
    // Map break requests to include employee name in root level for easier access
    const mappedBreakRequests = filteredBreaks?.map((br: any) => ({
      ...br,
      employeeName: br.employee?.full_name ?? null,
      employeeId: br.employee_id ?? br.employeeId,
    })) || []

    if (breakError) {
      console.error('❌ Error fetching break requests:', breakError)
    } else {
      console.log('☕ Break requests found (before filter):', breakRequestsRaw?.length || 0)
      console.log('☕ Break requests found (after manager filter):', mappedBreakRequests?.length || 0)
    }

    const response = {
      leave_requests: filteredLeave || [],
      salary_advances: filteredAdvances || [],
      attendance_requests: filteredAttendance || [],
      break_requests: mappedBreakRequests
    }

    console.log('✅ Total requests returned:', 
      response.leave_requests.length + 
      response.salary_advances.length + 
      response.attendance_requests.length +
      response.break_requests.length
    )

    return new Response(
      JSON.stringify(response),
      { 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200 
      }
    )

  } catch (error) {
    console.error('❌ Unexpected error:', error)
    const errorMessage = error instanceof Error ? error.message : 'Unknown error'
    return new Response(
      JSON.stringify({ error: errorMessage }),
      { 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500 
      }
    )
  }
})

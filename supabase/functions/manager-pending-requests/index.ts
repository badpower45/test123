import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.3'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

type PendingResponse = {
  leave_requests: any[]
  salary_advances: any[]
  attendance_requests: any[]
  break_requests: any[]
}

async function getManagerBranchScope(supabaseClient: any, managerId: string) {
  const { data, error } = await supabaseClient
    .from('employees')
    .select('id, branch_id, branch')
    .eq('id', managerId)
    .maybeSingle()

  if (error || !data) {
    return { branchId: null as string | null, branchName: null as string | null }
  }

  return {
    branchId: (data.branch_id as string | null) ?? null,
    branchName: (data.branch as string | null) ?? null,
  }
}

async function getBranchEmployeeIds(
  supabaseClient: any,
  branchId: string | null,
  branchName: string | null,
) {
  if (!branchId && !branchName) return [] as string[]

  let query = supabaseClient
    .from('employees')
    .select('id')
    .eq('is_active', true)

  if (branchId) {
    query = query.eq('branch_id', branchId)
  } else if (branchName) {
    query = query.eq('branch', branchName)
  }

  const { data, error } = await query
  if (error || !Array.isArray(data)) return [] as string[]

  return data.map((row: any) => row.id).filter(Boolean)
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

    const { data: { user } } = await supabaseClient.auth.getUser()
    if (!user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 401,
      })
    }

    const url = new URL(req.url)
    const managerId = url.searchParams.get('manager_id')
    const ownBranch = url.searchParams.get('own_branch') // optional: used to exclude own branch from breaks

    if (!managerId) {
      return new Response(JSON.stringify({ error: 'manager_id is required' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      })
    }

    const managerScope = await getManagerBranchScope(supabaseClient, managerId)
    const branchEmployeeIds = await getBranchEmployeeIds(
      supabaseClient,
      managerScope.branchId,
      managerScope.branchName ?? ownBranch,
    )

    // Pending leave assigned to manager or unassigned within the same branch
    const { data: leaves, error: leaveErr } = await supabaseClient
      .from('leave_requests')
      .select(`*, employees:employees!leave_requests_employee_id_fkey(id, full_name, branch, role)`) 
      .eq('status', 'pending')
      .order('created_at', { ascending: false })

    // Pending advances assigned to manager or unassigned within the same branch
    const { data: advances, error: advErr } = await supabaseClient
      .from('salary_advances')
      .select(`*, employees:employees!salary_advances_employee_id_fkey(id, full_name, branch, role)`) 
      .eq('status', 'pending')
      .order('created_at', { ascending: false })

    // Pending attendance assigned to manager or unassigned within the same branch
    const { data: attendance, error: attErr } = await supabaseClient
      .from('attendance_requests')
      .select(`*, employees:employees!attendance_requests_employee_id_fkey(id, full_name, branch, role)`) 
      .eq('status', 'pending')
      .order('created_at', { ascending: false })

    // Pending breaks assigned to manager (after adding assigned_manager_id column)
    const { data: assignedBreaks, error: brErr } = await supabaseClient
      .from('breaks')
      .select(`*, employees:employees!breaks_employee_id_fkey(id, full_name, branch, role)`) 
      .in('status', ['PENDING', 'pending'])
      .eq('assigned_manager_id', managerId)
      .order('created_at', { ascending: false })

    // Fallback for old records created without assigned_manager_id:
    // fetch pending requests for manager branch employees, then backfill assignment.
    const mergeById = (base: any[] = [], extra: any[] = []) => {
      const map = new Map<string, any>()
      for (const item of base) {
        if (item?.id) map.set(item.id, item)
      }
      for (const item of extra) {
        if (item?.id && !map.has(item.id)) map.set(item.id, item)
      }
      return Array.from(map.values())
    }

    const isSameBranchUnassigned = (row: any) => {
      if (!row || row.assigned_manager_id) return false
      const employeeId = row.employee_id?.toString?.() ?? ''
      return branchEmployeeIds.includes(employeeId)
    }

    const fallbackLeaves = (leaves || []).filter(isSameBranchUnassigned)
    const fallbackAdvances = (advances || []).filter(isSameBranchUnassigned)
    const fallbackAttendance = (attendance || []).filter(isSameBranchUnassigned)

    if (fallbackLeaves.length > 0) {
      await supabaseClient.from('leave_requests').update({ assigned_manager_id: managerId }).in('id', fallbackLeaves.map((row: any) => row.id))
    }
    if (fallbackAdvances.length > 0) {
      await supabaseClient.from('salary_advances').update({ assigned_manager_id: managerId }).in('id', fallbackAdvances.map((row: any) => row.id))
    }
    if (fallbackAttendance.length > 0) {
      await supabaseClient.from('attendance_requests').update({ assigned_manager_id: managerId }).in('id', fallbackAttendance.map((row: any) => row.id))
    }

    let fallbackBreaks: any[] = []
    try {
      console.log('[manager-pending-requests] Manager scope:', managerScope)

      if (managerScope.branchId || managerScope.branchName || ownBranch) {
        let employeesQuery = supabaseClient
          .from('employees')
          .select('id')
          .eq('is_active', true)

        if (managerScope.branchId) {
          console.log('[manager-pending-requests] Filtering employees by branch_id:', managerScope.branchId)
          employeesQuery = employeesQuery.eq('branch_id', managerScope.branchId)
        } else {
          const branchFilter = managerScope.branchName ?? ownBranch
          console.log('[manager-pending-requests] Filtering employees by branch:', branchFilter)
          employeesQuery = employeesQuery.eq('branch', branchFilter)
        }

        const { data: branchEmployees, error: branchEmployeesError } = await employeesQuery
        if (branchEmployeesError) {
          console.error('[manager-pending-requests] Error fetching branch employees:', branchEmployeesError)
        } else if (Array.isArray(branchEmployees) && branchEmployees.length > 0) {
          const employeeIds = branchEmployees.map((row: any) => row.id).filter(Boolean)
          console.log('[manager-pending-requests] Found branch employees:', employeeIds.length)

          if (employeeIds.length > 0) {
            const { data: unassignedBreaks, error: unassignedErr } = await supabaseClient
              .from('breaks')
              .select(`*, employees:employees!breaks_employee_id_fkey(id, full_name, branch, role)`)
              .in('status', ['PENDING', 'pending'])
              .in('employee_id', employeeIds)
              .is('assigned_manager_id', null)
              .order('created_at', { ascending: false })

            if (unassignedErr) {
              console.error('[manager-pending-requests] Error fetching unassigned breaks:', unassignedErr)
            } else if (Array.isArray(unassignedBreaks) && unassignedBreaks.length > 0) {
              console.log('[manager-pending-requests] Found unassigned breaks:', unassignedBreaks.length)
              fallbackBreaks = unassignedBreaks

              // Best-effort backfill so next fetch/realtime works with manager filter directly.
              const fallbackIds = unassignedBreaks.map((row: any) => row.id).filter(Boolean)
              if (fallbackIds.length > 0) {
                console.log('[manager-pending-requests] Backfilling assigned_manager_id for breaks:', fallbackIds)
                await supabaseClient
                  .from('breaks')
                  .update({ assigned_manager_id: managerId })
                  .in('id', fallbackIds)
              }
            } else {
              console.log('[manager-pending-requests] No unassigned breaks found for branch employees')
            }
          }
        } else {
          console.log('[manager-pending-requests] No active employees found in branch')
        }
      } else {
        console.log('[manager-pending-requests] No branch scope found for manager')
      }
    } catch (fallbackError) {
      console.error('[manager-pending-requests] Break fallback assignment failed:', fallbackError)
    }

    const allBreaksMap = new Map<string, any>()
    for (const item of assignedBreaks || []) {
      if (item?.id) allBreaksMap.set(item.id, item)
    }
    for (const item of fallbackBreaks || []) {
      if (item?.id && !allBreaksMap.has(item.id)) {
        allBreaksMap.set(item.id, item)
      }
    }
    const mergedBreaks = Array.from(allBreaksMap.values())

    if (leaveErr || advErr || attErr || brErr) {
      console.error('Errors:', { leaveErr, advErr, attErr, brErr })
    }

    const payload: PendingResponse = {
      leave_requests: mergeById(leaves || [], fallbackLeaves),
      salary_advances: mergeById(advances || [], fallbackAdvances),
      attendance_requests: mergeById(attendance || [], fallbackAttendance),
      break_requests: mergedBreaks,
    }

    return new Response(JSON.stringify(payload), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    })
  } catch (e) {
    const message = (e as any)?.message || 'Unexpected error'
    console.error('manager-pending-requests error:', message)
    return new Response(JSON.stringify({ error: message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 500,
    })
  }
})

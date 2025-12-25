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

    // Pending leave assigned to manager (across branches)
    const { data: leaves, error: leaveErr } = await supabaseClient
      .from('leave_requests')
      .select(`*, employees:employees!leave_requests_employee_id_fkey(id, full_name, branch, role)`) 
      .eq('status', 'pending')
      .eq('assigned_manager_id', managerId)
      .order('created_at', { ascending: false })

    // Pending advances assigned to manager
    const { data: advances, error: advErr } = await supabaseClient
      .from('salary_advances')
      .select(`*, employees:employees!salary_advances_employee_id_fkey(id, full_name, branch, role)`) 
      .eq('status', 'pending')
      .eq('assigned_manager_id', managerId)
      .order('created_at', { ascending: false })

    // Pending attendance assigned to manager
    const { data: attendance, error: attErr } = await supabaseClient
      .from('attendance_requests')
      .select(`*, employees:employees!attendance_requests_employee_id_fkey(id, full_name, branch, role)`) 
      .eq('status', 'pending')
      .eq('assigned_manager_id', managerId)
      .order('created_at', { ascending: false })

    // Pending breaks assigned to manager (after adding assigned_manager_id column)
    const { data: breaks, error: brErr } = await supabaseClient
      .from('breaks')
      .select(`*, employees:employees!breaks_employee_id_fkey(id, full_name, branch, role)`) 
      .eq('status', 'PENDING')
      .eq('assigned_manager_id', managerId)
      .order('created_at', { ascending: false })

    if (leaveErr || advErr || attErr || brErr) {
      console.error('Errors:', { leaveErr, advErr, attErr, brErr })
    }

    const payload: PendingResponse = {
      leave_requests: leaves || [],
      salary_advances: advances || [],
      attendance_requests: attendance || [],
      break_requests: breaks || [],
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
